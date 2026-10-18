---
status: proposed
date: 2026-10-18
decision-makers: [maintainers]
---

# 0009. Unlicensed code is reference only

## Context and Problem Statement

Liquidware's public samples (the liquidwarelabs SE PowerTools) carry no license file. Without a
license, no reuse rights are granted, even for public code. How may this project use such code?

## Considered Options

- Reference only: use facts from it and cite it, never copy, adapt or redistribute it
- Copy useful snippets with attribution

## Decision Outcome

Chosen option: "Reference only", because attribution doesn't grant rights the author never gave.

### Consequences

- Good, because the repo stays clean to reuse under its own licenses.
- Bad, because some sample logic has to be rewritten from the documented behavior.

## More Information

Also recorded in [nerdio-hcl 0013](https://github.com/nickprignano/nerdio-hcl/blob/main/docs/knowledge/decisions/0013-unlicensed-code-reference-only.md).
