---
title: "Networking for Stratusphere in Azure"
summary: "The ports the appliances and Connector ID Keys need, egress without default outbound access, peering, and how routes affect callbacks"
topic: azure
status: unverified
last_reviewed: 2026-10-18
---

# Networking for Stratusphere in Azure

The assessment environment sits in its own VNet, peered to the network the desktops are on. The
ports below come from Liquidware's documentation and are *unverified* on a real run.

| Traffic | Port | Between |
|---|---|---|
| Connector ID Key callbacks | TCP 443 | Desktops to the Hub or a Collector |
| Database | TCP 5432 (PostgreSQL) | Collectors and the Hub to the Database appliance, or to the Hub without one |
| Console | TCP 443 | Administrators to each appliance's web console |
| SSH | TCP 22 | Administrators (through Bastion, or a peered jump host) |

## Egress

With default outbound access turned off on the subnet, the appliances need an explicit way out for
updates and time sync. This repo uses a NAT Gateway. A NAT Gateway bills while it exists, even with
every VM stopped ([lab-costs.md](lab-costs.md)).

## Peering and routes

- Peering fails if the two address spaces overlap, so check the assessment range against the peer
  VNet and the VNets already peered to it.
- With direct peering, Azure adds a system route for the assessment range. A user route wins only
  if it's at least as specific, so a forced-tunnel `0.0.0.0/0` to a firewall doesn't divert the
  callbacks.
- Without direct peering (the desktops reach the assessment VNet through a hub network), the covering
  route decides, and a firewall on that path must allow TCP 443 to the Hub.
- NSG rules are evaluated by priority and the first match wins. A deny above the allow for TCP 443
  silently stops the callbacks.

The preflight checks all of this:
[stratusphere/docs/preflight.md](../../../stratusphere/docs/preflight.md).
