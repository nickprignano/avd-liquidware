---
title: "How Liquidware products fit with Azure Virtual Desktop and FSLogix"
summary: "Which job each Liquidware product does next to AVD's own features and FSLogix: profiles, app delivery, support and assessment"
topic: avd
status: partial
last_reviewed: 2026-10-19
---

# How Liquidware products fit with Azure Virtual Desktop and FSLogix

Each Liquidware product adds one job next to what AVD already does; none replaces FSLogix as the
profile container. The full design, with every fact's source, is the tier spec's
[product ownership section](../../spec.md#4-which-product-owns-what) and its
[facts table](../../spec.md#12-facts-and-what-is-still-unverified). FSLogix itself is the AVD
knowledge base's topic ([family.yaml](../family.yaml)); link there for FSLogix behavior.

| Job | AVD or Microsoft owns | Liquidware adds | Rule |
|---|---|---|---|
| Profile container | FSLogix profile containers | Nothing by default | FSLogix stays the system of record |
| Settings and user environment | Group Policy, Intune | ProfileUnity Portability and user environment management | Portability captures a named list of settings paths only, never a path also roaming in the FSLogix container, and never all of `AppData\Local` |
| Apps that don't convert to MSIX | AVD app attach (MSIX, App-V, CimFS, VHDX) | FlexApp packages registered as app attach packages | One assignment system per app; prefer app attach over ProfileUnity filter rules |
| Real-time support | Azure Monitor, AVD Insights | CommandCTRL (optional) | Not for alerts or health; its history is off where Stratusphere collects |
| Assessment and sizing | Azure Monitor (partly) | Stratusphere UX | A separate tier, deployed only for the assessment window |

## Facts worth knowing

- FlexApp packages sync to AVD app attach through an Entra app registration and a custom role over
  `appattachpackages` (ProfileUnity 6.8.7 and later). Keep the console's role to registering
  packages; assigning them to host pools belongs to the landing zone's own workflow.
- FlexApp Sandbox Isolation (6.9.5) needs Windows Sandbox, which needs nested virtualization inside
  a VM. Check it against Trusted Launch and the VM size before turning it on.
- ProfileUnity's cloud storage covers Portability and FlexApp on Azure Blob; FlexDisk, ProfileDisk
  and Folder Redirection aren't supported on cloud storage (6.8.6 docs; recheck for 6.9.5).

## Not confirmed yet

- Portability saves at logoff. Whether saves survive forced logoff, Lock, deallocation and host
  failure, and in what order against the FSLogix detach, is *unverified*; until then Portability
  carries only settings that can be lost without harm.
- FlexApp app attach on Entra-joined hosts without storage keys is *unverified*.
- ProfileDisk on Entra-only Azure Files is *unverified*.
