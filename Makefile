# make check = the grader's static checks. Needs uv, terraform and make; every other tool runs
# through uvx at a pinned version, except promtool and alloy (Docker images: skipped with a note where
# Docker isn't running). CI runs exactly this, with Docker.
.DEFAULT_GOAL := help
.PHONY: help check check-contracts lint lint-python lint-shell lint-workflows lint-terraform lint-observability test test-app test-pipelines test-serving test-mcp agent-check aws-env aws-check s2-next

UVX := uvx --quiet
RUFF := $(UVX) ruff@0.16.10
SHELLCHECK := $(UVX) --from shellcheck-py==0.11.0.1 shellcheck
ACTIONLINT := $(UVX) --from actionlint-py==1.7.12.25 actionlint
OPENAPI := $(UVX) openapi-spec-validator==0.9.0
TF_DIRS := $(sort $(dir $(wildcard infra/modules/*/*.tf infra/live/*.tf)))
WORKFLOWS := $(wildcard .github/workflows/*.yaml .github/workflows/*.yml)

help: ## list targets
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-16s %s\n", $$1, $$2}'

aws-env: ## create gitignored aws.env from aws.env.example if missing
	@if [[ -f aws.env ]]; then echo "aws.env already exists (edit the three AWS_* session lines after Start Lab)"; \
	else cp aws.env.example aws.env && chmod 600 aws.env && echo "created aws.env — paste Learner Lab AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY / AWS_SESSION_TOKEN"; fi

aws-check: ## load aws.env and verify STS (clear handoff if expired)
	@scripts/aws-check.sh

s2-next: ## print the exact S2 resume commands after credentials work (no apply)
	@printf '%s\n' \
	  '# 1) Paste session keys into aws.env, then:' \
	  'make aws-check' \
	  'scripts/health.sh' \
	  '# 2) Wake paused warehouse if needed:' \
	  'aws redshift resume-cluster --cluster-identifier lab' \
	  '# 3) Apply notebook (confirm in this chat / yourself — AGENTS.md):' \
	  'terraform -chdir=infra/live plan -out=tfplan-s2' \
	  'terraform -chdir=infra/live apply tfplan-s2' \
	  '# 4) Features + train (after platform is up):' \
	  'for m in 2024-01 2024-02 2024-03 2024-04; do scripts/dagster-run.sh ingest_month --partition "$$m" --wait; done' \
	  'scripts/dagster-run.sh train_model --wait' \
	  '# 5) After measuring MAE/p95, set PROMOTION_* in aws.env + gh variables, re-run train_model' \
	  'gh workflow run status.yaml'

check: check-contracts lint test ## everything the grader runs statically

check-contracts: ## contracts/ is valid and unchanged since it was frozen
	uv run --quiet tools/check_contracts.py
	uv run --quiet tools/check_pins.py
	$(OPENAPI) contracts/openapi.yaml
	$(OPENAPI) contracts/serving-openapi.yaml
	$(OPENAPI) contracts/assistant-openapi.yaml

lint: lint-python lint-shell lint-workflows lint-terraform lint-observability ## all linters

lint-python:
	$(RUFF) check --select E4,E7,E9,F,B app pipelines serving mcp tools

lint-shell:
	$(SHELLCHECK) -S warning scripts/*.sh infra/bootstrap/*.sh deploy/*.sh observability/*.sh

lint-workflows: ## actionlint plus this repo's rules (self-hosted runners vs pull requests)
	@if [ -n "$(WORKFLOWS)" ]; then $(ACTIONLINT) -config-file .github/actionlint.yaml $(WORKFLOWS); fi
	uv run --quiet tools/check_workflows.py

lint-terraform:
	terraform fmt -check -recursive infra
	@for d in $(TF_DIRS); do \
	  echo "terraform validate $$d"; \
	  tmp=$$(mktemp -d); \
	  TF_DATA_DIR=$$tmp terraform -chdir=$$d init -backend=false -input=false >/dev/null && \
	  TF_DATA_DIR=$$tmp terraform -chdir=$$d validate -no-color >/dev/null || { rm -rf $$tmp; exit 1; }; \
	  rm -rf $$tmp; \
	done

ALLOY_IMAGE := grafana/alloy:v1.19.2
lint-observability: ## promtool on the SLO rules and their unit tests; Alloy configs formatted (Docker)
	@if ! docker info >/dev/null 2>&1; then echo "lint-observability: skipped, Docker isn't running here (CI runs it)"; exit 0; fi; \
	observability/push-rules.sh --check-only && \
	for f in observability/alloy/*.alloy; do \
	  docker run --rm -v "$$PWD/observability/alloy:/c:ro" $(ALLOY_IMAGE) fmt "/c/$$(basename $$f)" | diff -q - "$$f" >/dev/null || \
	    { echo "$$f isn't formatted: docker run --rm -v \$$PWD/observability/alloy:/c $(ALLOY_IMAGE) fmt -w /c/$$(basename $$f)"; exit 1; }; \
	done && echo "alloy configs formatted"

test: test-app test-pipelines test-serving test-mcp ## unit and contract tests

test-app:
	cd app && uv run --quiet pytest -q

test-pipelines: ## pipeline tests, with fake Redshift and S3 (no AWS)
	cd pipelines && uv run --quiet pytest -q

test-serving: ## serving against a local MLflow registry (no AWS)
	cd serving && uv run --quiet pytest -q

test-mcp: ## the MCP server against contracts/mcp-tools.json, serving and Redshift faked
	cd mcp && uv run --quiet pytest -q

agent-check: ## prove Claude Code loads AGENTS.md, root and nested (three short requests on your plan)
	@scripts/agent-check.sh
