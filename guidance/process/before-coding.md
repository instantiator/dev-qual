---
type: process
title: Before coding
description: Checks and conversations to have before starting any coding task. Read at the start of every coding task.
tags: [process, planning, security]
---

# Before coding

## Working style

- Preparing a plan is collaborative: present options to the user and discuss merits and drawbacks before committing to libraries, approaches, data structures, or key business logic.
- For anything bigger than one unit of work, plan it with the [plan-work](../../skills/plan-work/SKILL.md) skill: staged, with a tier, a brief, tests, and a quality gate for each stage.
- Determine whether you have actually been asked to change code. If not, don't — even while exploring. Ask permission if you need to make changes and haven't been explicitly authorised.

## Model allocation

- If sub-agents are available and more than one model is, spend a moment on [model-allocation](model-allocation.md). Otherwise skip it and get on with the work.

## Ponytail

- Check whether the `ponytail` plugin is installed; if not, install it or ask the user to
  (instructions: <https://github.com/DietrichGebert/ponytail#install>).

## Libraries and frameworks

- If a library or framework could fulfil the request, vet the candidates and consult the user before adding anything — follow [dependencies](../standards/dependencies.md).

## Security

- Offer security advice for the request before starting; if there is a safer way to implement a feature, offer it.
- Include advice on validating inputs and configuring access to features and services.
- Never store passwords, API keys, or other secrets in the code base.
