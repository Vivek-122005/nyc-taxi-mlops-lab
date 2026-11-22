# scripts/

## Credentials (one file)

Learner Lab session keys expire. Keep them in repo-root `aws.env` (gitignored; copy from `aws.env.example`):

```bash
make aws-env          # creates aws.env once
# paste AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY / AWS_SESSION_TOKEN from AWS Details
make aws-check        # STS must succeed before AWS steps
```

`load-aws-env.sh` is sourced by the scripts below, so filling `aws.env` is enough — you do not need to re-export by hand each time. Override path with `LAB_AWS_ENV=/path/to/file` if needed.

## Tools

- `register-runner.sh [app|platform|llm]`: register a host as a self-hosted runner over SSM (S0 builds this).
- `gh-secrets.sh`: copy session credentials into GitHub secrets, only for workflows that call AWS from GitHub-hosted runners (S10's destroy). CI and CD don't need it.
- `catch-up.sh N`: rebuild infrastructure and pipeline state for `stage-N`.
- `dagster-run.sh JOB [--partition YYYY-MM] [--wait]`: start a Dagster job on the platform host via SSM.
- `health.sh` (S4, given): read-only, one line per piece of the lab, exit 0 only when all are OK. Start every morning and every incident with it.
- `verify-teardown.sh` (S10, given): every billable thing left in us-east-1 and us-west-2, one line each; you're done when it prints nothing.
- `restore.sh` (your S4 automation, in the reference): bring the lab back after a session end.
