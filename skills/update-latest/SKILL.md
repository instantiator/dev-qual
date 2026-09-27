---
name: update-latest
type: skill
title: Update to latest
description: Bring an installed dev-qual (project or user scope) up to date without losing customisations. Use when an update is reported, the dev-qual checkout has moved on, or setup looks stale.
tags: [skill, maintenance, upgrade]
---

# Update to latest

## When to use

`dev-qual/scripts/check-updates.sh` (or the session-start hook) reports an update, the user asks to update, or something in the installed setup looks out of date.

## Questions to ask

1. Update now? For a project install, the upgrade moves the submodule pointer, which the user then commits.
2. Has the user deliberately customised any installed files? The drift report shows which; ask before touching those.

## Steps

1. Run `dev-qual/scripts/upgrade.sh` (`--user` for a user-scope install, `--project <dir>` for another repo). It:
   - bumps the submodule, or pulls a user-scope clone (fast-forward only);
   - re-runs `install.sh --from-config`, replaying the choices recorded in `.dev-qual.env` (project scope) or `~/.config/dev-qual/config.env` (user scope);
   - finishes with `check-install.sh`.
2. For each FAIL in that report, look at what differs before changing anything:
   - `git -C dev-qual log --oneline <old>..HEAD -- <path>` for what changed upstream (upgrade.sh prints the old and new SHA);
   - `diff` the project's copy against the checkout's for what the user changed.
3. Tell the user what each difference is and which side you propose to keep. Keep anything that looks like a deliberate customisation unless they say otherwise.
4. Merge by hand what the installer doesn't own: text outside the `<!-- dev-qual:… -->` markers, hooks installed with `--copy` that the user edited, and custom entries in `.claude/settings.json`. Take the upstream version and re-apply the user's edits on top; never drop an edit silently.
5. Re-run `dev-qual/scripts/check-install.sh` until everything is PASS, or the remaining FAILs are customisations the user chose to keep.
6. Run `dev-qual/scripts/check.sh`: an updated gate may report things the old one didn't.
7. Project scope: remind the user to commit the new submodule pointer.

## Installs from before the state file

An install made before `install.sh` recorded its choices has no `.dev-qual.env`, so `upgrade.sh` stops with "not installed". Update the checkout by hand (`git submodule update --remote dev-qual`), then run `./dev-qual/install.sh` once, interactively. It records the choices, and `upgrade.sh` works from then on.

## Scripts

- `dev-qual/scripts/check-updates.sh`: is an update available? Never blocks; refreshes in the background at most daily.
- `dev-qual/scripts/upgrade.sh`: update and re-apply.
- `dev-qual/scripts/check-install.sh`: the drift report.

## Validate

- `check-install.sh` reports no unexplained differences.
- Every customisation the user chose to keep is still present.
- `check.sh` passes, and a test commit still triggers the pre-commit hook (project scope, if hooks were installed).
