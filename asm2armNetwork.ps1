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

    $addressSpace = [PSCustomObject] @{'addressPrefixes' = $AddressSpacePrefixes;}

    $createProperties = [PSCustomObject] @{"addressSpace" = $addressSpace; 'subnets'= $subnets;}

    $resource = New-ResourceTemplate -Type "Microsoft.Network/virtualNetworks" -Name $Name `
        -Location $Location -ApiVersion $Global:apiVersion -Properties $createProperties

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

    $subnet = @{'name' = $Name; 'properties' = [PSCustomObject] $properties}
    
    return [PSCustomObject] $subnet
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
    
    $publicIPAddress = [PSCustomObject] @{'id' = '[resourceId(''Microsoft.Network/publicIPAddresses'',''{0}'')]' -f $PublicIpAddressName;}
    $subnet = [PSCustomObject] @{'id' = $SubnetReference;}

    $ipConfigurations = [PSCustomObject] @{ `
        'privateIPAllocationMethod' = "Dynamic"; `
        'publicIPAddress' = $publicIPAddress; `
        'subnet' = $subnet;}

    $ipConfigName = "{0}_config1" -f $Name

    $createProperties = [PSCustomObject] @{'ipConfigurations' =  @([PSCustomObject] @{'name' =  $ipConfigName; 'properties' = $ipConfigurations;})}

    $resource = New-ResourceTemplate -Type "Microsoft.Network/networkInterfaces" -Name $Name `
        -Location $Location -ApiVersion $Global:apiVersion -Properties $createProperties -DependsOn $Dependecies

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
    
    $dnsSettings = [PSCustomObject] @{'domainNameLabel' = $DnsName}
    
    $createProperties = [PSCustomObject] @{'publicIPAllocationMethod' = $AllocationMethod; 'dnsSettings' = $dnsSettings}

    $resource = New-ResourceTemplate -Type "Microsoft.Network/publicIPAddresses" -Name $Name `
        -Location $Location -ApiVersion $Global:apiVersion -Properties $createProperties

    return $resource
}