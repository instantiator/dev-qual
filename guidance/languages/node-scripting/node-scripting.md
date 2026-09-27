---
type: standard
title: Node scripting standards
description: Using Node or TypeScript for project scripts instead of shell. Read when a script needs JSON, HTTP, or cross-platform logic.
tags: [node, typescript, scripting]
---

# Node for scripting

## When to prefer Node over shell

- The script parses or writes JSON/YAML, makes HTTP calls, or needs real data structures.
- The logic has branching/loops beyond what a page of bash can express clearly.
- Identical behaviour is needed on Windows without Git Bash quirks (paths, quoting).
- Otherwise, prefer shell — see [shell](../shell/shell.md); a 10-line bash script beats a Node project.

## Style

- Zero dependencies where possible: use `node:fs`, `node:path`, `node:util` (`parseArgs`), `fetch`.
- Single-file ESM scripts: `scripts/thing.mjs`, run with `node scripts/thing.mjs`.
- TypeScript only if the project already has a TS toolchain (run via `tsx` or `ts-node` that is already installed) — don't add a compiler for a script.
- Same self-documentation rules as shell scripts: `--help`, usage on bad input ([cli-tools](../cli-tools/cli-tools.md)).
- Exit non-zero on failure; print errors to stderr.
