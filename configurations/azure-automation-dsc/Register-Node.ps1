<#

.SYNOPSIS

Bootstraps a base server by installing WMF5 (if necessary) and registering the server with a Pull server.


.DESCRIPTION

Intended to be run on the server that you want added into a centralised DSC system.

This server MUST have outbound http and https access.

This script will install WMF5 and reboot if needed.


.PARAMETER RegistrationUrl

The Pull server registration URL. In Azure, this looks something like this:
https://we-agentservice-prod-1.azure-automation.net/accounts/deadbeef-582a-4e10-efef-acac123acac123

Required.


.PARAMETER RegistrationKey

An access key that allows the server to register. An opaque string that can be
found in the Azure Portal as 'Primary Access Key' or 'Secondary Access Key'. Required.


.PARAMETER ConfigurationName

The Configuration Name. Optional, defaults to 'MyConfig'


.PARAMETER NodeConfigurationName

The Node Configuration Name. Optional, defaults to the current machine's hostname
with any dash characters ('-') removed.


.PARAMETER BootTaskName

The name of a boot task to register. This task will be run after any reboot.
Optional, defaults to 'register-node-on-boot'


.EXAMPLE
Register this machine with Azure Automation DSC

Set-ExecutionPolicy Unrestricted

C:\Register-Node.ps1 `
    -RegistrationUrl https://registration-url.com/guid `
    -RegistrationKey SECRETKEY `
    -ConfigurationName MyConfig

.NOTES

You can override the NodeConfigurationName value if you want to assign this
server a 'generic' role.

#>

[CmdletBinding()]
Param(
    [Parameter(Mandatory=$True)]
    [ValidateScript({ if ([system.uri]::IsWellFormedUriString($_,[System.UriKind]::Absolute)) {
        $True
    } Else {
        Throw "$_ is not a valid URL. Please enter a valid Pull server registration URL."
    }})]
    [string]$RegistrationUrl,

    [Parameter(Mandatory=$True, HelpMessage="Enter a Pull server registration key")]
    [string]$RegistrationKey,

    [Parameter(Mandatory=$False)]
    [string]$ConfigurationName = "MyConfig",

    [Parameter(Mandatory=$False)]
    [string]$NodeConfigurationName,

    [string]$BootTaskName = 'register-node-on-boot'
)

# Get a reference to the current file
$SetupFileName = $MyInvocation.MyCommand.Definition

# Start logging
$LogFile = "C:\Register-Node.log"
Start-Transcript -Path $LogFile -Append

# Build a NodeConfigurationName value if it was not passed in as a parameter
if (!$NodeConfigurationName -or $NodeConfigurationName -eq "") {
    $NodeConfigurationName = $ConfigurationName + "." + $($env:COMPUTERNAME -replace '[-]','')
}

$Archives = @(
    # @{
    #     Name = "Demo File Archive"
    #     URI = "https://rdpsartifacts01.blob.core.windows.net/demo-01/files.zip"
    #     DestinationFile = "C:\\demo-files.zip"
    #     DestinationPath = "C:\\demo-files"
    #     Description = "Demo file archive"
    # }
)

<#

# A function to silently install WMF5

#>
function Install-WMF5
{
    Write-Host "Installing WMF5. This may take a few minutes and will trigger a reboot..."
    $WMF5FileName = "Win8.1AndW2K12R2-KB3134758-x64.msu"
    $WMF5BaseURL = "https://download.microsoft.com/download/2/C/6/2C6E1B4A-EBE5-48A6-B225-2D2058A9CEFB"
    $WMF5TempDir = "${Env:WinDir}\Temp"
    (New-Object -TypeName System.Net.webclient).DownloadFile("${WMF5BaseURL}/${WMF5FileName}", "${WMF5TempDir}\${WMF5FileName}")
    Start-Process -Wait -FilePath "${WMF5TempDir}\${WMF5FileName}" -ArgumentList '/quiet /norestart' -Verbose
}

<#

# A function to set up a boot task to re-call our setup script

#>
function Create-BootTask
{
    if (Get-ScheduledTask -TaskName $BootTaskName -ErrorAction SilentlyContinue) {
        return
    }
    Write-Host "Setting up a boot task named '$BootTaskName'"

    # Build a list of arguments (as an ugly long string)
    $Args = "-RegistrationUrl $RegistrationUrl -RegistrationKey $RegistrationKey -NodeConfigurationName $NodeConfigurationName -BootTaskName $BootTaskName"
    $A = New-ScheduledTaskAction `
        -Execute "PowerShell.exe" `
        -Argument "-ExecutionPolicy Bypass -File $SetupFileName $Args"
    $T = New-ScheduledTaskTrigger -AtStartup
    $P = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount
    $S = New-ScheduledTaskSettingsSet
    $D = New-ScheduledTask `
        -Action $A `
        -Principal $P `
        -Trigger $T `
        -Settings $S `
        -Description "Register Node with DSC Pull Server on Boot"
    $Task = Register-ScheduledTask $BootTaskName -InputObject $D
}

<#

# A function to remove the Boot Task

#>
function Remove-BootTask
{
    Unregister-ScheduledTask -TaskName $BootTaskName -Confirm:$false -ErrorAction SilentlyContinue
}

<#

# A function to ownload remote Archives

#>
function DownloadArchives {
    Write-Host "Downloading Remote Archives..."
    $Archives.GetEnumerator() | % {
        Write-Host "Downloading $($_.URI)"
        (New-Object System.Net.WebClient).DownloadFile($_.URI, $_.DestinationFile)
        Expand-Archive -Path $_.DestinationFile -DestinationPath $_.DestinationPath -Force
        Remove-Item $_.DestinationFile
    }
}


# Require Powershell 5.x - if we don't have it, let's install and reboot
if ($PSVersionTable.PSVersion.Major -lt 5) {
    Write-Host "PowerShell is not version 5.x!"
    Create-BootTask
    Install-WMF5
    Write-Host "Rebooting..."
    Restart-Computer -Force
}

# Get and unpack our archive files
DownloadArchives

# Set up the DSC Metaconfiguration as a string.
# We do this so that Powershell < 5.0 will not fail to parse this script.
$DscMetaConfig = @'
<#

Set up the LCM
@see https://azure.microsoft.com/en-gb/documentation/articles/automation-dsc-onboarding/#generating-dsc-metaconfigurations

#>
[DscLocalConfigurationManager()]
Configuration DscMetaConfig
{
    param
    (
        [Parameter(Mandatory=$True)]
        [String]$RegistrationUrl,

        [Parameter(Mandatory=$True)]
        [String]$RegistrationKey,

        [Parameter(Mandatory=$True)]
        [String[]]$ComputerName,

        [Parameter(Mandatory=$True)]
        [String]$NodeConfigurationName,

        [Int]$RefreshFrequencyMins = 30,

        [Int]$ConfigurationModeFrequencyMins = 15,

        [String]$ConfigurationMode = "ApplyAndAutoCorrect",

        [Boolean]$RebootNodeIfNeeded = $True,

        [String]$ActionAfterReboot = "ContinueConfiguration",

        [Boolean]$AllowModuleOverwrite = $True,

        [Boolean]$ReportOnly
    )

    $RefreshMode = "PULL"

    Node $ComputerName
    {
        Settings
        {
            RefreshFrequencyMins           = $RefreshFrequencyMins
            RefreshMode                    = $RefreshMode
            ConfigurationMode              = $ConfigurationMode
            AllowModuleOverwrite           = $AllowModuleOverwrite
            RebootNodeIfNeeded             = $RebootNodeIfNeeded
            ActionAfterReboot              = $ActionAfterReboot
            ConfigurationModeFrequencyMins = $ConfigurationModeFrequencyMins
        }
        ConfigurationRepositoryWeb AzureAutomationDSC
        {
            ServerUrl          = $RegistrationUrl
            RegistrationKey    = $RegistrationKey
            # As of July 2016, Azure Automation DSC does NOT support multiple
            # ConfigurationNames/'Partial' Configurations
            ConfigurationNames = @($NodeConfigurationName)
        }

        ResourceRepositoryWeb AzureAutomationDSC
        {
            ServerUrl       = $RegistrationUrl
            RegistrationKey = $RegistrationKey
        }

        ReportServerWeb AzureAutomationDSC
        {
            ServerUrl       = $RegistrationUrl
            RegistrationKey = $RegistrationKey
        }
    }
}
'@

# Load the DSC Metaconfiguration
Invoke-Expression $DscMetaConfig

# Create the metaconfigurations
# @see https://msdn.microsoft.com/en-us/powershell/dsc/metaconfig
$Params = @{
     RegistrationUrl                = $RegistrationUrl;
     RegistrationKey                = $RegistrationKey;
     ComputerName                   = @('localhost');
     NodeConfigurationName          = $NodeConfigurationName;
}

Write-Host ( $Params | Out-String )

# Use PowerShell splatting to pass parameters to the DSC configuration being invoked
# For more info about splatting, run: Get-Help -Name about_Splatting
DscMetaConfig @Params

# Apply the LCM configuration
Set-DscLocalConfigurationManager `
    -Verbose -Force -ErrorAction Stop `
    -Path .\DscMetaConfig

# Clean up
Remove-Item .\DscMetaConfig -recurse

# Remove the boot task
Remove-BootTask

Write-Host "Add Done!"
Stop-Transcript
