// Everything in rg-<base>-liquidware for slice B2 (deploy-spec section 5): the tier VNet with its
// NSGs and NAT Gateway, the tier side of the peering, the ops runner identity, the Key Vault, the
// live config account and the packages account, each with a file or vault private endpoint whose
// zone group writes into the landing zone's privatelink zones.

param location string
param tags object
param base string
param clean string
param environment string
param uniq string
param tierAddressPrefix string
param spokeVnetId string
param spokeAddressPrefixes array
param sessionHostSubnetPrefix string
param spokePrivateEndpointSubnetPrefix string
param fileDnsZoneId string
param vaultDnsZoneId string
param usersGroupObjectId string
param avdServicePrincipalObjectIds array
param deployBastion bool

// Built-in role definition IDs: the same in every tenant.
var roles = {
  smbShareReader: 'aba4ae5f-2193-4029-9191-0cb91df5e314'
  filePrivilegedContributor: '69566ab7-960f-475b-8e7c-b3118f30c6bd'
  readerAndDataAccess: 'c12c1c16-33a1-487b-954d-41c89c60f349'
}

// 10.61.0.0/24 by default: console .0/27, endpoints .32/27, packaging .64/27, ops .96/28,
// AzureBastionSubnet .128/26.
var subnets = {
  console: cidrSubnet(tierAddressPrefix, 27, 0)
  endpoints: cidrSubnet(tierAddressPrefix, 27, 1)
  packaging: cidrSubnet(tierAddressPrefix, 27, 2)
  ops: cidrSubnet(tierAddressPrefix, 28, 6)
  bastion: cidrSubnet(tierAddressPrefix, 26, 2)
}

var vnetName = 'vnet-${base}-liquidware'
var keyVaultName = take('kv${clean}${environment}lw${uniq}', 24)
var configAccountName = take('st${clean}${environment}lwc${uniq}', 24)
var packagesAccountName = take('st${clean}${environment}lwp${uniq}', 24)

// The profiles account's SMB settings (avd-landing-zone lesson 0028: both GCM channels, or
// Entra Kerberos clients get access denied). Multichannel is Premium-only, so it is left out.
var smbHardened = {
  versions: 'SMB3.1.1'
  authenticationMethods: 'Kerberos'
  kerberosTicketEncryption: 'AES-256'
  channelEncryption: 'AES-128-GCM;AES-256-GCM'
}

// ---------- Network ----------

resource natIp 'Microsoft.Network/publicIPAddresses@2023-11-01' = {
  name: 'pip-ng-${vnetName}'
  location: location
  tags: tags
  sku: { name: 'Standard' }
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
  }
}

resource nat 'Microsoft.Network/natGateways@2023-11-01' = {
  name: 'ng-${vnetName}'
  location: location
  tags: tags
  sku: { name: 'Standard' }
  properties: {
    idleTimeoutInMinutes: 4
    publicIpAddresses: [{ id: natIp.id }]
  }
}

// The landing zone's host NSG admits everything from the VirtualNetwork tag, which includes peered
// VNets, so the tier's own NSGs deny outbound to the spoke (DN-M1). Hosts open the 443 connection
// to the console, so its return traffic still flows. The spoke's private endpoint subnet stays
// reachable for the profiles account.
var outboundToSpoke = [
  {
    name: 'Allow-Spoke-Private-Endpoints'
    properties: {
      priority: 100
      direction: 'Outbound'
      access: 'Allow'
      protocol: '*'
      sourceAddressPrefix: '*'
      sourcePortRange: '*'
      destinationAddressPrefix: spokePrivateEndpointSubnetPrefix
      destinationPortRange: '*'
    }
  }
  {
    name: 'Deny-Spoke'
    properties: {
      priority: 110
      direction: 'Outbound'
      access: 'Deny'
      protocol: '*'
      sourceAddressPrefix: '*'
      sourcePortRange: '*'
      destinationAddressPrefixes: spokeAddressPrefixes
      destinationPortRange: '*'
    }
  }
]

func rdpFromBastion(bastionPrefix string, subnetPrefix string) object => {
  name: 'Allow-Rdp-From-Bastion'
  properties: {
    priority: 110
    direction: 'Inbound'
    access: 'Allow'
    protocol: 'Tcp'
    sourceAddressPrefix: bastionPrefix
    sourcePortRange: '*'
    destinationAddressPrefix: subnetPrefix
    destinationPortRange: '3389'
  }
}

var denyOtherInbound = {
  name: 'Deny-Other-Inbound'
  properties: {
    priority: 4000
    direction: 'Inbound'
    access: 'Deny'
    protocol: '*'
    sourceAddressPrefix: '*'
    sourcePortRange: '*'
    destinationAddressPrefix: '*'
    destinationPortRange: '*'
  }
}

resource consoleNsg 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: 'nsg-${vnetName}-console'
  location: location
  tags: tags
  properties: {
    securityRules: concat(
      [
        {
          name: 'Allow-Licensing-From-Session-Hosts'
          properties: {
            priority: 100
            direction: 'Inbound'
            access: 'Allow'
            protocol: 'Tcp'
            sourceAddressPrefix: sessionHostSubnetPrefix
            sourcePortRange: '*'
            destinationAddressPrefix: subnets.console
            destinationPortRange: '443'
          }
        }
      ],
      deployBastion ? [rdpFromBastion(subnets.bastion, subnets.console)] : [],
      [denyOtherInbound],
      outboundToSpoke
    )
  }
}

resource packagingNsg 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: 'nsg-${vnetName}-packaging'
  location: location
  tags: tags
  properties: {
    securityRules: concat(
      deployBastion ? [rdpFromBastion(subnets.bastion, subnets.packaging)] : [],
      [denyOtherInbound],
      outboundToSpoke
    )
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: vnetName
  location: location
  tags: tags
  properties: {
    addressSpace: { addressPrefixes: [tierAddressPrefix] }
    subnets: concat(
      [
        {
          name: 'snet-lw-console'
          properties: {
            addressPrefix: subnets.console
            defaultOutboundAccess: false
            networkSecurityGroup: { id: consoleNsg.id }
            natGateway: { id: nat.id }
          }
        }
        {
          name: 'snet-lw-endpoints'
          properties: {
            addressPrefix: subnets.endpoints
            defaultOutboundAccess: false
            privateEndpointNetworkPolicies: 'Disabled'
          }
        }
        {
          name: 'snet-lw-packaging'
          properties: {
            addressPrefix: subnets.packaging
            defaultOutboundAccess: false
            networkSecurityGroup: { id: packagingNsg.id }
            natGateway: { id: nat.id }
          }
        }
        {
          // The on-demand ops runner (deploy-spec section 7): Cloud Shell can't reach private endpoints.
          name: 'snet-lw-ops'
          properties: {
            addressPrefix: subnets.ops
            defaultOutboundAccess: false
            natGateway: { id: nat.id }
            delegations: [
              {
                name: 'aci'
                properties: { serviceName: 'Microsoft.ContainerInstance/containerGroups' }
              }
            ]
          }
        }
      ],
      deployBastion
        ? [
            {
              name: 'AzureBastionSubnet'
              properties: { addressPrefix: subnets.bastion }
            }
          ]
        : []
    )
  }
}

resource toSpoke 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-11-01' = {
  parent: vnet
  name: 'peer-${base}-liquidware-to-spoke'
  properties: {
    remoteVirtualNetwork: { id: spokeVnetId }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: false
    allowGatewayTransit: false
    useRemoteGateways: false
  }
}

// ---------- Identity ----------

// Used only by the on-demand container that promotes configuration (deploy-spec section 7).
resource opsIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'id-${base}-lw-ops'
  location: location
  tags: tags
}

// ---------- Key Vault ----------

// Holds the console password and the ProfileUnity license string, both written through the
// management plane; the roles that read them come with the console in slice B3.
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: {
    tenantId: tenant().tenantId
    sku: { family: 'A', name: 'standard' }
    enableRbacAuthorization: true
    enablePurgeProtection: true
    softDeleteRetentionInDays: 7
    publicNetworkAccess: 'Disabled'
    networkAcls: { bypass: 'None', defaultAction: 'Deny' }
  }
}

// ---------- Live config account ----------

resource configAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: configAccountName
  location: location
  tags: union(tags, { 'liquidware-role': 'config' })
  kind: 'StorageV2'
  sku: { name: 'Standard_LRS' }
  properties: {
    allowSharedKeyAccess: false
    allowBlobPublicAccess: false
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    publicNetworkAccess: 'Disabled'
    networkAcls: { bypass: 'None', defaultAction: 'Deny' }
    azureFilesIdentityBasedAuthentication: {
      directoryServiceOptions: 'AADKERB'
      defaultSharePermission: 'None'
    }
  }
}

resource configFiles 'Microsoft.Storage/storageAccounts/fileServices@2023-05-01' = {
  parent: configAccount
  name: 'default'
  properties: {
    protocolSettings: { smb: smbHardened }
  }
}

resource configShare 'Microsoft.Storage/storageAccounts/fileServices/shares@2023-05-01' = {
  parent: configFiles
  name: 'lwconfig'
  properties: {
    shareQuota: 5
    enabledProtocols: 'SMB'
  }
}

// Users read the INI their logon applies and can't change it (tier N-C1).
resource configUsersRead 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(configAccount.id, usersGroupObjectId, roles.smbShareReader)
  scope: configAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.smbShareReader)
    principalId: usersGroupObjectId
    principalType: 'Group'
  }
}

// The only writer: the ops runner, after the promote checks (deploy-spec section 7).
resource configOpsWrite 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(configAccount.id, opsIdentity.id, roles.filePrivilegedContributor)
  scope: configAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.filePrivilegedContributor)
    principalId: opsIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// ---------- Packages account ----------

// Tier spec section 5.1: the one account with shared key on, for app attach images only.
resource packagesAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: packagesAccountName
  location: location
  tags: union(tags, { 'liquidware-role': 'packages' })
  kind: 'StorageV2'
  sku: { name: 'Standard_LRS' }
  properties: {
    allowSharedKeyAccess: true
    allowBlobPublicAccess: false
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    publicNetworkAccess: 'Disabled'
    networkAcls: { bypass: 'None', defaultAction: 'Deny' }
  }
}

resource packagesFiles 'Microsoft.Storage/storageAccounts/fileServices@2023-05-01' = {
  parent: packagesAccount
  name: 'default'
  properties: {
    // Key-based mounts authenticate with NTLMv2.
    protocolSettings: { smb: union(smbHardened, { authenticationMethods: 'NTLMv2;Kerberos' }) }
  }
}

resource packagesShare 'Microsoft.Storage/storageAccounts/fileServices/shares@2023-05-01' = {
  parent: packagesFiles
  name: 'appattach'
  properties: {
    shareQuota: 100
    enabledProtocols: 'SMB'
  }
}

resource packagesAvdRead 'Microsoft.Authorization/roleAssignments@2022-04-01' = [
  for sp in avdServicePrincipalObjectIds: {
    name: guid(packagesAccount.id, sp, roles.readerAndDataAccess)
    scope: packagesAccount
    properties: {
      roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.readerAndDataAccess)
      principalId: sp
      principalType: 'ServicePrincipal'
    }
  }
]

// ---------- Private endpoints ----------

// Their zone groups write A records into the landing zone's zones (deploy-spec section 4, D-M4).
var endpoints = [
  { name: 'pe-${keyVaultName}', target: keyVault.id, groupId: 'vault', zoneId: vaultDnsZoneId }
  { name: 'pe-${configAccountName}-file', target: configAccount.id, groupId: 'file', zoneId: fileDnsZoneId }
  { name: 'pe-${packagesAccountName}-file', target: packagesAccount.id, groupId: 'file', zoneId: fileDnsZoneId }
]

module privateEndpoints 'privateEndpoint.bicep' = [
  for e in endpoints: {
    name: e.name
    params: {
      name: e.name
      location: location
      tags: tags
      subnetId: '${vnet.id}/subnets/snet-lw-endpoints'
      privateLinkServiceId: e.target
      groupId: e.groupId
      privateDnsZoneId: e.zoneId
    }
  }
]

output vnetId string = vnet.id
output keyVaultName string = keyVault.name
output configAccountName string = configAccount.name
output packagesAccountName string = packagesAccount.name
output opsIdentityId string = opsIdentity.id
