#!/usr/bin/env bash
# Deploy the Stratusphere UX assessment environment at subscription scope.
# Personal project, not for production use. Provided as is, without warranty of any kind (MIT License, see LICENSE). Not affiliated with the author's employer, with Liquidware or with Microsoft.
#
# Usage:
#   ./scripts/deploy/deploy.sh -p parameters/lab.bicepparam -l eastus2 --plan <marketplace-plan> \
#       [--version <image-version>] [--vm-size Standard_D4s_v5] \
#       [--peer-vnet <vnet-resource-id>] [--no-bastion] [--what-if]
#
# --plan is the Marketplace plan (SKU) of the Stratusphere Hub image. The preflight
# lists the plans offered in a region:
#   pwsh ./scripts/ops/Test-StratusphereReadiness.ps1 -Location eastus2
#
# Environment variables (any flag above overrides):
#   SSUX_HUB_PLAN, SSUX_HUB_VERSION, SSUX_HUB_VM_SIZE, SSUX_PEER_VNET_ID
#   SSUX_HUB_ADMIN_PASSWORD   appliance password Azure sets (random if unset, stored in Key Vault)
#   SSUX_KV_READER_ID         object ID allowed to read it (the signed-in user if unset)
set -euo pipefail

PARAM_FILE=""
LOCATION=""
WHATIF=false
PUBLISHER="liquidware"
OFFER="stratusphere"

usage() {
  sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -p) PARAM_FILE="$2"; shift 2 ;;
    -l) LOCATION="$2"; shift 2 ;;
    --plan) SSUX_HUB_PLAN="$2"; shift 2 ;;
    --version) SSUX_HUB_VERSION="$2"; shift 2 ;;
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
[[ "$SSUX_HUB_PLAN" =~ ^[A-Za-z0-9._-]+$ ]] || { echo "Not a Marketplace plan name: '$SSUX_HUB_PLAN'"; exit 1; }
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
echo "==> Accepting the Marketplace terms for $PUBLISHER/$OFFER/$SSUX_HUB_PLAN"
if [[ "$(az vm image terms show --publisher "$PUBLISHER" --offer "$OFFER" --plan "$SSUX_HUB_PLAN" --query accepted -o tsv 2>/dev/null || echo false)" != "true" ]]; then
  az vm image terms accept --publisher "$PUBLISHER" --offer "$OFFER" --plan "$SSUX_HUB_PLAN" >/dev/null
fi

if [[ -z "${SSUX_KV_READER_ID:-}" ]]; then
  SSUX_KV_READER_ID=$(az ad signed-in-user show --query id -o tsv 2>/dev/null || true)
  [[ -z "$SSUX_KV_READER_ID" ]] && { echo "Could not read the signed-in user (a service principal?). Set SSUX_KV_READER_ID."; exit 1; }
fi

if [[ -z "${SSUX_HUB_ADMIN_PASSWORD:-}" ]]; then
  rand=$(head -c 48 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 24)
  SSUX_HUB_ADMIN_PASSWORD="${rand}#Aa1"
  echo "    Generated a random appliance password (stored in Key Vault as hub-admin-password)."
fi

SSUX_LOCATION="$LOCATION"
export SSUX_LOCATION SSUX_HUB_PLAN SSUX_KV_READER_ID SSUX_HUB_ADMIN_PASSWORD
export SSUX_HUB_VERSION="${SSUX_HUB_VERSION:-}" SSUX_HUB_VM_SIZE="${SSUX_HUB_VM_SIZE:-}"
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
ip=$(jq -r .hubPrivateIp.value /tmp/ssux-outputs.json)
kv=$(jq -r .keyVaultName.value /tmp/ssux-outputs.json)

cat <<EOF

Deployed. Hub appliance: $ip in resource group $rg.

Next:
  1. Open the appliance console through Bastion (portal: VM > Connect > Bastion), or
     browse to https://$ip from a machine on a connected network.
  2. The password Azure set:
       az keyvault secret show --vault-name $kv -n hub-admin-password --query value -o tsv
  3. Finish first-time setup in the Hub console (license, API user, API whitelist).
EOF
