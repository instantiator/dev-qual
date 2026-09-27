---
type: process
title: Testing loop
description: Units of work, short change-test cycles, and which quality gate to run when. Read when working through a multi-step coding task.
tags: [process, testing, quality-gate]
---

# Testing loop

## Units of work

Split coding work into units that can be evaluated independently — each one a
group of changes with a single purpose, small enough that its tests either pass
or point at exactly what broke.

**Before each unit**, check it against the two lists in
[principles](../standards/principles.md): does the plan need to exist at all, is
there a simpler way, does each piece do one thing? Decide what tests it needs —
unit tests always, heavier tiers where the change warrants them.

**Then, for each unit:**

1. Make the changes, grouped by purpose.
2. Write or update tests for them and run them.
3. Fix anything that fails, or move on to the next unit.

In a plan, each unit is a stage and ends with its gate ([plan-work](../../skills/plan-work/SKILL.md)).

## The three gates

`dev-qual/scripts/check.sh` has three modes. Anything you change in
response to a gate gets re-checked by that same gate — a fix is not exempt from
the check that found it.

| When | Command | What it runs |
|-|-|-|
| After each unit of work | `check.sh --fast` | Format, lint, typecheck. Also the pre-commit hook. |
| Before pushing | `check.sh` | The above plus build, unit tests, and `aislop`. Also the pre-push hook. |
| After the **last** unit of work | `check.sh --comprehensive` | The above plus every test suite and a package security audit. |

## After the last unit

1. `check.sh --comprehensive` — 0 errors, 0 warnings, no severe or high vulnerabilities.
2. Re-run it after any fix it prompted.
3. Update the documentation relating to what changed ([documentation](../standards/documentation.md)).
4. Review conditional outstanding tasks ([outstanding-work](outstanding-work.md)).

## Which suites, when

- **After every change**: unit tests (fast, no external services) — included in the full gate.
- **After completing a task**: every other suite expected to take less than 1 minute
  (`dev-qual/scripts/run-tests.sh all` discovers and runs the project's suites).
- **Slower suites** (integration/e2e/smoke needing services): ask the user before running them, unless you are running the comprehensive gate at the end of the work.
- Suite organisation and naming: [testing standards](../standards/testing.md).

Do not rely on remembering this: install the git hooks (`dev-qual/scripts/setup-hooks.sh`) so pre-commit runs the fast checks and pre-push runs the full gate.
