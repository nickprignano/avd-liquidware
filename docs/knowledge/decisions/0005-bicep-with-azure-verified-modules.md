---
status: proposed
date: 2026-10-18
decision-makers: [maintainers]
---

# 0005. Bicep with pinned Azure Verified Modules, following avd-landing-zone

## Context and Problem Statement

The family's guardrails prefer Azure-native, GitHub, HashiCorp and open-source tooling, and the
reference kit uses Terraform. This project deploys a handful of Azure resources at subscription
scope, often next to an AVD landing zone built with Bicep. Which infrastructure-as-code tool fits?

## Considered Options

- Bicep with pinned Azure Verified Modules, following avd-landing-zone's conventions
- Terraform with the azurerm provider, like nerdio-hcl

## Decision Outcome

Chosen option: "Bicep with Azure Verified Modules", because it's Azure-native, needs no state
file or backend, runs from Cloud Shell as is, and matches the landing zone the assessed desktops
usually sit in.

### Consequences

- Good, because there's no state to store or protect, and what-if previews come free.
- Neutral, because Bicep is Azure-native, which the guardrails list alongside HashiCorp.
- Bad, because Terraform users of the family can't reuse these modules directly.

## More Information

The Terraform choice for Nerdio is [nerdio-hcl 0001](https://github.com/nickprignano/nerdio-hcl/blob/main/docs/knowledge/decisions/0001-build-on-nerdio-provider.md).

The tier's own template (`profileunity/bicep/`) uses native resources instead of modules, as a
named exception: its template tests check every role assignment's scope and principal in the
compiled template, and module wrappers hide them
([deploy-spec.md](https://github.com/nickprignano/avd-liquidware/blob/main/docs/deploy-spec.md)
section 5). The Stratusphere template keeps the modules.
