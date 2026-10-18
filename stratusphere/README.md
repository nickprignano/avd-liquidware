# Stratusphere UX in Azure

Deploy **Liquidware Stratusphere UX** in Azure for an **Azure Virtual Desktop** readiness assessment: check the subscription first, deploy the Hub (and optionally a Database and Collectors) from Azure Marketplace with one Bicep template, and roll the Connector ID Key out to the desktops you're assessing. Turning what Stratusphere measures into an AVD design is out of scope here.

> [!WARNING]
> **Personal project. Not for production. No warranty.**
>
> - This is my own personal project, built on my own time. It is **not affiliated with, endorsed by or supported by my employer**, and it does not represent my employer's views, products or guidance.
> - It is **not affiliated with or endorsed by Liquidware** or Microsoft. Stratusphere is Liquidware's product; this repo only automates deploying and using it. **Bring your own Stratusphere license** (Liquidware offers trial licenses).
> - It is a reference and learning project. **Do not run it in production** or against subscriptions and tenants that matter. Use a dedicated lab subscription.
> - It is provided **"as is", without warranty of any kind**, under the [MIT License](../LICENSE). You are responsible for what it deploys, for the Azure charges it incurs, and for reviewing the code before you run it.

## Status

Early. What works today and what is next:

| Stage | What it does | State |
|---|---|---|
| 1. Preflight | Identity and RBAC, providers, each role's Marketplace plan and terms, VM sizes, vCPU and network quota, policy, locks, address overlap, and the callback path from the endpoints (NSG and routes); captures the current state in a report. Reads an [avd-current-state](https://github.com/nickprignano/avd-current-state) package. `-Fix` registers providers, accepts terms, installs Bicep ([docs](docs/preflight.md)) | Done, not yet run against a real subscription |
| 2. Appliances | One script, by role (Hub, Database, Collector): plan, check, deploy, fix, clean up ([docs](docs/appliances.md)). Resource group, VNet (optionally peered to your endpoints), Key Vault, Bastion, appliances from Azure Marketplace with static IPs | Done, not yet run against a real subscription |
| 3. Hub setup | License, API user, API whitelist | Manual for now (console checklist below) |
| 4. Connector ID Key rollout | Azure Run Command to a host pool, resource group or tag: check, install, fix, uninstall, cleanup, retry from a report ([docs](docs/agent-rollout.md)). Golden image and Intune for hosts created later | Done, not yet run against real machines |
| 5. Teardown | Uninstall keys (`Deploy-CidKey.ps1 -Action Cleanup`), remove appliances or the environment (`Deploy-Stratusphere.ps1 -Action Cleanup`) | Done, not yet run against a real subscription |

## What gets deployed

| Resource | Notes |
|---|---|
| Resource group `rg-<prefix>-stratusphere` | One per assessment, so teardown is one delete |
| VNet with `snet-stratusphere` (+ `AzureBastionSubnet`) | NSG admits TCP 443 from `callbackSourcePrefixes` (default `VirtualNetwork`), SSH from Bastion, and TCP 5432 between appliances when there is a Database or Collectors |
| NAT Gateway | The subnet has default outbound access off; the appliances' egress (updates, NTP) leaves through it |
| Optional two-way peering | `-PeerVnetId` to the network the assessed desktops are on, for example an avd-landing-zone spoke |
| Key Vault | RBAC, purge protection; holds the appliance password Azure sets, readable by the deployer and reused on every rerun |
| Azure Bastion (Basic) | Console access with no public IP; `-NoBastion` skips it |
| Hub VM | Marketplace image with its matching `plan` block, `Standard_D4s_v5` (Liquidware lists 4 vCPU and 16 GB as the Hub minimum), 128 GB Premium SSD, static private IP `10.60.0.4` |
| Database VM (optional) | `-Role Database`; Liquidware advises one above 1,000 Connector ID Keys. `Standard_D4s_v5`, 256 GB, `10.60.0.5` |
| Collector VMs (optional) | `-Role Collector -CollectorCount 1-4`. `Standard_D2s_v5`, 64 GB, `10.60.0.10` onward |

Everything is built from pinned [Azure Verified Modules](https://aka.ms/avm).

## Quick start

From Azure Cloud Shell (PowerShell), in a lab subscription:

```powershell
git clone https://github.com/nickprignano/avd-liquidware.git
Set-Location avd-liquidware/stratusphere

# 1. List the Stratusphere plans offered in your region, then run the full preflight.
#    -Fix registers providers, accepts the Marketplace terms and installs the Bicep CLI.
#    The host pool (or -EndpointSubnetId) lets it check the callback path from the endpoints.
./scripts/ops/Test-StratusphereReadiness.ps1 -Location eastus2
./scripts/ops/Test-StratusphereReadiness.ps1 -Location eastus2 -HubPlan <plan> -Fix `
  -PeerVnetId <spoke-vnet-id> -HostPoolName <host-pool> -HostPoolResourceGroup <rg>

# 2. Preview, then deploy the Hub.
./scripts/ops/Deploy-Stratusphere.ps1 -HubPlan <plan>                 # Plan (what-if) is the default
./scripts/ops/Deploy-Stratusphere.ps1 -HubPlan <plan> -Action Deploy

# 3. Later: check it, repair it, or add roles.
./scripts/ops/Deploy-Stratusphere.ps1 -Action Check
./scripts/ops/Deploy-Stratusphere.ps1 -Action Fix
./scripts/ops/Deploy-Stratusphere.ps1 -Action Deploy -Role Database -DatabasePlan <plan>
```

To assess desktops on another VNet (for example an avd-landing-zone spoke), add `-PeerVnetId <vnet-resource-id>`. The address spaces must not overlap; the default here is `10.60.0.0/24`. Prefer bash? `scripts/deploy/deploy.sh` deploys the same template (no check, fix or cleanup). [docs/appliances.md](docs/appliances.md) covers every action and role.

### First-time Hub setup (manual for now)

1. Open the appliance console through Bastion (portal: VM > Connect > Bastion), or browse to `https://10.60.0.4` from a machine on a connected network.
2. The password Azure set is in Key Vault: `Get-AzKeyVaultSecret -VaultName <kv> -Name appliance-admin-password -AsPlainText`.
3. Apply your Stratusphere license.
4. Create a dedicated API user. The default `ssadmin` account can't use the API.
5. Under **Hub Administration > Configuration > Security Settings**, add the addresses that will call the API to the whitelist.

If you find the appliance doesn't use the credential Azure sets, or first boot asks for something not listed here, please open an issue: the first real runs decide how far this stage can be automated.

### Roll out the Connector ID Key

Download the Connector ID Key installer from your Hub, put it somewhere the desktops can reach (for example a storage container with a short-lived SAS URL), and note its SHA-256. Then:

```powershell
$t = @{ HostPoolName = 'hp-avdlz-dev'; HostPoolResourceGroup = 'rg-avdlz-dev-avd' }
./scripts/ops/Deploy-CidKey.ps1 @t                     # plan only
./scripts/ops/Deploy-CidKey.ps1 @t -Action Install -HubAddress 10.60.0.4 -InstallerUrl $url -InstallerSha256 $sha
./scripts/ops/Deploy-CidKey.ps1 @t -Action Check
```

`-Action Fix` repairs broken or half-installed keys, `-Action Cleanup` removes the key and its leftovers, and `-FromReport output/cid-rollout-<time>.json` reruns only the machines that did not end healthy. See [docs/agent-rollout.md](docs/agent-rollout.md).

## Validate before pushing

From `stratusphere/` (CI runs the same in `.github/workflows/stratusphere.yml`):

```bash
bicep lint bicep/main.bicep
SSUX_ADMIN_PASSWORD='Placeholder-only-1!' SSUX_KV_READER_ID=00000000-0000-0000-0000-000000000001 \
  bicep build-params parameters/lab.bicepparam --stdout > /dev/null
pwsh -c "Invoke-ScriptAnalyzer -Path scripts -Recurse -Settings ./PSScriptAnalyzerSettings.psd1 -EnableExit"
pwsh -c "Invoke-Pester -Path ./tests -CI"
shellcheck scripts/deploy/deploy.sh
```

## License

[MIT](../LICENSE). Stratusphere, Connector ID and Liquidware are trademarks of Liquidware Labs, Inc.; Azure is a trademark of Microsoft.
