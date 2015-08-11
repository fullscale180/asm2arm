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

function New-ClassicStorageAccountResource
{
    Param
    (
        $Name,
        $Location
    )

    $createProperties = @{"accountType" = "Standard-LRS";}
    $resource = New-ResourceTemplate -Type "Microsoft.ClassicStorage/storageAccounts" -Name $Name `
        -Location $Location -ApiVersion $Global:classicResourceApiVersion -Properties $createProperties

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
        $storageAccountExists = Azure\Test-AzureName -Storage $storageAccountName

        if ($storageAccountExists)
        {
            # Get-AzureStorageAccount -Name <name> always returns all of the V2 storage accounts on the subscription
            # at this time. Use a workaround to bring the accounts to an array and check instead.
            $storageAccounts = AzureResourceManager\Get-AzureStorageAccount 
            $existingStorageAccount = $storageAccounts | Where-Object {$_.Name -eq $storageAccountName}
        
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