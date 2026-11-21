#!/usr/bin/env bash
# Register a lab host as a self-hosted GitHub Actions runner over SSM.
# The runner uses the host's LabInstanceProfile, never static Learner Lab credentials.
set -euo pipefail
export AWS_REGION=us-east-1 AWS_DEFAULT_REGION=us-east-1 AWS_PAGER=""

runner_version="2.338.2"
role="${1:-app}"
token_mode="${2:-clipboard}"
case "$role" in
  app | platform | llm) ;;
  *) echo "usage: $0 [app|platform|llm]" >&2; exit 2 ;;
esac
case "$token_mode" in
  clipboard | --manual-token) ;;
  *) echo "usage: $0 [app|platform|llm] [--manual-token]" >&2; exit 2 ;;
esac

command -v gh >/dev/null || { echo "GitHub CLI (gh) is required" >&2; exit 1; }
command -v aws >/dev/null || { echo "AWS CLI v2 is required" >&2; exit 1; }

root="$(cd "$(dirname "$0")/.." && pwd)"
repo="$(gh repo view --json nameWithOwner -q .nameWithOwner)"
instance_id="$(terraform -chdir="$root/infra/live" output -raw "${role}_instance_id")"
label="lab-${role}"
archive="actions-runner-linux-arm64-${runner_version}.tar.gz"
archive_url="https://github.com/actions/runner/releases/download/v${runner_version}/${archive}"

# GitHub registration tokens expire within an hour. Do not put them in SSM Run Command parameters:
# command history may be visible to account administrators.
token_fingerprint=""
if [[ "$token_mode" == "clipboard" ]]; then
  command -v pbcopy >/dev/null || {
    echo "pbcopy is required so the registration token is never printed; run this from macOS." >&2
    exit 1
  }
  registration_token="$(gh api --method POST "repos/${repo}/actions/runners/registration-token" --jq .token)"
  token_fingerprint="$(printf '%s' "$registration_token" | shasum -a 256 | awk '{print $1}')"
  printf '%s' "$registration_token" | pbcopy
  unset registration_token
fi

prepare_command=$(cat <<EOF
set -euo pipefail
install -d -o runner -g runner /opt/actions-runner
cd /opt/actions-runner
if [[ ! -x ./config.sh || ! -x ./svc.sh ]]; then
  curl --fail --location --silent --show-error --output '$archive' '$archive_url'
  tar xzf '$archive'
  rm -f '$archive'
  chown -R runner:runner /opt/actions-runner
fi
EOF
)

# `commands` is an SSM StringList. Sending its multi-line program through AWS CLI shorthand makes
# characters such as `[` part of the CLI's own syntax. Base64 gives SSM one safe command instead.
encoded_prepare_command="$(printf '%s' "$prepare_command" | base64 | tr -d '\n')"

command_id="$(aws ssm send-command \
  --instance-ids "$instance_id" \
  --document-name AWS-RunShellScript \
  --comment "Install GitHub Actions runner $runner_version for $label" \
  --parameters "commands=echo $encoded_prepare_command | base64 --decode | bash" \
  --query 'Command.CommandId' --output text)"

for _ in {1..30}; do
  status="$(aws ssm get-command-invocation --command-id "$command_id" --instance-id "$instance_id" --query Status --output text 2>/dev/null || true)"
  case "$status" in
    Success) break ;;
    Failed | Cancelled | TimedOut)
      aws ssm get-command-invocation --command-id "$command_id" --instance-id "$instance_id" --query '[Status,StandardErrorContent]' --output text >&2 || true
      exit 1
      ;;
  esac
  sleep 2
done

[[ "${status:-}" == "Success" ]] || { echo "runner installation did not finish in time" >&2; exit 1; }
token_check=""
if [[ -n "$token_fingerprint" ]]; then
  token_check="actual_fingerprint=\$(printf '%s' \"\$token\" | sha256sum | awk '{print \$1}')
[[ \"\$actual_fingerprint\" == \"$token_fingerprint\" ]] || { echo 'The pasted token did not match the new token in your clipboard.' >&2; exit 1; }"
fi
register_command=$(cat <<EOF
set -euo pipefail
printf 'Paste the GitHub registration token from your clipboard, then press Enter: '
IFS= read -r -s token
echo
[[ -n "\$token" ]] || { echo 'No registration token was received.' >&2; exit 1; }
$token_check
cd /opt/actions-runner
sudo runuser -u runner -- ./config.sh --unattended --url https://github.com/$repo --token "\$token" --labels $label --name "\$(hostname)" --replace
unset token
sudo ./svc.sh install runner
sudo ./svc.sh start
EOF
)
encoded_register_command="$(printf '%s' "$register_command" | base64 | tr -d '\n')"
if [[ "$token_mode" == "clipboard" ]]; then
  echo "Registering https://github.com/$repo with label $label. The new short-lived token is in your clipboard."
else
  echo "Registering https://github.com/$repo with label $label. In GitHub: Settings > Actions > Runners > New self-hosted runner; copy only the fresh token after --token, then paste it into SSM."
fi
aws ssm start-session --target "$instance_id" --document-name AWS-StartInteractiveCommand \
  --parameters "command=echo $encoded_register_command | base64 --decode | bash"
