---
name: docs-review
type: skill
title: Docs review
description: Review and update project documentation against the code. Use after a feature lands, or when docs may be stale.
tags: [skill, documentation, review]
---

# Docs review

## When to use

After completing a feature or fix, or when asked to review/update documentation.

## Questions to ask

1. Which docs relate to the changed code? (Check `docs/index.md`; if unsure, ask the user.)
2. Would a diagram help (flows, topology)? Mermaid in markdown is the default.

## Steps

1. Read `guidance/standards/documentation.md`.
2. Find the candidates: `dev-qual/scripts/stale-docs.sh --base <branch-point>` lists every doc line that mentions a changed or deleted file, or a removed declaration. Work through each hit, then the docs for anything new.
3. For each related doc, compare its claims to the *actual* behaviour of the code — read the code, don't trust the doc. Fix discrepancies in the doc (or flag a code bug if the doc states the intended behaviour).
4. Remove documentation for code that no longer exists.
5. Add docs for new architecture-level parts or flows introduced by the change, with mermaid diagrams where they beat prose.
6. Update `docs/index.md` so every doc is listed with a one-line description.
7. Check readability: GFM formatting, working relative links, heading structure (`guidance/languages/markdown/markdown.md`).

## Scripts

- `dev-qual/scripts/stale-docs.sh [--base <ref>]`: docs that mention what changed.
- `markdownlint` where available; for this guidance repo itself, `dev-qual/scripts/lint-docs.sh`.

## Validate

- No dead links; every doc reachable from `docs/index.md`.
- A spot-check of documented claims against the code finds no contradictions.
