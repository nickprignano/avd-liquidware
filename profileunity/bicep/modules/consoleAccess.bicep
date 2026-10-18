// What the console's own identity may touch (deploy-spec sections 5 and 6.1): read installers
// in `media`, write compiled configuration to `staging` (never the live config account), and read
// the ProfileUnity license string, one secret, once the operator has stored it.

param mediaAccountName string
param keyVaultName string
param consolePrincipalId string

@description('True once Set-LiquidwareSecret.ps1 has stored lw-licstr; a role can only be scoped to a secret that exists.')
param licenseStored bool

var roles = {
  blobDataContributor: 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
  blobDataReader: '2a2b9908-6ea1-4ae2-8e65-a410df84e7d1'
  keyVaultSecretsUser: '4633458b-17de-408a-b874-0445c86b69e6'
}

resource mediaAccount 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: mediaAccountName
}

resource blobs 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' existing = {
  parent: mediaAccount
  name: 'default'
}

resource media 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' existing = {
  parent: blobs
  name: 'media'
}

resource staging 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' existing = {
  parent: blobs
  name: 'staging'
}

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}

resource license 'Microsoft.KeyVault/vaults/secrets@2023-07-01' existing = {
  parent: keyVault
  name: 'lw-licstr'
}

resource consoleMedia 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(media.id, consolePrincipalId, roles.blobDataReader)
  scope: media
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.blobDataReader)
    principalId: consolePrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource consoleStaging 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(staging.id, consolePrincipalId, roles.blobDataContributor)
  scope: staging
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.blobDataContributor)
    principalId: consolePrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource consoleLicense 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (licenseStored) {
  name: guid(keyVault.id, 'lw-licstr', consolePrincipalId, roles.keyVaultSecretsUser)
  scope: license
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.keyVaultSecretsUser)
    principalId: consolePrincipalId
    principalType: 'ServicePrincipal'
  }
}
