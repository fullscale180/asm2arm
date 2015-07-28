 function Get-ScriptDirectory
{
    $Invocation = (Get-Variable MyInvocation -Scope 1).Value
    Split-Path $Invocation.MyCommand.Path
}

$scriptDirectory = Get-ScriptDirectory

Set-ExecutionPolicy -Scope Process Undefined -Force
if ($(Get-ExecutionPolicy) -eq "Restricted")
{
    # TODO: inform user to set execution policy? Or create a signed script...
    Set-ExecutionPolicy -Scope Process -ExecutionPolicy RemoteSigned -Force
}
 
$azureModulesPath = Join-Path ${env:ProgramFiles(x86)} -ChildPath "Microsoft SDKs\Azure\PowerShell"
if (Test-Path $azureModulesPath) {
       $armPath = Join-Path $azureModulesPath -ChildPath "ResourceManager"
       Write-Output ("Adding Azure Resource Manager module path {0} to the PSModulePath" -f $armPath)
       $env:PSModulePath = $env:PSModulePath + ";" + $armPath

       cd $scriptDirectory
       $env:PSModulePath = $env:PSModulePath + ";" + $scriptDirectory
}
else {
   throw "Please make sure Azure PowerShell module is installed."
}

Write-Output 'Azure Service Management and Resource Manager modules are now ready to service user commands'
