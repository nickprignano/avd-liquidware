---
status: proposed
date: 2026-10-18
decision-makers: [maintainers]
---

# 0004. Deploy appliances from Azure Marketplace; no Liquidware binaries or license material in the repo

## Context and Problem Statement

The appliances can come from Azure Marketplace or a VHD download, and the Connector ID Key
installer is needed on every desktop. A public repo can't redistribute Liquidware's software or
licenses. How does the tooling get them?

## Considered Options

- Marketplace images for the appliances; the installer fetched from the user's own Hub
- Upload Liquidware's VHD to the user's subscription
- Ship the installer in the repo

## Decision Outcome

Chosen option: "Marketplace images, installer from the user's Hub", because Marketplace handles
the image and its terms, and the Hub already serves the installer that matches it.

### Consequences

- Good, because nothing Liquidware owns is redistributed, and users bring their own license.
- Bad, because the VM needs a matching `plan` block and accepted terms per subscription and plan
  ([azure/marketplace.md](../azure/marketplace.md)).
- Bad, because subscriptions that block Marketplace can't use the tooling until a VHD path exists.
