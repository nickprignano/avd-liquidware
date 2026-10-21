---
title: "Deployment gotchas"
summary: "What trips up a Liquidware deployment in Azure, across products, with a link to where each is explained"
topic: deployment
status: partial
last_reviewed: 2026-10-20
---

# Deployment gotchas

The short list to read before a deployment. Each line links to the page or known error that
explains it; errors with an exact message are in
[known-errors.yaml](../troubleshooting/known-errors.yaml).

## Stratusphere UX

- The Marketplace image needs a matching `plan` block and accepted terms per subscription and plan;
  policy that blocks Marketplace fails the VM ([azure/marketplace.md](../azure/marketplace.md)).
- Set the Hub's DNS name before downloading the Connector ID Key installer: the key calls whatever
  address was baked in ([stratusphere/connector-id-key.md](../stratusphere/connector-id-key.md)).
- Callbacks need TCP 443 from the desktops to the Hub; a higher-priority NSG deny or a firewall on a
  hub route silently stops them ([azure/networking.md](../azure/networking.md)).
- An appliance keeps the password it was created with, so reruns must reuse it
  ([stratusphere/appliances.md](../stratusphere/appliances.md)).
- The Hub and the Database appliance hold the only copy of the assessment data: removing either
  deletes it. Export first; `Cleanup` refuses without `-DiscardLastCopy`
  ([avd-second-brain decision 0016](https://github.com/nickprignano/avd-second-brain/blob/main/docs/knowledge/decisions/0016-never-delete-the-last-copy.md)).

## ProfileUnity, FlexApp and CommandCTRL

- Never let Portability and the FSLogix container both carry the same path, and never capture all
  of `AppData\Local` ([avd/fit-with-avd-and-fslogix.md](../avd/fit-with-avd-and-fslogix.md)).
- Assign each app in exactly one system (app attach, ProfileUnity rules or another manager)
  ([avd/fit-with-avd-and-fslogix.md](../avd/fit-with-avd-and-fslogix.md)).
- Images without a domain can't grant a domain service account "log on as a service"; ProfileUnity
  6.9.5 can run its startup service as LocalSystem instead
  ([tier spec, facts](../../spec.md#12-facts-and-what-is-still-unverified)).
- FlexApp Sandbox Isolation needs nested virtualization in the VM
  ([avd/fit-with-avd-and-fslogix.md](../avd/fit-with-avd-and-fslogix.md)).
- The tier resource group holds the only copy of the live ProfileUnity configuration, the FlexApp
  packages and the console. Copy them out and check the copy before `Cleanup`, which refuses
  without `-DiscardLastCopy` ([deploy spec section 11](../../deploy-spec.md#11-actions)).

## Any Azure lab

- Stopped isn't deallocated, and NAT Gateway, Bastion, public IPs and disks bill regardless
  ([azure/lab-costs.md](../azure/lab-costs.md)).
