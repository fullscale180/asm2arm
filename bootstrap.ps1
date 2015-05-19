function Get-ScriptDirectory
{
    $Invocation = (Get-Variable MyInvocation -Scope 1).Value
    Split-Path $Invocation.MyCommand.Path
}

# Trick to load in the Azure module
$preference = $ErrorActionPreference
$ErrorActionPreference = "SilentlyContinue"
Get-AzureAccount | Out-Null
# Restore error action preference
$ErrorActionPreference = $preference

$asmModule = Get-Module -Name Azure -ErrorAction SilentlyContinue
$armModule = Get-Module -Name AzureResourceManager -ErrorAction SilentlyContinue
$scriptDirectory = Get-ScriptDirectory

if ($asmModule -eq $null -and $armModule -ne $null)
{
    $asmPath = Join-Path $(Split-Path -Parent $(Split-Path -Parent $(Split-Path $armModule.Path))) -ChildPath "ServiceManagement\Azure\Services"
    cd $asmPath
    Import-Module $(Join-Path $asmPath -ChildPath "Azure.psd1")
} elseif ($asmModule -ne $null -and $armModule -eq $null) {
    $modulePath = Join-Path $(Split-Path -Parent $(Split-Path -Parent $(Split-Path $asmModule.Path))) -ChildPath "ResourceManager\AzureResourceManager\AzureResourceManager.psd1"
    Import-Module $modulePath    
} elseif ($asmModule -eq $null -and $armModule -eq $null) {
    $azureModulesPath = Join-Path ${env:ProgramFiles(x86)} -ChildPath "Microsoft SDKs\Azure\PowerShell"
    if (Test-Path $azureModulesPath) {
        Import-Module $(Join-Path $azureModulesPath -ChildPath "ResourceManager\AzureResourceManager\AzureResourceManager.psd1")
        $asmPath = Join-Path $azureModulesPath -ChildPath "ServiceManagement\Azure"
        cd $asmPath
        Import-Module $(Join-Path $asmPath -ChildPath "Azure.psd1")
    } else {
        throw "Azure Powershell Modules not found. Please install"
    }
}

cd $scriptDirectory

if ($(Get-ExecutionPolicy) -eq "Restricted")
{
 # TODO: inform user to set execution policy? Or create a signed script...
}

$modulePath = Join-Path $scriptDirectory "asm2arm.psd1"
Import-Module $modulePath
