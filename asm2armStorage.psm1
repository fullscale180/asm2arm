function New-StorageAccountResource
{
    Param
    (
        $Name,
        $Location
    )

    $createProperties = New-Object -TypeName PSCustomObject @{"accountType" = "Standard_LRS";}
    $resource = New-ResourceTemplate -Type "Microsoft.Storage/storageAccounts" -Name $Name `
        -Location $Location -ApiVersion $Global:apiVersion -Properties $createProperties

    return $resource
}

function New-ClassicStorageAccountResource
{
    Param
    (
        $Name,
        $Location
    )

    $createProperties = New-Object -TypeName PSCustomObject @{"accountType" = "Standard-LRS";}
    $resource = New-ResourceTemplate -Type "Microsoft.ClassicStorage/storageAccounts" -Name $Name `
        -Location $Location -ApiVersion $Global:classicResourceApiVersion -Properties $createProperties

    return $resource
}