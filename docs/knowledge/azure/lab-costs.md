---
title: "Lab costs and teardown"
summary: "What keeps billing while a Stratusphere lab is stopped, and why a lab run ends torn down"
topic: azure
status: partial
last_reviewed: 2026-10-18
---

# Lab costs and teardown

A lab run ends with the environment torn down, or with everything deallocated that can be. Stopping
the VMs isn't enough on its own.

- **Deallocate, don't just stop.** A VM stopped from inside the guest keeps its compute reserved and
  billed. Stop it from Azure so it's deallocated.
- **Some resources bill while the VMs are off.** A NAT Gateway, Azure Bastion, public IPs and
  managed disks keep billing whatever the VMs do. Tearing the environment down is the only way to
  stop those.
- **Key Vault after a teardown.** With purge protection the vault stays soft-deleted for its
  retention period, and its name can't be reused until it's recovered or purged. The repo's deploy
  script recovers it.
- **Cheaper console access.** One small desktop peered to the assessment VNet can replace Bastion
  as the way into the consoles. Deallocate it between sittings.

Prices change; check the [Azure pricing calculator](https://azure.microsoft.com/pricing/calculator/)
rather than recording figures here.
