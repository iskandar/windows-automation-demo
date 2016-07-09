
$Dir = "C:\cloud-automation"
New-Item -Path $Dir\logs -ItemType Directory -ErrorAction SilentlyContinue
Start-Transcript -Path $Dir\logs\configure.log -Append

# Load our bootstrap config
$BootstrapConfig = (Get-Content $Dir\bootstrap-config.json) -join "`n" | ConvertFrom-Json

# Load our setup config
$SetupFile = "$Dir\setup.json"
$SetupConfig = (Get-Content $SetupFile) -join "`n" | ConvertFrom-Json

<#

Set up the LCM
@see https://azure.microsoft.com/en-gb/documentation/articles/automation-dsc-onboarding/#generating-dsc-metaconfigurations

#>
[DscLocalConfigurationManager()]
Configuration DscMetaConfigs
{
    param
    (
        [Parameter(Mandatory=$True)]
        [String]$RegistrationUrl,

        [Parameter(Mandatory=$True)]
        [String]$RegistrationKey,

        [Parameter(Mandatory=$True)]
        [String[]]$ComputerName,

        [Int]$RefreshFrequencyMins = 30,

        [Int]$ConfigurationModeFrequencyMins = 15,

        [String]$ConfigurationMode = "ApplyAndMonitor",

        [String]$NodeConfigurationName,

        [Boolean]$RebootNodeIfNeeded= $False,

        [String]$ActionAfterReboot = "ContinueConfiguration",

        [Boolean]$AllowModuleOverwrite = $False,

        [Boolean]$ReportOnly
    )

    if (!$NodeConfigurationName -or $NodeConfigurationName -eq "") {
        $ConfigurationNames = $null
    } else {
        $ConfigurationNames = @($NodeConfigurationName)
    }

    if ($ReportOnly) {
       $RefreshMode = "PUSH"
    } else {
       $RefreshMode = "PULL"
    }

    Node $ComputerName
    {
        Settings
        {
            RefreshFrequencyMins = $RefreshFrequencyMins
            RefreshMode = $RefreshMode
            ConfigurationMode = $ConfigurationMode
            AllowModuleOverwrite  = $AllowModuleOverwrite
            RebootNodeIfNeeded = $RebootNodeIfNeeded
            ActionAfterReboot = $ActionAfterReboot
            ConfigurationModeFrequencyMins = $ConfigurationModeFrequencyMins
        }

        if(!$ReportOnly)
        {
           ConfigurationRepositoryWeb AzureAutomationDSC
            {
                ServerUrl = $RegistrationUrl
                RegistrationKey = $RegistrationKey
                ConfigurationNames = $ConfigurationNames
            }

            ResourceRepositoryWeb AzureAutomationDSC
            {
               ServerUrl = $RegistrationUrl
               RegistrationKey = $RegistrationKey
            }
        }

        ReportServerWeb AzureAutomationDSC
        {
            ServerUrl = $RegistrationUrl
            RegistrationKey = $RegistrationKey
        }
    }
}

# Create the metaconfigurations
$Params = @{
     RegistrationUrl = $BootstrapConfig.aa_dsc_reg_url;
     RegistrationKey = $BootstrapConfig.aa_dsc_reg_key;
     ComputerName = @('localhost');
     #NodeConfigurationName = $SetupConfig.Data.NodeConfigurationName;
     # We're going to use a node configuration for EACH host
     NodeConfigurationName ="$($SetupConfig.Data.NodeBaseConfigurationName).$($env:COMPUTERNAME)"
     RefreshFrequencyMins = 30;
     ConfigurationModeFrequencyMins = 15;
     RebootNodeIfNeeded = $False;
     AllowModuleOverwrite = $True;
     ConfigurationMode = 'ApplyAndAutoCorrect';
     ActionAfterReboot = 'ContinueConfiguration';
     ReportOnly = $False;  # Set to $True to have machines only report to AA DSC but not pull from it
}

# Use PowerShell splatting to pass parameters to the DSC configuration being invoked
# For more info about splatting, run: Get-Help -Name about_Splatting
DscMetaConfigs @Params

# Apply the LCM configuration
Set-DscLocalConfigurationManager -Path .\DscMetaConfigs -Verbose -Force

Stop-Transcript