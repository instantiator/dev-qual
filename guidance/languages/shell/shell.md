---
type: standard
title: Shell scripting standards
description: Shell choice, cross-platform compatibility, and script structure. Read when writing or editing any shell script.
tags: [shell, bash, scripting, cross-platform]
---

# Shell scripts

## Choice of shell

- Write scripts in **bash**, targeting **bash 3.2** (the macOS default; avoid associative arrays, `${var,,}`, and other bash-4+ features).
- Shebang: `#!/usr/bin/env bash`. Start with `set -euo pipefail`.
- Windows users run scripts via **Git Bash** (installed with git) — do not write `.ps1` twins unless the project has a real Windows-native requirement.
- If a script needs JSON parsing, HTTP calls, or complex data structures, use Node instead — see [node-scripting](../node-scripting/node-scripting.md).

## Structure

- Add a header comment near the top: what the script is for and how to use it.
- Break the script into blocks that perform specific activities, each with a single-line comment stating the intent.
- Self-document: print usage on `--help`, missing parameters, or invalid parameters (skip this if the script only wraps an application that already validates and prints usage).
- Quote all variable expansions (`"$var"`); prefer `$(...)` over backticks.

## Prerequisites

- Check for required tools before using them: `command -v tool >/dev/null` — and on failure print the install command per OS (brew / apt / winget).
- `dev-qual/scripts/check-prereqs.sh` does this for common project types; reuse it rather than re-implementing.

## Verification

- Run `shellcheck` on every script and fix all findings (it's the linter for shell — the 0-warnings rule applies).
