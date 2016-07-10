
$AutomationAccountName = "devops-ps"
$ResourceGroupName = "ps-test"

Import-AzureRmAutomationDscConfiguration `
    -AutomationAccountName $AutomationAccountName `
    -ResourceGroupName $ResourceGroupName `
    -Force -Verbose -Published `
    -SourcePath (Get-Item .\ExampleConfiguration.ps1).FullName

. .\ConfigurationData.ps1

$CompilationJob = Start-AzureRmAutomationDscCompilationJob `
    -AutomationAccountName $AutomationAccountName `
    -ResourceGroupName $ResourceGroupName `
    -ConfigurationData $ConfigData `
    -ConfigurationName "ExampleConfiguration"

while($CompilationJob.EndTime –eq $null -and $CompilationJob.Exception –eq $null)
{
    $CompilationJob = $CompilationJob | Get-AzureRmAutomationDscCompilationJob
    $CompilationJob
    Start-Sleep -Seconds 3
}

$CompilationJob | Get-AzureRmAutomationDscCompilationJobOutput –Stream Any
