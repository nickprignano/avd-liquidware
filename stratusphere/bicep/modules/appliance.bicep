// One Stratusphere appliance (Hub, Database or Collector) from Azure Marketplace.
// A Marketplace image needs a `plan` block that matches its imageReference;
// leaving it out is the most common Marketplace deployment failure. The terms
// for the plan must be accepted in the subscription first (the deploy scripts do it).
// The private IP is static: Liquidware requires a fixed address and DNS name for
// each appliance, and the Connector ID Keys and Collectors call back to it.

@description('Role, used to name the nested deployment: hub, database, collector-1 ...')
param role string
param location string
param tags object
param name string
param vmSize string
param osDiskSizeGB int
param subnetResourceId string
param privateIp string
param imagePublisher string
param imageOffer string
param imagePlan string
param imageVersion string
param adminUsername string

@secure()
param adminPassword string

module vm 'br/public:avm/res/compute/virtual-machine:0.22.3' = {
  name: 'vm-${role}'
  params: {
    name: name
    location: location
    tags: union(tags, { 'stratusphere-role': role })
    vmSize: vmSize
    osType: 'Linux'
    // The appliance's image decides its own zone support; keep it regional.
    availabilityZone: -1
    imageReference: {
      publisher: imagePublisher
      offer: imageOffer
      sku: imagePlan
      version: imageVersion
    }
    plan: {
      name: imagePlan
      publisher: imagePublisher
      product: imageOffer
    }
    osDisk: {
      caching: 'ReadWrite'
      deleteOption: 'Delete'
      diskSizeGB: osDiskSizeGB
      managedDisk: {
        storageAccountType: 'Premium_LRS'
      }
    }
    adminUsername: adminUsername
    adminPassword: adminPassword
    disablePasswordAuthentication: false
    nicConfigurations: [
      {
        nicSuffix: '-nic'
        deleteOption: 'Delete'
        ipConfigurations: [
          {
            name: 'ipconfig1'
            subnetResourceId: subnetResourceId
            privateIPAllocationMethod: 'Static'
            privateIPAddress: privateIp
          }
        ]
      }
    ]
    bootDiagnostics: true
  }
}

output name string = vm.outputs.name
output privateIp string = privateIp
