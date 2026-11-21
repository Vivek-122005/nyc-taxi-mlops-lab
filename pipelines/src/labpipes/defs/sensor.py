"""S1: the S3 sensor (and the job it starts).

Watch trips/ in the data bucket (DataBucket.trip_files). When a month's file appears or changes, add
the month to the trip_months partitions and request a run that goes from trip_files to zone_hour_stats.
Patterns: pipelines/reference/patterns.py.
"""

import json

import dagster as dg

from ..partitions import trip_months
from ..resources import DataBucket
from .marts import zone_hour_stats
from .quality import stg_trip_anomalies
from .raw_trips import raw_trips
from .schema_check import schema_contract
from .staging import stg_trips
from .trip_files import trip_files
from .zones import taxi_zones


ingest_month = dg.define_asset_job(
    "ingest_month",
    selection=(
        dg.AssetSelection.assets(trip_files, raw_trips, stg_trips, taxi_zones, zone_hour_stats).without_checks()
        | dg.AssetSelection.checks(schema_contract, stg_trip_anomalies)
    ),
)


@dg.sensor(job=ingest_month, minimum_interval_seconds=60)
def trip_files_sensor(context: dg.SensorEvaluationContext, data_bucket: DataBucket):
    """Request a partitioned ingest run once per new or changed source object, keyed by its ETag."""
    seen = json.loads(context.cursor or "{}")
    found = data_bucket.trip_files()
    changed = [file for file in found if seen.get(file.month) != file.etag]
    if not changed:
        return dg.SkipReason("no new or changed trip files")
    updated = {**seen, **{file.month: file.etag for file in found}}
    months = [file.month for file in changed]
    return dg.SensorResult(
        run_requests=[dg.RunRequest(partition_key=file.month, run_key=f"{file.month}:{file.etag}") for file in changed],
        dynamic_partitions_requests=[trip_months.build_add_request(months)],
        cursor=json.dumps(updated, sort_keys=True),
    )
