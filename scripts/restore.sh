#!/usr/bin/env bash
# Restore the state deliberately left down at the end of a Learner Lab session.
#
#   scripts/restore.sh
#
# This is deliberately an operator-triggered command, not a boot hook. It only starts the RDS
# instance and resumes the Redshift cluster when their states show they were intentionally stopped.
# It never starts the SageMaker notebook (exploration is optional and billable), restarts hosts, or
# changes application/model state. AWS Academy's Start Lab brings the EC2 hosts back itself.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/load-aws-env.sh
source "$root/scripts/load-aws-env.sh"

rds_id="${RDS_INSTANCE_ID:-lab}"
redshift_id="${REDSHIFT_CLUSTER_ID:-lab}"
poll_seconds="${RESTORE_POLL_SECONDS:-15}"
timeout_seconds="${RESTORE_TIMEOUT_SECONDS:-1200}"

die() {
  echo "restore: $*" >&2
  exit 1
}

[[ "$poll_seconds" =~ ^[1-9][0-9]*$ ]] || die "RESTORE_POLL_SECONDS must be a positive integer"
[[ "$timeout_seconds" =~ ^[1-9][0-9]*$ ]] || die "RESTORE_TIMEOUT_SECONDS must be a positive integer"

if ! aws sts get-caller-identity >/dev/null 2>&1; then
  die "AWS credentials are missing or expired. Refresh only $root/aws.env from Learner Lab > AWS Details, then re-run."
fi

rds_state() {
  aws rds describe-db-instances --db-instance-identifier "$rds_id" \
    --query 'DBInstances[0].DBInstanceStatus' --output text
}

redshift_state() {
  aws redshift describe-clusters --cluster-identifier "$redshift_id" \
    --query 'Clusters[0].ClusterStatus' --output text
}

wait_for() { # NAME TARGET COMMAND...
  local name=$1 target=$2 started=$SECONDS state
  shift 2
  while :; do
    state=$("$@") || die "could not read $name state while waiting"
    if [[ "$state" == "$target" ]]; then
      printf 'OK    %-12s %s after %ss\n' "$name" "$state" "$((SECONDS - started))"
      return
    fi
    if ((SECONDS - started >= timeout_seconds)); then
      die "$name is still $state after ${timeout_seconds}s; stop here and inspect it in AWS before retrying"
    fi
    printf 'WAIT  %-12s %s\n' "$name" "$state"
    sleep "$poll_seconds"
  done
}

rds=$(rds_state) || die "could not read RDS instance $rds_id"
case "$rds" in
  available) printf 'OK    %-12s already available\n' rds ;;
  stopped)
    printf 'START %-12s stopped -> starting\n' rds
    aws rds start-db-instance --db-instance-identifier "$rds_id" >/dev/null
    ;;
  starting) printf 'WAIT  %-12s already starting\n' rds ;;
  *) die "RDS is $rds; this script only acts on stopped/starting/available states" ;;
esac

redshift=$(redshift_state) || die "could not read Redshift cluster $redshift_id"
case "$redshift" in
  available) printf 'OK    %-12s already available\n' redshift ;;
  paused)
    printf 'START %-12s paused -> resuming\n' redshift
    aws redshift resume-cluster --cluster-identifier "$redshift_id" >/dev/null
    ;;
  resuming) printf 'WAIT  %-12s already resuming\n' redshift ;;
  *) die "Redshift is $redshift; this script only acts on paused/resuming/available states" ;;
esac

# Both start calls are made before waiting, so RDS and Redshift recover concurrently.
wait_for rds available rds_state
wait_for redshift available redshift_state

echo "INFO  notebook     left unchanged (stopped is healthy; start it manually only for exploration)"
echo "INFO  hosts        AWS Academy Start Lab owns EC2 host start-up; Docker restart policies bring their stacks back"
echo "INFO  next         run scripts/health.sh, then gh workflow run status.yaml once health is OK"
