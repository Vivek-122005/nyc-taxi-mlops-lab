# 005: Warehouse distribution and sort layout

Stage: S1 · Date: 2026-11-21 · Author: Vivek Vishnoi · Drafted by agent: yes

## Choice

Use `DISTSTYLE AUTO` for `ingest.raw_trips` and `staging.stg_trips`; use `DISTSTYLE ALL` for the small `ingest.taxi_zones` lookup. Sort raw trips by `(source_file, tpep_pickup_datetime)` and staging trips by `pickup_at`.

## Rejected alternative

Use a skewed categorical source field such as `VendorID`, `RatecodeID`, or `payment_type` as the distribution key.

## Why

The warehouse is currently one `ra3.large` node, so distribution does not improve inter-node placement today. The source profile shows 75.6% of rows use one vendor and 85.7% use one rate code, making those poor future distribution candidates. `source_file` supports idempotent monthly replacement, while time ordering supports staging queries; the tiny zone lookup is practical to replicate.

## What would show this was wrong

An increase to multiple Redshift nodes or measured query plans show repeated redistribution or scan cost that an explicit distribution or alternate sort key reliably improves.
