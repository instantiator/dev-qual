---
type: standard
title: NestJS standards
description: Module layout, DI, config, and testing for NestJS. Read when working in a NestJS application.
tags: [nestjs, backend, framework]
---

# NestJS

- One module per domain concept; keep controllers thin — business logic lives in services.
- Use constructor injection everywhere; avoid manually instantiating classes that the DI container should own.
- Validate configuration at startup (`@nestjs/config` with a validation schema) so a bad env fails fast, not mid-request.
- Validate inputs at the boundary with DTO classes + `class-validator` and a global `ValidationPipe` (`whitelist: true`).
- Use exception filters / built-in HTTP exceptions rather than returning error objects.
- For monorepos, share entities/DTOs via a library path alias (e.g. `@app/shared`) with explicit exports from a single `index.ts`.

## Testing

- Unit test services with `@nestjs/testing`'s `Test.createTestingModule`, mocking providers by token (typed mocks, no `any` — see [typescript](../languages/typescript/typescript.md)).
- E2E test controllers with `supertest` against a compiled app instance; keep a separate jest config per tier ([testing](../standards/testing.md)).
