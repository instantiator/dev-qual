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
| Run the pi extension in a live pi session | Install, list, remove and `check-install.sh` are verified against real pi 0.73.1, and the handlers are written to its shipped extension types and tested against a fake API. No live model session has exercised them: that needs a provider API key. | A pi session with a configured provider is available, or a pi user reports the post-edit or stop gate not firing | `adapters/pi/extension.mjs` |
