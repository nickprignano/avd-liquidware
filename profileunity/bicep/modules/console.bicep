// The ProfileUnity console VM (deploy-spec section 5): Windows Server 2025 Azure Edition, Trusted
// Launch, encryption at host, no public IP, a static private IP that hosts name for licensing
// (DN-M2). Its local admin password is written to the tier's Key Vault through the management
// plane here, in the same deployment that creates the VM (DN-C1). Deployed only when the VM
// doesn't exist yet: an existing VM keeps the password it was created with (lesson 0002).

param location string
param tags object
param environment string
param vmName string
param computerName string
param subnetId string
param privateIp string
param keyVaultName string

@description('Generated in memory by Deploy-LiquidwareTier.ps1 for this deployment only.')
@secure()
param adminPassword string

param adminUsername string = 'lwadmin'

param vmSize string = 'Standard_D2as_v5'

@description('Daily shutdown in dev and test, HHmm, because the landing zone budget Lock stops only session hosts (D-H6).')
param autoShutdownTime string = '1900'
param autoShutdownTimeZone string = 'UTC'

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}

resource adminSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'lw-console-password'
  properties: {
    value: adminPassword
    contentType: 'Local administrator ${adminUsername} on ${vmName}'
  }
}

resource nic 'Microsoft.Network/networkInterfaces@2023-11-01' = {
  name: 'nic-${vmName}'
  location: location
  tags: tags
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: { id: subnetId }
          privateIPAllocationMethod: 'Static'
          privateIPAddress: privateIp
        }
      }
    ]
  }
}

resource vm 'Microsoft.Compute/virtualMachines@2024-03-01' = {
  name: vmName
  location: location
  tags: union(tags, { 'liquidware-role': 'console' })
  identity: { type: 'SystemAssigned' }
  properties: {
    hardwareProfile: { vmSize: vmSize }
    securityProfile: {
      securityType: 'TrustedLaunch'
      uefiSettings: { secureBootEnabled: true, vTpmEnabled: true }
      encryptionAtHost: true
    }
    osProfile: {
      computerName: computerName
      adminUsername: adminUsername
      adminPassword: adminPassword
      windowsConfiguration: {
        provisionVMAgent: true
        enableAutomaticUpdates: true
        patchSettings: { patchMode: 'AutomaticByPlatform' }
      }
    }
    storageProfile: {
      imageReference: {
        publisher: 'MicrosoftWindowsServer'
        offer: 'WindowsServer'
        sku: '2025-datacenter-azure-edition'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        diskSizeGB: 128
        managedDisk: { storageAccountType: 'Premium_LRS' }
        deleteOption: 'Delete'
      }
    }
    networkProfile: {
      networkInterfaces: [{ id: nic.id, properties: { deleteOption: 'Delete' } }]
    }
    diagnosticsProfile: { bootDiagnostics: { enabled: true } }
  }
}

resource shutdown 'Microsoft.DevTestLab/schedules@2018-09-15' = if (environment != 'prod') {
  name: 'shutdown-computevm-${vmName}'
  location: location
  tags: tags
  properties: {
    status: 'Enabled'
    taskType: 'ComputeVmShutdownTask'
    dailyRecurrence: { time: autoShutdownTime }
    timeZoneId: autoShutdownTimeZone
    targetResourceId: vm.id
    notificationSettings: { status: 'Disabled' }
  }
}

output principalId string = vm.identity.principalId
