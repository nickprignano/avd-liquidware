---
title: "Lab costs and teardown"
summary: "What keeps billing while a Stratusphere lab is stopped, and why a lab run ends torn down"
topic: azure
status: partial
last_reviewed: 2026-10-21
---

# Lab costs and teardown

A lab run ends with the environment torn down, or with everything deallocated that can be. Stopping
the VMs isn't enough on its own.

- **Deallocate, don't just stop.** A VM stopped from inside the guest keeps its compute reserved and
  billed. Stop it from Azure so it's deallocated.
- **Some resources bill while the VMs are off.** A NAT Gateway, Azure Bastion Basic or higher,
  public IPs and managed disks keep billing whatever the VMs do. Bastion Developer is the exception:
  no hourly or outbound data charge, but one connection at a time and only to VMs in its own VNet
  ([SKU comparison](https://learn.microsoft.com/azure/bastion/bastion-sku-comparison)). Tearing the environment down is the only way to
  stop those.
- **Key Vault after a teardown.** With purge protection the vault stays soft-deleted for its
  retention period, and its name can't be reused until it's recovered or purged. The repo's deploy
  script recovers it.
- **Cheaper console access.** One small desktop peered to the assessment VNet can replace Bastion
  as the way into the consoles. Deallocate it between sittings. The landing zone's opt-in jumpbox
  ([avd-landing-zone decision 0019](https://github.com/nickprignano/avd-landing-zone/blob/master/build/decisions/0019-jumpbox-bastion-developer.md)) is a Linux VM in the spoke reached through Bastion
  Developer. Bastion Developer itself does not follow peering, so it can't reach VMs in a peered
  assessment VNet directly.

Prices change; check the [Azure pricing calculator](https://azure.microsoft.com/pricing/calculator/)
rather than recording figures here.
