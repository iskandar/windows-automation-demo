# A list of IIS Features to install
 $WebServerFeatures = @("Web-Mgmt-Console","Web-Mgmt-Service","Web-Default-Doc", `
                      "Web-Asp-Net45","Web-Dir-Browsing","Web-Http-Errors","Web-Static-Content", `
                      "Web-Http-Logging","Web-Stat-Compression","Web-Filtering", `
                      "Web-ISAPI-Ext","Web-ISAPI-Filter")


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
    Import-DscResource -ModuleName xPSDesiredStateConfiguration
    Import-DscResource -ModuleName xTimeZone
    Import-DscResource -ModuleName xNetworking
    Import-DscResource -ModuleName xWinEventLog
    Import-DscResource -ModuleName xWebAdministration
    Import-DscResource -ModuleName xCertificate
    Import-DscResource -ModuleName cChoco

    # Get data from Azure Automation
    $TestCredential = Get-AutomationPSCredential -Name "TestCredential01"
    $LocalAdminCredential = Get-AutomationPSCredential -Name "LocalAdminCredential"
    $TestCertificate = Get-AutomationCertificate -Name "Test1"
    $TestVar02 = Get-AutomationVariable -Name "TestVar02"

    Node $AllNodes.NodeName {

        if ($Node.Roles -contains "Base") {
            # Set the timezone to UTC
            xTimeZone TZ {
                IsSingleInstance = 'Yes'
                TimeZone         = 'UTC'
            }

            ##
            # Networking: IP Addresses
            ##
            xNetAdapterBinding "DisableIPv6-Public" {
                InterfaceAlias = "public0"
                ComponentId    = "ms_tcpip6"
                State          = "Disabled"
            }
            xNetAdapterBinding "DisableIPv6-Private" {
                InterfaceAlias = "private0"
                ComponentId    = "ms_tcpip6"
                State          = "Disabled"
            }

            # Go through our loop
            for ($i = 0; $i -lt $Node.IPAddresses.length; $i++) {
                $Item = $Node.IPAddresses[$i];
                xIpAddress "NodeIp_$($i)" {
                    InterfaceAlias = $Item.InterfaceAlias
                    IPAddress      = $Item.IPAddress
                    SubnetMask     = $Item.SubnetMask
                }
            }

            ##
            # Networking: DNS
            ##
            xDnsServerAddress DNS_1 {
                Address        = $Node.DnsServer.Address
                InterfaceAlias = $Node.DnsServer.InterfaceAlias
                AddressFamily  = "IPv4"
            }

            ##
            # Networking: Default GW
            ##
            xDefaultGatewayAddress NetGw_1 {
                Address        = $Node.DefaultGateway.Address
                InterfaceAlias = $Node.DefaultGateway.InterfaceAlias
                AddressFamily  = "IPv4"
            }

            ##
            # Networking: FW Rules
            # @TODO Base: Disable all inbound
            ##


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

            ###
            # Users
            ###
            User TestUser01 {
                Ensure = "Present"
                UserName = $TestCredential.UserName
                Description = "Test User 01"
                Password = $TestCredential
                PasswordChangeRequired = $false
                PasswordNeverExpires = $true
            }
            Group TestUser01GroupBUILTIN_ADMINISTRATORS {
                # Ugh, see http://stackoverflow.com/questions/26555051/add-user-to-default-users-group
                # And see https://msdn.microsoft.com/en-us/library/cc980032.aspx
                # We could just use 'Users' or 'Administrators', but this is a locale-dependent name
                GroupName = "S-1-5-32-544"
                Ensure = "Present"
                MembersToInclude = $TestCredential.UserName
                Credential = $LocalAdminCredential
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
                Contents = "Static file content from configure.ps1"
            }
            File TestFile2 {
                Ensure = "Present"
                Type = "File"
                DestinationPath = "C:\cloud-automation\TestFile2.txt"
                # Dynamic data from a Azure Automation Variable asset
                Contents = $TestVar02
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

            ##
            # Certificates
            ##
            #xPfxImport
            #{
            #    Thumbprint = 'c81b94933420221a7ac004a90242d8b1d3e5070d'
            #    Path = '\\Server\Share\Certificates\CompanyCert.pfx'
            #    Credential = $PfxPassword
            #}

        }


        if ($Node.Roles -contains "WebServer") {
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
        }

        if ($Node.Roles -contains "ServiceServer") {


        }
    }
}