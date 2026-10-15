// Key Vault: holds the appliance credential Azure sets at deployment, so no
// one has to remember it. RBAC-authorized and purge-protected; the deployer
// (or a named group) gets Key Vault Secrets User.

param location string
param tags object
param name string
param readerObjectId string
param readerPrincipalType string
param hubAdminUsername string

@secure()
param hubAdminPassword string

var keyVaultSecretsUserRoleId = '4633458b-17de-408a-b874-0445c86b69e6'

module vault 'br/public:avm/res/key-vault/vault:0.14.2' = {
  name: 'key-vault'
  params: {
    name: name
    location: location
    tags: tags
    sku: 'standard'
    enableRbacAuthorization: true
    enablePurgeProtection: true
    softDeleteRetentionInDays: 7
    enableVaultForDeployment: false
    enableVaultForDiskEncryption: false
    enableVaultForTemplateDeployment: false
    secrets: [
      {
        name: 'hub-admin-username'
        value: hubAdminUsername
      }
      {
        name: 'hub-admin-password'
        value: hubAdminPassword
        contentType: 'Local administrator Azure set on the Stratusphere Hub appliance'
      }
    ]
    roleAssignments: [
      {
        principalId: readerObjectId
        principalType: readerPrincipalType
        roleDefinitionIdOrName: keyVaultSecretsUserRoleId
      }
    ]
  }
}

output name string = vault.outputs.name
output resourceId string = vault.outputs.resourceId
