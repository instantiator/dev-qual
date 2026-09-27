---
type: standard
title: Markdown standards
description: Style rules for markdown files. Read when writing or editing .md files.
tags: [markdown, documentation]
---

# Markdown

- Use GitHub-flavoured markdown: tables, task lists, fenced code blocks with language tags, mermaid diagrams.
- No `---` horizontal rules before or after headings.
- Use relative links between docs in the same repository.
- One H1 per file, matching the doc's purpose; nest headings without skipping levels.
- Lint with `markdownlint` where available (the 0-warnings rule applies).
- Docs in this guidance system additionally carry YAML frontmatter (`type`, `title`, `description`, `tags`) — the `description` must say *when to read the doc*, because index files route agents by it.
