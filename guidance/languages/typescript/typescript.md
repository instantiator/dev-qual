---
type: standard
title: TypeScript standards
description: Rules and tooling for TypeScript code. Read when writing or reviewing .ts/.tsx files.
tags: [typescript, language]
---

# TypeScript

- Use strict mode (`"strict": true` in tsconfig).
- Avoid casting to `any` — especially in test mocks; type the mock instead. Enable `@typescript-eslint/no-explicit-any` so the rule is enforced, with targeted disables only where genuinely unavoidable.
- Prefer TSDoc multi-line comments, unless the comment fits on one line.
- Link to types in comments with `{@link TheType}`.

## Tooling

| Purpose | Tool |
|-|-|
| Lint | ESLint (flat config) + typescript-eslint recommended-type-checked |
| Format | Prettier, run via eslint-plugin-prettier so formatting issues surface as lint warnings |
| Typecheck | `tsc --noEmit`, exposed as an npm script named `typecheck` |
| Test | Jest or Vitest (match whatever the project already uses) |
| Slop scan | `npx aislop scan` |

- Expose each as an npm script (`lint`, `lint:check`, `format`, `typecheck`, `test`) so `check.sh` and CI can find them.
- For TypeScript as a scripting language (not an app), see [node-scripting](../node-scripting/node-scripting.md).
