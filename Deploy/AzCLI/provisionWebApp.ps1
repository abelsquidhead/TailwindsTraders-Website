# This IaC script provisions and configures a web app for tailwind traders
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
    $resourceGroupNameRegion,

    [Parameter(Mandatory = $True)]  
    [string]
    $webAppName,

    [Parameter(Mandatory = $True)]  
    [string]
    $appServiceRegion,

    [Parameter(Mandatory = $True)]  
    [string]
    $appServiceSKU,

    [Parameter(Mandatory = $True)]  
    [string]
    $apiUrl,

    [Parameter(Mandatory = $True)]  
    [string]
    $apiUrlShoppingCart,

    [Parameter(Mandatory = $True)]  
    [string]
    $cloudFlareZone,

    [Parameter(Mandatory = $True)]  
    [string]
    $dnsName,

    [Parameter(Mandatory = $True)]  
    [string]
    $cloudFlareKey,

    [Parameter(Mandatory = $True)]  
    [string]
    $cloudFlareEmail,

    [Parameter(Mandatory = $True)]  
    [string]
    $nakedDns
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

#region Create Resource Group
# This creates the resource group used to house all of Mercury Health
#
Write-Output "Creating resource group $resourceGroupName in region $resourceGroupNameRegion..."
az group create `
    --name $resourceGroupName `
    --location $resourceGroupNameRegion
Write-Output "Done creating resource group"
Write-Output ""
#endregion

#region create app service
# create app service plan
#
Write-Output "creating app service plan..."
az appservice plan create `
    --name $("$webAppName" + "plan") `
    --resource-group $resourceGroupName `
    --location $appServiceRegion `
    --sku $appServiceSKU
Write-Output "done creating app service plan"
Write-Output ""

Write-Output "creating web app..."
az webapp create `
    --name $webAppName `
    --plan $("$webAppName" + "plan") `
    --resource-group $resourceGroupName
Write-Output "done creating web app"
Write-Output ""
#endregion

#region set endpoints
# Set api endpoint and api shopping cart endpoint
Write-Output "Setting api endpoint..."
az webapp config appsettings set `
    --name $webAppName `
    --resource-group $resourceGroupName `
    --settings ApiUrl=$apiUrl
Write-Output "Done setting api endpoint"
Write-Output ""


Write-Output "Setting api shopping cart endpoint..."
az webapp config appsettings set `
    --name $webAppName `
    --resource-group $resourceGroupName `
    --settings ApiUrlShoppingCart=$apiUrlShoppingCart
Write-Output "Done setting api shopping cart endpoint"
Write-Output ""
#endregion


#region create application insights for web app
# this creates an instance of appliction insight for node 1
#
Write-Output "creating application insight for web app..."
$appInsightCreateResponse=$(az resource create `
    --resource-group $resourceGroupName `
    --resource-type "Microsoft.Insights/components" `
    --name $($webAppName + "AppInsight") `
    --properties '{\"Application_Type\":\"web\"}') | ConvertFrom-Json
Write-Output "done creating app insight for node 1: $appInsightCreateResponse"
Write-Output ""
#endregion

#region set dns at cloudflare
#region get all dns records from cloudflare
# this lists all dns records from cloudflare
#
Write-Output "getting all dns records from cloudflare..."
$headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
$headers.Add("X-Auth-Key", $cloudFlareKey)
$headers.Add("X-Auth-Email", $cloudFlareEmail)
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12
$listDnsResult=Invoke-RestMethod "https://api.cloudflare.com/client/v4/zones/$cloudFlareZone/dns_records" `
    -Headers $headers
Write-Output $listDnsResult
Write-Output "done getting all dns records"
$numEntries=$listDnsResult.result_info.count
Write-Output "number of dns entries: $numEntries" 
Write-Output ""
#endregion

#region look at all dns records, see if the our dns name has already 
# been set. This block looks for our dns name, see if it has been set or not
#
Write-Output "looking for correct DNS entry"
$foundDnsEntry = $false
$foundDnsEntryId = "x"
$listDnsResult.result | ForEach-Object {
    $dnsEntryName = $_.name
    Write-Output "dns entry name: $dnsEntryName"
    if ($dnsEntryName -eq $dnsName) {
        Write-Output "found correct dns entry"
        $foundDnsEntry =$true
        $foundDnsEntryId = $_.id
        return
    }
}
Write-Output "found dns entry: $foundDnsEntry"
Write-Output "dns entry id: $foundDnsEntryId"
Write-Output ""
#endregion

#region updates/adds dns entry to cloudflare
# this either updates or adds a new dns entry to cloudflare
#
$FQDN=$webAppName + ".azurewebsites.net"
Write-Output "fqdn: $FQDN"
if ($foundDnsEntry -eq $true) {
    Write-Output "updating dns entry..."
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("X-Auth-Key", $cloudFlareKey)
    $headers.Add("X-Auth-Email", $cloudFlareEmail)
    $updateDnsEntry = @{
        type='CNAME'
        name='www'
        content="$FQDN"
        proxied=$false
    }
    $json = $updateDnsEntry | ConvertTo-Json
    $updateDnsResponse = $(Invoke-RestMethod "https://api.cloudflare.com/client/v4/zones/$cloudFlareZone/dns_records/$foundDnsEntryId" `
        -Headers $headers `
        -Method Put `
        -Body $json `
        -ContentType 'application/json')

    Write-Output "done updating dns"
    Write-Output "cloudflare response: "
    Write-Output $updateDnsResponse
    Write-Output ""
}
else {
    Write-Output "adding new dns entry..."
    $newDnsResponse = $()
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("X-Auth-Key", $cloudFlareKey)
    $headers.Add("X-Auth-Email", $cloudFlareEmail)
    $newDnsEntry = @{
        type='CNAME'
        name='www'
        content="$FQDN"
        proxied=$false
        priority=10
    }
    $json = $newDnsEntry | ConvertTo-Json
    $newDnsResponse = $(Invoke-RestMethod "https://api.cloudflare.com/client/v4/zones/$cloudFlareZone/dns_records" `
    -Headers $headers `
    -Method Post `
    -Body $json `
    -ContentType 'application/json')

    Write-Output "done adding dns"
    Write-Output "cloudflare response: "
    Write-Output $newDnsResponse
    Write-Output ""
}
#endregion


#region gets all dns entries from cloudflare for apex domain
# this lists all dns records from cloudflare for apex domain
#
Write-Output "getting all dns records from cloudflare..."
$headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
$headers.Add("X-Auth-Key", $cloudFlareKey)
$headers.Add("X-Auth-Email", $cloudFlareEmail)
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12
$listDnsResult=Invoke-RestMethod "https://api.cloudflare.com/client/v4/zones/$cloudFlareZone/dns_records" `
    -Headers $headers
Write-Output $listDnsResult
Write-Output "done getting all dns records"
$numEntries=$listDnsResult.result_info.count
Write-Output "number of dns entries: $numEntries" 
Write-Output ""
#endregion

#region look at all dns records, see if our dns name has already been set
# this looks for our dns name, see if it has been set or not
#
$foundDnsEntry = $false
$foundDnsEntryId = "x"
$listDnsResult.result | ForEach-Object {
    $dnsEntryName = $_.name
    if ($dnsEntryName -eq $nakedDns) {
        $foundDnsEntry =$true
        $foundDnsEntryId = $_.id
        return
    }
}
Write-Output "found dns entry: $foundDnsEntry"
Write-Output "dns entry id: $foundDnsEntryId"
Write-Output ""
#endregion

#region update/add  dns entry to cloudflare for apex domain
# this either updates or adds a new dns entry to cloudflare for
# the apex domain
#
$FQDN=$webAppName + ".azurewebsites.net"
if ($foundDnsEntry -eq $true) {
    Write-Output "updating dns entry..."
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("X-Auth-Key", $cloudFlareKey)
    $headers.Add("X-Auth-Email", $cloudFlareEmail)
    $updateDnsEntry = @{
        type='CNAME'
        name='@'
        content="$FQDN"
        proxied=$true
    }
    $json = $updateDnsEntry | ConvertTo-Json
    $updateDnsResponse = $(Invoke-RestMethod "https://api.cloudflare.com/client/v4/zones/$cloudFlareZone/dns_records/$foundDnsEntryId" `
        -Headers $headers `
        -Method Put `
        -Body $json `
        -ContentType 'application/json')

    Write-Output "done updating dns"
    Write-Output "cloudflare response: "
    Write-Output $updateDnsResponse
    Write-Output ""

    Write-Output "done updating dns"
    Write-Output ""
}
else {
    Write-Output "adding new dns entry..."
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("X-Auth-Key", $cloudFlareKey)
    $headers.Add("X-Auth-Email", $cloudFlareEmail)
    $newDnsEntry = @{
        type='CNAME'
        name='@'
        content="$FQDN"
        proxied=$true
        priority=10
    }
    $json = $newDnsEntry | ConvertTo-Json
    $newDnsResponse = $(Invoke-RestMethod "https://api.cloudflare.com/client/v4/zones/$cloudFlareZone/dns_records" `
    -Headers $headers `
    -Method Post `
    -Body $json `
    -ContentType 'application/json')

    Write-Output "done adding dns"
    Write-Output "cloudflare response: "
    Write-Output $newDnsResponse
    Write-Output ""
    Write-Output "done adding new dns entry"
    Write-Output ""
}
#endregion

#region check page rules
# this looks to see if we need to add a page rule for apex domain
# first by looking up all the rules
#
Write-Output "getting all rules from cloudflare..."
$headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
$headers.Add("X-Auth-Key", $cloudFlareKey)
$headers.Add("X-Auth-Email", $cloudFlareEmail)
$headers.Add("Content-Type", "application/json")
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12
$listRulesResult=Invoke-RestMethod "https://api.cloudflare.com/client/v4/zones/$cloudFlareZone/pagerules?status=active&order=status&direction=desc&match=all" `
    -Headers $headers
Write-Output $listRulesResult
Write-Output "done getting all dns records"
$numEntries=$listRulesResult.result_info.count
Write-Output "number of dns entries: $numEntries" 
Write-Output ""
#endregion

#region delete old page rules
# delete these old rule entries
#
Write-Output "deleting all rule entries..."
$listRulesResult.result | ForEach-Object {
    $ruleId = $_.id
    Write-Output "deleting rule with id: $ruleId"
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("X-Auth-Key", $cloudFlareKey)
    $headers.Add("X-Auth-Email", $cloudFlareEmail)
    $deleteResult = Invoke-RestMethod "https://api.cloudflare.com/client/v4/zones/$cloudFlareZone/pagerules/$ruleId" `
        -Headers $headers `
        -Method Delete
    Write-Output "delete response: "
    Write-Output $deleteResult
}
Write-Output "done deleting all rule entries"    
Write-Output ""
#endregion

#region add new apex domain rules
# Add in the apex domain rule
#
Write-Output "adding apex domain rule..."
$json = '{"targets":[{"target":"url", "constraint":{"operator":"matches","value":"' + $nakedDns + '/*"}}],"actions":[{"id":"forwarding_url","value": {"url": "https://' + $dnsName + '/$1","status_code": 301}}],"priority":1,"status":"active"}'
Write-Output "body: $json"
$headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
$headers.Add("X-Auth-Key", $cloudFlareKey)
$headers.Add("X-Auth-Email", $cloudFlareEmail)
$headers.Add("Content-Type", "application/json")
$addRuleResponse = Invoke-RestMethod "https://api.cloudflare.com/client/v4/zones/$cloudFlareZone/pagerules" `
    -Headers $headers `
    -Method Post `
    -Body $json `
    -ContentType 'application/json'
Write-Output $addRuleResponse
Write-Output "done adding apex domain rule"
Write-Output ""
#endregion
#endregion

#region getting certificate
# Getting certificate from github secrets and decoding
#
Write-Output "getting certificate, decoding..."
$pfx=$env:PFX
$kvSecretBytes = [System.Convert]::FromBase64String($pfx)
$certCollection = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2Collection
$certCollection.Import($kvSecretBytes,$null,[System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::Exportable)
Write-Output "done getting dev certificate"
Write-Output ""
#endregion

#region saving pfx file to disk
# Saving pfx file to disk
#
Write-Output "saving pfx to disk"
$pfxPassword="abelpassword1"
$password = $pfxPassword
$protectedCertificateBytes = $certCollection.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Pkcs12, $password)
$pfxPath = [Environment]::GetFolderPath("Desktop") + "\MyCert.pfx"
[System.IO.File]::WriteAllBytes($pfxPath, $protectedCertificateBytes)
Write-Output "done saving pfx to disk"
Write-Output ""
#endregion

#region Uploading certificate
# Uploading ssl certificate to webapp, getting thumbprint
#
Write-Output "uploading certificate, getting thumbprint"
$thumbprint=$(az webapp config ssl upload `
--name $webAppName `
--resource-group $resourceGroupName `
--certificate-file $pfxPath `
--certificate-password $pfxPassword `
--query thumbprint `
--output tsv)
Write-Output "done uploading certificate, thumbprint: $thumbprint"
Write-Output ""
#endregion

#region adding custom domain
Write-Output "adding custom domain and adding certificate "
az webapp config hostname add `
    --webapp-name $webAppName `
    --resource-group $resourceGroupName `
    --hostname $dnsName

az webapp config ssl bind `
    --name $webAppName `
    --resource-group $resourceGroupName `
    --certificate-thumbprint $thumbprint `
    --ssl-type SNI
Write-Output "done adding custom domain and adding certificate"
#endregion
