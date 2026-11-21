# 001: Runner credentials

Stage: S0 · Date: 2026-11-21 · Author: Vivek Vishnoi · Drafted by agent: yes

## Choice

Use the pre-created `LabInstanceProfile` attached to each EC2 host. The self-hosted GitHub Actions runner receives short-lived AWS credentials through EC2 instance metadata.

## Rejected alternative

Copy temporary Learner Lab session credentials into GitHub repository secrets.

## Why

The instance profile avoids storing renewable AWS credentials in GitHub, survives runner restarts without secret rotation, and matches the lab's pre-created IAM model.

## What would show this was wrong

The runner cannot access an AWS service required by a deployment despite the host's instance profile being attached, and the missing permission cannot be resolved within the Learner Lab role constraints.
