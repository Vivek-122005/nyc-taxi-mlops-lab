# 009: Temporal training and holdout window

Stage: S2 · Date: 2026-11-21 · Author: Vivek Vishnoi · Drafted by agent: yes

## Choice

Train on January through March 2024 and evaluate on April 2024. April remains untouched by feature selection and hyperparameter tuning.

## Rejected alternative

Randomly split all four months, or include April in model selection.

## Why

The service predicts future trips. A strictly later holdout better represents that deployment condition and avoids leaking future seasonal or operational patterns into training decisions.

## What would show this was wrong

Additional months show that a longer or rolling temporal window produces a more stable, lower-error model without hiding a meaningful regime change.
