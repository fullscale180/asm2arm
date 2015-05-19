function Get-ScriptDirectory
{
    $Invocation = (Get-Variable MyInvocation -Scope 1).Value
    Split-Path $Invocation.MyCommand.Path
}

$asmModule = Get-Module -Name Azure -ErrorAction SilentlyContinue
$armModule = Get-Module -Name AzureResourceManager -ErrorAction SilentlyContinue

if ($asmModule -ne $null -and $armModule -eq $null)
{
    $modulePath = Join-Path $(Split-Path -Parent $(Split-Path -Parent $(Split-Path $asmModule.Path))) -ChildPath 'ServiceManagement\Azure\Azure.psd1'
    Import-Module $modulePath    
} elseif ($asmModule -eq $null -and $armModule -ne $null) {
    $modulePath = Join-Path $(Split-Path -Parent $(Split-Path -Parent $(Split-Path $asmModule.Path))) -ChildPath 'ResourceManager\AzureResourceManager\AzureResourceManager.psd1'
    Import-Module $modulePath    
} elseif ($asmModule -eq $null -and $armModule -eq $null) {
    $azureModulesPath = ${env:ProgramFiles(x86)} + '\\Microsoft SDKs\Azure\PowerShell'
    if (Test-Path $azureModulesPath) {
        Import-Module $(Join-Path $azureModulesPath -ChildPath 'ResourceManager\AzureResourceManager\AzureResourceManager.psd1')
        Import-Module $(Join-Path $azureModulesPath -ChildPath 'ServiceManagement\Azure\Azure.psd1')
    } else {
        throw "Azure Powershell Modules not found. Please install"
    }
}

if ($(Get-ExecutionPolicy) -eq "Restricted")
{
 # TODO: inform user to set execution policy? Or create a signed script...
}

$modulePath = Join-Path $(Get-ScriptDirectory) "asm2arm.psd1"
Import-Module $modulePath
