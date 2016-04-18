<#

* Setup any PS Repositories
* Install required DSC modules
* Trigger any Callback URLs

This script runs *after* the server has WMF5 installed.

#>
$Dir = "C:\cloud-automation"
New-Item -Path $Dir\logs -ItemType Directory -ErrorAction SilentlyContinue
Start-Transcript -Path $Dir\logs\setup.log -Append
Set-Location -Path $Dir

# Install the NuGet package provider
Install-PackageProvider -Name NuGet -Force

# Let's trust the PSGallery source
Set-PackageSource -Trusted -Name PSGallery -ProviderName PowerShellGet
Set-PSRepository -InstallationPolicy Trusted -name PSGallery

# Example of a customer PSRepository:
#Register-PSRepository -Name "nuget.org" `
#    -InstallationPolicy Trusted `
#    –SourceLocation "https://www.nuget.org/api/v2" `
#    -PublishLocation "https://www.nuget.org/api/v2/Packages"
#Set-PackageSource -Trusted -Name nuget.org -ProviderName PowerShellGet

# Load our bootstrap config
$BootstrapConfig = (Get-Content $Dir\bootstrap-config.json) -join "`n" | ConvertFrom-Json

# Download our setup.json file
# Load our remote Modules config file
$URI = Get-Content "$Dir\setup.url" -Raw
# @TODO Add API Token and other data?
$SetupFile = "$Dir\setup.json"
(New-Object System.Net.WebClient).DownloadFile($URI, $SetupFile)
$SetupConfig = (Get-Content $SetupFile) -join "`n" | ConvertFrom-Json

<#

Install PSGallery modules

Our Module manifest contains explicit RequiredVersion values that MUST be set
to avoid any surprises.

#>
$SetupConfig.PSGallery.GetEnumerator() | % {
    Write-Host "Installing $($_.Name) version $($_.RequiredVersion)"
    Install-Module -Verbose $_.Name `
        -Repository $_.Repository `
        -RequiredVersion $_.RequiredVersion
}

<#

Install Modules from Github

#>
Import-Module -Name GitHubRepository
$SetupConfig.GitHub.GetEnumerator() | % {
    Write-Host "Installing $($_.Owner)/$($_.Name) version $($_.RequiredVersion);"
    Install-GitHubRepository `
        -Owner $_.Owner `
        -Repository $_.Name `
        -Branch $_.RequiredVersion `
        -Force -Verbose
}

<#

Run remote scripts

#>
$SetupConfig.Scripts.GetEnumerator() | % {
    Write-Host "Downloading $($_.URI)"
    # Let's always download our files before we run them. This will help us debug and test.
    $Destination = "$Dir\$($_.Destination)"
    (New-Object System.Net.WebClient).DownloadFile($_.URI, $Destination)
    Write-Host "Running ${Destination}"
    Invoke-Expression -Command $Destination
}

<#

Send data to callback URLs

#>
$PublicIP = ((Get-NetIPConfiguration).IPv4Address | Where-Object {$_.InterfaceAlias -eq "public0"}).IpAddress

$SetupConfig.CallbackURLs.GetEnumerator() | %{
    Write-Host "Sending request to callback URL: $_"
    $Request = [System.UriBuilder]$_.URI
    $Parameters = [System.Web.HttpUtility]::ParseQueryString($Request.Query)
    # Add standard parameters
    $Parameters['NODE_NAME'] = $env:COMPUTERNAME
    $Parameters['NODE_IP'] = $PublicIP
    $Parameters['NAMESPACE'] = $BootstrapConfig.app_name
    $Parameters['ENVIRONMENT'] = $BootstrapConfig.environment_name
    $Parameters[$BootstrapConfig.api_token.name] = $BootstrapConfig.api_token.value
    $Request.Query = $Parameters.ToString()
    # Call the callback
    Invoke-RestMethod -Method Get -Uri $Request.Uri -Verbose
}

# Disable the on-boot task
Write-Host "Disabling Boot task"
Disable-ScheduledTask -TaskName rsBoot

Write-Host "All Done"
Stop-Transcript