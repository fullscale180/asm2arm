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

    $currentSubscription = AzureResourceManager\Get-AzureSubscription -Current
    
    # Generate a canonical subscription name to use as the stem for other names
    $canonicalSubscriptionName = ($($currentSubscription.SubscriptionName -replace [regex]'[aeiouAEIOU]','') -replace [regex]'[^a-zA-Z]','').ToLower()

    # Start building the ARM template
    
    # Parameters section
    $parametersObject = @{}
    $actualParameters = @{}

    $parametersObject.Add('location', $(New-ArmTemplateParameter -Type "string" -Description "location where the resources are going to be deployed to" `
                                            -AllowedValues @("East US", "West US", "West Europe", "East Asia", "South East Asia"))) 
    $actualParameters.Add('location', '')

    # Resources section
    $resources = @()

    # Storage account resource
    $storageAccountName = Get-StorageAccountName -NamePrefix $canonicalSubscriptionName
    if (-not $(Azure\Test-AzureName -Storage $storageAccountName))
    {
        $storageAccountResource = New-StorageAccountResource -Name $storageAccountName -Location '[parameters(''location'')]'
        $resources += $storageAccountResource
    }
    
    # Virtual network resource
    $vnetName = $canonicalSubscriptionName + 'armvnet'
    

    if ($(AzureResourceManager\Get-AzureVirtualNetwork -Name $vnetName) -eq $null)
    {
        $virtualNetworkAddressSpaces = AzureResourceManager\Get-AzureVirtualNetwork | %{$_.AddressSpace.AddressPrefixes}
        $vnetAddressSpace = Get-AvailableAddressSpace $virtualNetworkAddressSpaces
        if ($virtualNetworks)
        {
            
        }
        if ($(AzureResourceManager\Get-AzureVirtualNetwork) -eq $null)
        {
            $subnets = @(New-VirtualNetworkSubnet -Name 'default')
        }
    }

    # Compute, VM resource
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
    $actualParameters['location'] = $location

    $armImageReference = Azure\Get-AzureArmImageRef -Location $location -Image $vmImage


    $parameters = New-Object -TypeName PSCustomObject $parametersObject

    
    $template = New-ArmTemplate -Parameters $parameters -Resources $resources
    $templateFileName =  [IO.Path]::GetTempFileName()
    $template | Out-File $templateFileName

    $parametersFile = New-ArmTemplateParameterFile -ParametersList $actualParameters
    $actualParametersFileName =  [IO.Path]::GetTempFileName()
    $actualParameters | Out-File $actualParametersFileName

    AzureResourceManager\New-AzureResourceGroup -Name ecarm  -TemplateFile $templateFileName -TemplateParameterFile $actualParametersFileName
}






