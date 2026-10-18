---
title: "Stratusphere UX appliances in Azure"
summary: "Hub, Database and Collector roles: when each is needed, sizes, addresses, credentials and what hasn't been confirmed on a real run"
topic: stratusphere
status: unverified
last_reviewed: 2026-10-18
---

# Stratusphere UX appliances in Azure

Stratusphere UX runs as Linux appliances from Azure Marketplace. This repo deploys them with
[`Deploy-Stratusphere.ps1`](../../../stratusphere/docs/appliances.md); this page holds the facts
behind it. Nothing here has been confirmed on a real subscription yet, so every claim is
*unverified* until the first lab run.

## Roles

| Role | When | Size used here | Notes |
|---|---|---|---|
| Hub | Always | `Standard_D4s_v5`, 128 GB Premium SSD | Liquidware lists 4 vCPU, 16 GB RAM and 60 GB disk as the Hub minimum *(unverified)* |
| Database | Liquidware advises one above 1,000 Connector ID Keys *(unverified)* | `Standard_D4s_v5`, 256 GB | The Hub is pointed at it in its console (Hub Administration > Database) |
| Collector | Optional, to spread callback load | `Standard_D2s_v5`, 64 GB | Each one is registered with the Hub in its own console |

- Each role has its own Marketplace plan; see [azure/marketplace.md](../azure/marketplace.md).
  Whether Liquidware publishes Database and Collector plans in Azure Marketplace at all is
  *unverified*.
- A VM's Marketplace plan can't change after it's created, so changing role or plan means a new VM.

## Credentials

- Azure sets the appliance's admin password at creation. Whether the appliance honors that
  credential, or keeps its own default, is *unverified*.
- An appliance keeps the password it was created with, so a rerun has to reuse it. This repo
  generates it once and keeps it in Key Vault ([decision 0006](../decisions/0006-credentials-in-key-vault.md)).

## Licensing

Bring your own Stratusphere license. Liquidware offers a trial; the size and length of the trial
(25 desktops for 15 days was quoted) are *unverified*. No license material belongs in the repo
([decision 0004](../decisions/0004-marketplace-appliances-no-vendor-binaries.md)).

## First-time setup

The Hub's license, API user and API allow list are set in its web console. See
[hub-setup.md](hub-setup.md).
