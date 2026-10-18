# Red-team review: automated deployment of ProfileUnity, FlexApp and Stratusphere

- **Reviewed:** [deploy-spec.md](deploy-spec.md), first draft of 2026-10-18 (decision AL-0002, Proposed), against avd-landing-zone's templates and runbooks at its current `master`. Two passes: the author's, then an independent reviewer that had only the two specs, the landing zone and the Stratusphere tooling.
- **Method:** follow an operator's first deployment from Cloud Shell, a user's logon after the tier is on, a landing zone redeploy, rotation and scale-out, a teardown, and an attacker holding the ProfileUnity console, and ask at each step which identity touches which resource over which network path, what fails, what is left behind, what bills silently, and which landing zone guarantee breaks. Nothing here has run against a real tenant.
- **Status:** every finding is folded into the spec, which carries the IDs where the fix landed.

## Verdict

The automation is buildable without weakening the landing zone, but the first sketch broke four guarantees. Two came from reading the tier spec as if the landing zone were a blank page: a subnet added to the spoke breaks or is erased by the landing zone's next deploy (D-C1), and a config share on the profiles account is writable by every user because the landing zone grants SMB Share Contributor at account scope (D-C2). One is the tier spec's own console risk made concrete: a console that can write the live INI is a logon policy push to every host (D-C3). The fourth is about where the operator stands: Cloud Shell has no line of sight to private endpoints, so every data-plane step the draft gave the operator could not have run (D-C4). The independent pass found that the author's fix for D-C4 still left Key Vault reads in Cloud Shell (DN-C1), that the budget no longer stops all compute (DN-C2, which the author had rated high), that hosts couldn't resolve a blob endpoint nobody linked (DN-C3), and, the subtlest, that ProfileUnity 6.9.5 encrypts the INI, so the second hand of D-C3 would approve a file it can't read (DN-C4).

| Severity | Author's pass | Independent pass |
|---|---|---|
| Critical: a stated guarantee doesn't hold or a step can't work | 4 | 4 |
| High: wrong in a likely case | 6 | 7 |
| Medium | 4 | 8 |

## Critical

### D-C1. A subnet on the landing zone's VNet doesn't survive the landing zone
**Where:** tier §5.1 (`snet-mgmt` "added by this tier"), deploy-spec §4, §5.
**Scenario:** the landing zone declares its subnets as the VNet's `subnets` array (`bicep/modules/network.bicep`). Its next `deploy.sh` PUTs the VNet without `snet-mgmt`: ARM either refuses (`InUseSubnetCannotBeDeleted`, the console's NIC is in it), so the landing zone can no longer be deployed, or, once the subnet is empty, deletes it.
**Fix (folded, §4, §5):** the tier has its own VNet, peered to the spoke. Every write to a landing zone resource is a child resource that an incremental deployment leaves alone (peering, DNS links and records, a share, app attach packages, Run Commands), listed in one table and removed by `Cleanup`.

### D-C2. A config share on the profiles account is user-writable
**Where:** tier §5.1 ("Config share: its own share"), deploy-spec §5.
**Scenario:** `bicep/modules/storage.bicep` gives the users group SMB Share Contributor on the **account**, so it applies to every share on it, including a new config share. Share-scoped Reader on top doesn't take it away (RBAC is additive). Any user can edit the INI their own logon reads and switch off their restrictions (tier N-C1 again).
**Fix (folded, §5):** a separate config account, keyless, Entra Kerberos, with SMB Share Reader for users scoped to the live share only. A template test fails on any user write role on it.

### D-C3. The console can push a logon policy to every host
**Where:** tier §7 (C2), deploy-spec §7.
**Scenario:** with the console as the writer of the live INI (the obvious answer to V16), whoever holds the console changes every user's logon at their next sign-in: restrictions off, a logon script added.
**Fix (folded, §7):** two hands. The console's identity writes a staging share only; promote to live is a separate identity driven by a person or an approved swarm plan, with checks and a QA ring first; rollback is a promote of the previous version.

### D-C4. Cloud Shell can't reach the tier's private endpoints
**Where:** draft §6.4 (operator uploads media and mints a user delegation SAS), §7 (operator promotes over REST), §8.2 (operator uploads packages with `azcopy`).
**Scenario:** every one of those is a data-plane call to an account with public network access off. Cloud Shell isn't on the VNet, so each fails with `AuthorizationFailure`/403 from the storage firewall. Even the user delegation key request goes to the blob endpoint. Storage IP rules don't help: they don't apply to clients in the same Azure region as the account, which Cloud Shell often is.
**Fix (folded, §6.4, §7, §8, §10):**
- **No SAS at all.** Every VM that reads media uses its own managed identity: session hosts already have a system-assigned identity (the Entra join needs it), so the host sync grants each host Storage Blob Data Reader on the `media` container and the host script fetches with an IMDS token.
- **Media in its own account with a public endpoint, Entra-only** (shared key off, anonymous access off, TLS 1.2, Defender): installers are licensed software, not secrets, and this lets the operator upload from Cloud Shell. A named exception, pinned by template tests (fork F4 for whether it stays).
- **Small data-plane writes (promote, staging cleanup, live checks) run in an ops runner:** an Azure Container Instance started on demand in a delegated tier subnet, with its own user-assigned identity, the only identity with write on the live share. The operator starts it (ARM, which Cloud Shell can reach); the console can't. It is deleted when the job ends.
- **FlexApp packages are uploaded from the packaging VM** (inside the network, its identity scoped to the `appattach` share), where they are produced anyway.

## High

### D-H1. Hosts created later take logons without ProfileUnity
**Where:** draft §6. **Scenario:** scale-out, rotation and rebuild run the landing zone's `Configure-FSLogix` and `Register-AvdAgent`, not this tier's script; the host registers and users sign in without restrictions or user environment management. **Fix (folded, §6.3):** idempotent host sync, `Check` fails on unconfigured hosts, unconfigured hosts are held (drained) until configured; fork F1 for a hook in the landing zone.

### D-H2. A bad client rolls out to every host at once
**Where:** §6.2. **Scenario:** a client build that breaks logon is installed pool-wide in one pass. **Fix (folded, §6.2):** one host at a time by default, QA ring first, a failed host stays drained.

### D-H3. The app attach sync needs a client secret on the console
**Where:** tier §4.2, F4, N-C2. **Scenario:** the console holds a secret with write on app attach packages; taking the console takes the secret. **Fix (folded, §8.3):** register packages with the operator's identity through AVD's own import call; the console's sync is the fallback if V19 fails.

### D-H4. The config account needs the same Entra Kerberos setup as the profiles account
**Where:** §5. **Scenario:** Entra Kerberos on a new storage account creates a new Entra app for it, which needs admin consent and must be excluded from Conditional Access policies that require MFA, exactly the steps the landing zone's preflight checks for the profiles account (`Test-AvdStorageAdminConsent`, `Test-AvdConditionalAccessExclusion`). Without them every user's INI read fails at logon, silently: ProfileUnity just doesn't apply. **Fix (folded, §5, §11):** `Check` runs the same two checks for the config account (through the avd-opsbot Graph sign-in), and `Fix` grants the consent the way the landing zone's `-Fix` does.

### D-H5. Drains get undone behind the sync's back
**Where:** §6.2, §6.3. **Scenario:** the scaling plan's ramp-down drains hosts and its ramp-up undrains them, and the landing zone's `Invoke-AvdPowerAction.ps1 -Action Resume` sets `allowNewSession` to true on **every** host. A host held because it's unconfigured, or drained mid-install, takes logons again. **Fix (folded, §6.2, §6.3):** during a change the sync also sets the scaling plan's exclusion tag (`avd-scaling-exclude`), and every hold is recorded as a `liquidware-hold` tag so the next sync and `Check` re-apply it. Closing the Resume gap needs avd-landing-zone to skip held hosts on Resume: fork F1.

### D-H6. The budget Lock doesn't stop the tier's spend
**Where:** tier N-M5 ("Lock deallocates the console too"), §13. **Scenario:** the landing zone's budget alert runs `Invoke-AvdPowerAction.ps1 -Action Lock`, which only acts on `rg-<base>-hosts` and the host pool. The console, the packaging VM, the Stratusphere Hub, the NAT Gateway and the private endpoints keep billing. **Fix (folded, §5, §13):** in `dev` and `test` the console and packaging VM get a daily shutdown schedule at the landing zone's shutdown time (a free resource), `Plan` prints the hourly cost of what stays on, and in the sandbox every run ends with `Cleanup`. Making Lock tier-aware is part of fork F1.

## Medium

- **D-M1. Deallocated hosts.** A Run Command needs a running VM; with Start VM on Connect a stopped, unconfigured host wakes up for a user and takes the logon. Fix (folded, §6.2): the sync holds stopped unconfigured hosts (drain works on a deallocated host) and configures them when it next finds them running, or starts them with `-StartStopped`.
- **D-M2. Installers.** Liquidware binaries can't be in this repo, and a download URL behind a portal sign-in doesn't work from a host. Fix (folded, §6.4): operator uploads once, hash-pinned lock file kept in the customer's private repo, VMs read with their own identity.
- **D-M3. Stratusphere callback scope.** The instrument's default callback source is `VirtualNetwork`, which after peering includes the tier's VNet and anything else peered. Fix (folded, §9): the session host subnet's prefix.
- **D-M4. DNS records in the landing zone's zones.** The tier's file and Key Vault private endpoints register A records in the landing zone's `privatelink.file` and `privatelink.vaultcore` zones (so hosts resolve them), and the media account doesn't need a blob zone at all once it is public (D-C4). Fix (folded, §4): the records are in the writes table and removed with the endpoints.

## Independent pass

Findings the author's pass missed or under-rated. Each is folded into the spec under its ID. The reviewer read the landing zone's code and lessons; "unconfirmed" marks Azure facts it couldn't check.

### Critical
- **DN-C1. Cloud Shell can't reach any of the tier's data planes, Key Vault included.** Setting the license secret, reading it back for a Run Command, setting the Portability share's NTFS ACL, and the staging diff all fail from Cloud Shell, as the landing zone's decision 0005 already says. Fix (folded, §5, §6, §10, §11): secrets are written through the ARM management plane; VMs read secrets and media with their own identities; NTFS is set the decision 0005 way (a Run Command on a session host with a temporary role); `Check` says where each data-plane step runs.
- **DN-C2. The budget no longer stops the tier's compute.** The Lock runbook only enumerates session hosts and its identity has no role on the tier's resource groups; the Stratusphere Hub's Marketplace meter keeps billing. Fix (folded, §13, F1): `Plan` says the budget doesn't cover the tier, `dev` VMs get a shutdown schedule, sandbox runs end with `Cleanup` the same day, and fork F1 proposes a tag-based Lock extension in avd-landing-zone.
- **DN-C3. A blob endpoint nobody resolves.** The spoke links no `privatelink.blob` zone, and a tier-owned one would collide with any later landing zone or hub blob zone; the file and vault records in the landing zone's zones were also unlisted writes. Fix (folded, §4): no blob private endpoint at all (media is public, Entra-only, F4); the zone group records are listed.
- **DN-C4. The second hand approves ciphertext.** ProfileUnity 6.9.5 encrypts INI content by default, so Promote's parse, overlap and diff checks can't run and a malicious staged INI passes. Fix (folded, §7, V23): checks run on the console's plain-text export tied to the staged deploy; without one, Promote refuses.

### High
- **DN-H1. Drain has three writers** (the tier, the budget Lock and Resume, rotation). Fix (folded, §6.2): the tier undrains only what it drained (`liquidware-drained`), never while the budget lock is on; `Check` fails on any unconfigured host taking sessions.
- **DN-H2. Hosts are usually deallocated,** so Sync, Cleanup and Check would do nothing or leave Run Commands behind (lesson 0026). Fix (folded, §6.2, §11): lesson 0026's order: record power state, exclude from scaling, start, act, restore.
- **DN-H3. Share-scoped data roles are unconfirmed.** If Storage File Data Privileged Contributor only takes effect at account scope, the console could write live. Fix (folded, §5, §7): staging is a blob container (container-scoped roles are well established) on a different account from live; every Files grant is account-scoped.
- **DN-H4. Multichannel is Premium-only, and the new Entra Kerberos app needs consent and a Conditional Access exclusion.** Fix (folded, §5): the config account copies every SMB setting but multichannel; `Check`/`Fix` cover consent and the exclusion; `Cleanup` removes the app if it outlives the account.
- **DN-H5. An edit to the landing zone's data collection rule is lost on its next deploy.** Fix (folded, §4, §5): the tier's own rule and per-host associations, listed and cleaned up, and `Check` confirms events arrive.
- **DN-H6. Trusted Launch needs an Enhanced backup policy,** and items in the landing zone's vault outlive `Cleanup` and its soft delete. Fix (folded, §5, F3): no backup in `dev`; the tier's own vault with an Enhanced policy elsewhere; `Cleanup` stops protection first.
- **DN-H7. The Portability share bills on provisioned size (Premium, 100 GiB minimum), survives `Cleanup` and isn't backed up.** Fix (folded, §4, §13): only with `-Portability`, at the minimum, a cost line, a `WARN` with its monthly cost when `Cleanup` keeps it, and unbacked stated.

### Medium
- **DN-M1.** The landing zone's host NSG admits everything from `VirtualNetwork`, peers included: a taken-over console reaches hosts on 445, 135 and 5985. Fix (folded): outbound deny to the spoke from the console and packaging subnets, and a template guard.
- **DN-M2.** Azure-provided DNS doesn't resolve VM names across a peering; Entra-joined hosts need the storage FQDN. Fix (folded): the console by static IP; full FQDN in `USERINI`; V24 for the license service's certificate.
- **DN-M3.** A purge-protected vault blocks a rerun after `Cleanup` (lesson 0022). Fix (folded): `Plan`/`Check` offer recovery.
- **DN-M4.** `vm-<prefix>lwcon` can exceed the 15-character computer name limit. Fix (folded): `take(…, 15)` and a test.
- **DN-M5.** The import probably needs a running host (unconfirmed), and the landing zone's admins group doesn't hold Desktop Virtualization Contributor. Fix (folded, §8.3): start one host the lesson 0026 way; `Check` lists the role.
- **DN-M6.** Promote over REST isn't atomic. Fix (folded, §7): temporary names, then rename, XML first.
- **DN-M7.** Missing cost lines: NAT public IP, Defender for Key Vault, malware scanning, Log Analytics ingestion, backup, the Portability share. Fix (folded, §13).
- **DN-M8.** "Single session, the landing zone's image" contradicts itself: the landing zone's image is multi-session. Fix (folded, §8.1): the single-session SKU named.

### Corrections to the author's pass
- D-H6 (budget) is critical, not high: it is a stated guarantee of the tier spec (N-M5). Kept under its ID, raised by DN-C2.
- D-C4's first fix still had the deploy script reading `lw-licstr` from Cloud Shell to pass it as a protected parameter; that read is a Key Vault data-plane call. Now the VMs read it themselves (DN-C1).
