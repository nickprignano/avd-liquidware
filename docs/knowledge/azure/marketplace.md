---
title: "Stratusphere in Azure Marketplace"
summary: "Liquidware's Marketplace offer: finding the plan for a region, the plan block a VM needs, and accepting terms per subscription"
topic: azure
status: partial
last_reviewed: 2026-10-18
---

# Stratusphere in Azure Marketplace

The appliances are deployed from Liquidware's Azure Marketplace image: publisher `liquidware`,
offer `stratusphere`. Three things have to line up before a VM deploys.

1. **The plan (SKU) offered in your region.** Plan names aren't on the public listing. List them
   with `az vm image list-skus -l <region> -p liquidware -f stratusphere`, or
   `Get-AzVMImageSku`. Which plans exist for the Database and Collector roles is *unverified*.
2. **A matching `plan` block.** The image carries a purchase plan, so the VM must send a `plan`
   (name, publisher, product) that matches its `imageReference`, or Azure refuses it. The repo's
   Pester tests guard this.
3. **Accepted terms.** Acceptance is per subscription and per plan, and accepting again is harmless:
   `az vm image terms accept` or `Set-AzMarketplaceTerms`. It's done by script, not Bicep: the
   `Microsoft.MarketplaceOrdering` agreement resource needs the full terms record read back from
   Azure first, which a template can't do on its own.

## Gotchas

- An organization that blocks Marketplace purchases, or limits images with Azure Policy, fails the
  deployment at the VM. Check the subscription's policy before the first run.
- A VM's plan can't change after creation.
- Liquidware also offers a VHD download; deploying from it isn't covered here yet.

How-to: [stratusphere/docs/marketplace.md](../../../stratusphere/docs/marketplace.md).
