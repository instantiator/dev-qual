---
type: standard
title: CLI tool standards
description: Parameter design and self-documentation for CLI applications. Read when building a command-line tool.
tags: [cli, tools]
---

# CLI tools

When creating CLI tools (applications or scripts):

- Aim for small sets of simple, easily understood parameters, with sensible defaults where possible.
- Self-document: when required parameters are missing or invalid, or on `--help`, print a short description of the tool, all parameter options, and usage information.
- Exit non-zero on failure so callers and CI can react.
- If a wrapper script drives an application that already validates parameters and prints usage, the script doesn't need to repeat that.
- Script structure and shell choice: [shell](../shell/shell.md); Node-based tools: [node-scripting](../node-scripting/node-scripting.md).
