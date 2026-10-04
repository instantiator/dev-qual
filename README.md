# dev-qual

Guidance, skills, and scripts that help coding agents (Claude Code, OpenCode, pi, or any other) deliver consistently high-quality code — designed so that even small-context models can complete features and fixes to a high standard.

## How to use dev-qual

Install dev-qual with its installer: `./dev-qual/install.sh` (see [Install](#install) for the options).

dev-qual is geared for a planning/implementation cycle. Switch your agent into planning mode and describe the plan you want it to create. Let your most capable model drive this step, so it can make the best assessments and do a lot of the work upfront. Using the `plan-work` skill, it prepares a plan that divides the work among sub-agents for token efficiency (where other models are available). Your most capable agent then orchestrates the implementation: it hands tasks to less capable agents, reviews their work, and resolves complex issues.

It will ensure:

- High quality code, using the guidance in dev-qual
- Tests are written at appropriate levels (unit, integration, end-to-end)
- A plan that's broken into stages, each gated on a quality check
- Project documentation kept up to date

dev-qual also installs commit hooks (fast quality checks) and push hooks (the full quality gate) to catch issues before they enter your code base, plus agent hooks that check each edit and stop the agent finishing with failing checks or unfinished plan stages.

## What's here

| Path | What it is |
|-|-|
| `agents-files/` | Entry-point instructions merged into your project or user config (`local/` for small-context agents, `remote/` for capable ones, plus a Claude Code variant) |
| `guidance/` | Condensed standards and process docs, one topic per file, routed by `guidance/index.md`. Each language in `guidance/languages/<lang>/` carries its own `tools/`. |
| `skills/` | Step-by-step playbooks for multi-step tasks (planning, project setup, CI, reviews, deploys, ADRs, ...), routed by `skills/index.md` |
| `scripts/` | The automation: the quality gate, install/upgrade/enable/disable, git and agent hooks, and the reports described below |
| `adapters/` | Wiring for each agent platform: Claude Code (skills and hooks), OpenCode (AGENTS.md routing), pi (package extension) |
| `configs/` | Shared tool config used by the gate when a project supplies none (currently markdownlint) |

## Install

The installer is interactive: it asks for the scope, the agent tier, and your platforms (`claude`, `opencode`, `pi`). It merges its instructions into marked blocks, never overwriting your own content, and records your answers so upgrades and enable/disable can replay them. Re-run it any time; `--help` lists the non-interactive flags.

### For one repository (project scope)

```bash
git submodule add https://github.com/instantiator/dev-qual
./dev-qual/install.sh
```

This writes into the repo: AGENTS.md and CLAUDE.md blocks, `.claude/` skills and hooks, and `.dev-qual.env`, which records your choices. If the project uses Prettier, it also adds a block to `.prettierignore` listing every submodule, dev-qual included: each is its own repo's to lint. `check.sh` skips submodules for the linters it runs itself, and upgrades keep the block in step as submodules come and go. Commit `.dev-qual.env` so teammates can run `./dev-qual/install.sh --from-config`. If your plans live somewhere other than `docs/plans/`, add a line such as `PLANS_GLOB='docs/prompts/phase 04/*.plan*.md'` to it; re-installs keep it. The installer also offers the git hooks.

### For all your repositories (user scope)

```bash
git clone https://github.com/instantiator/dev-qual ~/.local/share/dev-qual
~/.local/share/dev-qual/install.sh --user
```

This wires `~/.claude/` (CLAUDE.md, skills, hooks) and `~/.config/opencode/AGENTS.md`, and records your choices in `~/.config/dev-qual/config.env`. Git hooks stay per repository: the first time an agent works in a repo without them, it offers to install them, and a "no" is remembered for that repo. A repo with its own project-scope install takes precedence over the user-scope one.

### pi

Choose `pi` as a platform, or install the checkout directly as a pi package:

```bash
pi install ./dev-qual -l                 # this project
pi install ~/.local/share/dev-qual      # all projects
```

A local-path install is loaded in place, so upgrading the checkout upgrades pi too. `scripts/build-pi-package.sh` builds an installable tarball in `dist/`, the first step towards publishing dev-qual as a pi package.

## Keep it up to date

Agents check for updates at the start of every session (without blocking or going online in the foreground) and offer to upgrade. To do it yourself:

```bash
./dev-qual/scripts/upgrade.sh           # project scope (then commit the submodule pointer)
~/.local/share/dev-qual/scripts/upgrade.sh --user
```

`upgrade.sh` updates the checkout, replays your recorded install, and runs `scripts/check-install.sh`, which reports anything in your setup that differs from the checkout — an edited block, copied hooks, a skill that is no longer a symlink — so you can merge rather than overwrite. The `update-latest` skill walks an agent through it.

### Upgrading from an earlier version

Installs from before `install.sh` recorded its choices have no `.dev-qual.env`, so `upgrade.sh` stops with "not installed". Upgrade once by hand; after that, `upgrade.sh` works.

1. Update the checkout: `git submodule update --remote dev-qual`.

   If it's still installed under its old name, `dev-environment`, move it first. The installer replaces the old marker blocks rather than duplicating them.

   ```bash
   git mv dev-environment dev-qual
   git submodule set-url dev-qual https://github.com/instantiator/dev-qual.git
   git submodule update --remote dev-qual
   ```

2. Re-run the installer once, interactively: `./dev-qual/install.sh`. Choose the same tier and platforms as before. It:
   - records your choices in `.dev-qual.env`;
   - refreshes the `AGENTS.md` block;
   - moves `CLAUDE.md` into a marked block. An unedited old copy is replaced cleanly. If you had edited it, the block is appended with a NOTE: delete the old copied text so the instructions don't appear twice;
   - replaces the old post-edit hook in `.claude/settings.json` with the three agent hooks, keeping hooks of your own.
   - adds the submodules block to `.prettierignore` if you use Prettier. Delete any `dev-environment` line of your own there: the submodule is now `dev-qual`, and the block covers it.
3. Git hooks installed the default way (`core.hooksPath`) are already current. If you installed them with `--copy`, re-run `./dev-qual/scripts/setup-hooks.sh --copy` (compare first if you edited them).
4. Run `./dev-qual/scripts/check-install.sh`: everything should PASS.
5. Commit the submodule pointer, `.dev-qual.env`, `AGENTS.md`, `CLAUDE.md`, `.prettierignore`, and `.claude/settings.json` if you track it. Teammates then run `./dev-qual/install.sh --from-config` instead of answering the questions.

## Enable and disable

```bash
./dev-qual/scripts/toggle.sh disable     # or: enable, status  (add --user for user scope)
```

`disable` removes everything the install wired in (blocks, skill links, agent hooks, git hooks) but keeps your recorded choices; `enable` restores exactly the same setup.

## The quality gate

`scripts/check.sh` detects every stack in your project — Node/TypeScript, .NET, Python, plus shell, markdown, and CI workflows wherever they appear — and runs format check → lint → typecheck → build → unit tests → `aislop scan`, printing PASS/FAIL with a fix hint per failure. Missing tools SKIP with an install command rather than breaking the run.

| Mode | Adds | Run by |
|-|-|-|
| `--fast` | format, lint, typecheck | pre-commit hook, the post-edit agent hook, each plan stage's gate |
| _(default)_ | build, unit tests, `aislop scan` | pre-push hook |
| `--comprehensive` | every test suite, package security audit | the final stage of a plan |

`pre-commit` checks exactly what is staged — unstaged edits and untracked files can neither block a commit nor hide a problem in it — then runs `scripts/pre-commit-fixups.sh` if your project has one (formatting, generated files, licence lists) and re-stages what it changed, leaving partially-staged files alone.

Tools that take effort off the agent:

- **Lint baselines**: TypeScript (ESLint), Python (ruff), and C# (MSBuild) baselines in `guidance/languages/<lang>/tools/` turn the written rules (no `any`, no blind excepts, bounded complexity, documented public APIs) into lint errors. The gate reports whether your project extends them and prints the exact lines to add.
- **`scripts/vuln-report.sh`**: runs each stack's audit and ranks the findings, with the command to fix each and major bumps flagged.
- **`scripts/stale-docs.sh`**: lists the doc lines that mention files or declarations your change touched, for the documentation step.

## Agent hooks

Claude Code (through `.claude/settings.json`) and pi (through the package's extension) call `scripts/agent-hook.sh` at three points:

| Hook | What it does |
|-|-|
| post-edit | Runs `check.sh --fast` after each edit and shows the agent any failures. |
| session-start | Reports a dev-qual update if one is available; at user scope, offers git hooks to a repo without them. |
| stop | When code (not just docs) has changed, runs the fast gate and lists unticked stages of active plans (`docs/plans/*.md`, or `PLANS_GLOB` in `.dev-qual.env`), blocking the agent from finishing once. |

## Third party tools

Some of these rules refer to and lean on third party tools. With gratitude:

| Tool | Description | License |
|-|-|-|
| [aislop](https://github.com/scanaislop/aislop) | Catch the slop AI coding agents leave in your code: narrative comments, swallowed exceptions, as-any casts, dead code, oversized functions. 50+ rules across 8 languages. | [MIT](https://github.com/scanaislop/aislop?tab=MIT-1-ov-file) |
| [ponytail](https://github.com/DietrichGebert/ponytail) | Makes your AI agent think like the laziest senior dev in the room. The best code is the code you never wrote. | [MIT](https://github.com/DietrichGebert/ponytail?tab=MIT-1-ov-file) |

## Contributing

- Enable hooks: `./scripts/setup-hooks.sh --project .` (pre-commit runs the fast gate, pre-push runs the full gate, which includes dev-qual's own tests via `npm test`).
- Run tests: `./scripts/run-unit-tests.sh` (`--strict` in CI, where a missing toolchain fails rather than skips). Tests live in `tests/` directories next to what they test — `test_*.sh`, `*.test.mjs`, `test_*.py`, `test_*.cs.sh` — and share helpers in `scripts/tests/lib/assert.sh`.
- CI: `.github/workflows/test-tools.yml` runs lint-docs, the fast gate, the strict tests, and the pi package build on every PR, merge to main, and on demand.
