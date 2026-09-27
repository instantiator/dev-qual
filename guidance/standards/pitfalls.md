---
type: standard
title: Common pitfalls
description: Mistakes coding agents make repeatedly. Read during code review, or when check.sh or aislop report problems.
tags: [standards, pitfalls, review]
---

# Common pitfalls

Avoid these — they are the most frequent defects in agent-written code:

- **Swallowed exceptions** — empty catch blocks, or catching just to log and continue when the operation actually failed. Handle it or let it propagate ([error-handling](error-handling.md)).
- **Narrative comments** — comments that narrate the diff ("added a check for null") or explain the obvious. Comments state intent (see [common](common.md)).
- **Stale comments** — a function changed but its doc comment didn't. When editing code, re-read its comment.
- **`TODO` / `LATER` / `qq` without a condition** — every deferred item MUST say WHEN or under what CONDITIONS it should be dealt with. Add the condition (ask the user if unclear), then decide whether to tackle it now ([outstanding-work](../process/outstanding-work.md)).
- **Dead code** — unused functions, unreachable branches, commented-out blocks. Delete them.
- **Casting to `any`** (TS) or equivalent type-system escapes — especially common in test mocks. Type the mock instead.
- **Oversized functions** — see [readability](readability.md).
- **Assumed versions** — pinning a dependency or Action version from memory. Check what is current ([dependencies](dependencies.md)).
- **Fix without diagnosis** — patching a symptom before forming a hypothesis about the cause ([fixing-issues](../process/fixing-issues.md)).

`npx aislop scan` catches many of these automatically; `scripts/check.sh` runs it when available.
