#!/usr/bin/env bash
# Load aws.env and prove STS works. Clear handoff when keys are missing or expired.
#
#   make aws-check
#   scripts/aws-check.sh
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
if [[ ! -f "$root/aws.env" ]]; then
  echo "missing $root/aws.env — run: make aws-env, then paste Learner Lab session keys" >&2
  exit 1
fi
# shellcheck source=scripts/load-aws-env.sh
source "$root/scripts/load-aws-env.sh"

for v in AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN; do
  [[ -n "${!v:-}" ]] || {
    echo "$v is empty in $root/aws.env — paste it from Learner Lab > AWS Details" >&2
    exit 1
  }
done

if ! arn=$(aws sts get-caller-identity --query Arn --output text 2>/dev/null); then
  echo "AWS rejected these credentials (expired session?). Update the three AWS_* lines in $root/aws.env after Start Lab." >&2
  exit 1
fi
echo "OK $arn"
echo "buckets: LAB_DATA_BUCKET=${LAB_DATA_BUCKET:-?} LAB_ARTIFACT_BUCKET=${LAB_ARTIFACT_BUCKET:-?}"
