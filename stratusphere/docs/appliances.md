# Appliances: Hub, Database, Collectors

`scripts/ops/Deploy-Stratusphere.ps1` is one entry point for every Stratusphere appliance in the assessment environment. `-Role` picks the appliances, `-Action` says what to do. Run it from Azure Cloud Shell (PowerShell).

## Roles

| Role | When | VM | Static IP |
|---|---|---|---|
| Hub | Always | `vm-<prefix>-hub`, `Standard_D4s_v5`, 128 GB | `10.60.0.4` |
| Database | Liquidware advises it above 1,000 Connector ID Keys | `vm-<prefix>-db`, `Standard_D4s_v5`, 256 GB | `10.60.0.5` |
| Collector | Optional, 1 to 4 | `vm-<prefix>-col<n>`, `Standard_D2s_v5`, 64 GB | `10.60.0.10` onward |

Each role has its own Marketplace plan (`-HubPlan`, `-DatabasePlan`, `-CollectorPlan`). The preflight lists the plans offered in a region. For roles already deployed, the plan is read from the VM, so later runs don't need it. A VM's plan can't change: the script refuses rather than fail halfway.

Every VM carries the tag `stratusphere-role` (`hub`, `database`, `collector-<n>`), which is how the script finds them. All appliances share one subnet, NSG, Key Vault and password.

## Actions

| Action | What it does |
|---|---|
| `Plan` (default) | What-if of the deployment, plus each plan's availability and terms. Changes nothing |
| `Check` | Resource group; each appliance exists, is running and has its static IP; NSG rules for the roles present; NAT Gateway with default outbound access off; Key Vault holds the credential; Marketplace terms. Each failure names its fix. Ends `RESULT PASS` or `RESULT FAIL` |
| `Deploy` | Registers the resource providers, accepts the terms, recovers a soft-deleted Key Vault, and deploys the roles asked for plus the ones that already exist. Then runs Check and prints the console steps for each role |
| `Fix` | Runs Check, then only what repairs it, in order: accept terms, recover the vault, one redeployment (puts back a missing VM, a dynamic IP, a failed provisioning, NSG rules, egress), start stopped VMs. Checks again. What it can't repair safely (a lost password) is listed |
| `Cleanup` | `-Role Collector` or `-Role Database` removes those VMs with their disks and NICs. `-Role Hub` removes the whole environment and the peering on the other VNet. Asks first (`-Force` skips); `-WhatIf` lists what would go. The Hub and the Database hold the only copy of the assessment data, so removing either also needs `-DiscardLastCopy`, after you have exported what you need and checked the copy (never delete the last copy, avd-second-brain decision 0016). `-Force` never implies it |

Results also go to `output/stratusphere-<action>-<time>.json` (git-ignored).

## Things the script keeps for you

- **The password.** Generated once, stored in Key Vault as `appliance-admin-password`, reused on every rerun. A new password would not match the appliances, so if the vault can't be read and appliances exist, the script stops.
- **Existing roles.** Deploying Collectors on an environment with a Database keeps the Database in the template, with its plan. Asking for fewer Collectors than exist keeps them all (remove them with Cleanup).
- **Bastion and peering.** Reruns keep what the environment has unless `-NoBastion` or `-PeerVnetId` says otherwise. Dropping the Bastion subnet under a running Bastion would fail the deployment.
- **The Key Vault after a teardown.** Purge protection keeps it soft-deleted for 7 days. The next Deploy recovers it rather than failing on the name.

## After deploying

- **Hub:** license, API user and API whitelist in the console (README, first-time Hub setup).
- **Database:** in the Hub console, point the Hub at it (Hub Administration > Database). Before removing a Database, point the Hub back at its own database.
- **Collectors:** in each Collector's console, register it with the Hub. It picks up the database and reboots.

TCP 5432 is open between the appliances whenever there is a Database or Collectors: Collectors write to the database, on the Database appliance or on the Hub without one.

## Not yet verified on a real subscription

Whether Liquidware publishes Database and Collector plans in Azure Marketplace (and under which offer), whether the appliances honor the credential Azure sets, and the console steps above come from Liquidware's documentation, not a real run. If a run shows something different, please open an issue.
