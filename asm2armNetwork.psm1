function New-VirtualNetworkResource
{
    Param
    (
        $Name,
        $Location,
        [string[]]
        $addressSpacePrefixes,
        [PSCustomObject[]]
        $subnets
    )

    $addressSpace = New-Object -TypeName PSCustomObject @{'addressPrefixes' = $addressSpacePrefixes;}

    $createProperties = New-Object -TypeName PSCustomObject @{"addressSpace" = $addressSpace; 'subnets'= $subnets;}

    $resource = New-ResourceTemplate -Type "Microsoft.Network/virtualNetworks" -Name $Name `
        -Location $Location -ApiVersion $Global:apiVersion-Properties $createProperties

    return $resource
}


function New-VirtualNetworkSubnet
{
    Param
    (
        $Name,
        $addressPrefix,
        $networkSecurityGroup
    )

    $properties = @{'addressPrefix' = $addressPrefix}
    if ($networkSecurityGroup)
    {
        $properties.Add('networkSecurityGroup', @{'id' = $networkSecurityGroup})
    }

    $subnet = @{'name' = $Name; 'properties' = $properties}
    
    return New-Object -TypeName PSCustomObject $subnet
}

