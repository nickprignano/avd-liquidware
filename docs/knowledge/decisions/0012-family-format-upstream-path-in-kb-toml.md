---
status: proposed
date: 2026-10-18
decision-makers: [maintainers]
---

# 0012. Family format: the upstream asks file's path set in kb.toml

## Context and Problem Statement

The shared scripts read a KB's upstream asks (`upstream.yaml`, gaps and asks for a vendor) from a
fixed folder named after one vendor, and the template doesn't ship its schema. A KB about another
vendor can't use the data file without changing the shared scripts, which the format forbids. This
KB keeps its asks as a Markdown table ([liquidware/upstream.md](../liquidware/upstream.md)) for
now. Should the path move into `kb.toml`?

## Considered Options

- An optional `upstream` path in `kb.toml`, read by `kblib.py`, with `upstream.schema.json`
  and the generated table shipped in the template
- Keep the fixed path and let other KBs use Markdown

## Decision Outcome

Chosen option: "A path in kb.toml", because `kb.toml` already holds every per-KB setting, and the
upstream asks are part of the family's shared layout.

### Consequences

- Good, because every KB can track vendor asks as data with the same schema and checks.
- Bad, because it's a change to the shared scripts and template, adopted by PR in every KB.

## More Information

A family format change, raised with ai-brain, which owns the format
([ai-brain 0007](https://github.com/nickprignano/ai-brain/blob/main/docs/knowledge/decisions/0007-family-format-ai-brain-as-format-source.md)). Once adopted, this KB moves
its table to `liquidware/upstream.yaml`.

Two more per-KB values sit in the shared scripts today and could move to `kb.toml` in the same
change: the code languages the prior-art check searches (Python and TypeScript; this KB would want
Bicep and PowerShell), and the examples in the known-errors schema's descriptions.
