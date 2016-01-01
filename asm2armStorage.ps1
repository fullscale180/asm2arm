<#
    © 2015 Microsoft Corporation. All rights reserved. This sample code is not supported under any Microsoft standard support program or service. 
    This sample code is provided AS IS without warranty of any kind. Microsoft disclaims all implied warranties including, without limitation, 
    any implied warranties of merchantability or of fitness for a particular purpose. The entire risk arising out of the use or performance 
    of the sample code and documentation remains with you. In no event shall Microsoft, its authors, or anyone else involved in the creation, 
    production, or delivery of the scripts be liable for any damages whatsoever (including, without limitation, damages for loss of business 
    profits, business interruption, loss of business information, or other pecuniary loss) arising out of the use of or inability to use the 
    sample scripts or documentation, even if Microsoft has been advised of the possibility of such damages.
#>

function New-StorageAccountResource
{
    Param
    (
        $Name,
        $Location,
        $storageAccountType
    )

    $createProperties = @{"accountType" = $storageAccountType;}
    $resource = New-ResourceTemplate -Type "Microsoft.Storage/storageAccounts" -Name $Name `
        -Location $Location -ApiVersion $Global:previewApiVersion -Properties $createProperties

    return $resource
}

function Get-StorageAccountName
{
    [OutputType([string])]
    Param
    (
        $NamePrefix,
        $Location
    )

    # Decide if we need to create a storage account
    $storageAccountName = $NamePrefix.Substring(0,[math]::Min(20, $NamePrefix.Length-1)) + 'arm'

    $storageAccountExists = $false

    $retryStorageAccountName = $true
    $index = 0

    do
    {
        $storageAccountExists = Test-AzureName -Storage $storageAccountName

        if ($storageAccountExists)
        {
            # Get-AzureStorageAccount -Name <name> always returns all of the V2 storage accounts on the subscription
            # at this time. Use a workaround to bring the accounts to an array and check instead.
            $storageAccounts = Get-AzureRmStorageAccount 
            $existingStorageAccount = $storageAccounts | Where-Object {$_.StorageAccountName -eq $storageAccountName}
        
            if ($existingStorageAccount)
            {
                # If we are here, this is a storage account on this subscription, and using V2
                $retryStorageAccountName = ($existingStorageAccount.Location -ne $Location)
            } 
            else
            {
                # If we are here, that means, storage account exists but some other subscription has it
                $retryStorageAccountName = $true            
            }

            if ($retryStorageAccountName)
            {
                $storageAccountName = "{0}{1:00}arm" -f $NamePrefix.Substring(0,[math]::Min(18, $NamePrefix.Length-1)), $index++
            }
        }
        else
        {
            $retryStorageAccountName = $false
        }
    }
    until (-not $retryStorageAccountName)

    return $storageAccountName
}

function Get-NewBlobLocation
{
    [OutputType([string])]
    Param(
        [string]
        $SourceBlobUri,
        [string]
        $StorageAccountName,
        [string]
        $ContainerName
    )

    $accName, $dnsNameParts = ([System.Uri]$SourceBlobUri).Host.Split('.')
    $root, $container, $blobName = ([System.Uri]$SourceBlobUri).Segments
    $destBlob = $blobName -join ""
    $hostName = $dnsNameParts -join "."

    return  "{0}://{1}.{2}/{3}/{4}" -f ([System.Uri]$SourceBlobUri).Scheme, $StorageAccountName, $hostName, $ContainerName, $destBlob
}