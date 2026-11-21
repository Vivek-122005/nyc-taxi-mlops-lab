"""S1: the schema_contract check on trip_files.

Compare the landed file's Parquet footer (the DataBucket resource reads it) with
contracts/trips.schema.yaml, before raw_trips copies anything. contracts/platform.yaml says this check
is blocking. The schema is exact and ordered because Redshift Parquet COPY maps fields by position.
"""

from dataclasses import asdict

import dagster as dg

from ..contracts import trips_schema
from ..partitions import trip_months
from ..resources import DataBucket
from .trip_files import trip_files


@dg.asset_check(
    asset=trip_files,
    partitions_def=trip_months,
    blocking=True,
    description="The landed Parquet footer exactly matches contracts/trips.schema.yaml.",
)
def schema_contract(context: dg.AssetCheckExecutionContext, data_bucket: DataBucket) -> dg.AssetCheckResult:
    """Fail before COPY when a file's column name, physical type, or order differs from the contract."""
    expected = trips_schema()
    actual = data_bucket.footer(context.partition_key).columns
    passed = actual == expected
    return dg.AssetCheckResult(
        passed=passed,
        severity=dg.AssetCheckSeverity.ERROR,
        description=(
            "Parquet footer matches the frozen trip schema."
            if passed
            else "Parquet footer differs from the frozen trip schema; COPY is blocked."
        ),
        metadata={
            "expected_columns": dg.MetadataValue.json([asdict(column) for column in expected]),
            "actual_columns": dg.MetadataValue.json([asdict(column) for column in actual]),
        },
    )
