metadata name = 'WAF-aligned'
metadata description = 'This instance deploys the module with WAF aligned settings.'

targetScope = 'subscription'

// ========== //
// Parameters //
// ========== //

@description('Optional. The name of the resource group to deploy for diagnostics settings')
@maxLength(90)
param diagnosticsResourceGroupName string = 'diag-${namePrefix}-appservicelza-${serviceShort}-rg'

@description('Optional. The location to deploy resources to.')
param resourceLocation string = deployment().location

@description('Optional. A short identifier for the kind of deployment. Should be kept short to not run into resource-name length-constraints.')
param serviceShort string = 'appwaf'

@description('Optional. Test name prefix.')
param namePrefix string = '#_namePrefix_#'

@description('Optional. The password to leverage for the login.')
@secure()
param password string = newGuid()

// Diagnostics
// ===========
resource resourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: diagnosticsResourceGroupName
  location: resourceLocation
}

module diagnosticDependencies '../../../../../../../utilities/e2e-template-assets/templates/diagnostic.dependencies.bicep' = {
  scope: resourceGroup
  name: '${uniqueString(deployment().name, resourceLocation)}-diagnosticDependencies'
  params: {
    storageAccountName: 'dep${namePrefix}diasa${serviceShort}03'
    logAnalyticsWorkspaceName: 'dep-${namePrefix}-law-${serviceShort}'
    eventHubNamespaceEventHubName: 'dep-${namePrefix}-evh-${serviceShort}01'
    eventHubNamespaceName: 'dep-${namePrefix}-evhns-${serviceShort}01'
    location: resourceLocation
  }
}

// ============== //
// Test Execution //
// ============== //

@batchSize(1)
module testDeployment '../../../main.bicep' = [
  for iteration in ['init', 'idem']: {
    name: '${uniqueString(deployment().name, resourceLocation)}-test-${serviceShort}-${iteration}'
    params: {
      workloadName: serviceShort
      tags: {
        environment: 'test'
      }
      aseDiagnosticSettings: [
        {
          eventHubName: diagnosticDependencies.outputs.eventHubNamespaceEventHubName
          eventHubAuthorizationRuleResourceId: diagnosticDependencies.outputs.eventHubAuthorizationRuleId
          storageAccountResourceId: diagnosticDependencies.outputs.storageAccountResourceId
          workspaceResourceId: diagnosticDependencies.outputs.logAnalyticsWorkspaceResourceId
          logCategoriesAndGroups: [
            {
              categoryGroup: 'allLogs'
            }
          ]
        }
      ]
      servicePlanDiagnosticSettings: [
        {
          eventHubName: diagnosticDependencies.outputs.eventHubNamespaceEventHubName
          eventHubAuthorizationRuleResourceId: diagnosticDependencies.outputs.eventHubAuthorizationRuleId
          storageAccountResourceId: diagnosticDependencies.outputs.storageAccountResourceId
          workspaceResourceId: diagnosticDependencies.outputs.logAnalyticsWorkspaceResourceId
          metricCategories: [
            {
              category: 'AllMetrics'
            }
          ]
        }
      ]
      appserviceDiagnosticSettings: [
        {
          eventHubName: diagnosticDependencies.outputs.eventHubNamespaceEventHubName
          eventHubAuthorizationRuleResourceId: diagnosticDependencies.outputs.eventHubAuthorizationRuleId
          storageAccountResourceId: diagnosticDependencies.outputs.storageAccountResourceId
          workspaceResourceId: diagnosticDependencies.outputs.logAnalyticsWorkspaceResourceId
          logCategoriesAndGroups: [
            {
              categoryGroup: 'allLogs'
            }
          ]
          metricCategories: [
            {
              category: 'AllMetrics'
            }
          ]
        }
      ]
      frontDoorDiagnosticSettings: [
        {
          eventHubName: diagnosticDependencies.outputs.eventHubNamespaceEventHubName
          eventHubAuthorizationRuleResourceId: diagnosticDependencies.outputs.eventHubAuthorizationRuleId
          storageAccountResourceId: diagnosticDependencies.outputs.storageAccountResourceId
          workspaceResourceId: diagnosticDependencies.outputs.logAnalyticsWorkspaceResourceId
          logCategoriesAndGroups: [
            {
              category: 'FrontdoorAccessLog'
            }
            {
              category: 'FrontdoorWebApplicationFirewallLog'
            }
          ]
        }
      ]
      vmSize: 'Standard_D2s_v4'
      adminUsername: 'azureuser'
      adminPassword: password
      enableEgressLockdown: true
    }
  }
]

output testDeploymentOutputs object = testDeployment[0].outputs
