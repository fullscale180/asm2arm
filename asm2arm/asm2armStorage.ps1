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