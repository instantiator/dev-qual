# Outstanding issues

Deferred work, each with a condition that says when to act on it. Reviewed at
the end of every task — see `guidance/process/outstanding-work.md`.

| Item | Why deferred | Condition to act | Where |
|-|-|-|-|
| Run `hadolint` as a gate stage | `check-prereqs.sh` checks for it, but the gate never runs it. No Dockerfile exists here to test the stage against. | A `Dockerfile` or `docker-compose*.yml` exists in this repo, or a consumer project reports a Dockerfile going unlinted | `scripts/check.sh`, generic stages section |
| Validate the guidance with a small model | Phase 4 of the 001 plan was never run: the three benchmark tasks (seeded bugfix, small feature, docs update) against `agents-files/local/AGENTS.md`. | A scratch or sample project is available to run OpenCode against with a small-context model | `prompts/001.2 - quality and reliability enhancements plan.md`, §9 |
| API design and versioning standard | Not needed by current consumers | A consumer project exposes a public HTTP API | `guidance/standards/` |
| UI accessibility standard | Not needed by current consumers | A React (or other UI) consumer project is onboarded | `guidance/frameworks/react.md` / `guidance/standards/` |
| Move-method refactoring tool (TypeScript, via ts-morph) | High-risk/high-edge-case; baseline lint rules and aislop already cover the detection side | Misplaced-method findings (aislop, lint, or review) recur in 3 or more reviews | `guidance/languages/typescript/tools/` |
| Pre-commit gate checks the working tree, not the staged snapshot | So unstaged work-in-progress (e.g. a parallel agent's half-written file) can block an unrelated commit, and conversely unstaged fixes can let a broken staged snapshot through | This blocks a commit, or lets a failing commit through, in real use a second time | `scripts/hooks/pre-commit` |
| C# dev-qual tools: `Baseline.props` + checker, and a vulnerability report | Deferred by choice in the 003 plan: no .NET SDK on the development machine to test them. The TypeScript and Python equivalents set the pattern (`guidance/languages/<lang>/tools/`). | A .NET 10+ SDK is available to develop and test against, or a C# consumer project is onboarded | `guidance/languages/csharp/tools/`, `scripts/vuln-report.sh` |
| Verify the pi extension against a real pi install | pi's docs don't name the fields on `tool_result` (tool name, result text) or `agent_before_settle` (a stop-hook-active flag), so `adapters/pi/extension.mjs` reads several candidates defensively and is tested only against a fake API | pi is installed on a development machine, or a pi user reports the post-edit or stop gate not firing | `adapters/pi/extension.mjs` |
