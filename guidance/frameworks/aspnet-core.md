---
type: standard
title: ASP.NET Core standards
description: API style, DI, and configuration for ASP.NET Core. Read when working in an ASP.NET Core application.
tags: [aspnet, dotnet, backend, framework]
---

# ASP.NET Core

- Prefer minimal APIs for small services; controllers (MVC) when the app has many endpoints needing filters/conventions. Don't mix both styles in one app without reason.
- Use the built-in DI container; register services with the narrowest lifetime that works (prefer scoped over singleton for anything holding request state).
- Use the options pattern (`IOptions<T>` with a validated options class, `ValidateOnStart`) for configuration; fail fast on invalid config.
- Validate request models at the boundary (data annotations or FluentValidation); return `ProblemDetails` for errors rather than ad-hoc shapes.
- Use `ILogger<T>` structured logging; no `Console.WriteLine` in app code.
- Expose health checks via `MapHealthChecks("/healthz")`.
- General C# rules (nullable, warnings-as-errors, xUnit): [csharp](../languages/csharp/csharp.md).
- Integration-test with `WebApplicationFactory<Program>`; unit-test services directly.
