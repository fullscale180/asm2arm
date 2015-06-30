<#
.Synopsis
   Retrieve the ARM Image reference for a given ASM image
.DESCRIPTION
   Do a search on the ARM image catalog, based on the input ASM VM Image.
.EXAMPLE
   Get-AzureArmImageRef -Location $vm.$location -Image $vmImage
#>
function Get-AzureArmImageRef
{
    [CmdletBinding()]
    Param
    (
        # Location to search the image reference in
        [Parameter(Mandatory=$true)]
        $Location,

        # Param2 help description
        [Microsoft.WindowsAzure.Commands.ServiceManagement.Model.OSImageContext]
        $Image
    )

    $asmToArmPublishersMap = @{
        "Barracuda Networks, Inc." = "barracudanetworks";
        "Bitnami" = "";
        "Canonical" = "Canonical";
        "Cloudera" = "cloudera";
        "CoreOS" = "CoreOS";
        "DataStax" = "datastax";
        "GitHub, Inc." = "GitHub";
        "Hortonworks" = "hortonworks";
        "Microsoft Azure Site Recovery group" = "MicrosoftAzureSiteRecovery";
        "Microsoft BizTalk Server Group" = "MicrosoftBizTalkServer";
        "Microsoft Dynamics AX" = "MicrosoftDynamicsAX";
        "Microsoft Dynamics GP Group" = "MicrosoftDynamicsGP";
        "Microsoft Dynamics NAV Group" = "MicrosoftDynamicsNAV";
        "Microsoft Hybrid Cloud Storage Group" = "MicrosoftHybridCloudStorage";
        "Microsoft Open Technologies, Inc." = "msopentech";
        "Microsoft SharePoint Group" = "MicrosoftSharePoint";
        "Microsoft SQL Server Group" = "MicrosoftSQLServer";
        "Microsoft Visual Studio Group" = "MicrosoftVisualStudio";
        "Microsoft Windows Server Essentials Group" = "MicrosoftWindowsServerEssentials";
        "Microsoft Windows Server Group" = "MicrosoftWindowsServer";
        "Microsoft Windows Server HPC Pack team" = "MicrosoftWindowsServerHPCPack";
        "Microsoft Windows Server Remote Desktop Group" = "MicrosoftWindowsServerRemoteDesktop";
        "OpenLogic" = "OpenLogic";
        "Oracle" = "Oracle";
        "Puppet Labs" = "PuppetLabs";
        "RightScale with Linux" = "RightScaleLinux";
        "RightScale with Windows Server" = "RightScaleWindowsServer";
        "Riverbed Technology" = "RiverbedTechnology";
        "SUSE" = "SUSE"}

    $publisher = $asmToArmPublishersMap[$Image.PublisherName]

    $offers = AzureResourceManager\Get-AzureVMImageOffer -Location $Location -PublisherName $publisher 

    $skus = @()
    $offers | ForEach-Object { $skus += AzureResourceManager\Get-AzureVMImageSku -Location $Location -PublisherName $publisher -Offer $_.Offer}

    $imageLabelTokens = $image.ImageFamily.Split()
    $skuRanks = @()     
    foreach ($sku in $skus)
    {
        $skuRank = [PSCustomObject] @{
            'Skus' = $sku.Skus;
            'Offer' = $sku.Offer;
            'Rank' = 0;
            }
        
        foreach ($token in $imageLabelTokens)
        {
            if ($sku.Skus.Contains($token)) {
                $skuRank.Rank++                
            }    
        }

        if ($skuRank.Rank -gt 0) {
            $skuRanks += $skuRank
        }
    }

    $maximumRank = ($skuRanks | Measure-Object -Maximum Rank).Maximum
    $skusWithMaximumRank = $skuRanks | Where-Object {$_.Rank -eq $maximumRank}

    if ($skusWithMaximumRank.length -eq 0)
    {
        return @()
    }

    $images = @()
    $optionCount = 0
    foreach ($imageSku in $skusWithMaximumRank)
    {
        $imagesForSku = AzureResourceManager\Get-AzureVMImage -Location $Location -PublisherName $publisher -Offer $imageSku.Offer -Skus $imageSku.Skus -ErrorAction SilentlyContinue
        if ($imagesForSku.Length -gt 0) {  
            $latestImage = ($imagesForSku | Sort-Object -Property Version -Descending)[0]

            $images += [PSCustomObject] @{
                'Publisher' = $latestImage.PublisherName
                'Offer' = $latestImage.Offer;
                'Skus' = $latestImage.Skus;
                'Version' = $latestImage.Version
                'Id' = $latestImage.Id;
                'Option' = $optionCount++;
            }
        }
    }

    if ($images.Length -gt 0)
    {
        Write-Output "Found the following potential images:"
        $images | Select-Object Option, Publisher, Offer, Skus, Version | Format-Table -AutoSize -Force | Out-Host
        $option = Read-Host -Prompt "Please type in the Option number and press Enter"

        return $images[$option].Id
    }

    if ($skusWithMaximumRank.length -eq 0)
    {
        return @()
    }
}



function Get-StorageAccountName
{
    [OutputType([string])]
    Param
    (
        $NamePrefix
    )

    # Decide if we need to create a storage account
    $storageAccountName = $NamePrefix.Substring(0,20) + 'arm'

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
            $storageAccounts = AzureResourceManager\Get-AzureStorageAccount | Select-Object Name
        
            if ($storageAccounts.Contains($storageAccountName))
            {
                # If we are here, this is a storage account on this subscription, and using V2
                $retryStorageAccountName = $false
            } 
            else
            {
                # If we are here, that means, storage account exists but some other subscription has it
                $retryStorageAccountName = $true
                $storageAccountName = "{0:00}{1}arm" -f $NamePrefix.Substring(0,18), $index++
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

function Get-AvailableAddressSpace
{
    [OutputType([string])]
    Param
    (
        [string[]]
        $addressSpaces
    )

    if ($addressSpaces -eq $null -or $addressSpaces.Length -eq 0)
    {
        # Return default, 0.0.0.1/20 network
        return "10.0.0.0/20"
    }

    $hostRanges = @()
    $addressSpaces | ForEach-Object {Get-HostRange $_} | Sort-Object -Property 'NetworkInt' | ForEach-Object {$hostRanges += $_}

    $minRange = [uint32]::MinValue
    $firstRangeNetwork = $hostRanges[0].Network.Split('.')
    if ($firstRangeNetwork[0] -eq 10)
    {
        $minRange = [uint32]([uint32]10 -shl 24) 
    } elseif ($firstRangeNetwork[0] -eq 172 -and $firstRangeNetwork[1] -eq 16)
    {
        $minRange = [uint32]([uint32]172 -shl 24) + [uint32]([uint32]16 -shl 16) 
    } elseif ($firstRangeNetwork[0] -eq 192 -and $firstRangeNetwork[1] -eq 168)
    {
        $minRange = [uint32]([uint32]192 -shl 24) + [uint32]([uint32]168 -shl 16) 
    } else
    {
        throw "Invalid IP range. Must conform rfc1918"
    }
     
    $networkRanges = @()
    $networkRanges += Get-FirstAvailableRange -Start $minRange -End ($hostRanges[0].NetworkInt - 1)

    for ($i = 0; $i -lt $hostRanges.Length - 1; $i++)
    { 
        $networkRanges += Get-FirstAvailableRange -Start ($hostRanges[$i].BroadcastInt + 1)  -End ($hostRanges[$i + 1].NetworkInt - 1)
    }

    $maxRange = [uint32]::MinValue
    $lastRangeNetwork = $hostRanges[$hostRanges.Length - 1].Network.Split('.')
    if ($lastRangeNetwork[0] -eq 10)
    {
        $maxRange = [uint32](([uint32]10 -shl 24) + ([uint32]255 -shl 16) + ([uint32]255 -shl 8) + [uint32]255) + 1        
    } elseif ($lastRangeNetwork[0] -eq 172 -and $lastRangeNetwork[1] -eq 16)
    {
        $maxRange = [uint32](([uint32]172 -shl 24) + ([uint32]31 -shl 16) + ([uint32]255 -shl 8) + [uint32]255) + 1
    } elseif ($lastRangeNetwork[0] -eq 192 -and $lastRangeNetwork[1] -eq 168)
    {
        $maxRange = [uint32](([uint32]192 -shl 24) + ([uint32]168 -shl 16) + ([uint32]255 -shl 8) + [uint32]255) + 1
    } else
    {
        throw "Invalid IP range. Must conform rfc1918"
    }

    $networkRanges += Get-FirstAvailableRange -Start ($hostRanges[$hostRanges.Length - 1].BroadcastInt + 1) -End $maxRange

    if (-not $networkRanges -or $networkRanges.Length -le 0)
    {
        return ""
    }

    $firstRange = $networkRanges[0]
    return "{0}/{1}" -f $firstRange.Network, $(Get-PrefixForNetwork $firstRange.Hosts)

}

function Get-HostRange
{
    [OutputType([PSCustomObject])]
    Param
    (
        [string]
        $cidrBlock
    )

    $network, [int]$cidrPrefix = $cidrBlock.Split('/')
    if ($cidrPrefix -eq 0)
    {
        throw "No network prefix is found"
    }

    $dottedDecimals = $network.Split('.')
    [uint32] $uintNetwork = [uint32]([uint32]$dottedDecimals[0] -shl 24) + [uint32]([uint32]$dottedDecimals[1] -shl 16) + [uint32]([uint32]$dottedDecimals[2] -shl 8) + [uint32]$dottedDecimals[3] 
    
    $networkMask = (-bnot [uint32]0) -shl (32 - $cidrPrefix)
    $broadcast = $uintNetwork -bor ((-bnot $networkMask) -band [uint32]::MaxValue) 

    $networkRange = @{'Network' = Get-DecimalIp $uintNetwork; 'Broadcast' = Get-DecimalIp $broadcast; `
        'Hosts' = ($broadcast - $uintNetwork - 1); 'StartHost' = Get-DecimalIp ($uintNetwork + 1); 'EndHost' = Get-DecimalIp($broadcast - 1); `
        'BroadcastInt' = $broadcast; 'NetworkInt' = $uintNetwork}
    return New-Object -TypeName PSCustomObject $networkRange
}

function Get-DecimalIp
{
    [OutputType([string])]
    Param
    (
        [uint32]
        $uintIp
    )

    return "{0}.{1}.{2}.{3}" -f [int]($uintIp -shr 24), [int](($uintIp -shr 16) -band 255), [int](($uintIp -shr 8) -band 255), [int]($uintIp -band 255)
}

function Get-FirstAvailableRange
{
    [OutputType([PSCustomObject])]
    Param
    (
        [uint32]
        $Start,
        [uint32] 
        $End
    ) 
    
    if ($Start -ge $End)
    {
        return @()
    }

    $blockSize = 4096
    $rangesCount = [math]::Floor(($End - $Start) / $blockSize)
    $ranges = @()
    if ($rangesCount -gt 0) 
    {
        #for ($i = 0; $i -lt $rangesCount; $i++)
        # Just grab the first range, but leave the above for reference. The potential number of ranges can 
        # be quite large, so go for this optimization for the small block sizes.
        for ($i = 0; $i -lt 1; $i++)
        { 
            $uintNetwork = ($start + ($i * $blockSize))
            $broadcast = ($start + ($i + 1) * $blockSize -1)
            $networkRange = @{'Network' = Get-DecimalIp $uintNetwork; 'Broadcast' = Get-DecimalIp $broadcast; `
            'Hosts' = ($broadcast - $uintNetwork - 1); 'StartHost' = Get-DecimalIp ($uintNetwork + 1); 'EndHost' = Get-DecimalIp($broadcast - 1); `
            'BroadcastInt' = $broadcast; 'NetworkInt' = $uintNetwork}
            $ranges += $networkRange
        }
    }

    $remainingRange = ($End - $Start) % $blockSize

    if ($remainingRange > 0) {
        $Start = ($rangesCount * $blockSize) + 1
        $uintNetwork = ($start + ($i * $blockSize))
        $broadcast = ($start + (($i + 1) * $blockSize) - 1)
        $networkRange = @{'Network' = Get-DecimalIp $uintNetwork; 'Broadcast' = Get-DecimalIp $broadcast; `
        'Hosts' = ($broadcast - $uintNetwork - 1); 'StartHost' = Get-DecimalIp ($uintNetwork + 1); 'EndHost' = Get-DecimalIp($broadcast - 1); `
        'BroadcastInt' = $broadcast; 'NetworkInt' = $uintNetwork}
        $ranges.Add($networkRange)
    }

    if($ranges.Count -gt 0)
    {
        return $ranges[0]
    }
}

function Get-PrefixForNetwork
{
    [OutputType([int])]
    Param
    (
        [uint32]
        $NetworkSize
    )

    $NetworkSize++
    
    $netPrefix = 0
    do
    {
        $NetworkSize = $NetworkSize -shr 1
        $netPrefix++
    }
    until ($NetworkSize -eq 0)

    return (32 - $netPrefix)
}

function Get-FirstSubnet
{
    [OutputType([string])]
    Param(
        [string]
        $AddressSpace
    )

    $network, [int]$cidrPrefix = $AddressSpace.Split('/')
    if ($cidrPrefix -eq 0)
    {
        throw "No network prefix is found"
    }

    if ($cidrPrefix -gt 28)
    {
        return "{0}/{1}" -f $network, $cidrPrefix
    }

    return  "{0}/{1}" -f $network, ($cidrPrefix + 2)
}