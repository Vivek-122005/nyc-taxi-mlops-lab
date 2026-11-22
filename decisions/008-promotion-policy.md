# 008: Challenger promotion policy

Stage: S2 · Date: 2026-11-21 · Author: Vivek Vishnoi · Drafted by agent: yes

## Choice

Evaluate a new LightGBM version on the April holdout against the current `champion`, or against the v1 baseline before a champion exists. It may become `challenger` only when it improves holdout MAE by at least **0.1 minutes** and stays within **50 ms** p95 single-prediction latency.

Numbers come from the first measured holdout (2024-04): candidate MAE ≈ 3.64 min vs baseline ≈ 3.96 min (Δ ≈ 0.32 min), p95 ≈ 3.7 ms. The 0.1 min margin keeps a clear win without requiring the full observed gap; 50 ms is well above measured latency and still protects interactive serving. Wired as `PROMOTION_MIN_MAE_IMPROVEMENT_MIN=0.1` and `PROMOTION_MAX_P95_LATENCY_MS=50` (GitHub Actions variables + platform compose).

## Rejected alternative

Promote a model from a notebook, or use an arbitrary initial MAE and latency threshold before measuring.

## Why

MAE measures the duration-prediction error the product cares about, while p95 latency protects the interactive serving path. Measuring the baseline and candidate first makes the numerical policy defensible rather than accidental.

## What would show this was wrong

Observed user experience, serving capacity, or error distribution shows MAE alone is insufficient, or the selected margin/latency limits either block useful models or allow regressions.
