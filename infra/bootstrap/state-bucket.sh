#!/usr/bin/env bash
# Create the Terraform state bucket (once per Learner Lab account) and write infra/live/backend.hcl.
#
# Fill aws.env (from aws.env.example) or export the three session vars, then:
#   infra/bootstrap/state-bucket.sh
#   terraform -chdir=infra/live init -backend-config=backend.hcl
#
# The bucket is made with the CLI, outside Terraform: Terraform can't manage its own state bucket,
# and the Learner Lab SCP breaks aws_s3_bucket anyway. Locking uses S3's native lockfile
# (use_lockfile), so no DynamoDB table. Safe to re-run: it adopts an existing bucket.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
# shellcheck source=scripts/load-aws-env.sh
source "$root/scripts/load-aws-env.sh"

account=$(aws sts get-caller-identity --query Account --output text) ||
  { echo "AWS credentials missing or expired: paste them into $root/aws.env (Learner Lab > AWS Details)" >&2; exit 1; }
bucket="lab-tfstate-${account}"

if aws s3api head-bucket --bucket "$bucket" 2>/dev/null; then
  echo "state bucket $bucket exists"
else
  aws s3api create-bucket --bucket "$bucket" --region us-east-1 >/dev/null
  echo "created state bucket $bucket"
fi
aws s3api put-public-access-block --bucket "$bucket" --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
aws s3api put-bucket-versioning --bucket "$bucket" --versioning-configuration Status=Enabled 2>/dev/null ||
  echo "warning: could not enable versioning; state history won't be kept" >&2
aws s3api put-bucket-tagging --bucket "$bucket" --tagging 'TagSet=[{Key=project,Value=mlops-lab}]'

cat >"$here/../live/backend.hcl" <<EOF
# Written by infra/bootstrap/state-bucket.sh. Gitignored: it names your account.
bucket       = "$bucket"
key          = "lab/terraform.tfstate"
region       = "us-east-1"
use_lockfile = true
encrypt      = true
EOF
echo "wrote infra/live/backend.hcl; next: terraform -chdir=infra/live init -backend-config=backend.hcl"
