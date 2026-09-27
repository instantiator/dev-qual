# Outstanding issues

Deferred work, each with a condition that says when to act on it. Reviewed at
the end of every task — see `guidance/process/outstanding-work.md`.

| Item | Why deferred | Condition to act | Where |
|-|-|-|-|
| Run `hadolint` as a gate stage | `check-prereqs.sh` checks for it, but the gate never runs it. No Dockerfile exists here to test the stage against. | A `Dockerfile` or `docker-compose*.yml` exists in this repo, or a consumer project reports a Dockerfile going unlinted | `scripts/check.sh`, generic stages section |
| Validate the guidance with a small model | Phase 4 of the 001 plan was never run: the three benchmark tasks (seeded bugfix, small feature, docs update) against `agents-files/local/AGENTS.md`. | A scratch or sample project is available to run OpenCode against with a small-context model | `prompts/001.2 - quality and reliability enhancements plan.md`, §9 |
