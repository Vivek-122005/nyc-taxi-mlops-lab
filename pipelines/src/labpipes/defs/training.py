"""S2: training_set, trained_model, eval_report, the challenger gate and the challenger asset.

- training_set: UNLOAD a window of staging.trip_features (and the holdout month) to the artifact bucket.
  The zone-pair distance lookup (contracts/features.yaml, est_distance_miles) comes from the window only.
- trained_model: fit tripmodel.LightGBMModel (the given v2), log it to MLflow as a pyfunc with
  tripmodel.model_signature() and the tripmodel package bundled, register a version of the model named
  in contracts/mlflow.yaml, and tag it as that contract says.
- eval_report: tripmodel.evaluate the new version and the champion (or the v1 baseline before there is
  one) on the same holdout; log the metrics.
- A blocking check that guards a `challenger` asset, which sets the alias. The pipeline never moves
  `champion`.
Decision points: what stays in the notebook; the promotion metric and margin; the training window.
"""

import os
from dataclasses import dataclass
from pathlib import Path

import dagster as dg
import mlflow
import mlflow.pyfunc
from mlflow.exceptions import MlflowException

import tripmodel
from tripmodel import BaselineModel, LightGBMModel, evaluate, model_signature

from ..contracts import features_contract, mlflow_contract
from ..resources import ArtifactBucket, MlflowTracking, RedshiftData
from .features import trip_features


# Decision 009: an earlier three-month window predicts the untouched immediately following month.
TRAIN_MONTHS = ("2024-01", "2024-02", "2024-03")
HOLDOUT_MONTH = "2024-04"
TRAINING_WINDOW = f"{TRAIN_MONTHS[0]}..{TRAIN_MONTHS[-1]}"
TRAINING_PREFIX = f"training/{TRAINING_WINDOW}"


@dataclass(frozen=True)
class Candidate:
    version: str
    run_id: str


def _months_sql(months: tuple[str, ...]) -> str:
    return ", ".join(f"'{month}'" for month in months)


def _unload(select: str, destination: str) -> str:
    """Redshift UNLOAD embeds SELECT as a SQL literal, so source literals must be escaped once more."""
    escaped = select.replace("'", "''")
    return f"unload ('{escaped}') to '{destination}' iam_role default format as parquet allowoverwrite"


def _candidate(context: dg.AssetExecutionContext, tracking: MlflowTracking):
    """The model version produced by this Dagster run, not merely the latest global version."""
    versions = tracking.client().search_model_versions(f"name = '{mlflow_contract()['registered_model']}'")
    matches = [version for version in versions if version.tags.get("dagster_run_id") == context.run_id]
    if len(matches) != 1:
        raise RuntimeError(f"expected one candidate model for Dagster run {context.run_id}, found {len(matches)}")
    return matches[0]


def _promotion_policy() -> tuple[float, float] | None:
    """Return the student-owned MAE margin and latency cap, or None until they are measured and chosen."""
    margin = os.environ.get("PROMOTION_MIN_MAE_IMPROVEMENT_MIN")
    latency = os.environ.get("PROMOTION_MAX_P95_LATENCY_MS")
    if not margin and not latency:
        return None
    if not margin or not latency:
        raise ValueError("set both PROMOTION_MIN_MAE_IMPROVEMENT_MIN and PROMOTION_MAX_P95_LATENCY_MS, or neither")
    margin_value, latency_value = float(margin), float(latency)
    if margin_value < 0 or latency_value <= 0:
        raise ValueError("promotion margin must be non-negative and latency limit must be positive")
    return margin_value, latency_value


@dg.asset(deps=[trip_features], group_name="model", kinds={"redshift", "s3"}, pool="redshift")
def training_set(redshift: RedshiftData, artifacts: ArtifactBucket) -> dg.MaterializeResult:
    """Export the selected training window, later holdout, and training-only distance lookup as Parquet."""
    train_months = _months_sql(TRAIN_MONTHS)
    base = artifacts.uri(TRAINING_PREFIX)
    redshift.execute(
        _unload(
            "select trip_month, pickup_zone_id, dropoff_zone_id, pickup_hour, pickup_dow, duration_min "
            f"from staging.trip_features where trip_month in ({train_months})",
            f"{base}/train/",
        ),
        _unload(
            "select trip_month, pickup_zone_id, dropoff_zone_id, pickup_hour, pickup_dow, duration_min "
            f"from staging.trip_features where trip_month = '{HOLDOUT_MONTH}'",
            f"{base}/holdout/",
        ),
        _unload(
            "select pickup_zone_id, dropoff_zone_id, median(trip_distance) as est_distance_miles "
            f"from staging.stg_trips where trip_month in ({train_months}) "
            "and duration_min > 0 and duration_min <= 180 and trip_distance > 0 group by 1, 2",
            f"{base}/distances/",
        ),
    )
    counts = redshift.query(
        "select trip_month, count(*) as rows from staging.trip_features "
        f"where trip_month in ({train_months}, '{HOLDOUT_MONTH}') group by 1 order by 1"
    )
    return dg.MaterializeResult(
        metadata={
            "training_window": TRAINING_WINDOW,
            "holdout_month": HOLDOUT_MONTH,
            "rows": dg.MetadataValue.json({row["trip_month"]: int(row["rows"]) for row in counts}),
            "artifact_prefix": base,
        }
    )


@dg.asset(deps=[training_set], group_name="model", kinds={"mlflow"})
def trained_model(context: dg.AssetExecutionContext, artifacts: ArtifactBucket, tracking: MlflowTracking) -> dg.MaterializeResult:
    """Train v2 and register it; evaluation and the gate decide whether it becomes challenger."""
    train = artifacts.read_parquet(f"{TRAINING_PREFIX}/train/")
    distances = artifacts.read_parquet(f"{TRAINING_PREFIX}/distances/")
    contract = mlflow_contract()
    tracking.client()  # sets the pipeline experiment from the frozen contract
    with mlflow.start_run(run_name=f"v2 {TRAINING_WINDOW} to {HOLDOUT_MONTH}") as run:
        model = LightGBMModel().fit(train, distances)
        info = mlflow.pyfunc.log_model(
            name="model",
            python_model=model,
            signature=model_signature(),
            code_paths=[str(Path(tripmodel.__file__).parent)],
            registered_model_name=contract["registered_model"],
        )
        if not info.registered_model_version:
            raise RuntimeError("MLflow did not return a registered model version")
        client = tracking.client()
        client.set_model_version_tag(contract["registered_model"], info.registered_model_version, "dagster_run_id", context.run_id)
        client.set_model_version_tag(contract["registered_model"], info.registered_model_version, "training_window", TRAINING_WINDOW)
        client.set_model_version_tag(contract["registered_model"], info.registered_model_version, "holdout_month", HOLDOUT_MONTH)
        client.set_model_version_tag(contract["registered_model"], info.registered_model_version, "features_version", str(features_contract()["version"]))
        client.set_model_version_tag(contract["registered_model"], info.registered_model_version, "git_sha", os.environ.get("GIT_SHA", "unknown"))
    return dg.MaterializeResult(metadata={"model_version": info.registered_model_version, "mlflow_run_id": run.info.run_id})


@dg.asset(deps=[trained_model], group_name="model", kinds={"mlflow"})
def eval_report(context: dg.AssetExecutionContext, artifacts: ArtifactBucket, redshift: RedshiftData, tracking: MlflowTracking) -> dg.MaterializeResult:
    """Evaluate the candidate and the current comparison model on precisely the same holdout rows."""
    holdout = artifacts.read_parquet(f"{TRAINING_PREFIX}/holdout/")
    boroughs = {int(row["location_id"]): row["borough"] for row in redshift.query("select location_id, borough from ingest.taxi_zones")}
    candidate = _candidate(context, tracking)
    candidate_model = mlflow.pyfunc.load_model(f"models:/{mlflow_contract()['registered_model']}/{candidate.version}")
    candidate_metrics = evaluate(candidate_model.predict, holdout, boroughs)
    comparison = "v1 baseline"
    try:
        champion = tracking.client().get_model_version_by_alias(mlflow_contract()["registered_model"], "champion")
        champion_model = mlflow.pyfunc.load_model(f"models:/{mlflow_contract()['registered_model']}/{champion.version}")
        champion_metrics = evaluate(champion_model.predict, holdout, boroughs)
        comparison = f"champion v{champion.version}"
    except MlflowException:
        train = artifacts.read_parquet(f"{TRAINING_PREFIX}/train/")
        distances = artifacts.read_parquet(f"{TRAINING_PREFIX}/distances/")
        champion_metrics = evaluate(lambda frame: BaselineModel().fit(train, distances).predict(None, frame), holdout, boroughs)
    client = tracking.client()
    with mlflow.start_run(run_id=candidate.run_id):
        mlflow.log_metrics(candidate_metrics)
        mlflow.log_metric("champion_mae_min", champion_metrics["mae_min"])
    tags = {name: str(candidate_metrics[name]) for name in mlflow_contract()["metrics"] if name in candidate_metrics}
    tags["champion_mae_min"] = str(champion_metrics["mae_min"])
    for name, value in tags.items():
        client.set_model_version_tag(mlflow_contract()["registered_model"], candidate.version, name, value)
    return dg.MaterializeResult(
        metadata={
            "model_version": candidate.version,
            "comparison": comparison,
            **candidate_metrics,
            "champion_mae_min": champion_metrics["mae_min"],
            "mae_improvement_min": champion_metrics["mae_min"] - candidate_metrics["mae_min"],
        }
    )


@dg.asset_check(
    asset=eval_report,
    blocking=True,
    description="Candidate must improve holdout MAE by the decided margin and stay within the decided p95 latency budget.",
)
def beats_champion(context: dg.AssetCheckExecutionContext, tracking: MlflowTracking) -> dg.AssetCheckResult:
    """Fail closed until the student records numerical gate values, then enforce both requirements."""
    candidate = _candidate(context, tracking)
    tags = candidate.tags
    policy = _promotion_policy()
    mae = float(tags["mae_min"])
    reference = float(tags["champion_mae_min"])
    latency = float(tags["p95_latency_ms"])
    if policy is None:
        return dg.AssetCheckResult(
            passed=False,
            severity=dg.AssetCheckSeverity.ERROR,
            description="Measured candidate metrics are recorded, but no promotion margin and latency cap have been decided yet.",
            metadata={"mae_min": mae, "champion_mae_min": reference, "p95_latency_ms": latency},
        )
    margin, latency_limit = policy
    improvement = reference - mae
    passed = improvement >= margin and latency <= latency_limit
    return dg.AssetCheckResult(
        passed=passed,
        severity=dg.AssetCheckSeverity.ERROR,
        description="Candidate beat the comparison model within the latency budget." if passed else "Candidate did not satisfy the MAE-and-latency promotion policy.",
        metadata={
            "mae_min": mae,
            "champion_mae_min": reference,
            "mae_improvement_min": improvement,
            "required_mae_improvement_min": margin,
            "p95_latency_ms": latency,
            "max_p95_latency_ms": latency_limit,
        },
    )


@dg.asset(deps=[eval_report], group_name="model", kinds={"mlflow"})
def challenger(context: dg.AssetExecutionContext, tracking: MlflowTracking) -> dg.MaterializeResult:
    """Set only challenger, after the blocking beats_champion check has passed in this run."""
    candidate = _candidate(context, tracking)
    tracking.client().set_registered_model_alias(mlflow_contract()["registered_model"], "challenger", candidate.version)
    return dg.MaterializeResult(metadata={"alias": "challenger", "model_version": candidate.version})


train_model = dg.define_asset_job(
    "train_model",
    selection=(
        dg.AssetSelection.assets(training_set, trained_model, eval_report, challenger).without_checks()
        | dg.AssetSelection.checks(beats_champion)
    ),
)
