# 006: Initial data-quality gate policy

Stage: S1 · Date: 2026-11-21 · Author: Vivek Vishnoi · Drafted by agent: yes

## Choice

Keep the exact Parquet schema contract blocking before COPY. Preserve all raw rows and initially report staging anomalies as warnings: nulls, non-positive durations, zero passenger counts, negative monetary amounts, pickup timestamps outside the partition month, exact 19-column duplicate rows, and observed trip-distance bounds.

The implementation has no numeric anomaly threshold and does not deduplicate on a candidate business key yet. Those values remain configurable until Redshift measurements and the business semantics of a duplicate have been reviewed.

## Rejected alternative

Silently drop anomalous rows, or block a month using an arbitrary initial percentage or distance cutoff.

## Why

The source profile found legitimate-looking null-bearing fields alongside extreme values. A schema change is unambiguously unsafe for positional Parquet COPY, while the operational meaning of an anomalous value and its acceptable rate requires evidence from the warehouse and an agreed business rule.

## What would change this

Measured Redshift anomaly counts, an agreed candidate business key, and an agreed effect of a failed quality gate can establish explicit thresholds and determine which checks should become blocking before the mart is rebuilt.
