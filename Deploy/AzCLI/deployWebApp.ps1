# powershell script which deploys web app using a az cli
#
[CmdletBinding()]
param(
    [Parameter(Mandatory = $True)]
    [string]
    $servicePrincipal,

    [Parameter(Mandatory = $True)]
    [string]
    $servicePrincipalSecret,

    [Parameter(Mandatory = $True)]
    [string]
    $servicePrincipalTenantId,

    [Parameter(Mandatory = $True)]
    [string]
    $resourceGroupName,

    [Parameter(Mandatory = $True)]  
    [string]
    $webAppName,

    [Parameter(Mandatory = $True)]  
    [string]
    $pathToWebsiteZip
)


#region Login
# This logs in a service principal
#
Write-Output "Logging in to Azure with a service principal..."
az login `
    --service-principal `
    --username $servicePrincipal `
    --password $servicePrincipalSecret `
    --tenant $servicePrincipalTenantId
Write-Output "Done"
Write-Output ""
#endregion


#region Deploy Web App
# Deploy Web App
#
az webapp deployment source config-zip -g $resourceGroupName -n $webAppName --src $pathToWebsiteZip --slot staging
#endregion