// Lab assessment environment. Values that differ per subscription come from
// environment variables (deploy.sh sets them); set-but-empty falls back to the default.
using '../bicep/main.bicep'

param namePrefix = 'ssux'
param location = empty(readEnvironmentVariable('SSUX_LOCATION', '')) ? 'eastus2' : readEnvironmentVariable('SSUX_LOCATION', '')
param tags = {
  environment: 'lab'
}

param hubImagePlan = empty(readEnvironmentVariable('SSUX_HUB_PLAN', '')) ? 'set-SSUX_HUB_PLAN' : readEnvironmentVariable('SSUX_HUB_PLAN', '')
param hubImageVersion = empty(readEnvironmentVariable('SSUX_HUB_VERSION', '')) ? 'latest' : readEnvironmentVariable('SSUX_HUB_VERSION', '')
param hubVmSize = empty(readEnvironmentVariable('SSUX_HUB_VM_SIZE', '')) ? 'Standard_D4s_v5' : readEnvironmentVariable('SSUX_HUB_VM_SIZE', '')
param hubAdminPassword = readEnvironmentVariable('SSUX_HUB_ADMIN_PASSWORD', '')

param peerVirtualNetworkResourceId = readEnvironmentVariable('SSUX_PEER_VNET_ID', '')
param deployBastion = readEnvironmentVariable('SSUX_DEPLOY_BASTION', 'true') != 'false'

param keyVaultReaderObjectId = readEnvironmentVariable('SSUX_KV_READER_ID', '')
