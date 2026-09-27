---
status: active
---

# Plan: <title>

- **Branch:** `<branch>`
- **Commits:** <one per stage | one for the whole plan | none: the user commits>
- **Orchestrator:** <model>. Sub-agent tiers: <e.g. Mid = …, Fast = …, or "none: single model">

## Context

<Why this work is happening: the problem, what prompted it, and the intended outcome.>

### Decisions taken

| Decision | Choice |
|-|-|
| <question agreed with the user> | <answer> |

### Constraints and reuse

- <Standards, budgets, and compatibility rules that apply.>
- <Existing helpers, scripts, and skills to reuse, with paths.>

## Stages

- [ ] Stage 1: <name>
- [ ] Stage 2: <name>
- [ ] Stage N: Documentation and wrap-up

### Stage 1: <name> (<tier>)

**Brief:** <exact files, the change, helpers to reuse, constraints, and what not to touch.>

**Tests:** <the cases to add or update, by name.>

**Gate:** `dev-qual/scripts/check.sh --fast` + `<new tests command>`. Expected: <what passing looks like>.

### Stage N: Documentation and wrap-up (<tier>)

1. `dev-qual/scripts/check.sh --comprehensive`
2. `dev-qual/scripts/stale-docs.sh --base <branch-point>`, then resolve every hit (`docs-review` skill).
3. Outstanding-work review: record anything deferred in `docs/outstanding-issues.md` with its condition.
4. Set `status: done` above.

## Verification

<How to confirm the whole change works end to end.>
