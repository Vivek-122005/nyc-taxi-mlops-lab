# 003: App ingress scope

Stage: S0 · Date: 2026-11-21 · Author: Vivek Vishnoi · Drafted by agent: yes

## Choice

Allow HTTP access to the app host only from the public IPv4 address recorded as a `/32` entry in `infra/live/terraform.tfvars`.

## Rejected alternative

Allow HTTP from every IPv4 address with `0.0.0.0/0`.

## Why

A single-address CIDR provides the smallest public attack surface while still allowing local smoke tests against the app host's Elastic IP.

## What would show this was wrong

The required grader, instructor, or legitimate collaborators cannot access the app and their stable source CIDRs cannot be safely added to the allow-list.
