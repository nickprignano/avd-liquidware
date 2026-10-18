---
status: proposed
date: 2026-10-18
decision-makers: [maintainers]
---

# 0010. Prefer Azure-native, GitHub, HashiCorp and open-source tooling

## Context and Problem Statement

Every extra service is something a user has to buy, sign up for and trust with access. Which tools
may this project depend on?

## Considered Options

- Azure-native, GitHub, HashiCorp and open-source tooling; a paid third-party service needs its own
  decision record
- Whatever tool fits each job

## Decision Outcome

Chosen option: "Azure-native, GitHub, HashiCorp and open source first", because users already have
these, and the KB's own tooling runs on the built-in GitHub token alone.

### Consequences

- Good, because nothing beyond the Azure subscription and a Stratusphere license is needed.
- Neutral, because Liquidware's own products are the subject, not a dependency choice.

## More Information

Also recorded in [nerdio-hcl 0009](https://github.com/nickprignano/nerdio-hcl/blob/main/docs/knowledge/decisions/0009-prefer-azure-github-hashicorp-oss.md).
