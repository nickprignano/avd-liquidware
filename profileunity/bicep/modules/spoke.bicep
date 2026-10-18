// Writes to the landing zone network resource group, and only these (deploy-spec section 4):
// the spoke side of the peering and the links from the landing zone's privatelink zones to the
// tier VNet. All are child resources, so a landing zone redeploy leaves them alone, and Cleanup
// removes them.

param base string
param spokeVnetName string
param tierVnetId string
param fileDnsZoneName string
param vaultDnsZoneName string

resource spokeVnet 'Microsoft.Network/virtualNetworks@2023-11-01' existing = {
  name: spokeVnetName
}

resource fileZone 'Microsoft.Network/privateDnsZones@2024-06-01' existing = {
  name: fileDnsZoneName
}

resource vaultZone 'Microsoft.Network/privateDnsZones@2024-06-01' existing = {
  name: vaultDnsZoneName
}

// Hosts reach the console (443, licensing) and the tier's private endpoints. No forwarded or
// gateway traffic: the tier is a leaf of the spoke.
resource toTier 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-11-01' = {
  parent: spokeVnet
  name: 'peer-${base}-to-liquidware'
  properties: {
    remoteVirtualNetwork: { id: tierVnetId }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: false
    allowGatewayTransit: false
    useRemoteGateways: false
  }
}

resource fileLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: fileZone
  name: 'link-${base}-liquidware'
  location: 'global'
  properties: {
    virtualNetwork: { id: tierVnetId }
    registrationEnabled: false
  }
}

resource vaultLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: vaultZone
  name: 'link-${base}-liquidware'
  location: 'global'
  properties: {
    virtualNetwork: { id: tierVnetId }
    registrationEnabled: false
  }
}
