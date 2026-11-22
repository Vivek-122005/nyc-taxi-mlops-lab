# 012: Operator-triggered restore script (not a boot hook)

Stage: S4 · Date: 2026-11-22 · Author: Vivek Vishnoi · Drafted by agent: yes

## Choice

Automate only the deliberate overnight shutdowns with `scripts/restore.sh`: start RDS when it is `stopped`, resume Redshift when it is `paused`, wait until both are `available`. Leave Learner Lab Start Lab, `aws.env` refresh, notebook start, host/runner diagnosis, status evidence, and any serving/model action as documented runbook steps a person runs.

## Rejected alternative

A platform-host boot service (`restart: unless-stopped`) that starts RDS/Redshift whenever the host comes back, or a broader script that also starts the notebook and restarts containers.

## Why

AWS Academy Start Lab already brings EC2 hosts back; Docker restart policies recover Dagster, MLflow and serving once RDS is up. Boot-time automation cannot refresh expiring Learner Lab credentials, and auto-starting the notebook burns budget while exploration is optional. An explicit script keeps restore idempotent and refuses unexpected states (anything other than stopped/starting/available for RDS, paused/resuming/available for Redshift), so a machine never "fixes" a half-failed or manually paused resource on its own.

## What would show this was wrong

Repeated mornings where hosts are up but nobody remembers to run `restore.sh` and riders stay down for longer than a boot hook would have taken; or restore acting on the wrong state (e.g. starting a failed/modifying instance) and making an incident worse.
