# Runbook: restore the lab after an AWS Academy session ends

Owner: Vivek Vishnoi · Last run: not yet measured · Time to restore last run: not yet measured

## When to use it

The morning after a Learner Lab session ends, or when `scripts/health.sh` reports a stopped RDS instance, a paused Redshift cluster, unavailable hosts, or a stale status artifact.

## Before you start

1. Start the AWS Academy Learner Lab.
2. Refresh only the three temporary `AWS_*` values in the ignored `aws.env` file from **AWS Details**. Do not put them in GitHub, chat, commits, or this runbook.
3. Confirm the new session works: `make aws-check`.
4. Take the initial, read-only snapshot: `scripts/health.sh | tee /tmp/s4-health-before.txt`. Copy every `FAIL` and `WARN` line into the table below before making a change.

## Steps

Record observed elapsed time while each action runs. Do not replace `TBD` with estimates.

| # | Check (command) | Healthy looks like | If not: fix (command) | Took | Automated? |
| --- | --- | --- | --- | --- | --- |
| 1 | `scripts/health.sh` | `OK session`; host rows show `running`; runners are `online` | Start Lab first. Refresh `aws.env` only if the session row fails. Record every failing/warning row before continuing. | TBD | no — a person starts the Academy lab and refreshes its expiring session |
| 2 | `aws rds describe-db-instances --db-instance-identifier lab --query 'DBInstances[0].DBInstanceStatus' --output text` | `available` | `scripts/restore.sh` starts only a `stopped` instance and waits for `available`. Stop if it reports another state. | TBD | yes — only after an operator explicitly runs the script |
| 3 | `aws redshift describe-clusters --cluster-identifier lab --query 'Clusters[0].ClusterStatus' --output text` | `available` | `scripts/restore.sh` resumes only a `paused` cluster and waits for `available`. Stop if it reports another state. | TBD | yes — only after an operator explicitly runs the script |
| 4 | `scripts/health.sh` | app/platform hosts running; Dagster, MLflow and serving recover through their Docker restart policies once dependencies are available | Wait and rerun the health check. If a host/runner remains failed, inspect it over SSM; do not recreate it during an incident. | TBD | no — recovery is observed and diagnosed before any manual host action |
| 5 | `gh workflow run status.yaml` then `gh run watch` | green status workflow; its `lab-status` artifact reports RDS and Redshift `available` | Read the failed workflow log. Do not change pipeline checks merely to make the status workflow green. | TBD | no — explicit evidence after restoration |
| 6 | `scripts/health.sh` and the `/predict` line | exit code `0`; prediction names model alias `champion` | Follow the serving/promotion runbooks. Do not move MLflow aliases by hand. | TBD | no — requires a rider-facing proof |
| 7 | `aws sagemaker describe-notebook-instance --notebook-instance-name lab --query NotebookInstanceStatus --output text` | `Stopped` (or `InService` only while actively exploring) | Start it manually only for notebook work; stop it again when finished. | TBD | no — it is optional and incurs cost while running |

## Done when

`scripts/health.sh` exits `0`; `/predict` answers with `"alias": "champion"`; and a newly triggered green `status.yaml` workflow reports RDS and Redshift as `available`.

## What we automated, and what we left as a step

`scripts/restore.sh` is intentionally an explicit, idempotent restore operation: it can start RDS only from `stopped` and resume Redshift only from `paused`, then waits for both to be `available`. It leaves the Learner Lab start, temporary credential refresh, notebook start, incident diagnosis, status evidence, and any model/serving decision to a person. The final decision record for this boundary is still required before S4 can be signed off.
