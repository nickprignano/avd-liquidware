// Lab assessment environment. Values that differ per subscription come from
// environment variables (Deploy-Stratusphere.ps1 and deploy.sh set them); set-but-empty falls back to the default.
using '../bicep/main.bicep'

param namePrefix = empty(readEnvironmentVariable('SSUX_NAME_PREFIX', '')) ? 'ssux' : readEnvironmentVariable('SSUX_NAME_PREFIX', '')
param location = empty(readEnvironmentVariable('SSUX_LOCATION', '')) ? 'eastus2' : readEnvironmentVariable('SSUX_LOCATION', '')
param tags = {
  environment: 'lab'
}

param imageVersion = empty(readEnvironmentVariable('SSUX_IMAGE_VERSION', '')) ? 'latest' : readEnvironmentVariable('SSUX_IMAGE_VERSION', '')
param adminPassword = readEnvironmentVariable('SSUX_ADMIN_PASSWORD', '')

param deployHub = readEnvironmentVariable('SSUX_DEPLOY_HUB', 'true') != 'false'
param hubImagePlan = empty(readEnvironmentVariable('SSUX_HUB_PLAN', '')) ? 'set-SSUX_HUB_PLAN' : readEnvironmentVariable('SSUX_HUB_PLAN', '')
param hubVmSize = empty(readEnvironmentVariable('SSUX_HUB_VM_SIZE', '')) ? 'Standard_D4s_v5' : readEnvironmentVariable('SSUX_HUB_VM_SIZE', '')

param deployDatabase = readEnvironmentVariable('SSUX_DEPLOY_DATABASE', 'false') == 'true'
param databaseImagePlan = readEnvironmentVariable('SSUX_DATABASE_PLAN', '')

param collectorCount = empty(readEnvironmentVariable('SSUX_COLLECTOR_COUNT', '')) ? 0 : int(readEnvironmentVariable('SSUX_COLLECTOR_COUNT', '0'))
param collectorImagePlan = readEnvironmentVariable('SSUX_COLLECTOR_PLAN', '')

param peerVirtualNetworkResourceId = readEnvironmentVariable('SSUX_PEER_VNET_ID', '')
param deployBastion = readEnvironmentVariable('SSUX_DEPLOY_BASTION', 'true') != 'false'

param keyVaultReaderObjectId = readEnvironmentVariable('SSUX_KV_READER_ID', '')
