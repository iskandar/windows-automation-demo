<#

The minimal core bootstrap task.

* Designed for Windows Server 2012R2.
* Installs WMF5
* Sets up an 'on boot' task to run 'setup-shim.ps1'
* Reboots!

#>
$Dir = "C:\cloud-automation"
New-Item -Path $Dir\logs -ItemType Directory -ErrorAction SilentlyContinue
Start-Transcript -Path $Dir\logs\bootstrap.log -Append

$SetupShimFileName = "$Dir\setup-shim.ps1"

# Install WMF5 without rebooting
$WMF5FileName = "Win8.1AndW2K12R2-KB3134758-x64.msu"
$WMF5BaseURL = "https://download.microsoft.com/download/2/C/6/2C6E1B4A-EBE5-48A6-B225-2D2058A9CEFB"
$WMF5TempDir = "${Env:WinDir}\Temp"
function Install-WMF5 {
    (New-Object -TypeName System.Net.webclient).DownloadFile("${WMF5BaseURL}/${WMF5FileName}", "${WMF5TempDir}\${WMF5FileName}")
    Start-Process -Wait -FilePath "${WMF5TempDir}\${WMF5FileName}" -ArgumentList '/quiet /norestart' -Verbose
}

# Set up a boot task to call our setup-shim
function Create-BootTask {
    $TaskName = 'rsBoot'
    if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
        return
    }
    $A = New-ScheduledTaskAction `
        -Execute "PowerShell.exe" `
        -Argument "-ExecutionPolicy Bypass -File $SetupShimFileName"
    $T = New-ScheduledTaskTrigger -AtStartup
    $P = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount
    $S = New-ScheduledTaskSettingsSet
    $D = New-ScheduledTask `
        -Action $A `
        -Principal $P `
        -Trigger $T `
        -Settings $S `
        -Description "Rackspace Setup on Boot"
    Register-ScheduledTask $TaskName -InputObject $D
}


Create-BootTask
Install-WMF5
Stop-Transcript
Restart-Computer -Force