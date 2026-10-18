---
status: accepted
date: 2026-10-18
decision-makers: [maintainers]
---

# 0001. Adopt the 2ndbrain knowledge base format, version 1

## Context and Problem Statement

This project learns things about Stratusphere in Azure that nobody has written down: Marketplace
plans, appliance credentials, callback paths, what the API can and can't do. Those findings were
spread across tool docs, a research note and memory. Where should they live, and in what format?

## Considered Options

- Adopt the family's 2ndbrain format (version 1), exported from ai-brain's template
- A format of its own, such as the lessons folder the tooling started with
- No in-repo knowledge base; keep notes elsewhere

## Decision Outcome

Chosen option: "Adopt the 2ndbrain format", because its checks, digest and freshness loops are
already built and tested, it uses no LLM tokens or API keys to run, and the sibling knowledge bases
in [family.yaml](../family.yaml) can watch and link to this one.

### Consequences

- Good, because knowledge changes in the same PR as the code it describes.
- Good, because format changes arrive through the template and are adopted by PR.
- Neutral, because topics and data are this project's own; only the format is shared.
- Neutral, because the tool docs under `stratusphere/docs/` stay as how-to guides, and the KB
  links to them rather than repeating them.

## More Information

The system is specified in [the 2ndbrain spec](../../2ndbrain/SPEC.md). The family's own record:
[nerdio-hcl 0021](https://github.com/nickprignano/nerdio-hcl/blob/main/docs/knowledge/decisions/0021-knowledge-base-family.md).
