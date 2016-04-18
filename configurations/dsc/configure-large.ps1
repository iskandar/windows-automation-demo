
$Dir = "C:\cloud-automation"
New-Item -Path $Dir\logs -ItemType Directory -ErrorAction SilentlyContinue
Start-Transcript -Path $Dir\logs\configure.log -Append

#Get-Content -Path C:\cloud-automation\logs\setup.log -Wait -Tail 10
#Get-Content -Path C:\cloud-automation\logs\configure.log -Wait -Tail 10

# Do some configuration
# @TODO Load from JSON or YAML
$ConfigurationData = @{
    AllNodes = @();
    NonNodeData = ""
}

$WebServerFeatures = @("Web-Mgmt-Console","Web-Mgmt-Service","Web-Default-Doc", `
                     "Web-Asp-Net45","Web-Dir-Browsing","Web-Http-Errors","Web-Static-Content",`
                     "Web-Http-Logging","Web-Stat-Compression","Web-Filtering",`
                     "Web-CGI","Web-ISAPI-Ext","Web-ISAPI-Filter")

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

$ChocoPackages = @(
    #"notepadplusplus.install",
    #"git.install",
    #"nodejs.install",
    #"googlechrome",
    #"windirstat"
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

$GitExe = "${env:ProgramFiles}\Git\bin\git.exe"
$GitConfig = "${env:ProgramData}\Git\config"

Configuration WebNode {
    Import-DscResource -ModuleName PSDesiredStateConfiguration
    Import-DscResource -ModuleName rsWPI,xWebAdministration,xTimeZone,cChoco,xWinEventLog
    Node localhost {

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

        # Set the timezone to UTC
        xTimeZone TZ {
            IsSingleInstance = 'Yes'
            TimeZone         = 'UTC'
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
            WindowsFeature "$Feature$Number"
            {
                Ensure     = "Present"
                Name       = $Feature
                DependsOn  = "[WindowsFeature]IIS"
            }
        }

        WindowsFeature MSMQ {
            Name   = "MSMQ"
            Ensure = "Present"
        }

        foreach ($Product in $WPIProducts) {
            rsWPI $Product.Name {
                Product    = $Product.Name
                DependsOn  = $Product.DependsOn
            }

            # 2016-04-17 IN: Seeing this on the first install attempt
            #[[rsWPI]WDeployPS] Installing WDeployPS
            #Unhandled Exception:
            #Unhandled Exception:
            #System.IO.IOException: The directory name is invalid.
        }

        # https://github.com/rsWinAutomationSupport/rsOctopusDSC
        File OctopusPath {
            Ensure = "Present"
            Type = "Directory"
            DestinationPath = "C:\Octopus"
        }
        # This causes a reboot!
        #Package OctopusTentacle{
        #    Name = "Octopus Deploy Tentacle"
        #    Ensure = "Present"
        #    Path = "https://download.octopusdeploy.com/octopus/Octopus.Tentacle.3.3.8-x64.msi"
        #    Arguments = "/quiet /l*v $($env:SystemDrive)\Octopus\Tentacle.msi.log"
        #    ProductId = ""
        #    DependsOn = @("[File]OctopusPath")
        #}

        cChocoInstaller installChoco {
            InstallDir = "C:\choco"
        }
        # Choco packages
        foreach ($Package in $ChocoPackages) {
            cChocoPackageInstaller $Package
            {
                Name      = $Package
                DependsOn = "[cChocoInstaller]installChoco"
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
        }

        <#

        Experimental Git installation, based on
        https://github.com/rsWinAutomationSupport/rsboot/blob/wmf4/boot.ps1#L236
        @TODO Update to look like this: https://github.com/rsWinAutomationSupport/DSCAutomation/blob/master/bootstrap/boot.ps1#L298

        This install method also seems to hang (just like the Choco install)

        Package InstallGit {
            # This may trigger a REBOOT!
            Name = 'Git version 2.8.1'
            Path = 'https://github.com/git-for-windows/git/releases/download/v2.8.1.windows.1/Git-2.8.1-64-bit.exe'
            ProductId = ''
            Arguments = '/verysilent'
            Ensure = 'Present'
        }

        Environment SetPath {
            Ensure = "Present"
            Name = "Path"
            Path = $true
            Value = "${env:ProgramFiles}\Git\bin\"
            DependsOn = '[Package]InstallGit'
        }

        Script UpdateGitConfig {
            SetScript =
@"
                Start-Process '$GitExe' -Wait -Verbose ``
                    -ArgumentList "config --system user.email `$env:COMPUTERNAME@localhost.local"
                Start-Process '$GitExe' -Wait -Verbose ``
                    -ArgumentList "config --system user.name `$env:COMPUTERNAME"
"@
            TestScript = "return [boolean]((Get-Content '$GitConfig') -match `$env:COMPUTERNAME)"
            GetScript = "return @{ Result = [boolean]((Get-Content '$GitConfig') -match `$env:COMPUTERNAME)"
            DependsOn = '[Environment]SetPath'
        }
        #>
    }
}

WebNode -ConfigurationData $ConfigurationData
Start-DscConfiguration -Path .\WebNode -Wait -Verbose -Force


Stop-Transcript