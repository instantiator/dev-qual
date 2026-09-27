---
type: standard
title: Error handling
description: Rules for failing fast, propagating with context, retries, cleanup, and structured logging. Read when writing code that can fail or that logs.
tags: [standards, error-handling, logging]
---

# Error handling

## Fail fast vs handle

- Programmer errors (violated invariants, impossible states) should fail fast — let them crash or assert, don't handle them.
- Expected failures (network down, invalid input, not found) should be handled explicitly at a level that can act on them.
- Never swallow an exception — no empty catch, no catch-log-and-continue when the operation actually failed ([pitfalls](pitfalls.md)).

## Propagation

- Catch where you can act; otherwise let it propagate.
- When rethrowing, add context (wrap with the original as `cause`) — don't discard the original error.
- Don't log an error and then rethrow it — it gets logged again at the level that finally handles it. Log once, where it's handled.
- Use typed/domain errors at module boundaries. At an API boundary, translate: internal detail goes to logs, a safe message plus a correlation id goes to the caller.

## Retries

- Retry only transient failures (timeouts, 5xx, connection resets) — never validation or logic errors.
- Bound retries with a count and backoff; only retry operations that are idempotent.

## Cleanup

- Release resources with the language's construct for it (`finally`, `using`, `with`, `defer`) — not a manual call that a thrown error can skip.

## Logging

- Levels have meaning: `error` = someone must act now, `warn` = degraded but working, `info` = a business event occurred, `debug` = diagnostics for developers.
- One event per line, with key-value context (not a formatted sentence to parse later).
- Include a correlation/request id so one request's events can be traced across services.
- Never log secrets or personal data ([security](security.md)).

## User-facing messages

- Say what happened and what to do next ("Payment failed — check your card details and retry"), not a stack trace or error code alone.
