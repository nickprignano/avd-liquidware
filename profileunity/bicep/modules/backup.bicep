// Recovery Services vault and Enhanced backup policy for the tier's Trusted Launch console VM
// (deploy-spec section 5, DN-H6, fork F3). Off in dev; opt-in for test and prod.

param location string
param tags object
param vaultName string

resource vault 'Microsoft.RecoveryServices/vaults@2023-06-01' = {
  name: vaultName
  location: location
  tags: tags
  sku: {
    name: 'RS0'
    tier: 'Standard'
  }
  properties: {
    publicNetworkAccess: 'Disabled'
  }
}

resource policy 'Microsoft.RecoveryServices/vaults/backupPolicies@2023-06-01' = {
  parent: vault
  name: 'EnhancedPolicy'
  properties: {
    backupManagementType: 'AzureIaasVM'
    policyType: 'V2'
    instantRPDetails: {}
    schedulePolicy: {
      schedulePolicyType: 'SimpleSchedulePolicyV2'
      scheduleRunFrequency: 'Daily'
      dailySchedule: {
        scheduleRunTimes: ['2026-01-01T02:00:00Z']
      }
    }
    retentionPolicy: {
      retentionPolicyType: 'LongTermRetentionPolicy'
      dailySchedule: {
        retentionTimes: ['2026-01-01T02:00:00Z']
        retentionDuration: {
          count: 14
          durationType: 'Days'
        }
      }
    }
    instantRpRetentionRangeInDays: 2
    timeZone: 'UTC'
  }
}

output vaultId string = vault.id
output policyId string = policy.id
