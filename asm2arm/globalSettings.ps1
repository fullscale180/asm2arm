<#
    © 2015 Microsoft Corporation. All rights reserved. This sample code is not supported under any Microsoft standard support program or service. 
    This sample code is provided AS IS without warranty of any kind. Microsoft disclaims all implied warranties including, without limitation, 
    any implied warranties of merchantability or of fitness for a particular purpose. The entire risk arising out of the use or performance 
    of the sample code and documentation remains with you. In no event shall Microsoft, its authors, or anyone else involved in the creation, 
    production, or delivery of the scripts be liable for any damages whatsoever (including, without limitation, damages for loss of business 
    profits, business interruption, loss of business information, or other pecuniary loss) arising out of the use of or inability to use the 
    sample scripts or documentation, even if Microsoft has been advised of the possibility of such damages.
#>

Set-StrictMode -Version 3

$Global:classicResourceApiVersion = "2015-06-01"
$Global:apiVersion = "2015-06-15"
$Global:previewApiVersion = "2015-05-01-preview"
$Global:asm2armVnetName = "armvnet"
$Global:asm2armSubnet = "armsubnet"
$Global:deploymentTag = "ASM to ARM migration"
$Global:armSuffix = "arm"
$Global:vhdContainerName = "vhds"
$Global:defaultAddressSpace = "10.0.0.0/18"
$Global:defaultSubnetAddressSpace = "10.0.0.0/22"