---
type: standard
title: Security
description: Concrete security rules for input handling, injection, auth, secrets, and transport. Read before handling untrusted input, secrets, or access control.
tags: [standards, security]
---

# Security

## Input

- Validate and normalise all input at every trust boundary — HTTP, CLI args, files, env vars, queue messages — before it reaches business logic.
- Use allow-lists and schema validation, not deny-lists. Reject invalid input; don't try to repair it.

## Injection and output

- SQL: parameterised queries only, never string-built ([databases](databases.md)).
- Shell: never build a command string from input; pass an argv array to the process API.
- HTML: use the framework's escaping; never inject raw HTML built from input.
- Paths: resolve and check against an allowed root before reading/writing a file from user-supplied path segments.

## Authentication and authorisation

- Deny by default; grant only what a role explicitly needs.
- Check authorisation on every request, server-side — never trust a client-side check or a hidden field.
- Give service accounts and tokens the least privilege that does the job, scoped and time-limited where the provider supports it.

## Secrets

- Never commit passwords, API keys, or other secrets to the code base, logs, or error messages.
- Load secrets from environment variables or a secret manager; ensure `.env` (and equivalents) are git-ignored.
- Rotate a secret immediately if it is ever exposed (commit, log, error report).

## Transport and storage

- Use TLS for data in transit; don't accept plaintext fallbacks.
- Hash passwords with a slow KDF (argon2id, bcrypt, or scrypt) — never a fast general-purpose hash, never a home-grown scheme.
- Never roll your own crypto; use vetted library primitives.

## Dependencies and errors

- Treat dependencies as an attack surface ([dependencies](dependencies.md)); `check.sh --comprehensive` audits them, and `dev-qual/scripts/vuln-report.sh` turns findings into ranked next steps.
- Errors must not leak internals (stack traces, queries, file paths) to the caller — see [error-handling](error-handling.md).

## Before shipping

- [ ] Every trust boundary validates input against an allow-list or schema.
- [ ] No string-built SQL or shell commands anywhere in the diff.
- [ ] Authorisation is checked server-side on every request.
- [ ] No secret appears in code, logs, or error messages; `.env` is git-ignored.
- [ ] `check.sh --comprehensive` has run and reports no unaddressed vulnerabilities.
