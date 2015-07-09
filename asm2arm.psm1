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
        [Microsoft.WindowsAzure.Commands.ServiceManagement.Model.PersistentVMRoleContext]
        $VM,

        # Name of the Resource Group the deployment is going to be placed into
        [Parameter(Mandatory=$true)]
        [ValidateNotNull()]
        [ValidateNotNullOrEmpty()]
        [string]
        $ResourceGroupName,

        [Parameter(Mandatory=$true)]
        [ValidateSet("KeepDisks", "NewDisks", "CopyDisks")]
        $DiskAction,

        # In case the VM uses custom certificates, they need to be uploaded to KeyVault
        # Please provide KeyVault resource name
        [Parameter(Mandatory=$false, ParameterSetName='Custom certificates')]
        [Parameter(ParameterSetName='Custom WinRM certificate')]
        [ValidateNotNull()]
        [ValidateNotNullOrEmpty()]
        [string]
        $KeyVaultResourceName,

        # In case the VM uses custom certificates, they need to be uploaded to KeyVault
        # Please provide vault name
        [Parameter(Mandatory=$false, ParameterSetName='Custom certificates')]
        [Parameter(ParameterSetName='Custom WinRM certificate')]
        [ValidateNotNull()]
        [ValidateNotNullOrEmpty()]
        [string]
        $KeyVaultVaultName
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

    if (-not $VM.VM.WinRMCertificate -and (-not $KeyVaultResourceName -or -not $KeyVaultVaultName -or -not $WinRmCertificateThumbprint) )
    {
        throw ("The VM uses a custom certificate for WinRM. Please upload it to KeyVault, and provide KeyVault resoruce name, vault name in the parameters. Thumbprint of the certificate is {0}" -f $VM.VM.WinRMCertificate)
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

    if ($DiskAction -eq 'NewDisks' -or $DiskAction -eq 'CopyDisks')
    {
        # Storage account resource
        $storageAccountName = Get-StorageAccountName -NamePrefix $canonicalSubscriptionName
        if (-not $(Azure\Test-AzureName -Storage $storageAccountName))
        {
            $storageAccountResource = New-StorageAccountResource -Name $storageAccountName -Location '[parameters(''location'')]'
            $resources += $storageAccountResource
        }
    }
    
    # Virtual network resource
    $vnetName = $asm2armVnetName
    if ($VM.VirtualNetworkName -ne "")
    {
        $vnetName += $Global:armSuffix
    }
    
    if ($(AzureResourceManager\Get-AzureVirtualNetwork -Name $vnetName -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue) -eq $null)
    {
        $virtualNetworkAddressSpaces = AzureResourceManager\Get-AzureVirtualNetwork | %{$_.AddressSpace.AddressPrefixes}
        $vnetAddressSpace = Get-AvailableAddressSpace $virtualNetworkAddressSpaces
        $subnetAddressSpace = Get-FirstSubnet -AddressSpace $vnetAddressSpace
        $subnet = New-VirtualNetworkSubnet -Name $Global:asm2armSubnet -AddressPrefix $subnetAddressSpace
        $vnetResource = New-VirtualNetworkResource -Name $vnetName -Location '[parameters(''location'')]' -AddressSpacePrefixes @($vnetAddressSpace) -Subnets @($subnet)
        $resources += $vnetResource
    }
    else {
        ###### TODO Take care of checking the subnet, and adding it to the resource as necessary
    }

    # Availability set resource
    if ($VM.AvailabilitySetName -ne "")
    {
        $availabilitySetResource = New-AvailabilitySetResource -Name $VM.AvailabilitySetName -Location '[parameters(''location'')]'
        $resources += $availabilitySetResource
    }

    $cloudService = Azure\Get-AzureService -ServiceName $VM.ServiceName
    $location= $cloudService.Location
    $actualParameters['location'] = $location
    $vmName = '{0}_{1}' -f $ServiceName, $Name

    # Public IP Address resource
    $ipAddressName = '{0}_armpublicip' -f $vmName
    $armDnsName = '{0}arm' -f $ServiceName
    $publicIPAddressResource = New-PublicIpAddressResource -Name $ipAddressName -Location '[parameters(''location'')]' `
        -AllocationMethod 'Dynamic' -DnsName $armDnsName
    $resources += $publicIPAddressResource
    
    # NIC resource
    $nicName = '{0}_nic' -f $vmName
    $subnetRef = '[concat(resourceId(''Microsoft.Network/virtualNetworks'',''{0}''),''/subnets/{1}'')]' -f $vnetName, $Global:asm2armSubnet
    $ipAddressDependency = 'Microsoft.Network/publicIPAddresses/{0}' -f $ipAddressName
    $vnetDependency = 'Microsoft.Network/virtualNetworks/{0}' -f $vnetName
    $dependencies = @( $ipAddressDependency, $vnetDependency)
    $nicResource = New-NetworkInterfaceResource -Name $nicName -Location '[parameters(''location'')]' `
        -PublicIpAddressName $ipAddressName -SubnetReference $subnetRef -Dependecies $dependencies
    $resources += $nicResource

    # VM


    $credentials = Get-Credential

    $vmResource = New-VmResource -VM $VM -Credentials $credentials -NetworkInterface $nicName -DiskAction $DiskAction
    $resources += $vmResource
    
    $parameters = [PSCustomObject] $parametersObject
    
    $template = New-ArmTemplate -Parameters $parameters -Resources $resources
    $templateFileName =  [IO.Path]::GetTempFileName()
    $template | Out-File $templateFileName

    $parametersFile = New-ArmTemplateParameterFile -ParametersList $actualParameters
    $actualParametersFileName =  [IO.Path]::GetTempFileName()
    $parametersFile | Out-File $actualParametersFileName

    $resourceGroup = AzureResourceManager\Get-AzureResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue

    if ($resourceGroup -eq $null)
    {
        AzureResourceManager\New-AzureResourceGroup -Name $ResourceGroupName -Location $location
    }

    $deploymentName = "{0}_{1}" -f $ServiceName, $Name

    AzureResourceManager\New-AzureResourceGroupDeployment  -ResourceGroupName $ResourceGroupName -Name $deploymentName -TemplateFile $templateFileName -TemplateParameterFile $actualParametersFileName -Location $location
}