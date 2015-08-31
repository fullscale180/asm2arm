<#
    © 2015 Microsoft Corporation. All rights reserved. This sample code is not supported under any Microsoft standard support program or service. 
    This sample code is provided AS IS without warranty of any kind. Microsoft disclaims all implied warranties including, without limitation, 
    any implied warranties of merchantability or of fitness for a particular purpose. The entire risk arising out of the use or performance 
    of the sample code and documentation remains with you. In no event shall Microsoft, its authors, or anyone else involved in the creation, 
    production, or delivery of the scripts be liable for any damages whatsoever (including, without limitation, damages for loss of business 
    profits, business interruption, loss of business information, or other pecuniary loss) arising out of the use of or inability to use the 
    sample scripts or documentation, even if Microsoft has been advised of the possibility of such damages.
#>

function Get-ScriptDirectory
{
    $Invocation = (Get-Variable MyInvocation -Scope 1).Value
    Split-Path $Invocation.MyCommand.Path
}

$scriptDirectory = Get-ScriptDirectory

Set-ExecutionPolicy -Scope Process -ExecutionPolicy RemoteSigned -Force
 
$azureModulesPath = Join-Path ${env:ProgramFiles(x86)} -ChildPath "Microsoft SDKs\Azure\PowerShell"
if (Test-Path $azureModulesPath) {
       $armPath = Join-Path $azureModulesPath -ChildPath "ResourceManager"
       Write-Verbose ("Adding Azure Resource Manager module path {0} to the PSModulePath" -f $armPath)
       $env:PSModulePath = $env:PSModulePath + ";" + $armPath

       cd $scriptDirectory
       $env:PSModulePath = $env:PSModulePath + ";" + $scriptDirectory
}
else {
   throw "Please make sure Azure PowerShell module is installed."
}

Write-Verbose 'Azure Service Management and Resource Manager modules are now ready to service user commands'
