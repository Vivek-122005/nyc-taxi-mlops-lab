# shellcheck shell=bash
# Load repo-root aws.env into the current shell.
# Source this file; do not execute it.
#
#   # from a lab script:
#   # shellcheck source=scripts/load-aws-env.sh
#   source "$root/scripts/load-aws-env.sh"
#
#   # from your laptop:
#   set -a && source ./aws.env && set +a
#
# Does not override variables already set in the environment (including empty-but-exported
# is overridden only when the current value is empty and aws.env has a non-empty value).
# Never prints secret values.

_lab_aws_env_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
_lab_aws_env_file="${LAB_AWS_ENV:-$_lab_aws_env_root/aws.env}"

if [[ ! -f "$_lab_aws_env_file" ]]; then
  if [[ "${LAB_AWS_ENV_REQUIRED:-}" == 1 ]]; then
    echo "missing credentials file: $_lab_aws_env_file" >&2
    echo "copy aws.env.example → aws.env, paste Learner Lab AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY / AWS_SESSION_TOKEN, then re-run." >&2
    return 1 2>/dev/null || exit 1
  fi
else
  while IFS= read -r _lab_line || [[ -n "$_lab_line" ]]; do
    [[ "$_lab_line" =~ ^[[:space:]]*# ]] && continue
    [[ "$_lab_line" =~ ^[[:space:]]*$ ]] && continue
    if [[ "$_lab_line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
      _lab_key="${BASH_REMATCH[1]}"
      _lab_val="${BASH_REMATCH[2]}"
      if [[ "$_lab_val" =~ ^\"(.*)\"$ ]] || [[ "$_lab_val" =~ ^\'(.*)\'$ ]]; then
        _lab_val="${BASH_REMATCH[1]}"
      fi
      if [[ -z "${!_lab_key:-}" && -n "$_lab_val" ]]; then
        export "${_lab_key}=${_lab_val}"
      fi
    fi
  done <"$_lab_aws_env_file"
fi

# Keep region defaults consistent even when aws.env is incomplete.
export AWS_REGION="${AWS_REGION:-us-east-1}"
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-$AWS_REGION}"
export AWS_PAGER="${AWS_PAGER:-}"

unset _lab_aws_env_root _lab_aws_env_file _lab_line _lab_key _lab_val
