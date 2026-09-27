---
name: toolchain-setup
type: skill
title: Toolchain setup
description: Set up or repair linters, formatters, and typechecking, consistent across CLI and IDE. Use when configuring tooling or when CLI and editor disagree.
tags: [skill, linting, formatting, tooling]
---

# Toolchain setup

## When to use

New repo needing lint/format/typecheck; existing repo where tools are missing, inconsistent, or the IDE disagrees with the CLI.

## Questions to ask

1. Which languages are in the repo? (Every language present must be covered — including shell scripts and markdown.)
2. Which IDE? (Default: VS Code.)
3. Any existing configs to preserve or migrate?

## Steps

1. Read the language docs for each language present (`guidance/languages/index.md`) — they name the blessed tools.
2. Configure per language. TS: ESLint flat config + typescript-eslint + Prettier via eslint-plugin-prettier (formatting failures surface as lint warnings); C#: `.editorconfig` + analyzers + `dotnet format`; shell: shellcheck; markdown: markdownlint.
3. Adopt dev-qual's lint baseline for each language that has one (`guidance/languages/<lang>/tools/`). It turns the written rules (no `any`, no blind excepts, bounded complexity) into lint errors. `check.sh` reports the baseline stage: a SKIP prints the exact lines to add.
4. Expose CLI entry points so `check.sh` and CI find them: npm scripts `lint`, `lint:check`, `format`, `typecheck` (or dotnet equivalents).
5. Make the IDE agree with the CLI: `.vscode/settings.json` + `.vscode/extensions.json` pointing at the *same* tools and configs — no IDE-only rules.
6. Confirm every file type in the repo is in scope of at least one tool; check ignore files don't accidentally exclude source.
7. Get everything to 0 errors and 0 warnings (`guidance/standards/common.md`), or agree documented exceptions with the user.

## Scripts

- `dev-qual/scripts/check.sh` as the acceptance test.

## Validate

- `check.sh` passes, and deliberately mis-formatting a file makes it fail.
- Opening the repo in VS Code shows the same problems the CLI reports (spot-check one induced error).
