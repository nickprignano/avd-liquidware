// One private endpoint in snet-lw-endpoints and its zone group, which writes the A record into the
// landing zone's privatelink zone (deploy-spec section 4, D-M4).

param name string
param location string
param tags object
param subnetId string
param privateLinkServiceId string
param groupId string
param privateDnsZoneId string

resource endpoint 'Microsoft.Network/privateEndpoints@2023-11-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    subnet: { id: subnetId }
    privateLinkServiceConnections: [
      {
        name: name
        properties: {
          privateLinkServiceId: privateLinkServiceId
          groupIds: [groupId]
        }
      }
    ]
  }
}

resource zoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-11-01' = {
  parent: endpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: groupId
        properties: { privateDnsZoneId: privateDnsZoneId }
      }
    ]
  }
}
