// The Liquidware tier's network and storage against an existing avd-landing-zone landing zone
// (docs/deploy-spec.md sections 4 and 5, slice B2). Deploy-LiquidwareTier.ps1 discovers the
// landing zone and passes what it found; nothing here reads the landing zone by itself.
// Personal project, not for production use. Provided as is, without warranty of any kind. Not affiliated with the author's employer, with Liquidware or with Microsoft.
//
// Native resources rather than Azure Verified Modules: the template tests check every role
// assignment's scope and principal in the compiled template, which module wrappers hide.
// The console VM, the media account and the packaging VM come in slice B3.

targetScope = 'subscription'

@description('Region of the landing zone (Deploy-LiquidwareTier.ps1 passes the spoke VNet location).')
param location string

@description('The landing zone prefix (2-8 lowercase letters, digits or hyphens).')
@minLength(2)
@maxLength(8)
param namePrefix string

@allowed(['dev', 'test', 'prod'])
param environment string

@description('The tier VNet. /24 or larger; must not overlap the spoke, its peers or the Stratusphere VNet.')
param tierAddressPrefix string = '10.61.0.0/24'

@description('Resource ID of the landing zone spoke VNet (vnet-<base>).')
param spokeVnetId string

@description('The spoke address space. The tier NSGs deny outbound to it.')
param spokeAddressPrefixes array

@description('Prefix of snet-session-hosts: the only source allowed to reach the console (443, licensing).')
param sessionHostSubnetPrefix string

@description('Prefix of the spoke private endpoint subnet: the one part of the spoke the tier may reach (the profiles account).')
param spokePrivateEndpointSubnetPrefix string

@description('Resource ID of the landing zone privatelink.file zone (Standalone mode).')
param fileDnsZoneId string

@description('Resource ID of the landing zone privatelink.vaultcore zone (Standalone mode).')
param vaultDnsZoneId string

@description('Object ID of the landing zone users group (the group with SMB Share Contributor on the profiles account).')
param usersGroupObjectId string

@description('Object IDs of the Azure Virtual Desktop and Azure Virtual Desktop ARM Provider service principals in this tenant.')
param avdServicePrincipalObjectIds array

@description('Add AzureBastionSubnet and allow 3389 from it to the console and packaging subnets.')
param deployBastion bool = false

param tags object = {}

var clean = replace(toLower(namePrefix), '-', '')
var base = '${clean}-${environment}'
var uniq = take(uniqueString(subscription().id, base, 'liquidware'), 5)
var allTags = union(tags, { workload: 'liquidware', 'landing-zone': base })
var spokeParts = split(spokeVnetId, '/')
var spokeResourceGroup = spokeParts[4]
var spokeVnetName = spokeParts[8]

resource tierGroup 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: 'rg-${base}-liquidware'
  location: location
  tags: allTags
}

module tier 'modules/tier.bicep' = {
  name: 'liquidware-tier'
  scope: tierGroup
  params: {
    location: location
    tags: allTags
    base: base
    clean: clean
    environment: environment
    uniq: uniq
    tierAddressPrefix: tierAddressPrefix
    spokeVnetId: spokeVnetId
    spokeAddressPrefixes: spokeAddressPrefixes
    sessionHostSubnetPrefix: sessionHostSubnetPrefix
    spokePrivateEndpointSubnetPrefix: spokePrivateEndpointSubnetPrefix
    fileDnsZoneId: fileDnsZoneId
    vaultDnsZoneId: vaultDnsZoneId
    usersGroupObjectId: usersGroupObjectId
    avdServicePrincipalObjectIds: avdServicePrincipalObjectIds
    deployBastion: deployBastion
  }
}

// The only writes to landing zone resources in this slice: child resources, each removed by Cleanup
// (deploy-spec section 4).
module spoke 'modules/spoke.bicep' = {
  name: 'liquidware-spoke'
  scope: resourceGroup(spokeResourceGroup)
  params: {
    base: base
    spokeVnetName: spokeVnetName
    tierVnetId: tier.outputs.vnetId
    fileDnsZoneName: last(split(fileDnsZoneId, '/'))
    vaultDnsZoneName: last(split(vaultDnsZoneId, '/'))
  }
}

output resourceGroupName string = tierGroup.name
output vnetId string = tier.outputs.vnetId
output keyVaultName string = tier.outputs.keyVaultName
output configAccountName string = tier.outputs.configAccountName
output packagesAccountName string = tier.outputs.packagesAccountName
output opsIdentityId string = tier.outputs.opsIdentityId
