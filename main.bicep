@description('Specifies whether to deploy Azure Databricks workspace with secure cluster connectivity (SCC) enabled or not (No Public IP)')
param disablePublicIp bool = true
param publicNetworkAccess string = 'Disabled'

@description('Indicates whether to retain or remove the AzureDatabricks outbound NSG rule - possible values are AllRules or NoAzureDatabricksRules.')
@allowed([
  'AllRules'
  'NoAzureDatabricksRules'
])
param requiredNsgRules string = 'NoAzureDatabricksRules'

@description('Location for all resources.')
param location string = resourceGroup().location

@description('The pricing tier of workspace.')
@allowed([
  'trial'
  'standard'
  'premium'
])
param pricingTier string = 'premium'

@description('The name of the public subnet to create.')
param publicSubnetName string = 'sn-dbw-public'

@description('The name of the private subnet to create.')
param privateSubnetName string = 'sn-dbw-private'

@description('Name of the VNET to add a subnet to')
param existingVNETName string = 'vnet-sec-dbw-prod'

@description('Name of the subnet to add')
param PrivateEndpointSubnetName string

@description('CIDR range for the private endpoint subnet..')
param privateEndpointSubnetCidr string = '10.110.2.128/27'

@description('The name of the subnet to create the private endpoint in.')
param PrivateEndpointSubnetName string = 'sn-dbw-private-ep'

@description('The name of the virtual network to create.')
param vnetName string = 'databricks-vnet'

@description('The name of the Azure Databricks workspace to create.')
param workspaceName string

var managedResourceGroupName = 'databricks-rg-${workspaceName}-${uniqueString(workspaceName, resourceGroup().id)}'
var trimmedMRGName = substring(managedResourceGroupName, 0, min(length(managedResourceGroupName), 90))
var managedResourceGroupId = '${subscription().id}/resourceGroups/${trimmedMRGName}'

var privateEndpointName = '${workspaceName}-pvtEndpoint'
var privateDnsZoneName = 'privatelink.azuredatabricks.net'
var pvtEndpointDnsGroupName = '${privateEndpointName}/mydnsgroupname'


resource vnet 'Microsoft.Network/virtualNetworks@2021-03-01' existing = {
   name: existingVNETName
}
resource subnet 'Microsoft.Network/virtualNetworks/subnets@2021-03-01' = {
  parent: vnet
  name: PrivateEndpointSubnetName
  properties: {
    addressPrefix: privateEndpointSubnetCidr
  }
}
resource symbolicname 'Microsoft.Databricks/workspaces@2023-02-01' = {
  name: workspaceName
  location: location
  sku: {
    name: pricingTier
  }
  properties: {
    managedResourceGroupId: managedResourceGroupId
    parameters: {
      customVirtualNetworkId: {
        value: vnet.id
        //value: '/subscriptions/2f054702-74ef-49dc-8055-920692478b36/resourceGroups/rg-sec-dbw-prod/providers/Microsoft.Network/virtualNetworks/vnet-sec-dbw-prod'
      }
      customPublicSubnetName: {
        value: publicSubnetName
      }
      customPrivateSubnetName: {
        value: privateSubnetName
      }
      enableNoPublicIp: {
        value: disablePublicIp
      }
    }
  }
}

resource privateEndpoint 'Microsoft.Network/privateEndpoints@2021-08-01' = {
  name: privateEndpointName
  location: location
  properties: {
    subnet: {
      id: resourceId('Microsoft.Network/virtualNetworks/subnets', vnetName, PrivateEndpointSubnetName)
    }
    privateLinkServiceConnections: [
      {
        name: privateEndpointName
        properties: {
          privateLinkServiceId: symbolicname.id
          groupIds: [
            'databricks_ui_api'
          ]
        }
      }
    ]
  }
}

resource privateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: privateDnsZoneName
  location: 'global'
  dependsOn: [
    privateEndpoint
  ]
}

resource privateDnsZoneName_privateDnsZoneName_link 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: privateDnsZone
  name: '${privateDnsZoneName}-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnet.id
    }
  }
}

resource pvtEndpointDnsGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2021-12-01' = {
  name: pvtEndpointDnsGroupName
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'config1'
        properties: {
          privateDnsZoneId: privateDnsZone.id
        }
      }
    ]
  }
  dependsOn: [
    privateEndpoint
  ]
}
