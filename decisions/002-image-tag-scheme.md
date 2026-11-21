# 002: Image tag scheme

Stage: S0 · Date: 2026-11-21 · Author: Vivek Vishnoi · Drafted by agent: yes

## Choice

Publish each deployable app image only as `sha-<short-commit>`. A rollback deploys a previously known immutable SHA tag.

## Rejected alternative

Publish the immutable SHA tag alongside a mutable `latest` tag.

## Why

The SHA tag directly identifies the source revision and cannot be silently retargeted, so the deployed image and rollback point are auditable.

## What would show this was wrong

Operators repeatedly need a human-friendly release reference and SHA-based lookup causes deployment or rollback mistakes despite documentation and workflow output.
