---
type: standard
title: AWS CDK
description: Writing and verifying CDK stacks. Read when editing CDK infrastructure code.
tags: [infra, aws, cdk, typescript]
---

# AWS CDK

- Use TypeScript CDK unless the project's language dictates otherwise; usual TS rules apply ([typescript](../languages/typescript/typescript.md)).
- Prefer L2 constructs; drop to L1 (`Cfn*`) only when the L2 doesn't expose what you need — comment why.
- One stack per deployable unit; share values between stacks via props, not `Fn.importValue` string coupling.
- Grant permissions with the construct helpers (`bucket.grantRead(fn)`) rather than hand-written policies.
- Pin the CDK library version and keep `cdk.context.json` committed (deterministic synth).
- No secrets in code or context — reference Secrets Manager / SSM at deploy time.

## Verification (run before every deploy)

- `cdk synth` must succeed; run unit tests with CDK assertions (`aws-cdk-lib/assertions`) for critical resources.
- `cdk diff` before every deploy — read it, especially for replacements and IAM changes.
