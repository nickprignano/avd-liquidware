# Preflight

`scripts/ops/Test-StratusphereReadiness.ps1` answers one question before you deploy: will the appliances deploy here, and will the Connector ID Keys be able to call back? It is read-only unless you pass `-Fix`. Run it from Azure Cloud Shell (PowerShell).

```powershell
# Plans offered in the region
./scripts/ops/Test-StratusphereReadiness.ps1 -Location eastus2

# Everything, for a Hub peered with an avd-landing-zone spoke
./scripts/ops/Test-StratusphereReadiness.ps1 -Location eastus2 -HubPlan <plan> `
  -PeerVnetId <spoke-vnet-id> -HostPoolName hp-avdlz-dev -HostPoolResourceGroup rg-avdlz-dev-avd

# The same from a config file (see parameters/preflight.example.json), fixing what it can
./scripts/ops/Test-StratusphereReadiness.ps1 -ConfigPath parameters/preflight.local.json -Fix
```

## Checks

| Category | What it checks |
|---|---|
| Tooling | PowerShell, the Az modules, the Bicep CLI (`Deploy-Stratusphere.ps1` reads a `.bicepparam` file) |
| Identity | The subscription is enabled. You hold Owner, or Contributor plus User Access Administrator: the deployment grants you read access to the Key Vault, which Contributor alone can't do |
| Providers | Compute, Network, KeyVault, MarketplaceOrdering registered |
| Marketplace | For each role (`-Role Hub,Database,Collector`): its plan is offered in the region, the image carries a purchase plan, the terms are accepted |
| Capacity | Each role's VM size is offered and not restricted. vCPU quota per family and regionally, summed over every appliance; when a family is short, the families that have room. Network interfaces (one per appliance) and public IPs (NAT Gateway, Bastion) |
| Policy | Allowed-locations and allowed-VM-size policies against the region and sizes; other deny policies listed; initiatives noted (not expanded) |
| Subscription | ReadOnly locks (block the deployment), CanNotDelete locks (block cleanup), an existing environment and its roles, a soft-deleted Key Vault (Deploy recovers it) |
| Network | The assessment address space (`10.60.0.0/24`) against the peer VNet (an overlap fails: Azure refuses the peering), the VNets peered with it, the endpoint VNets and every VNet in an avd-current-state package. The peer VNet's region and DNS |
| Endpoints | For each subnet the Connector ID Keys run in: whether its NSG lets TCP 443 out to the Hub (rules evaluated by priority, first match wins), and where its routes send the callbacks (peering, firewall, gateway, black hole). The number of endpoints against Liquidware's advice of a Database appliance above 1,000 Connector ID Keys |

Statuses: `FAIL` blocks the deployment or the callbacks, `WARN` is worth a look, `PASS`, `INFO` is recorded state, `SKIP` means an input was missing, `FIXED` means `-Fix` changed it. Exit code 0 with no `FAIL`, 1 with one, 2 when it could not run.

### Routes, briefly

With direct peering, Azure adds a system route for the assessment VNet's `/24`. A user route only wins if it is at least as specific, so a forced-tunnel `0.0.0.0/0` (or `10.0.0.0/8`) to a firewall does not affect the callbacks. Without direct peering (the endpoints reach the assessment VNet through a hub), the covering route decides, and a firewall on that path must allow TCP 443 to the Hub.

## Endpoints, three ways

- `-HostPoolName` and `-HostPoolResourceGroup`: the session hosts' subnets (from their NICs) and their count.
- `-EndpointSubnetId`: any subnets, for desktops that aren't in a host pool.
- `-AvdCurrentStatePath`: a package (folder or zip) from [avd-current-state](https://github.com/nickprignano/avd-current-state)'s collector. The preflight reads the session host count and every VNet's address space from it, so you can size and check overlaps against an estate you don't have live access to.

`-EndpointCount` overrides the count.

## Output

`output/preflight-<time>/` (git-ignored, because it holds machine and network names):

| File | Contents |
|---|---|
| `report.md` | Verdict, what to fix, what to look at, every check |
| `results.csv`, `results.json` | One row per check: category, status, check, detail, recommendation |
| `current-state.json` | What the preflight read: subscription and your roles, providers, plans and terms, quota rows, policy assignments, locks, existing appliances, the peer VNet and its peerings, each endpoint subnet's NSG rules and routes, the address ranges checked |
| `manifest.json` | Inputs, verdict and counts, so a run can be repeated |

`-OutputPath` writes elsewhere, for example `~/clouddrive` so the report outlives the Cloud Shell session.

## Not yet verified on a real subscription

The policy reading copes with the property shapes of recent Az.Resources versions; an older or newer module may read some policies as unknown. Please open an issue with the check name if a check reports something you can see is wrong.
