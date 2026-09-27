---
name: essential-behaviours
type: skill
title: Essential behaviours
description: Install the enforcement that makes key behaviours automatic. Use at project onboarding, or when asked to make sure something always happens.
tags: [skill, hooks, enforcement]
---

# Essential behaviours

## When to use

Onboarding a project into this guidance system, or the user says "make sure X always happens" (tests after changes, formatting, slop scans).

## Why this skill exists

Behaviours that live in an agent's memory get forgotten, especially by small-context models. Anything essential must be enforced by machinery. Git hooks catch every commit, whichever model, editor, or human made it; agent hooks catch the agent before it moves on.

## Questions to ask

1. Which behaviours matter here? (Default: the quality gate on commit and push, plus the agent hooks.)
2. Which agent platforms are in use: Claude Code, OpenCode, pi, others?
3. Install for this project, or for the user across all their repos?
4. Does the project already have git hooks to preserve? (If yes, use `--copy` mode.)

## Steps

1. Run `dev-qual/install.sh` (add `--user` for a user-scope install). It merges the entry instructions, wires each platform's adapter, offers the git hooks (project scope), and records the choices so upgrades and enable/disable can replay them.
2. Git hooks: pre-commit runs `check.sh --fast` on exactly what is staged, and pre-push runs the full `check.sh`. At project scope the installer offers them. At user scope, the agent offers them the first time it works in a repo without them. To add them by hand: `dev-qual/scripts/setup-hooks.sh --project <repo>` (`--copy` to keep the repo's own hooks).
3. Agent hooks, via `dev-qual/scripts/agent-hook.sh`, are wired for Claude Code (`.claude/settings.json`) and pi (the package's extension):
   - **post-edit**: `check.sh --fast` after each edit; failures go back to the agent.
   - **session-start**: reports available dev-qual updates and, at user scope, offers the repo's git hooks.
   - **stop**: when code (not just docs) changed, runs the fast gate and lists unticked stages of active plans in `docs/plans/`, blocking the agent's finish once.
4. OpenCode reads the entry instructions and skills routing from AGENTS.md; it has no hooks, so the git hooks are its gate.

## Scripts

- `dev-qual/install.sh`, `dev-qual/scripts/setup-hooks.sh`, `dev-qual/scripts/agent-hook.sh`
- `dev-qual/scripts/toggle.sh enable|disable|status`: switch all of it off and on again, keeping the recorded choices.

## Validate

- A deliberately bad commit (e.g. a lint error) is blocked by pre-commit with actionable output; revert the test change after.
- `dev-qual/scripts/check-install.sh` (with `--user` for user scope) reports PASS for what was installed.
