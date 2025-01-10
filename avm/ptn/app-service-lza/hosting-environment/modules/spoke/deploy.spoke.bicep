targetScope = 'subscription'

import { NamingOutput } from '../naming/naming.module.bicep'

param naming NamingOutput

@description('Required. Azure region where the resources will be deployed in')
param location string

@description('Required. Whether to enable deployment telemetry.')
param enableTelemetry bool

@description('Optional. default is false. Set to true if you want to deploy ASE v3 instead of Multi-tenant App Service Plan.')
param deployAseV3 bool = false

@description('Required. CIDR of the SPOKE vnet i.e. 192.168.0.0/24')
param vnetSpokeAddressSpace string

@description('Required. CIDR of the subnet that will hold the app services plan')
param subnetSpokeAppSvcAddressSpace string

@description('Required. CIDR of the subnet that will hold devOps agents etc ')
param subnetSpokeDevOpsAddressSpace string

@description('Required. CIDR of the subnet that will hold the private endpoints of the supporting services')
param subnetSpokePrivateEndpointAddressSpace string

@description('Optional. Internal IP of the Azure firewall deployed in Hub. Used for creating UDR to route all vnet egress traffic through Firewall. If empty no UDR')
param firewallInternalIp string = ''

@description('Optional. if empty, private dns zone will be deployed in the current RG scope')
param vnetHubResourceId string = ''

@description('Resource tags that we might need to add to all resources (i.e. Environment, Cost center, application name etc)')
param tags object = {}

@description('Required. Create (or not) a UDR for the App Service Subnet, to route all egress traffic through Hub Azure Firewall')
param enableEgressLockdown bool

@description('Conditional. The size of the jump box virtual machine to create. See https://learn.microsoft.com/azure/virtual-machines/sizes for more information.')
param vmSize string

@description('Optional. The zone to create the jump box in. Defaults to 0.')
param vmZone int = 0

@description('Optional. The storage account type to use for the jump box. Defaults to Standard_LRS.')
param storageAccountType string = 'Standard_LRS'

@description('Conditional. The username to use for the jump box.')
param vmAdminUsername string

@description('Conditional. The password to use for the jump box.')
@secure()
param vmAdminPassword string

@description('Optional. Default is windows. The OS of the jump box virtual machine to create.')
@allowed(['linux', 'windows', 'none'])
param vmJumpboxOSType string = 'windows'

@description('Optional. The name of the subnet to create for the jump box. If set, it overrides the name generated by the template.')
param vmSubnetName string = 'snet-jumpbox'

@description('Optional. Type of authentication to use on the Virtual Machine. SSH key is recommended.')
@allowed([
  'sshPublicKey'
  'password'
])
param vmAuthenticationType string = 'password'

@description('Required. Deploy (or not) an Azure virtual machine (to be used as jumphost)')
param deployJumpHost bool

@description('Optional. P1V3 is default. Defines the name, tier, size, family and capacity of the App Service Plan. Plans ending to _AZ, are deploying at least three instances in three Availability Zones. EP* is only for functions')
@allowed([
  'S1'
  'S2'
  'S3'
  'P1V3'
  'P2V3'
  'P3V3'
  'EP1'
  'EP2'
  'EP3'
  'ASE_I1V2'
  'ASE_I2V2'
  'ASE_I3V2'
])
param webAppPlanSku string = 'P1V3'

@description('Optional. Set to true if you want to deploy the App Service Plan in a zone redundant manner. Defult is true.')
param zoneRedundant bool = true

@description('Required. Kind of server OS of the App Service Plan')
@allowed(['windows', 'linux'])
param webAppBaseOs string

@description('Conditional. default value is azureuser')
param adminUsername string

@description('Conditional. the password of the admin user')
@secure()
param adminPassword string

@description('Optional. Set to true if you want to auto approve the Private Endpoint of the AFD')
param autoApproveAfdPrivateEndpoint bool = true

@description('Optional. The resource ID of the bastion host. If set, the spoke virtual network will be peered with the hub virtual network and the bastion host will be allowed to connect to the jump box. Default is empty.')
param bastionResourceId string = ''

param resourceGroupName string

var resourceNames = {
  vnetSpoke: take('${naming.virtualNetwork.name}-spoke', 80)
  pepNsg: take('${naming.networkSecurityGroup.name}-pep', 80)
  aseNsg: take('${naming.networkSecurityGroup.name}-ase', 80)
  appSvcUserAssignedManagedIdentity: take('${naming.managedIdentity.name}-appSvc', 128)
  vmJumpHostUserAssignedManagedIdentity: take('${naming.managedIdentity.name}-vmJumpHost', 128)
  keyvault: naming.keyVault.nameUnique
  logAnalyticsWs: naming.logAnalyticsWorkspace.name
  appInsights: naming.applicationInsights.name
  aseName: naming.appServiceEnvironment.nameUnique
  aspName: naming.appServicePlan.name
  webApp: naming.appService.nameUnique
  vmWindowsJumpbox: take('${naming.windowsVirtualMachine.name}-win-jumpbox', 64)
  frontDoorEndPoint: 'webAppLza-${take( uniqueString(resourceGroupName), 6) }' //globally unique
  frontDoorWaf: naming.frontDoorFirewallPolicy.name
  frontDoor: naming.frontDoor.name
  frontDoorOriginGroup: '${naming.frontDoor.name}-originGroup'
  routeTable: naming.routeTable.name
  routeEgressLockdown: '${naming.route.name}-egress-lockdown'
  snetDevOps: 'snet-devOps-${naming.virtualNetwork.name}-spoke'
  idAfdApprovePeAutoApprover: take('${naming.managedIdentity.name}-AfdApprovePe', 128)
}

var virtualNetworkLinks = [
  {
    name: networking.outputs.vnetSpokeName
    virtualNetworkResourceId: networking.outputs.vnetSpokeId
    registrationEnabled: false
  }
]

module networking '../networking/network.module.bicep' = {
  name: 'networkingModule-Deployment'
  scope: resourceGroup(resourceGroupName)
  params: {
    naming: naming
    enableEgressLockdown: enableEgressLockdown
    vnetSpokeAddressSpace: vnetSpokeAddressSpace
    subnetSpokeAppSvcAddressSpace: subnetSpokeAppSvcAddressSpace
    subnetSpokePrivateEndpointAddressSpace: subnetSpokePrivateEndpointAddressSpace
    firewallInternalIp: firewallInternalIp
    hubVnetId: vnetHubResourceId
    logAnalyticsWorkspaceId: logAnalyticsWs.outputs.resourceId
    tags: tags
  }
}

module logAnalyticsWs 'br/public:avm/res/operational-insights/workspace:0.7.1' = {
  name: 'logAnalyticsWs-Deployment'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: resourceNames.logAnalyticsWs
    location: location
    tags: tags
  }
}

module webApp '../app-service/app-service.module.bicep' = {
  name: 'webAppModule-Deployment'
  scope: resourceGroup(resourceGroupName)
  params: {
    deployAseV3: deployAseV3
    aseName: resourceNames.aseName
    appServicePlanName: resourceNames.aspName
    webAppName: resourceNames.webApp
    managedIdentityName: resourceNames.appSvcUserAssignedManagedIdentity
    location: location
    logAnalyticsWsId: logAnalyticsWs.outputs.resourceId
    subnetIdForVnetInjection: networking.outputs.snetAppSvcId
    tags: tags
    webAppBaseOs: webAppBaseOs
    zoneRedundant: zoneRedundant
    subnetPrivateEndpointId: networking.outputs.snetPeId
    virtualNetworkLinks: virtualNetworkLinks
    sku: webAppPlanSku
  }
}

module afd '../front-door/front-door.module.bicep' = {
  name: take('AzureFrontDoor-${resourceNames.frontDoor}-deployment', 64)
  scope: resourceGroup(resourceGroupName)
  params: {
    afdName: resourceNames.frontDoor
    endpointName: resourceNames.frontDoorEndPoint
    originGroupName: resourceNames.frontDoorOriginGroup
    origins: [
      {
        name: webApp.outputs.webAppName
        hostname: webApp.outputs.webAppHostName
        enabledState: true
        privateLinkOrigin: {
          privateEndpointResourceId: webApp.outputs.webAppResourceId
          privateLinkResourceType: 'sites'
          privateEndpointLocation: webApp.outputs.webAppLocation
        }
      }
    ]
    skuName: 'Premium_AzureFrontDoor'
    wafPolicyName: resourceNames.frontDoorWaf
  }
}

module autoApproveAfdPe '../front-door/approve-afd-pe.module.bicep' = if (autoApproveAfdPrivateEndpoint) {
  name: take('autoApproveAfdPe-${resourceNames.frontDoor}-deployment', 64)
  scope: resourceGroup(resourceGroupName)
  params: {
    location: location
    idAfdPeAutoApproverName: resourceNames.idAfdApprovePeAutoApprover
  }
  dependsOn: [
    afd
  ]
}

@description('An optional Linux virtual machine deployment to act as a jump box.')
module jumpboxLinuxVM '../compute/linux-vm.bicep' = if (deployJumpHost && vmJumpboxOSType == 'linux') {
  name: take('vm-linux-${deployment().name}', 64)
  scope: resourceGroup(resourceGroupName)
  params: {
    location: location
    tags: tags
    enableTelemetry: enableTelemetry
    vmName: naming.linuxVirtualMachine.name
    bastionResourceId: bastionResourceId
    vmAdminUsername: adminUsername
    vmAdminPassword: adminPassword
    vmSize: vmSize
    vmZone: vmZone
    storageAccountType: storageAccountType
    vmVnetName: networking.outputs.vnetSpokeName
    vmSubnetName: resourceNames.snetDevOps
    vmSubnetAddressPrefix: subnetSpokeDevOpsAddressSpace
    vmNetworkInterfaceName: naming.networkInterface.name
    vmNetworkSecurityGroupName: naming.networkSecurityGroup.name
    vmAuthenticationType: vmAuthenticationType
    logAnalyticsWorkspaceResourceId: logAnalyticsWs.outputs.resourceId
  }
}

@description('An optional Windows virtual machine deployment to act as a jump box.')
module jumpboxWindowsVM '../compute/windows-vm.bicep' = if (deployJumpHost && vmJumpboxOSType == 'windows') {
  name: take('vm-windows-${deployment().name}', 64)
  scope: resourceGroup(resourceGroupName)
  params: {
    location: location
    tags: tags
    enableTelemetry: enableTelemetry
    vmName: naming.windowsVirtualMachine.name
    bastionResourceId: bastionResourceId
    vmAdminUsername: vmAdminUsername
    vmAdminPassword: vmAdminPassword
    vmSize: vmSize
    vmZone: vmZone
    storageAccountType: storageAccountType
    vmVnetName: networking.outputs.vnetSpokeName
    vmSubnetName: vmSubnetName
    vmSubnetAddressPrefix: subnetSpokeDevOpsAddressSpace
    vmNetworkInterfaceName: naming.networkInterface.name
    vmNetworkSecurityGroupName: naming.networkSecurityGroup.name
    logAnalyticsWorkspaceResourceId: logAnalyticsWs.outputs.resourceId
  }
}

output vnetSpokeName string = networking.outputs.vnetSpokeName
output vnetSpokeId string = networking.outputs.vnetSpokeId
output spokePrivateEndpointSubnetName string = networking.outputs.snetPeName
output appServiceManagedIdentityPrincipalId string = webApp.outputs.webAppSystemAssignedPrincipalId
output logAnalyticsWorkspaceId string = logAnalyticsWs.outputs.resourceId
