// Assessment VNet: one subnet for the Stratusphere appliances, an optional
// AzureBastionSubnet, and an optional two-way peering to the network the
// endpoints live in. The Hub NSG admits only what Stratusphere needs:
// TCP 443 (Connector ID Key callbacks and the web console) and TCP 22 from Bastion.
// Egress is explicit, as in avd-landing-zone: the subnet has default outbound
// access off (Azure is retiring it) and leaves through a NAT Gateway.

param location string
param tags object
param vnetName string
param addressPrefix string
param hubSubnetPrefix string
param bastionSubnetPrefix string
param callbackSourcePrefixes array
param peerVirtualNetworkResourceId string
param deployBastion bool
param bastionName string

var peer = !empty(peerVirtualNetworkResourceId)

module natGateway 'br/public:avm/res/network/nat-gateway:2.1.1' = {
  name: 'nat-gateway'
  params: {
    name: 'ng-${vnetName}'
    location: location
    tags: tags
    availabilityZone: -1
    publicIPAddresses: [
      {
        name: 'pip-ng-${vnetName}'
        // The module defaults this IP to zones 1-3, which fails in regions without
        // availability zones (avd-landing-zone lesson 0001). The appliance is regional.
        availabilityZones: []
      }
    ]
  }
}

module hubNsg 'br/public:avm/res/network/network-security-group:0.5.3' = {
  name: 'nsg-hub'
  params: {
    name: 'nsg-${vnetName}-hub'
    location: location
    tags: tags
    securityRules: concat(
      [
        {
          name: 'Allow-Https-Callbacks-And-Console'
          properties: {
            priority: 100
            direction: 'Inbound'
            access: 'Allow'
            protocol: 'Tcp'
            sourceAddressPrefixes: callbackSourcePrefixes
            sourcePortRange: '*'
            destinationAddressPrefix: hubSubnetPrefix
            destinationPortRange: '443'
          }
        }
      ],
      deployBastion
        ? [
            {
              name: 'Allow-Ssh-From-Bastion'
              properties: {
                priority: 110
                direction: 'Inbound'
                access: 'Allow'
                protocol: 'Tcp'
                sourceAddressPrefix: bastionSubnetPrefix
                sourcePortRange: '*'
                destinationAddressPrefix: hubSubnetPrefix
                destinationPortRange: '22'
              }
            }
          ]
        : [],
      [
        {
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
      ]
    )
  }
}

module vnet 'br/public:avm/res/network/virtual-network:0.10.2' = {
  name: 'vnet'
  params: {
    name: vnetName
    location: location
    tags: tags
    addressPrefixes: [
      addressPrefix
    ]
    subnets: concat(
      [
        {
          name: 'snet-stratusphere'
          addressPrefix: hubSubnetPrefix
          networkSecurityGroupResourceId: hubNsg.outputs.resourceId
          defaultOutboundAccess: false
          natGatewayResourceId: natGateway.outputs.resourceId
        }
      ],
      deployBastion
        ? [
            {
              name: 'AzureBastionSubnet'
              addressPrefix: bastionSubnetPrefix
            }
          ]
        : []
    )
    peerings: peer
      ? [
          {
            remoteVirtualNetworkResourceId: peerVirtualNetworkResourceId
            allowForwardedTraffic: true
            allowVirtualNetworkAccess: true
            useRemoteGateways: false
            remotePeeringEnabled: true
            remotePeeringAllowForwardedTraffic: true
            remotePeeringAllowVirtualNetworkAccess: true
          }
        ]
      : []
  }
}

module bastion 'br/public:avm/res/network/bastion-host:0.8.2' = if (deployBastion) {
  name: 'bastion'
  params: {
    name: bastionName
    location: location
    tags: tags
    virtualNetworkResourceId: vnet.outputs.resourceId
    skuName: 'Basic'
  }
}

output vnetResourceId string = vnet.outputs.resourceId
output hubSubnetResourceId string = vnet.outputs.subnetResourceIds[0]
