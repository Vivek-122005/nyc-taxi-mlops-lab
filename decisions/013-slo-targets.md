# 013: Ride-app SLO targets

Stage: S5 · Date: 2026-11-22 · Author: Vivek Vishnoi · Drafted by agent: yes

## Choice

Three SLIs from `contracts/metrics.yaml`:

1. **predict-availability** — non-5xx share of `/predict` → **99%**
2. **predict-latency** — share of `/predict` finishing within **0.5 s** → **95%**
3. **model-not-fallback** — share of quotes from `source="model"` → **99%**

Alert with multi-window **fast burn 14.4×** (5m AND 1h), `for: 2m`, so a short spike does not page.

## Rejected alternative

A single 99.9% availability SLO with a threshold alert on raw error rate (or p95 latency alone), and no model/fallback SLI.

## Why

99% / 30d leaves ~7 h of budget — enough for Academy session restore without constant pages. Latency at 500 ms / 95% matches the app’s 300 ms serving timeout plus Traefik/fallback headroom; 99% < 100 ms would page on cold loads. The model-not-fallback SLI is the rider-visible signal when `serving-champion` is stopped (S5 prove step) even when HTTP stays 200 via the static median. Multi-window burn follows the SRE workbook pattern so brief blips do not page ([SLO burn-rate alerting](https://dev.to/dwoitzik/slo-burn-rate-alerting-with-prometheus-beyond-threshold-alerts-2218)).

## What would show this was wrong

Pages during every Learner Lab restore, or a stopped champion that never alerts because HTTP 200 fallback hid the outage; or chronic latency pages while riders still find quotes acceptable.
