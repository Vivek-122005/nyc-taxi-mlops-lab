"""S1: the raw_trips asset.

One partition per month (partitions.trip_months), depending on trip_files. COPY the month's file into
Redshift with the LabRole attached to the cluster (`iam_role default`), so that re-running a month never
duplicates its rows. The landing columns come from contracts/trips.schema.yaml. Source rows stay
unchanged; the only added value is source_file provenance.
"""

import dagster as dg

from ..contracts import redshift_columns, trips_schema
from ..partitions import check_month, source_file, trip_months
from ..resources import DataBucket, RedshiftData


@dg.asset(partitions_def=trip_months, deps=["trip_files"], group_name="ingest", kinds={"redshift"}, pool="redshift")
def raw_trips(context: dg.AssetExecutionContext, redshift: RedshiftData, data_bucket: DataBucket) -> dg.MaterializeResult:
    """COPY a month idempotently, using a temporary Parquet-shaped table then add source provenance."""
    month = check_month(context.partition_key)
    file = source_file(month)
    schema = trips_schema()
    columns = redshift_columns(schema)
    column_names = ", ".join(column.name.lower() for column in schema)
    redshift.execute(
        "create schema if not exists ingest",
        "create table if not exists ingest.raw_trips "
        f"({columns}, source_file varchar(64) not null) "
        "diststyle auto sortkey (source_file, tpep_pickup_datetime)",
        f"create temp table trip_load ({columns})",
        f"copy trip_load from '{data_bucket.trip_uri(month)}' iam_role default format as parquet",
        f"delete from ingest.raw_trips where source_file = '{file}'",
        "insert into ingest.raw_trips "
        f"({column_names}, source_file) select {column_names}, '{file}' from trip_load",
    )
    rows = redshift.scalar(f"select count(*) from ingest.raw_trips where source_file = '{file}'")
    return dg.MaterializeResult(
        metadata={
            "rows": dg.MetadataValue.int(int(rows)),
            "source": data_bucket.trip_uri(month),
            "source_file": file,
        }
    )
