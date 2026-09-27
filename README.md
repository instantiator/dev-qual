# dev-qual

Guidance, skills, and scripts that help coding agents (Claude Code, OpenCode, or any other) deliver consistently high-quality code — designed so that even small-context models can complete features and fixes to a high standard.

## What's here

| Path | What it is |
|-|-|
| `agents-files/` | Entry-point instructions to copy/merge into your project (`local/` for small-context agents, `remote/` for capable ones, plus a Claude Code variant) |
| `guidance/` | Condensed standards and process docs, one topic per file, routed by `guidance/index.md` |
| `skills/` | Step-by-step playbooks for multi-step tasks (project setup, CI, reviews, deploys, ADRs, ...), routed by `skills/index.md` |
| `scripts/` | The automation: `check.sh` (quality gate), `run-tests.sh`, `check-prereqs.sh`, `check-install.sh`, `setup-hooks.sh`, git hooks |
| `adapters/` | Wiring for specific agent platforms (Claude Code skills + hooks, OpenCode) |
| `configs/` | Shared tool config used by the gate when a project supplies none (currently markdownlint) |

## Install into a project

```bash
git submodule add https://github.com/instantiator/dev-qual
./dev-qual/install.sh
```

The installer is interactive: it asks which agent tier(s) and platforms you use, merges entry files into your repo (never clobbering existing AGENTS.md/CLAUDE.md), and offers to install the git hooks that run the quality gate on commit and push. Re-run it any time.

Prefer manual setup? Copy a file from `agents-files/` to your repo root, then run `./dev-qual/scripts/setup-hooks.sh`.

## Keep it up to date

```bash
git submodule update --remote dev-qual && ./dev-qual/install.sh
```

Installed before the rename, as `dev-environment`? Move the submodule and re-run the installer — it replaces the old marker block rather than duplicating it:

```bash
git mv dev-environment dev-qual
git submodule set-url dev-qual https://github.com/instantiator/dev-qual.git
./dev-qual/install.sh
```

`scripts/check-install.sh` reports what in your project has drifted from the checkout — an edited `CLAUDE.md`, copied hooks, a skill that is no longer a symlink — so you can merge rather than overwrite. The `update-latest` skill walks an agent through it.

## The quality gate

`scripts/check.sh` detects every stack in your project — Node/TypeScript, .NET, Python, plus shell and markdown wherever they appear — and runs format check → lint → typecheck → build → unit tests → `aislop scan`, printing PASS/FAIL with a fix-hint per failure. Missing tools SKIP with an install command rather than breaking the run.

| Mode | Adds | Run by |
|-|-|-|
| `--fast` | format, lint, typecheck | pre-commit hook, after each unit of work |
| _(default)_ | build, unit tests, `aislop scan` | pre-push hook |
| `--comprehensive` | every test suite, package security audit | you, after the last unit of work |

The git hooks run the first two automatically, so quality doesn't depend on anyone, human or model, remembering. `pre-commit` also runs `scripts/pre-commit-fixups.sh` if your project has one — formatting, generated files, licence lists — and re-stages what it changed, leaving partially-staged files alone.

## Third party tools

Some of these rules refer to and lean on third party tools. With gratitude:

| Tool | Description | License |
|-|-|-|
| [aislop](https://github.com/scanaislop/aislop) | Catch the slop AI coding agents leave in your code: narrative comments, swallowed exceptions, as-any casts, dead code, oversized functions. 50+ rules across 8 languages. | [MIT](https://github.com/scanaislop/aislop?tab=MIT-1-ov-file) |
| [ponytail](https://github.com/DietrichGebert/ponytail) | Makes your AI agent think like the laziest senior dev in the room. The best code is the code you never wrote. | [MIT](https://github.com/DietrichGebert/ponytail?tab=MIT-1-ov-file) |

## Contributing

- Enable hooks: `./scripts/setup-hooks.sh --project .` (pre-commit runs the fast gate, pre-push runs the full gate, which includes dev-qual's own tests via `npm test`).
- Run tests: `./scripts/run-unit-tests.sh` (`--strict` in CI, where a missing toolchain fails rather than skips). Tests live in `tests/` directories next to what they test — `test_*.sh`, `*.test.mjs`, `test_*.py`, `test_*.cs.sh` — and share helpers in `scripts/tests/lib/assert.sh`.
- CI: `.github/workflows/test-tools.yml` runs lint-docs, the fast gate, and the strict tests on every PR, merge to main, and on demand.
