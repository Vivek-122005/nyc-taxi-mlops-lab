# 007: Notebook and pipeline boundary

Stage: S2 · Date: 2026-11-21 · Author: Vivek Vishnoi · Drafted by agent: yes

## Choice

Use the SageMaker notebook for exploration, visualizations and model experimentation. Keep feature engineering, training, evaluation, MLflow registration and promotion to `challenger` in the repeatable Dagster pipeline.

## Rejected alternative

Train and register models directly from an exploratory notebook.

## Why

Exploration benefits from rapid iteration, while the deployed model requires a traceable data window, held-out evaluation, contract checks and a gate that runs consistently without manual alias changes.

## What would show this was wrong

The pipeline becomes unable to express a required, repeatable training step, or notebook experiments repeatedly need the same controlled operation and show it should become a pipeline asset.
