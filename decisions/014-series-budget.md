# 014: Grafana Cloud series budget (what Alloy keeps)

Stage: S5 · Date: 2026-11-22 · Author: Vivek Vishnoi · Drafted by agent: yes

## Choice

Keep only what the ride-app dashboard, SLOs, or an incident need; drop the rest in `observability/alloy/budget.alloy`:

- **host:** `node_cpu_seconds_total`, `node_memory_MemAvailable_bytes`, `node_memory_MemTotal_bytes`, `node_filesystem_avail_bytes`, `node_filesystem_size_bytes`
- **containers:** `container_memory_working_set_bytes`, `container_cpu_usage_seconds_total`, and **labeldrop** `id`, `image_id`, compose config-hash / image labels (change every CD recreate)
- **services:** `lab_.*` plus Traefik service request count/duration histogram series

Target: stay **well under ~3,000 active series** across app + platform today (headroom for the LLM host in S6), against the **10,000** free-tier cap.

## Rejected alternative

Ship everything Alloy scrapes (no budget rules), or keep all cAdvisor/node_exporter metrics and only drop a few labels.

## Why

Unfiltered node_exporter + cAdvisor easily burns thousands of series per host; container `id`/`image_id` create a new series on every deploy, so a CD burst would look like a leak. Keeping contract `lab_*` metrics and Traefik service series preserves SLOs and the canary path without paying for unused exporter cardinality.

## What would show this was wrong

Grafana Cloud refused writes / `alloy-stats` shows refused samples; active series >~5k after three CD deploys; or an incident where the missing metric was one we dropped (then add that name deliberately).
