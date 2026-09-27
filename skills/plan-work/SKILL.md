---
name: plan-work
type: skill
title: Plan work
description: Build a staged, gated implementation plan before coding. Use when asked to plan, in planning mode, or before any task with more than one unit of work.
tags: [skill, planning, process, sub-agents]
---

# Plan work

## When to use

Planning mode, a request to "plan" something, or any task that will take more than one unit of work ([testing-loop](../../guidance/process/testing-loop.md)). A one-line fix needs no plan.

## Questions to ask

1. Which branch will the work happen on? Create one, or use the current one?
2. How should the work be committed: **one commit per stage** once its gate passes, **one commit** for the whole plan, or **no commits** (the user reviews and commits)?
3. Which models or sub-agents are available? Skip this if [model-allocation](../../guidance/process/model-allocation.md) says to.

Ask these alongside the design questions, not as a separate round.

## Steps

1. Run `dev-qual/scripts/check-updates.sh`. If an update is reported, offer `dev-qual/scripts/upgrade.sh` before planning.
2. Explore before proposing. Find the existing code, helpers, scripts, and skills the work can reuse, and name them in the plan with their paths.
3. Planning is collaborative. Present the options and trade-offs for libraries, approaches, data structures, and key business logic, and agree them with the user before writing stages ([before-coding](../../guidance/process/before-coding.md)).
4. Write the plan from [templates/plan.md](templates/plan.md) to `docs/plans/<yyyy-mm-dd>-<slug>.md` with `status: active`, and list it in `docs/index.md`.
5. Split the work into **stages**. Each stage is one unit of work with one purpose, small enough that its gate either passes or points at what broke. Each stage has:
   - **Tier or sub-agent**: assigned per [model-allocation](../../guidance/process/model-allocation.md) where the environment allows. Keep the decisions with the capable model and hand the mechanics down.
   - **Brief**: what the stage's agent needs to get it right first time. That means the exact files and line references, the helpers to reuse, the concrete change, the constraints that apply (the language docs, line budgets, "don't commit"), and the acceptance commands with their expected output. A retry or a round-trip to the orchestrator costs more than a longer brief, so when unsure, add detail rather than raising the tier.
   - **Tests**: the tests this stage adds or updates for its own changes ([testing standards](../../guidance/standards/testing.md)). Name the cases, not just the file.
   - **Gate**: `dev-qual/scripts/check.sh --fast`, plus this stage's new tests (`dev-qual/scripts/run-tests.sh <suite>` or the specific command), plus longer suites the stage added. The stage is done only when the gate passes.
   - **Commit**: per the agreed strategy.
6. Order stages so each builds on committed, gated work. Stages that don't touch the same files can run in parallel sub-agents.
7. **The final stage is always "Documentation and wrap-up"**:
   - `dev-qual/scripts/check.sh --comprehensive`, which runs every suite and a security audit;
   - `dev-qual/scripts/stale-docs.sh --base <branch-point>`, then the `docs-review` skill, to update every doc the work made stale (README, guidance, skills, ADRs);
   - the outstanding-work review ([after-coding](../../guidance/process/after-coding.md) §3–4);
   - set the plan's `status: done`.
8. Get the user's approval of the plan before starting stage 1.

## While implementing the plan

- Tick each stage (`- [x]`) in the plan file as its gate passes. The Stop hook (`dev-qual/scripts/agent-hook.sh stop`) and `dev-qual/scripts/plan-status.sh` report unticked stages of active plans.
- The orchestrating model reviews each sub-agent's output against the brief's acceptance criteria and reads the diff before ticking or committing. A sub-agent's report says what it intended to do, not what it did.
- If the plan turns out to be wrong, update the plan file first, then carry on. The file is the record.

## Scripts

- `dev-qual/scripts/check-updates.sh`, `dev-qual/scripts/upgrade.sh`: check for and apply updates before starting.
- `dev-qual/scripts/check.sh` (`--fast` for stage gates, `--comprehensive` for the final stage).
- `dev-qual/scripts/run-tests.sh <suite>`: runs one test suite.
- `dev-qual/scripts/plan-status.sh`: lists unticked stages of active plans.
- `dev-qual/scripts/stale-docs.sh`: lists docs that mention what changed.

## Validate

- The plan names its branch and its commit strategy.
- Every stage has a tier (or says why not), a brief a cheaper model could act on without asking questions, tests, and a gate.
- The last stage covers comprehensive checks, documentation, and outstanding work.
