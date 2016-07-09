
# DSC Configuration Data
$ConfigurationData = @{
    AllNodes = @();
    NonNodeData = ""
}

# A list of IIS Features to install
$WebServerFeatures = @("Web-Mgmt-Console","Web-Mgmt-Service","Web-Default-Doc", `
                     "Web-Asp-Net45","Web-Dir-Browsing","Web-Http-Errors","Web-Static-Content", `
                     "Web-Http-Logging","Web-Stat-Compression","Web-Filtering", `
                     "Web-ISAPI-Ext","Web-ISAPI-Filter")

# A list of Web Platform Installer products to install
$WPIProducts = @(
    # WebDeploy for powershell, needed to allow remote WebDeploy-based deployments
    @{
        Name = "WDeployPS"
        DependsOn = "[WindowsFeature]IIS"
    },
    @{
        Name = "UrlRewrite2"
        DependsOn = "[WindowsFeature]IIS"
    }
)

# A list of Web Applications to set up
$WebApplications = @(
    @{
        Name = "WebApplication1"
        PhysicalPath = "C:\Applications\WebApplication1"
    }
    #,@{
    #    Name = "WebApplication2"
    #    PhysicalPath = "C:\Applications\WebApplication2"
    #}
)

<#

Do our main config

#>

Configuration ExampleConfiguration {
    Import-DscResource -ModuleName PSDesiredStateConfiguration
    Import-DscResource -ModuleName rsWPI,xWebAdministration,xTimeZone,xWinEventLog,cChoco
    Node WebNode {

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

        # IIS-related features
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

        # Web Platform installer products
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

        # Remove the default website
        xWebsite DefaultSite {
            Ensure          = "Absent"
            Name            = "Default Web Site"
            PhysicalPath    = "C:\inetpub\wwwroot"
            State           = "Stopped"
            DependsOn       = "[WindowsFeature]IIS"
        }

        # Set up our WebApplications in IIS
        foreach ($App in $WebApplications) {
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

        # Install MSMQ
        #WindowsFeature MSMQ {
        #    Ensure          = "Present"
        #    Name            = "MSMQ"
        #}

        ###
        # Chocolatey installer
        ###
        cChocoInstaller installChoco {
            InstallDir = "C:\choco"
        }

        ###
        # Environment Variables
        ##
        Environment BootstrapTypeEnvironmentVariable {
            Name   = "BootstrapType"
            # @TODO Dynamic value from our AA DSC data
            Value  = "STATIC"
            Ensure = "Present"
        }

        ###
        # Files
        ###
        File TestFile1 {
            Ensure = "Present"  # You can also set Ensure to "Absent"
            Type = "File" # Default is "File".
            DestinationPath = "C:\cloud-automation\TestFile1.txt"
            # @TODO Dynamic value from our AA DSC data
            Contents = "STATIC"
        }
        File TestFile2 {
            Ensure = "Present"
            Type = "File"
            DestinationPath = "C:\cloud-automation\TestFile2.txt"
            Contents = "Static file content from configure.ps1"
        }

        ###
        # Registry Keys
        ###
        Registry KeyOne {
            Ensure    = "Present"  # You can also set Ensure to "Absent"
            Key       = "HKEY_LOCAL_MACHINE\SOFTWARE\WindowsAutomationDemo\Settings"
            ValueName = "Value1"
            # @TODO Dynamic value from our AA DSC data
            ValueData = "STATIC"
            Force     = $true
        }
        Registry KeyTwo {
            Ensure    = "Present"  # You can also set Ensure to "Absent"
            Key       = "HKEY_LOCAL_MACHINE\SOFTWARE\WindowsAutomationDemo\Settings"
            ValueName = "Value2"
            ValueData = "Value from configure.ps1"
            Force     = $true
        }
        Registry KeyThree {
            Ensure    = "Absent"
            Key       = "HKEY_LOCAL_MACHINE\SOFTWARE\WindowsAutomationDemo\Settings"
            ValueName = "Value3"
            ValueData = "ExampleData3"
            Force     = $true
        }

        ###
        # Groups
        ###
        Group GroupPresentExample {
             # This will create TestGroup1, if absent
             Ensure = "Present"
             GroupName = "TestGroup1"
        }
        Group GroupAbsentExample {
             # This will remove TestGroup2, if present
             Ensure = "Absent"
             GroupName = "TestGroup2"
        }
    }
}