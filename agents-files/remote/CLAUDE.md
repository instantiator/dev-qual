# Claude Code instructions

Follow `dev-qual/agents-files/remote/AGENTS.md` — those rules are mandatory. If this project has its own AGENTS.md merged from it, that copy governs.

## Claude Code specifics

- Skills from `dev-qual/skills/` may be installed at `.claude/skills/` (or `~/.claude/skills/`) — prefer invoking them over improvising the same workflow.
- If dev-qual's hooks are in `settings.json` (they call `dev-qual/scripts/agent-hook.sh`), `check.sh --fast` runs after every edit and its failures are shown to you: fix them, and don't re-run it redundantly. Otherwise run `dev-qual/scripts/check.sh` yourself after every change.
- Session-start output from dev-qual is actionable: offer the update or git hooks it names, and act on the user's answer.
- A dev-qual stop-hook block lists failing checks or unticked plan stages: fix them, or tell the user why they remain.
- Git hooks installed by `dev-qual/scripts/setup-hooks.sh` are the final gate: a failing pre-commit means fix the reported problems, never `--no-verify`.
- Mirror deferred work into memory with the same measurable condition it has in `docs/outstanding-issues.md` — the file is still the record, memory is only a reminder.
