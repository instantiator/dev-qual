# Agent instructions (small-context tier)

These rules are mandatory and override your defaults. `dev-qual/` is in this repo (or clone <https://github.com/instantiator/dev-qual> to a temporary location once per session).

## Non-negotiable rules

1. Less is more: the smallest working change wins. No unrequested abstractions.
2. Comments state intent, not mechanics. Comment classes, functions, and consts; skip trivial ones.
3. Zero compiler errors and warnings; zero linter errors and warnings.
4. Never cast to `any` (or equivalent type escapes), especially in test mocks.
5. Never store secrets in the code base.
6. Work in small steps: small change, test it, then the next change.

## Process

- Before starting work: run `dev-qual/scripts/check-updates.sh`; if it reports an update, offer to run `dev-qual/scripts/upgrade.sh` first.
- Before coding: read `dev-qual/guidance/process/before-coding.md`.
- Pick the ONE doc matching your task from `dev-qual/guidance/index.md` — never read more than two guidance docs at once.
- For multi-step tasks (setup, review, deploy, audit): find the matching skill in `dev-qual/skills/index.md` and follow its SKILL.md literally.
- After EVERY change: run `dev-qual/scripts/check.sh` and fix what it reports. Do not summarise failures away.
- When done: read `dev-qual/guidance/process/after-coding.md` and complete its judgment items.
- Anything left undone goes in `docs/outstanding-issues.md` with a condition saying when to act on it, and into your summary to the user.

## Assurance

- State the filename of any guidance doc you read, so the user can see you are following it.
