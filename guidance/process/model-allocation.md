---
type: process
title: Model allocation
description: Choosing the right model for a task, and delegating cheaper work to sub-agents. Read when starting a task that could be split across models.
tags: [process, models, sub-agents, cost]
---

# Model allocation

## Skip this if

- your platform has no sub-agents, or
- only one model is available to you, or
- the task is small enough that choosing costs more than it saves.

Then just do the work. Nothing below applies. This is the common case for local
and small-context agents, and thinking about it further is pure waste.

## Tiers, not model names

Model names and prices change faster than this document can. Reason in tiers,
and map them to whatever the provider actually offers today:

| Tier | Use it for |
|-|-|
| High-reasoning | Architecture, ambiguous problems, diagnosing a bug with no obvious cause, authoring a plan, judgement calls with lasting consequences. |
| Mid | Ordinary implementation against a clear specification. |
| Fast / cheap | Mechanical edits: renames, applying a decision already made across many files, formatting, filling in a fixed template. |

## Establishing the available set

If you do not know which models to choose between, ask the user once — not per
task:

1. List the models this provider actually offers. Check current reality; your
   training data goes stale ([dependencies](../standards/dependencies.md)).
2. Order them by capability, noting which are token-efficient and which are best
   for complex work.
3. Ask which the user wants in the selectable set.
4. Record the answer in `docs/agent-models.md`, listed in `docs/index.md`, and
   in platform memory if there is one. Read it instead of asking again.

## Responding to a prompt

If the task suits a different tier than the model you are running as, either:

- **halt** and recommend the user switch model, saying why and what it saves, or
- **delegate** to a sub-agent at the right tier and carry on.

Prefer delegating when you have the decision already; prefer halting when the
whole task is misallocated.

## In planning mode

The [plan-work](../../skills/plan-work/SKILL.md) skill sets the plan's structure; this section covers the model choice within it.

- Produce a table of the tasks a sub-agent could take, with the tier assigned to each and one line of reasoning.
- Where a task would suit a cheaper tier *if it were more specific*, add the specificity — concrete steps, exact file lists, exact changes — rather than escalating the model.

## In build mode

1. Identify the tasks.
2. Evaluate the available models **before** starting any of them.
3. Delegate downward wherever a cheaper model suffices, giving it the same added specificity.

## Split the decision from the mechanics

Most tasks are one judgement followed by repetitive application. Make the
judgement with the capable model, state it precisely, then hand the mechanical
steps to a cheap sub-agent. Do not spend a high-reasoning model on the second
half, and do not hand the first half to a model that cannot make the call.
