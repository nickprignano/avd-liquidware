---
status: proposed
date: 2026-10-18
decision-makers: [maintainers]
---

# 0011. Family format: a guard field on known errors

## Context and Problem Statement

This project's rule is that every lesson from a real run adds a guard, a test or a check that stops
it coming back ([0007](0007-real-runs-are-the-source-of-truth.md)). The family's known-error
entries record symptom, cause, fix and source, but not whether anything now prevents the error. A
fixed error with no guard is likely to return. Should the shared format record the guard?

## Considered Options

- An optional `guard` field on each known error (a repo path to the test or check, or a short
  description), and the freshness check lists verified entries without one
- Keep guards in the fix text

## Decision Outcome

Chosen option: "An optional `guard` field", because a separate field can be checked and listed,
and an optional one costs KBs without tests nothing.

### Consequences

- Good, because each KB can see which fixed errors could still come back.
- Neutral, because it's optional, so existing entries stay valid.
- Bad, because it's a change to the shared schema and freshness script, adopted by PR in every KB.

## More Information

A family format change: written here as proposed, then raised with ai-brain, which owns the format
([ai-brain 0007](https://github.com/nickprignano/ai-brain/blob/main/docs/knowledge/decisions/0007-family-format-ai-brain-as-format-source.md)). This KB keeps the shared
schema unchanged until the family adopts it.
