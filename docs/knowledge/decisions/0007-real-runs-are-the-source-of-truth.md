---
status: proposed
date: 2026-10-18
decision-makers: [maintainers]
---

# 0007. Real runs are the source of truth; every lesson adds a guard

## Context and Problem Statement

Much of how the appliances behave in Azure (first boot, which credential they honor, what the API
covers) comes from vendor documentation and hasn't been seen on a real run. When a run proves the
documentation wrong, how does that lesson stick?

## Considered Options

- Fix the code, add a guard (a Pester test or a preflight check), and record the lesson in the KB
- Fix the code and note it in the commit message

## Decision Outcome

Chosen option: "Fix, guard and record", because a lesson that only lives in a commit is found again
by the next person who hits it, and a guard stops the same mistake coming back.

### Consequences

- Good, because the KB's *unverified* markers turn into checked facts one run at a time.
- Good, because a known error can point at the guard that now prevents it.
- Neutral, because the family's known-error format has no field for the guard yet; a format change
  is proposed in [0011](0011-family-format-guard-on-known-errors.md).
