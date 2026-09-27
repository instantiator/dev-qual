---
type: standard
title: Python standards
description: Rules and tooling for Python code. Read when writing or reviewing .py files.
tags: [python, language]
---

# Python

- Type-hint every public function, method, and module-level constant. Internal helpers too where the type isn't obvious from the name.
- Run `mypy` in strict mode on new code. Where an existing codebase can't reach strict, enable it per-module and widen over time — don't disable it globally.
- No bare `except:` and no `except Exception: pass` — catch the specific error, handle it or let it propagate ([pitfalls](../../standards/pitfalls.md)).
- Avoid `typing.Any` and `# type: ignore` for the same reason TypeScript avoids `any`; where genuinely unavoidable, narrow the ignore to the specific rule and say why.
- Use `pathlib` over `os.path`, f-strings over `%` and `.format()`, and context managers for anything that must be closed.
- Mutable default arguments (`def f(x=[])`) are a bug; use `None` and build inside the function.
- Prefer the standard library: `dataclasses`, `enum`, `functools`, `itertools`, `argparse` ([cli-tools](../cli-tools/cli-tools.md)).
- Use the latest stable Python the project's platform supports — verify what that is, don't assume.

## Docstrings

Docstrings follow the intent rule in [common](../../standards/common.md): say what
the thing *is* and what it guarantees, not how it works. Triple-quoted, opening
with one short sentence, blank line before anything further.

## Tooling

| Purpose | Tool |
|-|-|
| Lint | `ruff check` (replaces flake8, isort, pyupgrade, and more — one tool, one config) |
| Format | `ruff format` (verify in CI with `ruff format --check`) |
| Typecheck | `mypy` |
| Test | `pytest` |
| Vulnerabilities | `pip-audit` |
| Slop scan | `npx aislop scan` |

- Configure all of it in `pyproject.toml` — one file, no scattered `.cfg`/`.ini` twins.
- Pin the dependency set with a lockfile (`uv.lock`, `poetry.lock`, or a compiled `requirements.txt`) and commit it.
- `scripts/check.sh` runs format, lint, typecheck, and tests automatically when it detects a Python project.
- For Python as a scripting language, the shell/Node trade-off in [node-scripting](../node-scripting/node-scripting.md) applies equally: a 10-line bash script beats a Python project.
