// The media account (deploy-spec section 5, fork F4): installers in `media`, compiled configuration
// from the console in `staging`. Shared key and anonymous access off; the public endpoint is on
// with an Entra-only data plane, because Cloud Shell has no line of sight to private endpoints
// (D-C4). Never packages, never the live configuration.

param location string
param tags object
param accountName string

@description('Object ID of the operator who uploads installers (Publish-LiquidwareMedia.ps1).')
param operatorObjectId string

@description('Principal ID of the ops runner identity, which reads staging to promote it.')
param opsPrincipalId string

// Built-in role definition IDs: the same in every tenant.
var roles = {
  blobDataContributor: 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
  blobDataReader: '2a2b9908-6ea1-4ae2-8e65-a410df84e7d1'
}

resource account 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: accountName
  location: location
  tags: union(tags, { 'liquidware-role': 'media' })
  kind: 'StorageV2'
  sku: { name: 'Standard_LRS' }
  properties: {
    allowSharedKeyAccess: false
    allowBlobPublicAccess: false
    defaultToOAuthAuthentication: true
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    publicNetworkAccess: 'Enabled'
  }
}

resource blobs 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: account
  name: 'default'
}

resource media 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobs
  name: 'media'
  properties: { publicAccess: 'None' }
}

resource staging 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobs
  name: 'staging'
  properties: { publicAccess: 'None' }
}

resource operatorMedia 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(media.id, operatorObjectId, roles.blobDataContributor)
  scope: media
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.blobDataContributor)
    principalId: operatorObjectId
    principalType: 'User'
  }
}

resource opsStaging 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(staging.id, opsPrincipalId, roles.blobDataReader)
  scope: staging
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.blobDataReader)
    principalId: opsPrincipalId
    principalType: 'ServicePrincipal'
  }
}

output accountName string = account.name
output blobEndpoint string = account.properties.primaryEndpoints.blob
