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
        $VM,

        # Name of the VM
        [Parameter(Mandatory=$true)]
        [string]
        [ValidateNotNull()]
        [ValidateNotNullOrEmpty()]
        $TargetStorageAccountName
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
    $vmLocation= $cloudService.Location

    $armImageReference = Azure\Get-AzureArmImageRef -Location $vm.$vmLocation -Image $vmImage

}

<#
.Synopsis
   Retrieve the ARM Image reference for a given ASM image
.DESCRIPTION
   Do a search on the ARM image catalog, based on the input ASM VM Image.
.EXAMPLE
   Get-AzureArmImageRef -Location $vm.$vmLocation -Image $vmImage
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
        $images | Select Option, Publisher, Offer, Skus, Version | Format-Table -AutoSize 
        $option = Read-Host -Prompt "Please type in the Option number and press Enter"

        return $images[$option].Id
    }

    if ($skusWithMaximumRank.length -eq 0)
    {
        return @()
    }
}


