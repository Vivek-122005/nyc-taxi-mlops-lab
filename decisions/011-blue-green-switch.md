# 011: Blue-green switch after idle smoke

Stage: S3 · Date: 2026-11-22 · Author: Vivek Vishnoi · Drafted by agent: yes

## Choice

CD deploys the new image tag only to the idle colour (`deploy/compose.web.yaml`), runs `deploy/web.sh smoke` on that colour (version provenance plus `/predict`), and only then calls `deploy/web.sh switch`. Rollback is a `workflow_dispatch` with `switch_only=true` (or `deploy/web.sh switch` to the other colour) without rebuilding.

## Rejected alternative

Switch traffic as soon as the idle container is healthy, or replace the live colour in place (rolling / recreate).

## Why

Smoke through Traefik pinned to the idle colour proves the new image answers `/version` with the expected git SHA and can predict before any rider sees it. Keeping the previous colour running makes rollback a weight flip instead of another deploy. In-place recreate would briefly take the only live colour down.

## What would show this was wrong

Smokes that pass while riders still see broken behaviour (missing Traefik route coverage), or rollbacks that need a full redeploy because the previous colour was removed.
