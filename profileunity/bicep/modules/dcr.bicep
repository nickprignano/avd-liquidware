// Data collection rule for ProfileUnity application restriction events (deploy-spec sections 4 and 5,
// DN-H5). Deployed in rg-<base>-liquidware when enableApplicationRestrictions is true, never modifying
// the landing zone's own DCR.

param location string
param tags object
param dcrName string
param logAnalyticsWorkspaceId string

resource dcr 'Microsoft.Insights/dataCollectionRules@2022-06-01' = {
  name: dcrName
  location: location
  tags: tags
  kind: 'Windows'
  properties: {
    dataSources: {
      windowsEventLogs: [
        {
          name: 'lw-restrictions'
          streams: ['Microsoft-Event']
          xPathQueries: [
            'Application!*[System[(Provider[@Name=\'ProfileUnity\'] or Provider[@Name=\'Liquidware\'])]]'
            'Microsoft-Windows-AppLocker/EXE and DLL!*[System[(EventID=8002 or EventID=8003 or EventID=8004)]]'
          ]
        }
      ]
    }
    destinations: {
      logAnalytics: [
        {
          workspaceResourceId: logAnalyticsWorkspaceId
          name: 'law'
        }
      ]
    }
    dataFlows: [
      {
        streams: ['Microsoft-Event']
        destinations: ['law']
      }
    ]
  }
}

output dcrId string = dcr.id
