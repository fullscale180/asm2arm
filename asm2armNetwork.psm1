function New-VirtualNetworkResource
{
    Param
    (
        $Name,
        $Location,
        [string[]]
        $AddressSpacePrefixes,
        [PSCustomObject[]]
        $Subnets
    )

    $addressSpace = New-Object -TypeName PSCustomObject @{'addressPrefixes' = $AddressSpacePrefixes;}

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
        $AddressPrefix,
        $NetworkSecurityGroup
    )

    $properties = @{'addressPrefix' = $addressPrefix}
    if ($networkSecurityGroup)
    {
        $properties.Add('networkSecurityGroup', @{'id' = $networkSecurityGroup})
    }

    $subnet = @{'name' = $Name; 'properties' = $properties}
    
    return New-Object -TypeName PSCustomObject $subnet
}

function New-NetworkInterfaceResource
{
    Param
    (
        $Name,
        $Location,
        [string]
        $SubnetReference,
        [string]
        $PublicIpAddressName,
        [string[]]
        $Dependecies
    )
    
    $publicIPAddress = New-Object -TypeName PSCustomObject @{'id' = '[resourceId(''Microsoft.Network/publicIPAddresses'',''{0}'')]' -f $PublicAddressName;}
    $subnet = New-Object -TypeName PSCustomObject @{'id' = $SubnetReference;}

    $ipConfigurations = New-Object -TypeName PSCustomObject @{ `
        'privateIPAllocationMethod' = "Dynamic"; `
        'publicIPAddress' = $publicIPAddress; `
        'subnet' = $subnet;}
    $createProperties = New-Object -TypeName PSCustomObject @{'ipConfigurations' = $ipConfigurations;}

    $resource = New-ResourceTemplate -Type "Microsoft.Network/networkInterfaces" -Name $Name `
        -Location $Location -ApiVersion $Global:apiVersion-Properties $createProperties

    return $resource
}

function New-PublicIpAddressResource
{
    Param
    (
        $Name,
        $Location,
        [string]
        $AllocationMethod,
        [string]
        $DnsName
    )
    
    $dnsSettings = New-Object -TypeName PSCustomObject @{'domainNameLabel' = $DnsName}
    
    $createProperties = New-Object -TypeName PSCustomObject @{'publicIPAllocationMethod' = $AllocationMethod; 'dnsSettings' = $dnsSettings}

    $resource = New-ResourceTemplate -Type "Microsoft.Network/publicIPAddresses" -Name $Name `
        -Location $Location -ApiVersion $Global:apiVersion-Properties $createProperties

    return $resource
}