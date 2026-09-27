---
type: standard
title: C# standards
description: Rules and tooling for C# code. Read when writing or reviewing .cs files or .csproj projects.
tags: [csharp, dotnet, language]
---

# C# standards

- Prefer fluent LINQ to keep code concise.
- Use C# documentation comments (`///`) for methods, classes, interfaces, and public members; link with `<see cref="MyClass.MyMethod"/>`.
- Namespaces match the directory structure.
- Enable nullable reference types (`<Nullable>enable</Nullable>`).
- Treat warnings as errors in the project file (`<TreatWarningsAsErrors>true</TreatWarningsAsErrors>`) — this enforces the 0-warnings rule at build time.
- Use the latest LTS .NET SDK (verify what is current — training data goes stale).

## Tooling

| Purpose | Tool |
|-|-|
| Lint | Roslyn analyzers (on by default) + `.editorconfig` for style rules |
| Format | `dotnet format` (verify in CI with `dotnet format --verify-no-changes`) |
| Build/typecheck | `dotnet build` |
| Test | xUnit via `dotnet test` |
| Vulnerabilities | `dotnet list package --vulnerable` |

## dev-qual tools

- Adopt `tools/Baseline.props` from `Directory.Build.props` **and** `tools/Baseline.targets` from `Directory.Build.targets` (the latter carries the one setting that must see the project's own properties); check both with `dotnet run --file tools/check-baseline.cs -- --project <dir>`.
- Run `dotnet run --file tools/vuln-report.cs` for a ranked, actionable `dotnet list package --vulnerable` report (the deps-audit skill calls it during audits).
