# AL-0002. Automated deployment: own resource group and VNet, keyless config with two hands, no console secret

- **Status:** Proposed

## Context
Decision AL-0001 (PR #1) decides what the Liquidware tier is. This decides how it is deployed, by script, against an existing avd-landing-zone landing zone, from Azure Cloud Shell, without changing the landing zone's default deployment. Reading the landing zone's templates showed that the obvious placements break it: a subnet on its VNet is erased or blocks its redeploy, a share on its profiles account is writable by every user, and Cloud Shell can't reach private endpoints. Details, sources and red-team findings: [deploy-spec.md](../deploy-spec.md), [deploy-redteam.md](../deploy-redteam.md).

## Decision
- **One entry point,** `scripts/Deploy-LiquidwareTier.ps1 -Component ProfileUnity,FlexApp,Stratusphere -Action Plan|Check|Deploy|Configure|Promote|Fix|Cleanup`, which finds the landing zone by its naming convention.
- **Own resource group and VNet,** peered to the spoke. The tier writes to landing zone resources only as child resources (peering, DNS links and records, a Portability share, app attach packages, Run Commands), listed in one table and removed by `Cleanup`.
- **Live configuration in its own keyless account,** users read-only; the console writes a staging container on a different account; promote is a separate identity in an on-demand ops runner inside the network, driven by a person or an approved swarm plan, QA ring first, checked on a plain-text export because the INI is encrypted.
- **FlexApp packages registered with the operator's identity** through AVD's own import, not the console's app registration and client secret (fallback if that doesn't read FlexApp images).
- **Hosts configured by drained Run Command,** one at a time; hosts created later are held until a host sync configures them.
- **VMs fetch installers and secrets with their own managed identities;** the operator writes secrets through the management plane and never reads them back; no SAS, no keys, no binaries in the repo.
- **The budget no longer stops all compute** while the tier is on, until avd-landing-zone's Lock is extended (fork F1); until then `Plan` says so and sandbox runs end with `Cleanup` the same day.
- **Stratusphere** uses the landing zone's region, spoke, host pool and session host subnet, without Bastion, with a window end date.

## Alternatives considered
- **A subnet on the landing zone's VNet:** fewer resources, but the landing zone's next deploy fails or deletes it.
- **Config share on the profiles account:** no second Entra Kerberos account, but users hold SMB Share Contributor on the whole account.
- **The console writes live configuration:** one hand fewer, but whoever holds the console changes every logon.
- **Liquidware's app attach sync:** supported by the vendor, but a client secret with write on app attach packages lives on the console.
- **A hook in avd-landing-zone's host deployment:** closes the new-host gap at creation, but changes the landing zone; left as a fork for the owner.

## Consequences
The tier adds a resource group, a VNet with a NAT Gateway, a console VM, three storage accounts (live config, packages, media with staging) and a Key Vault, plus an ops runner that exists only while a job runs. Two things wait on vendor facts (silent install switches, AVD reading FlexApp images) and degrade to a checklist or the vendor's sync if they fail.
