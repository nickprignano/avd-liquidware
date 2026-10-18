#!/usr/bin/env bash
# Deploy the Stratusphere UX assessment environment at subscription scope (bash).
# scripts/ops/Deploy-Stratusphere.ps1 is the full lifecycle (Plan, Check, Deploy, Fix, Cleanup);
# this script deploys only, for those who prefer bash.
# Personal project, not for production use. Provided as is, without warranty of any kind (MIT License, see LICENSE at the repo root). Not affiliated with the author's employer, with Liquidware or with Microsoft.
#
# Usage:
#   ./scripts/deploy/deploy.sh -p parameters/lab.bicepparam -l eastus2 --plan <marketplace-plan> \
#       [--database-plan <plan>] [--collector-plan <plan> --collectors <1-4>] \
#       [--version <image-version>] [--vm-size Standard_D4s_v5] \
#       [--peer-vnet <vnet-resource-id>] [--no-bastion] [--what-if]
#
# --plan is the Marketplace plan (SKU) of the Hub; --database-plan adds the Database
# appliance and --collector-plan adds Collectors. Pass the same role flags on every rerun:
# a role left out keeps its VM but loses its NSG rule (Deploy-Stratusphere.ps1 keeps
# existing roles by itself). The preflight lists the plans offered:
#   pwsh ./scripts/ops/Test-StratusphereReadiness.ps1 -Location eastus2
#
# Environment variables (any flag above overrides):
#   SSUX_NAME_PREFIX, SSUX_HUB_PLAN, SSUX_DATABASE_PLAN, SSUX_COLLECTOR_PLAN, SSUX_COLLECTOR_COUNT,
#   SSUX_IMAGE_VERSION, SSUX_HUB_VM_SIZE, SSUX_PEER_VNET_ID
#   SSUX_ADMIN_PASSWORD       appliance password Azure sets (reused from Key Vault on reruns,
#                             random the first time, stored in Key Vault)
#   SSUX_KV_READER_ID         object ID allowed to read it (the signed-in user if unset)
set -euo pipefail

PARAM_FILE=""
LOCATION=""
WHATIF=false
PUBLISHER="liquidware"
OFFER="stratusphere"

usage() {
  sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -p) PARAM_FILE="$2"; shift 2 ;;
    -l) LOCATION="$2"; shift 2 ;;
    --plan) SSUX_HUB_PLAN="$2"; shift 2 ;;
    --database-plan) SSUX_DATABASE_PLAN="$2"; shift 2 ;;
    --collector-plan) SSUX_COLLECTOR_PLAN="$2"; shift 2 ;;
    --collectors) SSUX_COLLECTOR_COUNT="$2"; shift 2 ;;
    --version) SSUX_IMAGE_VERSION="$2"; shift 2 ;;
    --vm-size) SSUX_HUB_VM_SIZE="$2"; shift 2 ;;
    --peer-vnet) SSUX_PEER_VNET_ID="$2"; shift 2 ;;
    --no-bastion) SSUX_DEPLOY_BASTION=false; shift ;;
    --what-if) WHATIF=true; shift ;;
    *) usage ;;
  esac
done

[[ -z "$PARAM_FILE" || -z "$LOCATION" ]] && usage
[[ ! -f "$PARAM_FILE" ]] && { echo "Parameter file not found: $PARAM_FILE"; exit 1; }
[[ -z "${SSUX_HUB_PLAN:-}" ]] && { echo "Pass --plan (or set SSUX_HUB_PLAN). The preflight lists the plans offered in your region."; exit 1; }
PLANS=("$SSUX_HUB_PLAN")
SSUX_DEPLOY_DATABASE=false
if [[ -n "${SSUX_DATABASE_PLAN:-}" ]]; then SSUX_DEPLOY_DATABASE=true; PLANS+=("$SSUX_DATABASE_PLAN"); fi
SSUX_COLLECTOR_COUNT="${SSUX_COLLECTOR_COUNT:-}"
if [[ -n "${SSUX_COLLECTOR_PLAN:-}" ]]; then
  PLANS+=("$SSUX_COLLECTOR_PLAN")
  SSUX_COLLECTOR_COUNT="${SSUX_COLLECTOR_COUNT:-1}"
fi
[[ -z "$SSUX_COLLECTOR_COUNT" || "$SSUX_COLLECTOR_COUNT" =~ ^[0-4]$ ]] || { echo "--collectors must be 0-4"; exit 1; }
[[ "${SSUX_COLLECTOR_COUNT:-0}" -gt 0 && -z "${SSUX_COLLECTOR_PLAN:-}" ]] && { echo "--collectors needs --collector-plan"; exit 1; }
for p in "${PLANS[@]}"; do
  [[ "$p" =~ ^[A-Za-z0-9._-]+$ ]] || { echo "Not a Marketplace plan name: '$p'"; exit 1; }
done
PREFIX="${SSUX_NAME_PREFIX:-ssux}"
[[ "$PREFIX" =~ ^[a-z0-9]{2,8}$ ]] || { echo "SSUX_NAME_PREFIX must be 2-8 lowercase letters or digits"; exit 1; }
[[ -z "${SSUX_HUB_VM_SIZE:-}" || "$SSUX_HUB_VM_SIZE" =~ ^Standard_[A-Za-z0-9_]+$ ]] || { echo "Not a VM size: '$SSUX_HUB_VM_SIZE'"; exit 1; }

echo "==> Checking az and Bicep"
az bicep version >/dev/null 2>&1 || az bicep install
az account show >/dev/null 2>&1 || { echo "Run 'az login' and 'az account set --subscription <id>' first."; exit 1; }
echo "    Subscription: $(az account show --query name -o tsv)"

echo "==> Registering resource providers"
for ns in Microsoft.Compute Microsoft.Network Microsoft.KeyVault Microsoft.MarketplaceOrdering; do
  state=$(az provider show -n "$ns" --query registrationState -o tsv 2>/dev/null || echo NotRegistered)
  if [[ "$state" != "Registered" ]]; then
    echo "    $ns"
    az provider register -n "$ns" --wait >/dev/null
  fi
done

# Marketplace terms are per subscription and per plan; accepting again is harmless.
for p in $(printf '%s\n' "${PLANS[@]}" | sort -u); do
  echo "==> Accepting the Marketplace terms for $PUBLISHER/$OFFER/$p"
  if [[ "$(az vm image terms show --publisher "$PUBLISHER" --offer "$OFFER" --plan "$p" --query accepted -o tsv 2>/dev/null || echo false)" != "true" ]]; then
    az vm image terms accept --publisher "$PUBLISHER" --offer "$OFFER" --plan "$p" >/dev/null
  fi
done

if [[ -z "${SSUX_KV_READER_ID:-}" ]]; then
  SSUX_KV_READER_ID=$(az ad signed-in-user show --query id -o tsv 2>/dev/null || true)
  [[ -z "$SSUX_KV_READER_ID" ]] && { echo "Could not read the signed-in user (a service principal?). Set SSUX_KV_READER_ID."; exit 1; }
fi

# Reuse the password in Key Vault on reruns: the appliances keep the one they were created with.
if [[ -z "${SSUX_ADMIN_PASSWORD:-}" ]]; then
  kv=$(az keyvault list -g "rg-$PREFIX-stratusphere" --query "[?starts_with(name, 'kv-$PREFIX-ss-')].name | [0]" -o tsv 2>/dev/null || true)
  if [[ -n "$kv" ]]; then
    SSUX_ADMIN_PASSWORD=$(az keyvault secret show --vault-name "$kv" -n appliance-admin-password --query value -o tsv 2>/dev/null || true)
    [[ -z "$SSUX_ADMIN_PASSWORD" ]] && { echo "Can't read appliance-admin-password from $kv; you need Key Vault Secrets User on it."; exit 1; }
    echo "    Reusing the appliance password in $kv."
  else
    rand=$(head -c 48 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 24)
    SSUX_ADMIN_PASSWORD="${rand}#Aa1"
    echo "    Generated a random appliance password (stored in Key Vault as appliance-admin-password)."
  fi
fi

SSUX_LOCATION="$LOCATION"
export SSUX_LOCATION SSUX_HUB_PLAN SSUX_KV_READER_ID SSUX_ADMIN_PASSWORD SSUX_DEPLOY_DATABASE SSUX_COLLECTOR_COUNT
export SSUX_NAME_PREFIX="$PREFIX" SSUX_DATABASE_PLAN="${SSUX_DATABASE_PLAN:-}" SSUX_COLLECTOR_PLAN="${SSUX_COLLECTOR_PLAN:-}"
export SSUX_IMAGE_VERSION="${SSUX_IMAGE_VERSION:-}" SSUX_HUB_VM_SIZE="${SSUX_HUB_VM_SIZE:-}"
export SSUX_PEER_VNET_ID="${SSUX_PEER_VNET_ID:-}" SSUX_DEPLOY_BASTION="${SSUX_DEPLOY_BASTION:-true}"

name="ssux-$(date +%Y%m%d%H%M%S)"
if [[ "$WHATIF" == true ]]; then
  echo "==> What-if (nothing is deployed)"
  az deployment sub what-if -n "$name" -l "$LOCATION" -p "$PARAM_FILE"
  exit 0
fi

echo "==> Deploying (Bastion takes several minutes the first time)"
az deployment sub create -n "$name" -l "$LOCATION" -p "$PARAM_FILE" \
  --query properties.outputs -o json > /tmp/ssux-outputs.json
rg=$(jq -r .resourceGroupName.value /tmp/ssux-outputs.json)
ip=$(jq -r '.appliances.value[] | select(.role == "Hub") | .privateIp' /tmp/ssux-outputs.json)
kv=$(jq -r .keyVaultName.value /tmp/ssux-outputs.json)

echo ""
echo "Deployed in resource group $rg:"
jq -r '.appliances.value[] | "  \(.role)\t\(.name)\t\(.privateIp)"' /tmp/ssux-outputs.json
cat <<EOF

Next:
  1. Open the appliance console through Bastion (portal: VM > Connect > Bastion), or
     browse to https://$ip from a machine on a connected network.
  2. The password Azure set:
       az keyvault secret show --vault-name $kv -n appliance-admin-password --query value -o tsv
  3. Finish first-time setup in the Hub console (license, API user, API whitelist).
  4. Database or Collectors: point them at the Hub (docs/appliances.md).
  Check, fix or clean up later with: pwsh ./scripts/ops/Deploy-Stratusphere.ps1 -Action Check
EOF
