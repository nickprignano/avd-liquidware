---
status: proposed
date: 2026-10-18
decision-makers: [maintainers]
---

# 0008. Everything runs from Azure Cloud Shell

## Context and Problem Statement

The maintainer often works from an iPad, and assessment environments are often set up from a
customer's or a lab's browser session. A step that needs local installs stalls the run. Where must
the tooling run?

## Considered Options

- Azure Cloud Shell in a browser, with nothing installed locally
- A local workstation with PowerShell, the Az modules and Bicep

## Decision Outcome

Chosen option: "Azure Cloud Shell", because it has PowerShell, the Az modules, the Azure CLI and
Bicep, and works from any browser.

### Consequences

- Good, because there's nothing to install, and the signed-in identity is the operator's own.
- Bad, because Cloud Shell sessions time out, so long rollouts write their results to files that
  can be resumed from.

## More Information

Also recorded in [nerdio-hcl 0012](https://github.com/nickprignano/nerdio-hcl/blob/main/docs/knowledge/decisions/0012-cloud-shell-baseline.md).
