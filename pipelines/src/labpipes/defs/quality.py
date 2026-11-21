"""S1: data-quality checks on stg_trips (nulls, ranges, duplicates, row counts).

Raw records remain available for investigation. This check reports measurable anomalies as a warning,
so it never blocks the mart until the student chooses evidence-backed thresholds and gate strictness.
"""

import dagster as dg

from ..contracts import trips_schema
from ..partitions import check_month, source_file, trip_months
from ..resources import RedshiftData
from .staging import stg_trips


@dg.asset_check(
    asset=stg_trips,
    partitions_def=trip_months,
    description="Observed null, range, amount, passenger, and reporting-period anomalies for one month.",
)
def stg_trip_anomalies(context: dg.AssetCheckExecutionContext, redshift: RedshiftData) -> dg.AssetCheckResult:
    """Report anomaly counts without discarding raw or staging records or choosing a blocking threshold."""
    month = check_month(context.partition_key)
    file = source_file(month)
    row = redshift.query(
        "select count(*) as rows, "
        "sum(case when pickup_at is null or dropoff_at is null then 1 else 0 end) as null_timestamps, "
        "sum(case when pickup_zone_id is null or dropoff_zone_id is null then 1 else 0 end) as null_zones, "
        "sum(case when passenger_count is null then 1 else 0 end) as null_passenger_count, "
        "sum(case when trip_distance is null then 1 else 0 end) as null_trip_distance, "
        "sum(case when fare_amount is null or total_amount is null then 1 else 0 end) as null_amounts, "
        "sum(case when duration_min <= 0 then 1 else 0 end) as nonpositive_duration, "
        "sum(case when passenger_count = 0 then 1 else 0 end) as zero_passengers, "
        "sum(case when fare_amount < 0 or total_amount < 0 then 1 else 0 end) as negative_amounts, "
        "sum(case when pickup_at < date_trunc('month', to_date('" + month + "-01', 'YYYY-MM-DD')) "
        "or pickup_at >= dateadd(month, 1, date_trunc('month', to_date('" + month + "-01', 'YYYY-MM-DD'))) "
        "then 1 else 0 end) as pickup_outside_month, "
        "min(trip_distance) as min_trip_distance, max(trip_distance) as max_trip_distance "
        "from staging.stg_trips where trip_month = '" + month + "'"
    )[0]
    source_columns = ", ".join(column.name.lower() for column in trips_schema())
    exact_duplicate_rows = redshift.scalar(
        "select coalesce(sum(group_rows - 1), 0) from ("
        "select count(*) as group_rows from ingest.raw_trips "
        f"where source_file = '{file}' group by {source_columns} having count(*) > 1"
        ") exact_duplicate_groups"
    )
    numeric = [
        "null_timestamps",
        "null_zones",
        "null_passenger_count",
        "null_trip_distance",
        "null_amounts",
        "nonpositive_duration",
        "zero_passengers",
        "negative_amounts",
        "pickup_outside_month",
    ]
    anomaly_count = sum(int(row[name] or 0) for name in numeric) + int(exact_duplicate_rows or 0)
    return dg.AssetCheckResult(
        passed=anomaly_count == 0,
        severity=dg.AssetCheckSeverity.WARN,
        description=f"{anomaly_count} observed anomaly value(s); warning-only until thresholds are decided.",
        metadata={
            "rows": dg.MetadataValue.int(int(row["rows"])),
            **{name: dg.MetadataValue.int(int(row[name] or 0)) for name in numeric},
            "exact_19_column_duplicate_rows": dg.MetadataValue.int(int(exact_duplicate_rows or 0)),
            "min_trip_distance": row["min_trip_distance"],
            "max_trip_distance": row["max_trip_distance"],
        },
    )
