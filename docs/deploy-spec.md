# Spec: automated deployment of ProfileUnity, FlexApp and Stratusphere on Azure Virtual Desktop

- **Status:** Proposed (see [decision AL-0002](decisions/AL-0002-automated-deployment.md)). Red-teamed twice in [deploy-redteam.md](deploy-redteam.md); every finding is folded in below and tagged with its ID (D-C1, D-H2, DN-C1, …).
- **Date:** 2026-10-18
- **Builds on:** the tier spec, [spec.md](spec.md) (decision AL-0001, PR #1), which decides *what* the tier is: FSLogix stays the container, ProfileUnity adds Portability and user environment management, FlexApp goes through AVD app attach with one assignment system per app, version floor 6.9.5. This spec decides *how it gets deployed*, end to end, by script. Section references like "tier §4.2" point at spec.md; plain decision and lesson numbers are [avd-landing-zone](https://github.com/nickprignano/avd-landing-zone)'s.
- **Also builds on:** the Stratusphere instrument already in this repo ([stratusphere/](../stratusphere/README.md)), which this spec connects to a landing zone rather than rewrites.
- **Scope:** ProfileUnity (console, client, configuration), FlexApp (packaging, upload, app attach registration and assignment) and Stratusphere UX (assessment instrument) against an existing avd-landing-zone landing zone. CommandCTRL stays in tier phase L3 and is not part of this spec.
- **Out of scope:** Nerdio. Liquidware is the only partner of this family and Nerdio variants belong to the separate nerdio-hcl project through shared interfaces (owner's rule, 2026-10-18 20:17). Tier spec §8 predates that rule; this spec has no Nerdio path, and the scripts here are written so a Nerdio scripted action *could* call them, without depending on Nerdio.

This is a personal project, not for production, provided as is. Nothing here has run against a real tenant. Liquidware, ProfileUnity, FlexApp, Stratusphere and CommandCTRL are trademarks of Liquidware; Azure, Microsoft Entra, Intune and FSLogix are trademarks of Microsoft; this project is not affiliated with either.

## 1. What gets automated

| Step | Today | After this spec |
|---|---|---|
| Find the landing zone | Each Stratusphere script takes IDs by hand (`-PeerVnetId`, host pool) | One discovery function reads the landing zone from its naming convention (`rg-<prefix>-<env>-*`), the same convention `Get-AvdLandingZone` uses |
| Stratusphere Hub, Database, Collectors | `Deploy-Stratusphere.ps1`, own region and prefix defaults (`eastus2`, `ssux`), Bastion Basic on | Same script, called with the landing zone's region, spoke and session host subnet; Bastion off by default against a landing zone (§9) |
| Stratusphere Hub setup (license, API user, whitelist) | Manual checklist | Still a checklist: the Hub API is unverified (DV5). `Check` verifies what it can see from Azure |
| Connector ID Key on session hosts | `Deploy-CidKey.ps1` to a host pool | Same, targeted at the landing zone's host pool, plus a host sync for hosts created later (§6.3) |
| ProfileUnity console | Nothing | VM, network, Key Vault, backup and install by one deployment and one Run Command (§5, §6.1) |
| ProfileUnity client on session hosts | Nothing | Run Command per host, drained first, installer pinned by SHA-256, secrets in protected parameters (§6.2) |
| ProfileUnity configuration (the compiled INI) | Nothing | Console writes to a staging share; a promote step copies it to the live share over REST with Entra, QA hosts first (§7) |
| FlexApp packaging | Nothing | On-demand packaging VM, created and deleted by the same script (§8.1) |
| FlexApp package upload, registration, assignment | Nothing | Upload with Entra, register as an AVD app attach package with the operator's own identity, assign through the landing zone's control plane, never from the console (§8) |
| Teardown | Stratusphere only | Every component: one resource group each, plus the few child resources it added to the landing zone, listed and removed (§11) |

## 2. Defaults picked, and the forks left for Nick

Defaults (each is the reasonable choice; the rest of the spec is written to them):

1. **Own resource group and own VNet for the tier, peered to the spoke** (D-C1). Never a subnet on the landing zone's VNet.
2. **Live configuration lives in its own keyless storage account**, not on the profiles account (D-C2), and staging lives in a different account from live (DN-H3).
3. **The tier registers FlexApp packages itself, with the operator's identity**, instead of the console's app registration and client secret. The console's sync is the fallback if V19 fails (D-H3).
4. **Session hosts that exist today are configured by drained Run Command; hosts created later are caught by a host sync that holds them until configured** (D-H1, D-H5). No change to avd-landing-zone.
5. **Installers are never in the repo, and no VM gets a key or a SAS for them.** The operator uploads each installer once from Cloud Shell to a media account that is Entra-only; every VM reads it with its own managed identity (D-C4, D-M2).
6. **Data-plane writes the operator can't make from Cloud Shell run inside the network:** small ones (promote, checks) in an on-demand ops runner container, large ones (FlexApp packages) from the packaging VM (D-C4).
7. **One entry point, `Deploy-LiquidwareTier.ps1`,** with the same actions as `Deploy-Stratusphere.ps1` (Plan, Check, Deploy, Fix, Cleanup) plus `Configure` and `Promote`.
8. **Smallest sizes that meet the vendor's minimums, verified in V5:** console `Standard_D2as_v5` until Liquidware's 6.9.5 guide says otherwise.

Forks only Nick can decide (§16): a small change in avd-landing-zone so its host deployment and Resume respect the tier, whether Stratusphere runs in the sandbox before there is a customer, the console's backup, and whether the media account may keep a public, Entra-only endpoint.

## 3. Shape

```
avd-liquidware/
  scripts/                      shared, PowerShell 7.4, Cloud Shell
    Deploy-LiquidwareTier.ps1   the entry point: -Component, -Action
    LiquidwareTier.psm1         pure functions (plans, checks, names), tested offline
  profileunity/                 ProfileUnity and FlexApp (new, same layout as stratusphere/)
    bicep/main.bicep            subscription scope: RG, VNet, peering, DNS links, console, storage, Key Vault
    parameters/*.bicepparam
    scripts/host/               Windows PowerShell 5.1, run on VMs by Run Command
      Install-ProfileUnityClient.ps1
      Install-ProfileUnityConsole.ps1
      Publish-ProfileUnityStaging.ps1    (on the console: compiled INI to the staging share)
    scripts/ops/                PowerShell 7.4, Cloud Shell
      Sync-LiquidwareHosts.ps1, Set-LwSecret.ps1, Publish-LiquidwareMedia.ps1,
      Publish-ProfileUnityConfig.ps1 (starts the ops runner), Publish-FlexAppPackage.ps1, Set-FlexAppAssignment.ps1
    scripts/runner/             the ops runner's job scripts (bash, Azure CLI image), passed as its command
    tests/                      Pester: template guards, plans, host script static checks
  stratusphere/                 unchanged layout; gains -LandingZone discovery (§9)
```

`Deploy-LiquidwareTier.ps1 -NamePrefix avdlz -Environment dev -Component ProfileUnity,FlexApp,Stratusphere -Action Plan` is the whole operator surface. Every component prints the same check lines and a final `RESULT PASS|FAIL` line, as the Stratusphere scripts do. Commands given to operators are self-contained Cloud Shell blocks (lesson 0015): clone or update, `Set-Location`, `Connect-AvdLandingZone.ps1` when Graph is needed.

## 4. Reading the landing zone, and the only things written to it

**Discovery** (`Get-LwLandingZone`, a pure function over what Azure returns): from `-NamePrefix` and `-Environment`, the five resource groups, `vnet-<base>` and its address space, `snet-session-hosts` and its prefix, the profiles account (the `FileStorage` account in `rg-<base>-storage`) and its share, the Key Vault, Log Analytics and the AVD data collection rule, the host pool and desktop application group, the private DNS zones the spoke links (file, vault, wvd), and `connectivityMode` (Standalone or HubPeered, from whether the zones are local). Anything missing is a `FAIL` with the landing zone's own remedy (run its deploy).

**Writes to landing zone resources** are listed here and nowhere else, each one a child resource so a landing zone redeploy (incremental) leaves it alone, and each removed by `Cleanup` (D-C1):

| Write | Why | Removed by |
|---|---|---|
| VNet peering `peer-<base>-to-liquidware` on `vnet-<base>` | Hosts reach the console's license service (443) and the config account's private endpoint | `Cleanup -Component ProfileUnity` |
| Virtual network links from the landing zone's `privatelink.file` and `privatelink.vaultcore` zones to the tier VNet (Standalone only) | The console and packaging VM resolve the profiles account and the tier's own endpoints | same |
| A records in those two zones, written by the tier's private endpoints' DNS zone groups (D-M4) | Hosts resolve the config and packages accounts and the tier's Key Vault | removed with the private endpoints |
| Tags `avd-scaling-exclude` and `liquidware-hold` on session host VMs, while a host is being changed or held (D-H5) | The scaling plan leaves it drained; the next sync sees why | the sync, when the host is configured; a landing zone redeploy can also drop them, and the next sync puts back what still applies |
| A `portability` share on the profiles account, only with `-Portability`, at the 100 GiB minimum, with the profiles share's NTFS pattern set the way decision 0005 sets it (a Run Command on a session host with a temporary role on the host's identity, removed after) | Tier §5.1; users already hold SMB Share Contributor there. Premium shares bill on provisioned size and this one isn't in the landing zone's backup (DN-H7) | same, only with `-RemoveUserData` (it holds user settings); without it `Cleanup` prints a `WARN` with the share's monthly cost |
| A data collection rule association `lw-restrictions` on each session host, to the tier's own data collection rule (never an edit of the landing zone's, which its next deploy would overwrite, DN-H5) | ProfileUnity's restriction events reach Log Analytics | the component's `Cleanup` |
| App attach packages and their host pool references in `rg-<base>-avd` | §8.3 | `Cleanup -Component FlexApp` |
| Managed Run Commands `lw-profileunity-client` and `lw-stratusphere-cid` on session hosts | §6 | the component's `Cleanup` (uninstalls, then deletes the Run Command resource; a stopped host is started first, lesson 0026) |

The tier's own private endpoints write A records into the landing zone's `privatelink.file` and `privatelink.vaultcore` zones through their DNS zone groups (DN-C3); those rows are above. The tier never creates a `privatelink.blob` zone: the one blob account it has (media) is reached on its public endpoint (§6.4), so nothing collides with a blob zone the landing zone or a hub adds later.

In **HubPeered** mode the tier never creates DNS zones or links; it takes the platform's zone IDs (`-CentralDnsZoneIds`, the same shape as the landing zone's `centralPrivateDnsZoneResourceIds`) and the peering goes to the hub, not the spoke, with a route for the tier's prefix through the firewall. HubPeered is specified, not built in the first slices.

## 5. ProfileUnity resources

One deployment, subscription scope, `profileunity/bicep/main.bicep`. Native resources, not Azure Verified Modules: the template tests check every role assignment's scope and principal in the compiled template, and module wrappers hide them. Resource group **`rg-<base>-liquidware`** (one lifecycle, one delete).

| Resource | Settings |
|---|---|
| VNet `vnet-<base>-liquidware`, default `10.61.0.0/24` | `snet-lw-console` (/27), `snet-lw-endpoints` (/27), `snet-lw-packaging` (/27), `snet-lw-ops` (/28, delegated to Azure Container Instances, D-C4), `AzureBastionSubnet` only with `-Bastion`. Default outbound access off on every subnet. `Check` fails on overlap with the spoke, the Stratusphere VNet (`10.60.0.0/24`) and anything already peered |
| NSGs on `snet-lw-console` and `snet-lw-packaging` | Inbound: 443 from `snet-session-hosts`' prefix to the console only (licensing); 3389 only from `AzureBastionSubnet` when Bastion is on; nothing else. **Outbound: deny the spoke's prefix** except the private endpoint subnet, because the landing zone's host NSG admits everything from the `VirtualNetwork` tag, which includes peered VNets: without it a taken-over console reaches every host on 445, 135 and 5985 (DN-M1). Hosts open the 443 connection, so its return traffic still flows |
| NAT Gateway on `snet-lw-console`, `snet-lw-packaging` and `snet-lw-ops` | Windows Update, Liquidware's update checks, the media account's public endpoint (§6.4) and the ops runner's image pull. Same pattern as the Stratusphere VNet. Without it, `Check` warns that the console can't patch |
| Console VM `vm-<prefix>lwcon`, computer name `take('<prefix>lwcon', 15)` (DN-M4) | Windows Server 2025 Datacenter Azure Edition, `Standard_D2as_v5` (V5), Trusted Launch (Secure Boot, vTPM), encryption at host (`Check` verifies the subscription feature), Premium SSD 128 GiB, no public IP, static private IP `10.61.0.4`, system-assigned managed identity. Local admin `lwadmin` with a password generated in memory and written to the tier's Key Vault through the ARM management plane (`Microsoft.KeyVault/vaults/secrets`, which works on a private vault from Cloud Shell, DN-C1); a rerun finds the VM and leaves the password alone, since the VM keeps the one it was created with (lesson 0002). Hosts name the console by its static IP (or a record in a zone linked to the spoke), never by host name: Azure-provided DNS doesn't resolve across a peering (DN-M2). Tagged `liquidware-role: console`. Not Entra-joined in the first slices: it's a server, and nobody signs in to it routinely. In `dev` and `test`, a daily shutdown schedule at the landing zone's auto-shutdown time, because the landing zone's budget Lock only stops session hosts (D-H6) |
| Key Vault `kv<prefix><env>lw<uniq>` | RBAC, purge protection, private endpoint in `snet-lw-endpoints`, public access off. Holds the console password and the ProfileUnity license string (`lw-licstr`, §10) and nothing else. Both are written through the management plane; only VMs inside the network read them, each with its own identity and a role scoped to that one secret. `Plan` and `Check` find a soft-deleted vault of the same name and offer to recover it, as the landing zone's preflight does (lesson 0022, DN-M3) |
| Live config account `st<prefix><env>lwc<uniq>` (StorageV2, Standard_LRS) | **Shared key off** (`allowSharedKeyAccess: false`), Entra Kerberos (`AADKERB`), SMB hardened like the profiles account (SMB 3.1.1, Kerberos, AES-256 tickets, AES-128-GCM and AES-256-GCM channels, lesson 0028) **except multichannel**, which only Premium file accounts support (DN-H4), public access off, file private endpoint. One share, `lwconfig`. **Staging is not on this account** (DN-H3): with only live here, every grant is account-scoped and the separation doesn't rest on share-scoped data roles. Users group: **SMB Share Reader**. Ops runner identity: Storage File Data Privileged Contributor. Nothing else. Hosts read it as the user at logon (tier §6 row 2), by its full `<account>.file.core.windows.net` name. Entra Kerberos creates an Entra app for this account, which needs admin consent and must be excluded from Conditional Access policies that require MFA: `Check` runs the landing zone's two checks for it and `Fix` grants the consent (D-H4); `Cleanup` removes that app if it outlives the account (unconfirmed whether Azure removes it) |
| Media account `st<prefix><env>lwm<uniq>` (StorageV2, Standard_LRS) | Containers `media` (installers) and `staging` (compiled configuration from the console, §7). **Shared key off, anonymous access off, public endpoint on with Entra-only data plane** (a named exception, fork F4: Cloud Shell has no line of sight to private endpoints, D-C4). Operator: Storage Blob Data Contributor on `media`. Console identity: Storage Blob Data Contributor on `staging` only (container scope, which blob roles support). Packaging VM and each session host's system-assigned identity (the Entra join already needs it): Storage Blob Data Reader on `media`, granted by the deploy and the host sync. Ops runner: Reader on `staging`. Never packages |
| Ops runner identity `id-<base>-lw-ops` (user-assigned) | Used only by the on-demand container (§7). The console can't use it: it isn't assigned to the console, and assigning it needs Managed Identity Operator, which the console's identity doesn't have |
| Packages account `st<prefix><env>lwp<uniq>` (StorageV2, Standard_LRS) | Exactly tier §5.1: the one account with shared key on, app attach images only, share `appattach`, file private endpoint, Reader and Data Access for the *Azure Virtual Desktop* and *Azure Virtual Desktop ARM Provider* service principals. A template test fails if it gains a second share, a blob container or a role for any user group |
| Backup | **Off in `dev`** (the sandbox; nothing on the console that a rebuild doesn't restore). In `test` and `prod`, a Recovery Services vault in the tier resource group with an **Enhanced** policy, which Trusted Launch VMs need (the landing zone's default policy is Standard, DN-H6). `Cleanup` stops protection and deletes the backup data first; soft delete keeps the vault for 14 days, recorded in the teardown evidence (fork F3) |
| Diagnostics | The accounts and the Key Vault to the landing zone's Log Analytics. With `-ApplicationRestrictions`, the tier's own data collection rule `dcr-<base>-liquidware` collects ProfileUnity's restriction events (tier §7) from the hosts it is associated with (§4), and `Check` confirms events arrive (DN-H5) |

**Guards in the template tests** (`tests/ProfileUnityTemplate.Tests.ps1`, compiled template, offline; slice B2 covers the network, Key Vault, config and packages accounts, B3 adds the VM, media and console guards):
- the profiles account is never in this template except as an `existing` reference and the `portability` share;
- the live config account has `allowSharedKeyAccess: false`, Entra Kerberos and the landing zone's SMB settings other than multichannel;
- no user group holds a write role on the live config account, or any role on the packages or media accounts (tier N-C1);
- the console identity holds exactly one data role, Blob Data Contributor scoped to the `staging` container;
- the media account has shared key and anonymous access off and two containers;
- the console and packaging subnets' NSGs deny outbound to the spoke;
- no public IP, no `0.0.0.0/0` or `Internet` inbound rule, no 3389 without Bastion;
- every VM has Trusted Launch and encryption at host;
- the peering, the DNS links and the private endpoints' zone groups are the only resources that touch a landing zone resource group.

## 6. Hosts and the console: configuration by Run Command

All host scripts are Windows PowerShell 5.1, no modules (lesson 0011). They take secrets only through `protectedParameters`, never log their command line, never use MSI verbose logging (tier N-M2).

### 6.1 Console install

`Install-ProfileUnityConsole.ps1` runs on the console by managed Run Command: downloads the installer from `media` with the console's managed identity (§6.4), checks its SHA-256 against the pin, installs silently, sets the console's deploy path to a local folder (`C:\ProgramData\avd-liquidware\deploy`), reads the license from `lw-licstr` with the console's own identity (a role on that secret only; the value never crosses Cloud Shell, DN-C1), and turns Swagger off. **The silent install switches for the 6.9.5 console are unverified (V18).** Until V18 passes, the script stops after download and hash check and prints the checklist of console steps (`docs/console.md`); everything around the console (network, storage, identity, backup, staging publish) is still automated.

### 6.2 Client install on existing hosts

`Sync-LiquidwareHosts.ps1 -Component ProfileUnity` (also `Deploy -Component ProfileUnity` and `Configure`):
1. **Plan** per host: wants client (yes, unless excluded), has client (version from the Run Command's last output or the instance view), sessions (from the host pool), drain state and who set it, power state, and whether the host pool carries the landing zone's budget lock. Pure function `Get-LwHostPlan`. Hosts are usually deallocated (scaling plan, scheduled stop), and a Run Command can't run on, or be deleted from, a stopped VM (lesson 0026). So the sync follows lesson 0026's order: record the power state, set the scaling exclusion tag, start, act, then put both back (DN-H2). While the budget lock is on, the sync starts nothing and undrains nothing; it only reports (DN-H1).
2. For each host that needs a change: grant its managed identity read on `media`, **drain** (`allowNewSession: false`) and tag it `avd-scaling-exclude` so the scaling plan's ramp-up doesn't undrain it mid-install (D-H5), wait for zero sessions up to `-DrainTimeoutMinutes` (default 0: only hosts already empty; `-Force` logs users off with a message, never by default), run `lw-profileunity-client` with `ACCEPTEULA=1 E=1 USERINI=\\<config account>.file.core.windows.net\lwconfig\... CLIENTXML=…` and the installer SHA-256 (the host reads `LICSTR` from Key Vault with its own identity, so no secret is passed at all), read the exit code, **undrain and remove the tag only on success, and only if the tier set the drain** (tagged `liquidware-drained`): a host drained by someone else, the budget lock or rotation (decision 0013) stays as it was (DN-H1). A host that fails stays drained and is a `FAIL` line with its Run Command output (lesson 0012: report everything it returned).
3. Hosts are done one at a time by default (`-Parallel` up to 25 % of the pool), so a bad client never drains the whole pool (D-H2).

The client binary may also be baked into the image (tier H6: binary only, no settings). Then step 2 only writes the settings, and a version below the floor (6.9.5) is a `FAIL`, not an upgrade in place.

### 6.3 Hosts created later (D-H1)

The landing zone adds hosts on scale-out, image rotation and rebuild, and its own Run Commands (`Configure-FSLogix`, `Register-AvdAgent`) don't know about this tier. A new host registers and takes logons **without** ProfileUnity, so restrictions and user environment management silently don't apply. So:
- `Sync-LiquidwareHosts.ps1` is idempotent and safe to run any time; `Check` lists every host without the client as `FAIL` and every host without the Connector ID Key during a Stratusphere window as `WARN`;
- run from Cloud Shell after every landing zone deploy or rotation (`docs/operations.md` gets the line), and later as a swarm plan on a schedule (§14);
- `-HoldUnconfigured` (on by default when `-ApplicationRestrictions` is on) holds any host that is registered but unconfigured: drained, excluded from the scaling plan, tagged `liquidware-hold`, so it takes no logons until configured;
- **the gap that stays:** the landing zone's `Invoke-AvdPowerAction.ps1 -Action Resume` sets `allowNewSession` on every host, so after a budget Lock and Resume a held host takes logons until the next sync. `Check` fails on any host without the client whose `allowNewSession` is true;
- fork F1: a small, generic change in avd-landing-zone (Resume skips hosts tagged `liquidware-hold`, and an optional post-FSLogix hook in its host deployment) would close both gaps. It is not needed for the first slices.

### 6.4 Media without keys or SAS (D-M2, D-C4)

The operator uploads each installer once, from Cloud Shell: `Publish-LiquidwareMedia.ps1 -Path <file> -Component ProfileUnityClient -Version 6.9.5` computes the SHA-256, uploads to `media/<component>/<version>/<file>` with Entra (Storage Blob Data Contributor, the operator's own), and writes `media.lock.json` locally (component, version, file, SHA-256; no URLs, no secrets). The lock file is committed to the customer's private repo, never to this one; this repo has `media.lock.example.json`. At run time the host script gets a token for `https://storage.azure.com/` from the VM's own managed identity (IMDS, which Windows PowerShell 5.1 reaches with `Invoke-RestMethod`), downloads the blob over HTTPS through the NAT Gateway, and refuses it unless the SHA-256 matches the lock file's, which the deploy script passes in. Nothing secret crosses the Run Command for media at all.

Why not a SAS over a private endpoint: a user delegation key is requested from the blob endpoint itself, which Cloud Shell can't reach when the account is private, and IP firewall rules don't apply to clients in the account's own region (D-C4). Fork F4 asks whether the public, Entra-only media endpoint is acceptable; the alternative is uploading media from the packaging VM's browser, which makes every new version a manual step.

## 7. ProfileUnity configuration: staging, then promote (D-C3)

The console's *Deploy Configuration* writes the compiled INI and its XML. On Entra-only, the console's machine account can't write SMB to Azure Files (tier §6 row 2a, V16). This spec settles the default writer:

```
console (local deploy folder)
   │  Publish-ProfileUnityStaging.ps1, scheduled task on the console,
   │  Blob REST + managed identity (Blob Data Contributor on the staging container only)
   ▼
media account: staging/<configName>/<timestamp>/  ── diff, hash and the exclusion check (tier H1) ┐
                                                                                               │
   Publish-ProfileUnityConfig.ps1 -Promote <timestamp> -Ring QA|All  (operator or swarm plan)  │
   starts the ops runner: a container in snet-lw-ops with id-<base>-lw-ops, which copies      ◄┘
   staging to the live config account over Files REST inside the network, prints the
   hashes, exits and is deleted
   ▼
live config account: lwconfig/<configName>/   ◄── hosts read it as the user at logon (SMB Share Reader)
```

- **Two hands.** Whoever controls the console can write staging, never live. Promote is a person or an approved swarm plan, so a taken-over console can't push a logon policy to every host on its own (D-C3).
- **Why a container.** Cloud Shell can't reach the live config account's private endpoint (D-C4), and the console mustn't hold the live write. The ops runner is an Azure Container Instance created by the operator's ARM call (which Cloud Shell can make) from Microsoft's Azure CLI image, with the job's script passed as its command; it holds no secret, lives for the job, and its logs (hashes and file counts only) go back to the operator's output. Creating it needs Contributor on the tier resource group and Managed Identity Operator on `id-<base>-lw-ops`, which the console's identity doesn't have.
- **Rings.** `-Ring QA` writes `lwconfig/<configName>-qa/`, which only hosts tagged `liquidware-ring: qa` read (the client's `USERINI` points at the ring's folder). `-Ring All` moves the same timestamp to the main folder. With one host pool and one host (dev), QA and All are the same host, said so in the output.
- **The second hand must see what it approves (DN-C4).** ProfileUnity 6.9.5 encrypts INI content by default, so a staged INI can be opaque. Whether the tooling can read it off the console is V23. Until it passes, the console's staging task also exports the configuration as plain text (the console's own export), the runner checks that the export and the staged INI come from the same deploy (same timestamp and the console's recorded hash), and the checks below run on the export; with no export, Promote refuses.
- **Checks before promote** (pure functions, offline-tested): the configuration parses; its Portability paths don't overlap FSLogix's (tier H1, against the landing zone's `Set-FSLogixConfiguration.ps1` defaults and the host-side check); it isn't empty; its hash differs from live (or `-Force`).
- **Atomic per file (DN-M6).** The runner writes each file under a temporary name, then renames it into place (Files' rename is atomic per file), the XML before the INI, so a logon during a promote reads the old pair or the new one, not half of one.
- **Rollback** is a promote of the previous timestamp, which staging keeps (last 10).

## 8. FlexApp

### 8.1 Packaging

`Deploy-LiquidwareTier.ps1 -Component FlexApp -Action Deploy -Packaging` creates the packaging VM in `snet-lw-packaging`: Windows 11 Enterprise **single session** (`microsoftwindowsdesktop`/`windows-11`/`win11-24h2-ent`, the same build as the landing zone's multi-session image, `win11-24h2-avd-m365`; DN-M8), `Standard_D2as_v5`, Trusted Launch, no public IP, local admin in Key Vault, the FlexApp Packaging Console installed from `media` like §6.1 (silent switches: V18). Packaging itself is interactive (Bastion Developer, opt-in) or the Packaging Console's command line when V20 shows one. `-Action Cleanup -Packaging` deletes the VM, disk and NIC; `Check` warns when a packaging VM has existed for more than 24 hours. The packaging VM never joins the host pool and is never in `snet-session-hosts`.

### 8.2 Upload

Packages are produced on the packaging VM, which is inside the network, so they are uploaded from there (D-C4): `Publish-FlexAppPackage.ps1` runs on the packaging VM by Run Command and copies the package's VHDX (or CimFS) and its metadata to `appattach/<app>/<version>/` on the packages account with `azcopy` and the VM's managed identity (Storage File Data Privileged Contributor scoped to the `appattach` share, and only while the packaging VM exists), never the account key. Whether `azcopy` with a managed identity and the backup intent handles a multi-GiB image to Azure Files is V22. It records the app's **fallback install method** (tier H4) in the package's tag.

### 8.3 Registration and assignment without the console's secret (D-H3)

Liquidware's sync gives the console an app registration with a client secret and a subscription-scoped custom role on `appattachpackages` (tier F4, N-C2). This spec avoids that credential entirely:
- **Register:** `Publish-FlexAppPackage.ps1` asks AVD to read the image (`importAppAttachPackageInfo` on the host pool, the same call the portal uses) and creates `Microsoft.DesktopVirtualization/appAttachPackages/<app>-<version>` in `rg-<base>-avd` with the operator's identity. That needs Desktop Virtualization Contributor on `rg-<base>-avd`, which the landing zone's admins group does **not** hold (it has VM Administrator Login, SMB Share Elevated Contributor and Key Vault Secrets User), so `Check` lists it as a missing role (DN-M5). The import probably needs a running, available host (unconfirmed), so the script starts one the lesson 0026 way. **Whether AVD reads FlexApp images this way is V19.** If not, the console's sync is the fallback, configured exactly as tier §4.2 says (custom role on the packages resource group only, no host pool permission, credential in Key Vault, set by Run Command), and §8.3's assignment rule still holds.
- **Assign:** `Set-FlexAppAssignment.ps1 -App <app> -Version <v> -Ring QA|All` sets the package's host pool reference and its user assignment (the landing zone's users group, or a group per app), QA hosts first, and is the **only** writer of assignments (tier H5). Version swap is blue/green: the new version on QA, then All, then the old version's reference removed; the old package stays registered until `-Retire`.
- **Double-assignment check** (`Get-LwAssignmentConflict`, pure): an app found in two of native app attach, FlexApp app attach and ProfileUnity rules is a `FAIL` at `Check`.

## 9. Stratusphere against the landing zone

The instrument is built (stratusphere/README.md stages 1, 2, 4, 5). What changes is how it is pointed:
- `Deploy-LiquidwareTier.ps1 -Component Stratusphere` calls `Test-StratusphereReadiness.ps1` and `Deploy-Stratusphere.ps1` with `-Location` = the landing zone's region (northcentralus in the sandbox, so the subscription's allowed-locations policy passes), `-NamePrefix <prefix><env>` (so the resource group is `rg-<prefix><env>-stratusphere` beside the landing zone's), `-PeerVnetId` = the spoke, `-HostPoolName`/`-HostPoolResourceGroup` = the landing zone's, and the callback source = `snet-session-hosts`' prefix instead of `VirtualNetwork` (D-M3);
- `-NoBastion` by default against a landing zone (Bastion Basic bills by the hour; the Hub console is reached from a session host over the peering, through the browser, by an operator in the admins group). `-Bastion` turns it back on;
- `Deploy-CidKey.ps1 -Action Install` to the landing zone's host pool after the Hub is set up; `Sync-LiquidwareHosts.ps1 -Component Stratusphere` catches hosts added during the window;
- **The window has an end.** `Deploy` writes `stratusphere-window-end` (default 28 days) as a tag on the resource group; `Check` warns a week before, fails after; `Cleanup -Component Stratusphere` uninstalls the key from every host, then removes the environment and the peering (already built in `Deploy-Stratusphere.ps1 -Action Cleanup -Role Hub`);
- **C16** (`stratusphere-instrument/v1`, brain contracts): the reports these scripts write (preflight manifest and current state, appliance check, rollout) get a schema in this repo, `contracts/schemas/stratusphere-instrument.schema.json`, and the scripts validate what they write against it. The factory's consumer test follows in avd-readiness-ux (boundaries spec §4). The reports hold machine names, so they stay in `output/` (git-ignored) and never reach the brain (§14).

## 10. Identities and secrets

| What | Where it lives | Who sees it |
|---|---|---|
| Console and packaging VM local admin | Tier Key Vault, generated, reused | Landing zone admins group (Key Vault Secrets User) |
| ProfileUnity license string (`LICSTR`) | Tier Key Vault `lw-licstr`, set once by the operator with `Set-LwSecret.ps1` (prompts with `Read-Host -AsSecureString`, writes through the ARM management plane; never a parameter, never chat) | The console and each session host, read with their own identities over the vault's private endpoint; never Cloud Shell after it is set |
| Installers | No credential: each VM reads `media` with its own managed identity | n/a |
| Console managed identity | Entra | Writes the `staging` container only; reads `media` and its two secrets |
| Session host managed identities (the landing zone's, system-assigned) | Entra | Read `media` and `lw-licstr`, granted per host by the sync and removed by `Cleanup` |
| Packaging VM managed identity | Entra, exists only with the VM | Reads `media`; writes the `appattach` share |
| Ops runner identity `id-<base>-lw-ops` | Entra, user-assigned, used only by the on-demand container | Reads `staging`, writes the live config account |
| Operator | Their own Entra sign-in in Cloud Shell, plus the avd-opsbot Graph sign-in when a script needs Graph (`Connect-AvdLandingZone.ps1`: the config account's consent and Conditional Access checks) | Uploads media; starts the ops runner and the packaging VM; registers and assigns packages; needs the roles listed by `Check` |
| App attach sync app registration | Not created (D-H3), unless V19 fails | n/a |
| Stratusphere appliance password | Its own Key Vault (built) | Deployer |

`Check` lists the operator's missing roles (from `Get-AzRoleAssignment` on each scope) the way the landing zone's `Test-AvdCallerPermission` does, and says which steps are data-plane calls and where each one runs (Cloud Shell, a VM, the ops runner), because Cloud Shell can't reach anything private (DN-C1). Swarm plans on GitHub-hosted runners have the same limit and use the same ops runner.

## 11. Actions

| Action | ProfileUnity | FlexApp | Stratusphere |
|---|---|---|---|
| Plan (default) | What-if of the template, the host plan, the cost lines (§13). Changes nothing | Packages and assignments found, conflicts | Its own Plan |
| Check | Resources, guards re-checked live (profiles account still keyless, users can't write the live config account), console reachable from one running host (Run Command `Test-NetConnection` 443; a host is started the lesson 0026 way only with `-StartStopped`), hosts' client versions, Key Vault secrets present (management plane), the config account's consent and Conditional Access exclusion | Registered packages, image paths resolve, assignment conflicts, packaging VM age | Its own Check, plus window end |
| Deploy | Template, then console install (§6.1), then hosts (§6.2) | `-Packaging` creates the VM | Readiness, then Hub |
| Configure | Hosts only (§6.2, §6.3) | n/a | Connector ID Key rollout |
| Promote | §7 | `Set-FlexAppAssignment.ps1` | n/a |
| Fix | Check, then only what repairs it: redeploy the template, rerun a failed host, start a stopped console | Re-register a package whose image moved | Its own Fix |
| Cleanup | Uninstall from hosts (drained, stopped ones started first), remove the Run Commands, data collection rule associations and host role grants, the peering and links, stop backup protection, then the resource group; `-RemoveUserData` also removes the `portability` share. Asks; `-Force` skips; `-WhatIf` lists | Remove assignments, then packages, then (with `-Packaging`) the VM | Its own Cleanup, uninstalling keys first |

Every action prints one line per check and ends with `RESULT PASS` or `RESULT FAIL <reason>`, and writes a JSON report to `output/` (git-ignored; it holds host names).

## 12. Testing, offline first

- **Pester, offline:** every function in `LiquidwareTier.psm1` (discovery from fake ARM responses, host plan, drain ownership and the budget lock, power-state order, promote checks and the rename order, INI overlap, assignment conflicts, cleanup order). ARM responses in fixtures omit empty properties the way ARM does (landing zone lesson 0020).
- **Template guards:** §5's list, over the compiled JSON (`bicep build`), plus `bicep lint` with the security rules as errors (copied from stratusphere/bicepconfig.json).
- **Host scripts:** parsed with the Windows PowerShell 5.1 grammar check (no PowerShell 7-only syntax: `??`, ternary, `&&`, `-Parallel`), no `Write-*` of a parameter named like a secret, no `/l*v`.
- **What-if** in the sandbox is the first step of any real run, and it is free.
- **CI:** `.github/workflows/profileunity.yml` mirrors `stratusphere.yml` (lint, build, PSScriptAnalyzer, Pester), triggered by `profileunity/**` and `scripts/**`.

## 13. Cost

Decision 0010: never guess a price. `Plan` prices each line from the retail price API (`prices.azure.com`), matching exactly one meter per line or listing the meters it saw, the same as the landing zone's `Get-AvdCostEstimate`. The session that wrote this spec couldn't reach that API, so no number is given here. The lines:

| Line | Meter | Hours in a sandbox run |
|---|---|---|
| Console VM | `Standard_D2as_v5` Windows, northcentralus | run length |
| Console OS disk | Premium SSD P10 | prorated month |
| Packaging VM (only if packaging is tested) | `Standard_D2as_v5` Windows client | ≤ 2 |
| NAT Gateway | per hour plus data processed | run length |
| Private endpoints (Key Vault, config file, packages file) | 3 × per hour plus data | run length |
| Storage (config, packages, media) | Standard LRS, a few GiB | prorated month |
| Ops runner | Container Instances, 1 vCPU and 1.5 GiB per second, per promote | minutes |
| NAT Gateway public IP | Standard static public IP | run length |
| `portability` share (only with `-Portability`) | Premium Files, provisioned, 100 GiB minimum; **keeps billing after `Cleanup` unless `-RemoveUserData`** | prorated month |
| Log Analytics ingestion (only with `-ApplicationRestrictions`) | Analytics logs per GiB | prorated |
| Backup (test and prod only) | Protected instance plus storage | prorated month |
| Defender for Key Vault, Defender for Storage malware scanning on uploads | where the landing zone turned them on (unconfirmed default for malware scanning) | per operation |
| Stratusphere Hub (only if Stratusphere is tested) | `Standard_D4s_v5` Linux plus the Marketplace plan's software meter (Liquidware's trial is $0 license, the Azure meter still bills) | run length |
| Defender for Servers P2 and Defender for Storage | billed automatically where the landing zone turned them on | prorated |
| Bastion | Developer (free) only if the console UI is needed; Basic is never on in the sandbox | 0 |

**The budget no longer stops all compute once the tier is on (D-H6, DN-C2).** The landing zone's Lock enumerates only the host pool's session hosts, and its identity has roles only on the hosts and control plane resource groups. The console, the packaging VM and the Stratusphere Hub (whose Marketplace meter bills on top of the VM) keep running; NAT, private endpoints and storage can't be stopped at all. Until fork F1 extends the runbook, `Plan` prints "the budget does not cover this tier" with the hourly cost of what stays on, `dev` VMs carry a daily shutdown schedule, and a sandbox run ends with `Cleanup` the same day.

Licenses: Liquidware trial, $0. **Before any run:** `Plan` prints the estimate, it goes in the thread, Nick says go. **After:** `Cleanup`, then teardown evidence (resource groups not found, no peering left on the spoke, no Run Command left on hosts) and run-cost evidence kept privately, outside this public repo.

## 14. Second brain and swarm

Rule: avd-swarm and avd-second-brain stay connected; a change in one is integrated into the other, in the same set of PRs. Rule: the brain reads estate facts only as C11 and C12, and the `liquidware.*` facts in its register (C15) stay `proposed` until a producer here builds them.

- **This spec changes no contract.** It produces no fact the brain reads yet. The Check report (§11) is operator output with host names, in `output/`, like C16's reports, and never reaches the brain.
- **The first `liquidware.*` facts** (tier §10.1: `liquidware.version`, `liquidware.flexapp.assignments`, `liquidware.profileunity.config` as hash and time) are built in slice B6 as an *extension of C11* produced by avd-current-state's collector (it already reads host pools and app groups), not by a new contract. That needs three PRs together: avd-second-brain (register status `proposed` → `built`, schema path), avd-current-state (producer) and avd-swarm (gate rule). Not started by this spec.
- **Swarm plans** (tier §10.3) map onto this spec's actions one to one: *promote a ProfileUnity configuration* = §7 Promote, *assign or swap a FlexApp version* = §8.3, *sync hosts* = §6.3, *close a Stratusphere window* = §9 Cleanup. avd-swarm runs them through its approval and kill switch; the brain never holds a write credential (decision 0003). The plans land in avd-swarm when B6 does.
- **Knowledge:** each real run's lessons go to `docs/lessons/` here, then a harvest to the brain's `knowledge/` by a PR Nick merges.

## 15. Build slices

Each slice is one small PR with offline tests, merged before the next starts. None deploys anything.

| Slice | What | Tests |
|---|---|---|
| **B1** | `scripts/LiquidwareTier.psm1` discovery (`Get-LwLandingZone` over ARM data, names, address overlap), `Deploy-LiquidwareTier.ps1` skeleton with Plan and Check for discovery only, `profileunity/` scaffolding, CI workflow | Pester over fixtures; PSScriptAnalyzer |
| **B2** | `profileunity/bicep/main.bicep`: RG, VNet, peering, DNS links, Key Vault, config account, packages account, NAT, ops runner identity; Plan runs what-if and fails on any landing zone change outside §4 | Template guards (§5); what-if summary |
| **B3** | Console VM and `Install-ProfileUnityConsole.ps1` (download, hash, checklist stop until V18); media upload; secrets through the management plane | Template guards; host script grammar checks; IMDS token and hash check |
| **B4** | Client: `Install-ProfileUnityClient.ps1`, `Sync-LiquidwareHosts.ps1`, drain logic | Host plan and drain decisions; protected parameters |
| **B5** | Config staging and promote (§7); FlexApp upload, register, assign (§8) | Promote checks, INI overlap, assignment conflicts, cleanup order |
| **B6** | Stratusphere against the landing zone (§9), C16 schema; brain and swarm hooks (§14) paired with avd-second-brain, avd-swarm and avd-current-state PRs | Schema tests; connector tests in the brain |

## 16. Unverified, and the forks

New verify items (the tier spec's V1 to V17 still stand, notably V1, V2/V3, V5, V7, V8, V14, V16):

| # | Question | How | Blocks |
|---|---|---|---|
| V18 | Silent install switches for the 6.9.5 console and the FlexApp Packaging Console | Liquidware install guide | Console install automation (§6.1) |
| V19 | Does AVD's `importAppAttachPackageInfo` read a FlexApp app attach image, so the tier can register it without the console's secret? | Liquidware docs, then the sandbox | §8.3 default |
| V20 | FlexApp Packaging Console command line | Liquidware docs | Unattended packaging |
| V21 | Does the client read `USERINI` from Azure Files with Entra Kerberos as the user, from a host that is drained and reconfigured without reboot? | Sandbox | §6.2 ordering |
| V22 | `azcopy` to Azure Files with a managed identity and the backup intent, for a multi-GiB VHDX | Sandbox | §8.2 |
| V23 | Can the console export the configuration in plain text, and can that export be tied to the staged, encrypted INI? | Liquidware docs, then the sandbox | Promote's checks (§7) |
| V24 | Does the client validate the license service's TLS certificate, and does it accept an IP address as the console's name? | Liquidware docs, then the sandbox | §5 console naming |
| DV5 | Stratusphere Hub API for license, API user and whitelist | Liquidware docs | Hub setup automation |

**Forks for Nick:**
1. **F1. A small, generic change in avd-landing-zone so it respects the tier?** Three parts: Resume skips hosts tagged `liquidware-hold`; Lock also deallocates VMs tagged `avdlz-power-managed` in resource groups it is granted (the tier's and Stratusphere's); and its host deployment takes an optional post-FSLogix Run Command. Recommended: yes for the first two before any customer use (they restore "the budget stops compute" and close the held-host gap), as one avd-landing-zone PR paired with slice B4; not yet for the hook.
2. **F2. Stratusphere in the sandbox before there's a customer?** Recommended: no; its tooling is built and offline-tested, and a run costs a Hub VM for days. Test ProfileUnity first.
3. **F3. Console backup:** off in `dev`, and the tier's own vault with an Enhanced policy in `test` and `prod`. Recommended: that, rather than the landing zone's vault, whose Standard default policy doesn't take Trusted Launch VMs and whose items `Cleanup` would have to reach into.
4. **F4. Media account with a public, Entra-only endpoint?** Shared key and anonymous access off; installers and the staged configuration (which ProfileUnity encrypts). Recommended: yes, it is the only keyless way to upload from Cloud Shell. The alternative is a private account filled from the packaging VM's browser, by hand, for every new version.
