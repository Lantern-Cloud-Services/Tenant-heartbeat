targetScope = 'subscription'

@description('Name of the heartbeat resource group to create or update.')
param resourceGroupName string

@description('Azure region for the heartbeat resource group.')
param location string

@description('Nickname of the tenant this heartbeat belongs to (e.g. "LCS P3").')
param tenantNickname string

@description('UTC timestamp of the current heartbeat run. Defaults to deployment time.')
param heartbeatTimestamp string = utcNow('yyyy-MM-ddTHH:mm:ssZ')

resource heartbeatResourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: resourceGroupName
  location: location
  tags: {
    purpose: 'tenant-heartbeat'
    managedBy: 'github-actions'
    tenantNickname: tenantNickname
    lastHeartbeatUtc: heartbeatTimestamp
  }
}

output resourceGroupId string = heartbeatResourceGroup.id
output lastHeartbeatUtc string = heartbeatTimestamp
