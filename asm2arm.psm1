Set-StrictMode -Version 3

$apiVersion = "2015-05-01-preview"

<#
.Synopsis
   Discover a single VM deployment on the Azure Service Management (ASM) deployments and
   deploy a VM with the same image to an Azure Resource Manager (ARM) deployment.
.DESCRIPTION
   Starts with the VM the user provided, discovers the VMs image, then queries the ARM
   VM image catalog, then creates an ARM template to be deployed to the ARM stack.
.EXAMPLE
   
.EXAMPLE
   
.INPUTS
   Inputs to this cmdlet (if any)
.OUTPUTS
   Output from this cmdlet (if any)
.NOTES
   General notes
.COMPONENT
   The component this cmdlet belongs to
.ROLE
   The role this cmdlet belongs to
.FUNCTIONALITY
   The functionality that best describes this cmdlet
#>
function Add-AzureSMVmToRM
{
    [CmdletBinding(DefaultParameterSetName='Service and VM Name', 
                  PositionalBinding=$false,
                  ConfirmImpact='Medium')]
    Param
    (
        # ServiceName the VM is deployed on
        [Parameter(Mandatory=$true, 
                   ParameterSetName='Service and VM Name')]
        [ValidateNotNull()]
        [ValidateNotNullOrEmpty()]
        [string]
        $ServiceName,

        # Name of the VM
        [Parameter(Mandatory=$true, 
                   ParameterSetName='Service and VM Name')]
        [ValidateNotNull()]
        [ValidateNotNullOrEmpty()]
        [string]
        $Name,

        # VM Object
        [Parameter(Mandatory=$true, 
                   ParameterSetName='VM only')]
        [ValidateNotNull()]
        [ValidateNotNullOrEmpty()]
        [PersistentVm]
        $VM
    )

    if ($psCmdlet.ParameterSetName -eq "Service and VM Name")
    { 
        $lastError = $null
        $VM = Azure\Get-AzureVM -ServiceName $ServiceName -Name $Name -ErrorAction SilentlyContinue -ErrorVariable $lastError
        if ($lastError)
        {
            $message = "VM with name {0} on service {1} cannot be found. Details are {2}" -f $Name, $ServiceName, $lastError
            Write-Error $message
        }
    }
    else
    {
        $ServiceName = $VM.ServiceName
        $Name = $VM.Name
    }

    if (-not $VM)
    {
        throw "VM is not present"
    } 

    # Find the VMs image on the catalog
    $imageName = $vm.VM.OSVirtualHardDisk.SourceImageName

    $vmImage = Azure\Get-AzureVMImage -ImageName $imageName -ErrorAction SilentlyContinue -ErrorVariable $lastError

    if (-not $vmImage)
    {
        $message = "VM Image {0} for VM {1} on service {3} cannot be found." -f $imageName, $Name, $imageName
        Write-Verbose $lastError
        throw $message
    }

    $cloudService = Azure\Get-AzureService -ServiceName $VM.ServiceName
    $location= $cloudService.Location

    $armImageReference = Azure\Get-AzureArmImageRef -Location $location -Image $vmImage

    $currentSubscription = AzureResourceManager\Get-AzureSubscription -Current
    $canonicalSubscriptionName = ($($currentSubscription.SubscriptionName -replace [regex]'[aeiouAEIOU]','') -replace [regex]'[^a-zA-Z]','').ToLower()

    $resources = @()

    $parametersObject = @{}
    $parametersObject.Add('location', $(New-ArmTemplateParameter -Type "string" -Description "location where the resources are going to be deployed to" `
                                            -AllowedValues @("East US", "West US", "West Europe", "East Asia", "South East Asia"))) 

    $parameters = New-Object -TypeName PSCustomObject $parametersObject

    $storageAccountName = Get-StorageAccountName -NamePrefix $canonicalSubscriptionName
    if (-not $(Azure\Test-AzureName -Storage $storageAccountName))
    {
        $storageAccountResource = New-StorageAccountResource -Name $storageAccountName -Location '[parameters(''location'')]'
        $resources += $storageAccountResource
    }
    
    
    $template = New-ArmTemplate -Parameters $parameters -Resources $resources
    $templateFileName =  [IO.Path]::GetTempFileName()
    $template | Out-File $templateFileName

    AzureResourceManager\New-AzureResourceGroup -Name ecarm  -TemplateFile $templateFileName
}


function New-ArmTemplateParameter
{
    Param
    (
        [ValidateSet("string", "securestring", "int", "bool", "array", "object")]
        $Type,
        $Description,
        [array]
        $AllowedValues,
        $DefaultValue
    )

    $parameterDefinition = @{'type' = $Type; 'metadata' = New-Object -TypeName PSCustomObject @{'description' = $Description}}

    if ($AllowedValues)
    {
        $parameterDefinition.Add('allowedValues', $AllowedValues)
    }

    if ($DefaultValue)
    {
        $parameterDefinition.Add('defaultValue', $DefaultValue)
    }

    return New-Object -TypeName PSCustomObject $parameterDefinition
  
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


function New-ResourceTemplate 
{
    Param
    (
        $Type,
        $Name,
        $ApiVersion,
        $Location,
        $Properties,
        [array]
        $DependsOn,
        [PSCustomObject]
        $Resources
    )

    $template = @{
        "name" = $Name;
        "type"=  $Type;
        "apiVersion" = $ApiVersion;
        "location" = $Location;
        "tags" = New-Object -TypeName PSCustomObject @{"deploymentReason" = "ARM";};
        "properties" = $Properties;
    }

    if ($Resources) 
    {
        $template.Add("resources", $Resources)
    }

    if ($DependsOn)
    {
        $template.Add("dependsOn", $DependsOn)
    }

    return New-Object -TypeName PSCustomObject $template
}

function New-ArmTemplate 
{
    Param
    (
        $Version,
        [PSCustomObject]
        $Parameters,
        [PSCustomObject]
        $Variables,
        [PSCustomObject[]]
        $Resources,
        [PSCustomObject[]]
        $Outputs
    )

    $template = @{
        '$schema' = 'https://schema.management.azure.com/schemas/2015-01-01/deploymentTemplate.json#';
        'parameters' = $Parameters;
        'resources' = $Resources;
    }

    if (-not $Version)
    {
        $Version = '1.0.0.0'
    }

    $template.Add('contentVersion', $Version)

    if ($Outputs) 
    {
        $template.Add("outputs", $Outputs)
    }

    if ($Variables)
    {
       $template.Add("variables", $Variables)
    }

    $templateObject = New-Object -TypeName PSCustomObject $template
    return ConvertTo-Json $templateObject -Depth 5
}

function New-StorageAccountResource
{
    Param
    (
        $Name,
        $Location
    )

    $createProperties = New-Object -TypeName PSCustomObject @{"accountType" = "Standard_LRS";}
    $resource = New-ResourceTemplate -Type "Microsoft.Storage/storageAccounts" -Name $Name `
        -Location $Location -ApiVersion "2015-05-01-preview" -Properties $createProperties

    return $resource
}

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
        $images | Select-Object Option, Publisher, Offer, Skus, Version | Format-Table -AutoSize 
        $option = Read-Host -Prompt "Please type in the Option number and press Enter"

        return $images[$option].Id
    }

    if ($skusWithMaximumRank.length -eq 0)
    {
        return @()
    }
}
