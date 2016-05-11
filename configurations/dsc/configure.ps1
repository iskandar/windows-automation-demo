
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

#>
Configuration LCMConfig {
    LocalConfigurationManager {
        CertificateID = (Get-ChildItem Cert:\LocalMachine\My)[0].Thumbprint
        AllowModuleOverwrite = $true
        ConfigurationModeFrequencyMins = 30
        ConfigurationMode = 'ApplyAndAutoCorrect'
        RebootNodeIfNeeded = $false
        RefreshMode = 'PUSH'
        RefreshFrequencyMins = 30
        DebugMode = 'ForceModuleImport'
    }
}

LCMConfig
Set-DscLocalConfigurationManager -Path .\LCMConfig -Verbose -Force


Stop-Transcript