# 010: Serving picks up a new champion via reload

Stage: S3 · Date: 2026-11-22 · Author: Vivek Vishnoi · Drafted by agent: yes

## Choice

Serving loads `models:/trip-duration@<alias>` at start-up, and after a promotion the workflow calls `POST /reload` on `serving-champion` (via `deploy/web.sh reload champion`). Riders keep getting predictions from the previously loaded model until the new version finishes loading; then the in-process reference swaps.

## Rejected alternative

Restart the serving container (or redeploy the compose stack) every time the champion alias moves.

## Why

`/reload` is already in the serving contract and keeps the container healthy while the new model warms up. A full restart would drop in-flight requests and add multi-second downtime for every promotion. The promote workflow already runs on the app host, so an explicit reload after the alias move is a single, auditable step.

## What would show this was wrong

Reloads that leave the old version answering after a successful alias move, OOM or long stalls during in-process load, or promotions that need a compose redeploy anyway for unrelated config.
