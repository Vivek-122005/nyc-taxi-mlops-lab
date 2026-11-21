# 008: Challenger promotion policy

Stage: S2 · Date: 2026-11-21 · Author: Vivek Vishnoi · Drafted by agent: yes

## Choice

Evaluate a new LightGBM version on the April holdout against the current `champion`, or against the v1 baseline before a champion exists. It may become `challenger` only when it improves holdout MAE by an agreed margin and stays within an agreed p95 single-prediction latency limit.

The exact margin and latency limit will be set only after v1 and v2 measurements are recorded in MLflow. Until then, the blocking gate fails closed and no alias moves.

## Rejected alternative

Promote a model from a notebook, or use an arbitrary initial MAE and latency threshold.

## Why

MAE measures the duration-prediction error the product cares about, while p95 latency protects the interactive serving path. Measuring the baseline and candidate first makes the numerical policy defensible rather than accidental.

## What would show this was wrong

Observed user experience, serving capacity, or error distribution shows MAE alone is insufficient, or the selected margin/latency limits either block useful models or allow regressions.
