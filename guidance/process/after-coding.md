---
type: process
title: After coding
description: Steps after every coding activity - run the quality gate, then apply judgment. Read after completing any code change.
tags: [process, quality, testing]
---

# After coding

## 1. Run the quality gate

Run `dev-qual/scripts/check.sh`. It formats, lints, typechecks, builds, runs unit tests, and runs `npx aislop scan` where available, and prints a fix-hint for every failure.

- Fix what it reports until it passes. Do not summarise failures away or defer them. Re-run the gate after every fix it prompted.
- After the *last* unit of work in a task, run `check.sh --comprehensive` instead — it adds every test suite and a package security audit ([testing-loop](testing-loop.md)).
- aislop is opinionated and can disagree with these documented standards (e.g. on commenting). Where there's a conflict, these standards win; where it finds a genuine clean-up, make it.

## 2. Judgment items (the script can't do these)

- Review the tests: are they thorough? Add tests for missed cases and edge cases. Test the *intent* of the changed code, so passing tests mean correct behaviour. Remove tests for removed code.
- If a new class of test suite is needed (e.g. introducing integration tests), offer to tackle it next.
- Simplify the new code; look for opportunities to divide it into logical groupings ([readability](../standards/readability.md)), and check it against the acceptance list in [principles](../standards/principles.md).
- Review comments: they must state intent, and match the code as it now is. Find any made stale by this change.
- Find `TODO`/`LATER`/`qq` comments: each must say when or under what conditions it will be dealt with — add the condition if missing (consult the user if unclear), and decide whether to tackle it now.
- Run the wider test suites per [testing-loop](testing-loop.md).

## 3. Documentation

- Update project docs that relate to the new or changed code; remove docs for removed code ([documentation](../standards/documentation.md)).
- `dev-qual/scripts/stale-docs.sh --base <branch-point>` lists the doc lines that mention changed files or removed declarations: resolve each hit.

## 4. Outstanding work

- Anything you left undone goes in `docs/outstanding-issues.md` with a measurable condition for when to act on it, and into your final summary to the user.
- At the end of a task, review what is already recorded there against the state of the repo — some conditions may now be met ([outstanding-work](outstanding-work.md)).
