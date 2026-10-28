// Optional Portability share on the landing zone's existing profiles storage account
// (deploy-spec section 4, tier section 5.1). Deployed only when -Portability is passed.

param profilesStorageAccountName string

resource profilesAccount 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: profilesStorageAccountName
}

resource profilesFiles 'Microsoft.Storage/storageAccounts/fileServices@2023-05-01' existing = {
  parent: profilesAccount
  name: 'default'
}

resource portabilityShare 'Microsoft.Storage/storageAccounts/fileServices/shares@2023-05-01' = {
  parent: profilesFiles
  name: 'portability'
  properties: {
    shareQuota: 100
    enabledProtocols: 'SMB'
  }
}

output shareName string = portabilityShare.name
