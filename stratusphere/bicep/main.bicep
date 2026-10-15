// =====================================================================
// AVD readiness with Stratusphere UX — assessment environment
// Personal project, not for production use. Provided as is, without warranty of any kind (MIT License, see LICENSE). Not affiliated with the author's employer, with Liquidware or with Microsoft.
//
// One resource group per assessment: a small VNet (optionally peered to the
// network the endpoints live in), Key Vault for the appliance credential, an
// optional Azure Bastion for the console, and the Stratusphere Hub appliance
// from Azure Marketplace. Bring your own Stratusphere license.
//
// The Marketplace terms are accepted by scripts/deploy/deploy.sh (or the
// preflight's -Fix) before this template runs; see docs/marketplace.md.
// =====================================================================

targetScope = 'subscription'

metadata name = 'Stratusphere UX assessment environment'
metadata description = 'Stratusphere UX Hub appliance in Azure for AVD readiness assessments.'

// ---------- Core ----------
@description('Short prefix (lowercase letters/digits, 2-8 chars). Resource names derive from this.')
@minLength(2)
@maxLength(8)
param namePrefix string

@description('Azure region for all resources.')
param location string = deployment().location

@description('Extra tags merged onto the resource group and every resource.')
param tags object = {}

// ---------- Hub appliance image (Azure Marketplace) ----------
@description('Marketplace publisher of the Stratusphere Hub image.')
param hubImagePublisher string = 'liquidware'

@description('Marketplace offer of the Stratusphere Hub image.')
param hubImageOffer string = 'stratusphere'

@description('Marketplace plan (SKU). List the ones available in your region with the preflight or `az vm image list-skus -l <region> -p liquidware -f stratusphere`.')
@minLength(1)
param hubImagePlan string

@description('Image version, or latest.')
param hubImageVersion string = 'latest'

// ---------- Hub VM ----------
@description('Hub VM size. Liquidware lists 4 vCPU and 16 GB as the Hub minimum.')
param hubVmSize string = 'Standard_D4s_v5'

@description('OS disk size in GB for the Hub. Liquidware lists 60 GB as the minimum; the database grows with endpoints and retention.')
@minValue(64)
param hubOsDiskSizeGB int = 128

@description('Local administrator name Azure sets on the appliance.')
param hubAdminUsername string = 'ssadmin-azure'

@description('Local administrator password Azure sets on the appliance. deploy.sh generates one and it is stored in Key Vault.')
@secure()
param hubAdminPassword string

// ---------- Network ----------
@description('Address space of the assessment VNet.')
param addressPrefix string = '10.60.0.0/24'

@description('Subnet for the Hub (and later the Database appliance and Collectors).')
param hubSubnetPrefix string = '10.60.0.0/26'

@description('AzureBastionSubnet prefix (/26 or larger). Used only when deployBastion is true.')
param bastionSubnetPrefix string = '10.60.0.64/26'

@description('Static private IP of the Hub, inside hubSubnetPrefix (Azure reserves the first four addresses).')
param hubPrivateIp string = '10.60.0.4'

@description('Source prefixes allowed to reach the Hub on TCP 443: the endpoints running the Connector ID Key and the admins using the web console.')
param callbackSourcePrefixes array = [
  'VirtualNetwork'
]

@description('Optional VNet to peer with both ways (for example the avd-landing-zone spoke whose session hosts will run the Connector ID Key). Empty for none.')
param peerVirtualNetworkResourceId string = ''

@description('Deploy Azure Bastion (Basic) for the appliance console.')
param deployBastion bool = true

// ---------- Access ----------
@description('Object ID of the user or group allowed to read the appliance credential from Key Vault (deploy.sh passes the signed-in user).')
param keyVaultReaderObjectId string

@description('Principal type of keyVaultReaderObjectId.')
@allowed([
  'User'
  'Group'
  'ServicePrincipal'
])
param keyVaultReaderPrincipalType string = 'User'

// ---------- Naming ----------
var suffix = substring(uniqueString(subscription().subscriptionId, namePrefix, location), 0, 5)
var rgName = 'rg-${namePrefix}-stratusphere'
var allTags = union(
  {
    workload: 'stratusphere-assessment'
    'managed-by': 'avd-readiness-stratusphere'
  },
  tags
)

resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: rgName
  location: location
  tags: allTags
}

module network 'modules/network.bicep' = {
  name: '${namePrefix}-network'
  scope: rg
  params: {
    location: location
    tags: allTags
    vnetName: 'vnet-${namePrefix}-stratusphere'
    addressPrefix: addressPrefix
    hubSubnetPrefix: hubSubnetPrefix
    bastionSubnetPrefix: bastionSubnetPrefix
    callbackSourcePrefixes: callbackSourcePrefixes
    peerVirtualNetworkResourceId: peerVirtualNetworkResourceId
    deployBastion: deployBastion
    bastionName: 'bas-${namePrefix}-stratusphere'
  }
}

module keyVault 'modules/keyVault.bicep' = {
  name: '${namePrefix}-keyvault'
  scope: rg
  params: {
    location: location
    tags: allTags
    name: 'kv-${namePrefix}-ss-${suffix}'
    readerObjectId: keyVaultReaderObjectId
    readerPrincipalType: keyVaultReaderPrincipalType
    hubAdminUsername: hubAdminUsername
    hubAdminPassword: hubAdminPassword
  }
}

module hub 'modules/hub.bicep' = {
  name: '${namePrefix}-hub'
  scope: rg
  params: {
    location: location
    tags: allTags
    name: 'vm-${namePrefix}-hub'
    vmSize: hubVmSize
    osDiskSizeGB: hubOsDiskSizeGB
    subnetResourceId: network.outputs.hubSubnetResourceId
    privateIp: hubPrivateIp
    imagePublisher: hubImagePublisher
    imageOffer: hubImageOffer
    imagePlan: hubImagePlan
    imageVersion: hubImageVersion
    adminUsername: hubAdminUsername
    adminPassword: hubAdminPassword
  }
}

output resourceGroupName string = rg.name
output hubVmName string = hub.outputs.name
output hubPrivateIp string = hub.outputs.privateIp
output keyVaultName string = keyVault.outputs.name
output vnetResourceId string = network.outputs.vnetResourceId
