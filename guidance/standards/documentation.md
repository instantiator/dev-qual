---
type: standard
title: Documentation standards
description: How project documentation is organised and written. Read when writing or updating docs, or adding a feature that needs documenting.
tags: [standards, documentation, markdown]
---

# Documentation standards

- Every high-level part of the system architecture gets a doc describing what it does and why it exists.
- Keep a `docs/index.md` that lists every doc with a one-line description — docs nobody can find don't exist.
- Document important flows (request handling, auth, deployment) step by step.
- Illustrate with mermaid diagrams in markdown where a diagram beats prose (sequence diagrams for flows, graphs for topology).
- Use GitHub-flavoured markdown: tables for enumerable facts, code fences with language tags, relative links between docs.
- Documentation describes _current_ behaviour. When code changes, update the related docs in the same change; remove docs for removed code.
- Record architectural decisions as ADRs in `docs/ADRs/NNNN-title.md` with context, decision, and consequences (see the `adr` skill).
- Markdown style rules: [markdown](../languages/markdown/markdown.md).

## Writing ADRs for clarity

An ADR is read by someone deciding whether to agree, not just by someone implementing it. Keep the summary skimmable and push everything else below it.

- **Split the summary from the detail.** Context, Decision, Consequences (and any "what needs deciding" / "options considered" / "alternatives considered" sections) stay short and plain — a reader unfamiliar with the specifics should follow the reasoning without decoding jargon or metaphor. Move mechanics, code snippets, and deeper trade-off reasoning into a `## Detail` section at the very end, with `###` subheadings, and link to it from the summary (`— see [why](#anchor)`) so a reader who wants the specifics can jump straight there.
- **Don't pad a list with a throwaway lead-in.** A list needs no separate sentence whose only job is to announce it exists and count its items ("Two things:", "Four points carry the decision:") — a heading, or the sentence before it, is usually enough context; just start the list. Keep a lead-in only when it says something the list doesn't already say for itself — a requirement ("Three things must happen on every request:"), a name the list is referred to elsewhere by ("The six browser journeys:"), or similar.
- **Explain jargon on first use** — inline, or as a footnote — rather than assuming the reader already knows it.
- **Prefer the literal statement over idiom or metaphor.** Figures of speech read as clever, not clear, and cost an unfamiliar reader a decoding step. See the example below.

## Example: replacing unusual terminology with direct language

| Was                                            | Now                                                                                            |
| ---------------------------------------------- | ---------------------------------------------------------------------------------------------- |
| "a blind spot"                                 | "a gap in coverage"                                                                            |
| "passes a compile and fails a person"          | "won't be caught by the compiler — it only shows up as a person noticing something is missing" |
| "a knob"                                       | "a small configuration change"                                                                 |
| "grows a second application registration"      | "gets a second application registration"                                                       |
| "on a path to simply not working"              | "likely to stop working, not just occasionally fail"                                           |
| "building on a disappearing foundation"        | "depends on something that is actively being taken away"                                       |
| "the wrong half of the problem"                | "solves the part of the problem we don't have, not the part we do"                             |
| "the other pole"                               | "the opposite approach"                                                                        |
| "steals the cursor"                            | "pulls a screen reader user away, without warning"                                             |
| "made unremarkable by the workspace split"     | "no longer unusual now that the workspace split gives each part its own tooling"               |
| "doubles as continuous accessibility pressure" | "also works as an ongoing accessibility check"                                                 |
