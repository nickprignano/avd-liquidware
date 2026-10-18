---
status: accepted
date: 2026-10-18
decision-makers: [maintainers]
---

# 0002. MIT for the repo; the knowledge base tooling keeps Apache-2.0

## Context and Problem Statement

The repo is public and needs a license. Its knowledge base tooling is adapted from Apache-2.0
projects in the family, while the maintainer's other public AVD repos use MIT. Which license
applies, and how do the adapted files keep theirs?

## Considered Options

- MIT for the repo, with the adapted tooling under Apache-2.0 and a NOTICE
- Apache-2.0 for the whole repo, like the family's reference KBs
- No license

## Decision Outcome

Chosen option: "MIT for the repo, with the adapted tooling under Apache-2.0", because the
maintainer chose MIT to match the other public AVD repos (Apache's patent grant doesn't matter for
this automation), and Apache-2.0 lets its files sit in an MIT repo as long as the license text and
NOTICE travel with them.

### Consequences

- Good, because reusers of the Bicep and PowerShell get the simple MIT terms.
- Good, because the shared tooling stays byte-identical with the family's, so format updates apply
  cleanly.
- Bad, because the repo carries two licenses; [NOTICE](../../../NOTICE) lists which paths each
  covers.

## More Information

The Apache-2.0 text is in [LICENSE-APACHE](../../../LICENSE-APACHE).
