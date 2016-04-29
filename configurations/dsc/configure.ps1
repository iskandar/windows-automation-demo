
$Dir = "C:\cloud-automation"
New-Item -Path $Dir\logs -ItemType Directory -ErrorAction SilentlyContinue
Start-Transcript -Path $Dir\logs\configure.log -Append

# Load our bootstrap config
$BootstrapConfig = (Get-Content $Dir\bootstrap-config.json) -join "`n" | ConvertFrom-Json

# @TODO Load from JSON or YAML
$ConfigurationData = @{
    AllNodes = @();
    NonNodeData = ""
}

$WebServerFeatures = @("Web-Mgmt-Console","Web-Mgmt-Service","Web-Default-Doc", `
                     "Web-Asp-Net45","Web-Dir-Browsing","Web-Http-Errors","Web-Static-Content", `
                     "Web-Http-Logging","Web-Stat-Compression","Web-Filtering", `
                     "Web-ISAPI-Ext","Web-ISAPI-Filter")

$WPIProducts = @(
    # WebDeploy for powershell, needed to allow remote WebDeploy-based deployments
    @{
        Name = "WDeployPS"
        DependsOn = "[WindowsFeature]IIS"
    }
)

$WebApplications = @(
    @{
        Name = "WebApplication1"
        PhysicalPath = "C:\Applications\WebApplication1"
    }
)

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


<#

Do our main config

#>

Configuration WebNode {
    Import-DscResource -ModuleName PSDesiredStateConfiguration
    Import-DscResource -ModuleName rsWPI,xWebAdministration,xTimeZone,xWinEventLog
    Node localhost {

        # Set the timezone to UTC
        xTimeZone TZ {
            IsSingleInstance = 'Yes'
            TimeZone         = 'UTC'
        }

        # Enable DSC Analytic and Debug Event Logs
        #wevtutil.exe set-log "Microsoft-Windows-Dsc/Analytic" /q:true /e:true
        #wevtutil.exe set-log "Microsoft-Windows-Dsc/Debug" /q:True /e:true
        xWinEventLog DSCAnalytic {
            LogName            = "Microsoft-Windows-Dsc/Analytic"
            IsEnabled          = $true
            # Changing the properties below is wonky and can cause various errors like
            # "The requested operation cannot be performed over
            #  an enabled direct channel. The channel must first be disabled before performing the requested operation"
            #LogMode            = "Circular"
            #MaximumSizeInBytes = 5mb
            #LogFilePath        = "C:\cloud-automation\logs\Dsc-Analytic.evtx"
        }
        xWinEventLog DSCDebug {
            LogName            = "Microsoft-Windows-Dsc/Debug"
            IsEnabled          = $true
            #LogMode            = "Circular"
            #MaximumSizeInBytes = 5mb
            #LogFilePath        = "C:\cloud-automation\logs\Dsc-Debug.evtx"
        }

        # Install the IIS role
        WindowsFeature IIS {
            Ensure          = "Present"
            Name            = "Web-Server"
        }

        # Stop the default website
        xWebsite DefaultSite {
            Ensure          = "Present"
            Name            = "Default Web Site"
            State           = "Stopped"
            DependsOn       = "[WindowsFeature]IIS"
        }

        # IIS and related features
        foreach ($Feature in $WebServerFeatures) {
            WindowsFeature "$Feature$Number" {
                Ensure     = "Present"
                Name       = $Feature
                DependsOn  = "[WindowsFeature]IIS"
            }
            Log "$Feature$Number-Log" {
                Message = "Finished adding WindowsFeature $Feature$Number"
                DependsOn = "[WindowsFeature]$Feature$Number"
            }
        }

        foreach ($Product in $WPIProducts) {
            rsWPI $Product.Name {
                Product    = $Product.Name
                DependsOn  = $Product.DependsOn
            }
            Log "$($Product.Name)-Log" {
                Message = "Finished adding WPI Product $($Product.Name)"
                DependsOn = "[rsWPI]$($Product.Name)"
            }
        }

        foreach ($App in $WebApplications) {
            # Set up our demo WebApplication for IIS
            File "$($App.Name)-Root" {
                DestinationPath = $App.PhysicalPath
                Type            = "Directory"
                Ensure          = "Present"
            }
            xWebAppPool "$($App.Name)-Pool" {
                Name      = "$($App.Name)-Pool"
                Ensure    = "Present"
                State     = "Started"
                startMode = "AlwaysRunning"
                DependsOn = "[WindowsFeature]IIS"
            }
            xWebsite "$($App.Name)-Site" {
                Name            = $App.Name
                PhysicalPath    = $App.PhysicalPath
                ApplicationPool = "$($App.Name)-Pool"
                State           = "Started"
                Ensure          = "Present"
                DependsOn       = "[WindowsFeature]IIS"
            }
            Log "$($App.Name)-Log" {
                # The message below gets written to the Microsoft-Windows-Desired State Configuration/Analytic log
                Message = "Finished configuring IIS for $($App.Name) ($($App.PhysicalPath))"
                DependsOn = "[xWebsite]$($App.Name)-Site"
            }
        }

        Environment BootstrapTypeEnvironmentVariable {
            Name   = "BootstrapType"
            Value  = $BootstrapConfig.bootstrap_type
            Ensure = "Present"
        }

        Registry KeyOne {
            Ensure    = "Present"  # You can also set Ensure to "Absent"
            Key       = "HKEY_LOCAL_MACHINE\SOFTWARE\WindowsAutomationDemo"
            ValueName = "ExampleValue"
            ValueData = "ExampleData"
            Force     = $true
        }

        Group GroupExample {
             # This will remove TestGroup, if present
             # To create a new group, set Ensure to "Present“
             Ensure = "Absent"
             GroupName = "TestGroup"
         }
    }
}

WebNode -ConfigurationData $ConfigurationData
Start-DscConfiguration -Path .\WebNode -Wait -Verbose -Force


Stop-Transcript