// =====================================================================
// AVD readiness with Stratusphere UX — assessment environment
// Personal project, not for production use. Provided as is, without warranty of any kind. Not affiliated with the author's employer, with Liquidware or with Microsoft.
//
// One resource group per assessment: a small VNet (optionally peered to the
// network the endpoints live in), Key Vault for the appliance credential, an
// optional Azure Bastion for the console, and the Stratusphere Hub appliance
// from Azure Marketplace. Bring your own Stratusphere license.
//
// The Marketplace terms are accepted by scripts/ops/Deploy-Stratusphere.ps1,
// scripts/deploy/deploy.sh or the preflight's -Fix before this template runs;
// see docs/marketplace.md and docs/appliances.md.
// =====================================================================

targetScope = 'subscription'

metadata name = 'Stratusphere UX assessment environment'
metadata description = 'Stratusphere UX appliances (Hub, Database, Collectors) in Azure for AVD readiness assessments.'

// ---------- Core ----------
@description('Short prefix (lowercase letters/digits, 2-8 chars). Resource names derive from this.')
@minLength(2)
@maxLength(8)
param namePrefix string

@description('Azure region for all resources.')
param location string = deployment().location

@description('Extra tags merged onto the resource group and every resource.')
param tags object = {}

// ---------- Appliance images (Azure Marketplace) ----------
@description('Marketplace publisher of the Stratusphere images.')
param imagePublisher string = 'liquidware'

@description('Marketplace offer of the Stratusphere images.')
param imageOffer string = 'stratusphere'

@description('Image version for every appliance, or latest.')
param imageVersion string = 'latest'

// ---------- Hub ----------
@description('Deploy the Hub. Turned off only to change other roles without touching it.')
param deployHub bool = true

@description('Marketplace plan (SKU) of the Hub. The preflight lists the plans offered in your region.')
@minLength(1)
param hubImagePlan string

@description('Hub VM size. Liquidware lists 4 vCPU and 16 GB as the Hub minimum.')
param hubVmSize string = 'Standard_D4s_v5'

@description('OS disk size in GB for the Hub. Liquidware lists 60 GB as the minimum; the database grows with endpoints and retention.')
@minValue(64)
param hubOsDiskSizeGB int = 128

@description('Static private IP of the Hub, inside hubSubnetPrefix (Azure reserves the first four addresses).')
param hubPrivateIp string = '10.60.0.4'

// ---------- Database (optional) ----------
@description('Deploy the Database appliance. Liquidware advises one above 1,000 Connector ID Keys.')
param deployDatabase bool = false

@description('Marketplace plan (SKU) of the Database appliance. Required when deployDatabase is true.')
param databaseImagePlan string = ''

@description('Database VM size. Liquidware lists 4 vCPU and 16 GB as the minimum.')
param databaseVmSize string = 'Standard_D4s_v5'

@description('OS disk size in GB for the Database appliance.')
@minValue(64)
param databaseOsDiskSizeGB int = 256

@description('Static private IP of the Database appliance.')
param databasePrivateIp string = '10.60.0.5'

// ---------- Collectors (optional) ----------
@description('Number of Collector appliances (0 for none).')
@minValue(0)
@maxValue(4)
param collectorCount int = 0

@description('Marketplace plan (SKU) of the Collector appliance. Required when collectorCount is above 0.')
param collectorImagePlan string = ''

@description('Collector VM size. Liquidware lists 2 vCPU and 8 GB as the minimum.')
param collectorVmSize string = 'Standard_D2s_v5'

@description('OS disk size in GB for each Collector.')
@minValue(32)
param collectorOsDiskSizeGB int = 64

@description('Static private IPs of the Collectors, in order. Needs at least collectorCount entries.')
param collectorPrivateIps array = [
  '10.60.0.10'
  '10.60.0.11'
  '10.60.0.12'
  '10.60.0.13'
]

// ---------- Appliance credential ----------
@description('Local administrator name Azure sets on every appliance.')
param adminUsername string = 'ssadmin-azure'

@description('Local administrator password Azure sets on every appliance. The deploy scripts generate one, store it in Key Vault and reuse it on later runs.')
@secure()
param adminPassword string

// ---------- Network ----------
@description('Address space of the assessment VNet.')
param addressPrefix string = '10.60.0.0/24'

@description('Subnet for the appliances: Hub, Database and Collectors.')
param hubSubnetPrefix string = '10.60.0.0/26'

@description('AzureBastionSubnet prefix (/26 or larger). Used only when deployBastion is true.')
param bastionSubnetPrefix string = '10.60.0.64/26'

@description('Source prefixes allowed to reach the Hub on TCP 443: the endpoints running the Connector ID Key and the admins using the web console.')
param callbackSourcePrefixes array = [
  'VirtualNetwork'
]

@description('Optional VNet to peer with both ways (for example the avd-landing-zone spoke whose session hosts will run the Connector ID Key). Empty for none.')
param peerVirtualNetworkResourceId string = ''

@description('Deploy Azure Bastion (Basic) for the appliance console.')
param deployBastion bool = true

// ---------- Access ----------
@description('Object ID of the user or group allowed to read the appliance credential from Key Vault (the deploy scripts pass the signed-in user).')
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
    'managed-by': 'avd-liquidware'
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
    // Collectors write to the database: on the Database appliance, or on the Hub without one.
    allowPostgres: deployDatabase || collectorCount > 0
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
    adminUsername: adminUsername
    adminPassword: adminPassword
  }
}

module hub 'modules/appliance.bicep' = if (deployHub) {
  name: '${namePrefix}-hub'
  scope: rg
  params: {
    role: 'hub'
    name: 'vm-${namePrefix}-hub'
    vmSize: hubVmSize
    osDiskSizeGB: hubOsDiskSizeGB
    privateIp: hubPrivateIp
    imagePlan: hubImagePlan
    location: location
    tags: allTags
    subnetResourceId: network.outputs.hubSubnetResourceId
    imagePublisher: imagePublisher
    imageOffer: imageOffer
    imageVersion: imageVersion
    adminUsername: adminUsername
    adminPassword: adminPassword
  }
}

module database 'modules/appliance.bicep' = if (deployDatabase) {
  name: '${namePrefix}-database'
  scope: rg
  params: {
    role: 'database'
    name: 'vm-${namePrefix}-db'
    vmSize: databaseVmSize
    osDiskSizeGB: databaseOsDiskSizeGB
    privateIp: databasePrivateIp
    imagePlan: databaseImagePlan
    location: location
    tags: allTags
    subnetResourceId: network.outputs.hubSubnetResourceId
    imagePublisher: imagePublisher
    imageOffer: imageOffer
    imageVersion: imageVersion
    adminUsername: adminUsername
    adminPassword: adminPassword
  }
}

module collectors 'modules/appliance.bicep' = [
  for i in range(0, collectorCount): {
    name: '${namePrefix}-collector-${i + 1}'
    scope: rg
    params: {
      role: 'collector-${i + 1}'
      name: 'vm-${namePrefix}-col${i + 1}'
      vmSize: collectorVmSize
      osDiskSizeGB: collectorOsDiskSizeGB
      privateIp: collectorPrivateIps[i]
      imagePlan: collectorImagePlan
      location: location
      tags: allTags
      subnetResourceId: network.outputs.hubSubnetResourceId
      imagePublisher: imagePublisher
      imageOffer: imageOffer
      imageVersion: imageVersion
      adminUsername: adminUsername
      adminPassword: adminPassword
    }
  }
]

var collectorRows = [
  for i in range(0, collectorCount): { role: 'Collector', name: 'vm-${namePrefix}-col${i + 1}', privateIp: collectorPrivateIps[i] }
]

output resourceGroupName string = rg.name
output keyVaultName string = keyVault.outputs.name
output vnetResourceId string = network.outputs.vnetResourceId
output appliances array = concat(
  deployHub ? [{ role: 'Hub', name: 'vm-${namePrefix}-hub', privateIp: hubPrivateIp }] : [],
  deployDatabase ? [{ role: 'Database', name: 'vm-${namePrefix}-db', privateIp: databasePrivateIp }] : [],
  collectorRows
)
