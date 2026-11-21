"""S2: the feature_contract check on trip_features.

contracts/features.yaml lists the model's inputs, label and the post-trip columns that must never be
inputs; contracts/mlflow.yaml says this check blocks. It checks exact column names, types and order,
then checks the frozen value ranges. Gameday E1 will test it.
"""

import dagster as dg

from ..contracts import features_contract
from ..partitions import check_month, trip_months
from ..resources import RedshiftData
from .features import trip_features


def expected_columns() -> list[tuple[str, str]]:
    """The exact ordered table boundary from the frozen feature contract."""
    contract = features_contract()
    return [(item["name"], item["type"]) for item in [*contract["keys"], *contract["inputs"], contract["label"]]]


@dg.asset_check(
    asset=trip_features,
    partitions_def=trip_months,
    blocking=True,
    description="trip_features exactly follows contracts/features.yaml and its allowed ranges.",
)
def feature_contract(context: dg.AssetCheckExecutionContext, redshift: RedshiftData) -> dg.AssetCheckResult:
    """Block training on a leaked, reshaped, or out-of-range feature partition."""
    month = check_month(context.partition_key)
    actual_rows = redshift.query(
        "select column_name, data_type, character_maximum_length from information_schema.columns "
        "where table_schema = 'staging' and table_name = 'trip_features' order by ordinal_position"
    )
    actual = [
        (row["column_name"], "char(7)" if row["data_type"] == "character" and row["character_maximum_length"] == 7 else row["data_type"])
        for row in actual_rows
    ]
    expected = expected_columns()
    contract = features_contract()
    ranges = {item["name"]: item["range"] for item in [*contract["inputs"], contract["label"]]}
    invalid_exprs = []
    for name, bounds in ranges.items():
        low, high = bounds
        lower = f"{name} <= {low}" if name == contract["label"]["name"] and contract["label"].get("exclusive_min") else f"{name} < {low}"
        invalid_exprs.append(f"sum(case when {lower} or {name} > {high} then 1 else 0 end) as {name}_outside_range")
    counts = redshift.query(
        "select count(*) as rows, " + ", ".join(invalid_exprs) + " from staging.trip_features " + f"where trip_month = '{month}'"
    )[0]
    bad = sum(int(counts[f"{name}_outside_range"] or 0) for name in ranges)
    matches = actual == expected
    return dg.AssetCheckResult(
        passed=matches and bad == 0,
        severity=dg.AssetCheckSeverity.ERROR,
        description="Feature schema and ranges match the frozen contract." if matches and bad == 0 else "Feature schema or ranges violate the frozen contract.",
        metadata={
            "rows": dg.MetadataValue.int(int(counts["rows"])),
            "expected_columns": dg.MetadataValue.json(expected),
            "actual_columns": dg.MetadataValue.json(actual),
            **{f"{name}_outside_range": dg.MetadataValue.int(int(counts[f"{name}_outside_range"] or 0)) for name in ranges},
        },
    )
