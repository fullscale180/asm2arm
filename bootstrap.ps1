<#
    © 2015 Microsoft Corporation. All rights reserved. This sample code is not supported under any Microsoft standard support program or service. 
    This sample code is provided AS IS without warranty of any kind. Microsoft disclaims all implied warranties including, without limitation, 
    any implied warranties of merchantability or of fitness for a particular purpose. The entire risk arising out of the use or performance 
    of the sample code and documentation remains with you. In no event shall Microsoft, its authors, or anyone else involved in the creation, 
    production, or delivery of the scripts be liable for any damages whatsoever (including, without limitation, damages for loss of business 
    profits, business interruption, loss of business information, or other pecuniary loss) arising out of the use of or inability to use the 
    sample scripts or documentation, even if Microsoft has been advised of the possibility of such damages.
#>

#requires -module azure

# Support advanced function behavior, for -Verbose flag.
[CmdletBinding()]
param()

<#
The following section exists with a special purpose, that is for being able to load the two required Azure modules (Service Management and Resource Manager) together.
Azure PowerShell module installer does not modify the PSModulePath variable. Using this part of the code, we are adding the location of both ARM and ASM modules to the path. 
Just using #requires will not bring in the AzureResourceManager module in but will make sure the module is installed.
#>
$armPath = Join-Path ${env:ProgramFiles(x86)} -ChildPath "Microsoft SDKs\Azure\PowerShell\ResourceManager"
Write-Verbose ("Adding Azure Resource Manager module path {0} to the PSModulePath environment variable" -f $armPath)
$env:PSModulePath = $env:PSModulePath + ";" + $armPath

Import-Module (Join-Path $PSScriptRoot -ChildPath 'asm2arm')

Write-Verbose 'Azure Service Management and Resource Manager modules are now ready to service user commands'