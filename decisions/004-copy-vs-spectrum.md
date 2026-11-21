# 004: Monthly trip-data access strategy

Stage: S1 · Date: 2026-11-21 · Author: Vivek Vishnoi · Drafted by agent: yes

## Choice

Copy each contracted monthly Parquet file into `ingest.raw_trips` in Redshift. The load will be idempotent, so rerunning a month replaces that month's source file rows rather than duplicating them.

## Rejected alternative

Use Redshift Spectrum to query the Parquet files in place in the instructor data bucket.

## Why

Persistent Redshift tables make staging, data-quality checks, and later data preparation local to the warehouse. This avoids repeatedly scanning remote files during those downstream operations and provides a stable raw-table boundary.

## What would show this was wrong

The copied raw table becomes too expensive or slow to maintain relative to the limited number of source-file queries, or Spectrum's external-table access proves sufficient for the required transformations and marts.
