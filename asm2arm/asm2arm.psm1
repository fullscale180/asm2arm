<#
.Synopsis
   Discover a single VM deployment on the Azure Service Management (ASM) deployments and
   deploy a VM with the same image to an Azure Resource Manager (ARM) deployment.
.DESCRIPTION
   Starts with the VM the user provided, discovers the VMs image, then queries the ARM
   VM image catalog, then creates an ARM template to be deployed to the ARM stack.
   The target VM needs to be in stopped state. If the machine is not stopped, the cmdlet will exit.
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
        [ValidateSet("NewDisks", "CopyDisks")]
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
        $KeyVaultVaultName,

        # In case the VM uses custom certificates, they need to be uploaded to KeyVault
        # Please provide certificate names that reside on the given vault
        [Parameter(Mandatory=$false, ParameterSetName='Custom certificates')]
        [Parameter(ParameterSetName='Custom WinRM certificate')]
        [ValidateNotNull()]
        [ValidateNotNullOrEmpty()]
        [string[]]
        $CertificatesToInstall,

        # In case the VM uses a custom WinRM certificate, they need to be uploaded to KeyVault
        # Please name the certificate to be used for WinRM among the names provided in $CertificatesToInstall parameter
        [Parameter(ParameterSetName='Custom WinRM certificate')]
        [ValidateNotNull()]
        [ValidateNotNullOrEmpty()]
        [string]
        $WinRmCertificateName,

        # Folder for the generated template and parameter files
        [Parameter(Mandatory=$true)]
        [ValidateNotNull()]
        [ValidateNotNullOrEmpty()]
        [string]
        $OutputFileFolder,

        # Generate timestamp in the file name or not, default is to generate the timestamp
        [Parameter(Mandatory=$false)]        
        [switch]
        $AppendTimeStampForFiles,

        # Kick off a new deployment automatically after generating the ARM template files
        [Parameter(Mandatory=$false)]        
        [switch]
        $Deploy
    )

    if ($psCmdlet.ParameterSetName -eq "Service and VM Name")
    { 
        $lastError = $null
        $VM = Azure\Get-AzureVM -ServiceName $ServiceName -Name $Name -ErrorAction SilentlyContinue -ErrorVariable $lastError
        if ($lastError)
        {
            $message = "VM with name '{0}' on service '{1}' cannot be found. Details are {2}" -f $Name, $ServiceName, $lastError
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

    if ($vm.PowerState -ne "Stopped")
    {
        $vmMessage = "The VM {0} on service {1} needs to be stopped. It's power state is {2}" -f $vm.Name, $vm.ServiceName, $vm.PowerState
        Write-Error $vmMessage
        return
    }

    if (($VM.VM.WinRMCertificate -ne $null) -and (-not $KeyVaultResourceName -or -not $KeyVaultVaultName -or -not $WinRmCertificateThumbprint) )
    {
        throw ("The VM uses a custom certificate for WinRM. Please upload it to KeyVault, and provide KeyVault resoruce name, vault name in the parameters. Thumbprint of the certificate is {0}" -f $VM.VM.WinRMCertificate)
    }

    if ($WinRmCertificateName -and -not $CertificatesToInstall.Contains($WinRmCertificateName))
    {
        throw ("Please ensure WinRM certificate name {0} is included in the $CertificatesToInstall parameter" -f $WinRmCertificateName)
    }

    if ($VM.VM.WinRMCertificate)
    {
        $cert = AzureResourceManager\Get-AzureKeyVaultSecret -VaultName $KeyVaultVaultName -Name $WinRmCertificateName -ErrorAction SilentlyContinue
        if ($cert -eq $null)
        {
            throw ("Cannot find the WinRM certificate {0} with thumbprint {1}. Please ensure certificate is added in the vault {2} secrets." -f $WinRmCertificateName, $VM.VM.WinRMCertificate, $KeyVaultVaultName)
        }
    }

    $cloudService = Azure\Get-AzureService -ServiceName $VM.ServiceName
    $location = $cloudService.Location

    $currentSubscription = AzureResourceManager\Get-AzureSubscription -Current
    
    # Generate a canonical subscription name to use as the stem for other names
    $canonicalSubscriptionName = Get-CanonicalString $currentSubscription.SubscriptionName 

    # Start building the ARM template
    
    # Parameters section
    $parametersObject = @{}
    $actualParameters = @{}

    $parametersObject.Add('location', $(New-ArmTemplateParameter -Type "string" -Description "location where the resources are going to be deployed to" `
                                            -AllowedValues @("East US", "West US", "West Europe", "East Asia", "South East Asia"))) 
    $actualParameters.Add('location', '')
    
    # Compose an expression that allows capturing the resource location from ARM template parameters
    $resourceLocation = "[parameters('location')]"

    if ($DiskAction -eq 'NewDisks')
    {
        $credentials = Get-Credential
        $parametersObject.Add('adminUser', $(New-ArmTemplateParameter -Type "string" -Description "Administrator user name")) 
        $actualParameters.Add('adminUser', $credentials.UserName)

        $parametersObject.Add('adminPassword', $(New-ArmTemplateParameter -Type "securestring" -Description "Administrator user password")) 
        $actualParameters.Add('adminPassword', $credentials.GetNetworkCredential().Password);
    }

    # Resources section
    $resources = @()

    # This varibale gathers all resources that form a setup phase. These include storage accounts, virtual networks, availability sets.
    $setupResources = @()
    
    # Generate the storage account name for the ARM deployments. This function will test the existence of the account, and will generate a new name 
    # if the storage account exists on a different location.
    $storageAccountName = Get-StorageAccountName -NamePrefix $canonicalSubscriptionName  -Location $location

    # Check if we need to create storage account resource. 
    if (-not $(Azure\Test-AzureName -Storage $storageAccountName))
    {
        Write-Verbose $("Adding a resource definition for '{0}' storage account" -f $storageAccountName)

        $vmOsDiskStorageAccountName = ([System.Uri]$VM.VM.OSVirtualHardDisk.MediaLink).Host.Split('.')[0]

        $storageAccount = Azure\Get-AzureStorageAccount -StorageAccountName $vmOsDiskStorageAccountName
        $storageAccountResource = New-StorageAccountResource -Name $storageAccountName -Location $resourceLocation -StorageAccountType $storageAccount.AccountType
        $setupResources += $storageAccountResource
    }
    
    # Virtual network resource
    $virtualNetworkSite = $null
    $vmSumbnet = ''
    $networkConfiguration = $null
    $classicSubnet = $null
    $vmSubnetName = ""
    if ($VM.VirtualNetworkName -eq $null)
    {
        $vnetName = $Global:asm2armVnetName
    } 
    else {
        $vnetName = $(Get-CanonicalString $VM.VirtualNetworkName) + $Global:armSuffix
        # Wrapping in try-catch as the commandlet does not implement -ErrorAction SilentlyContinue
        try
        {
    		$virtualNetworkSite = Azure\Get-AzureVNetSite -VNetName $vm.VirtualNetworkName -ErrorAction SilentlyContinue
        }
        catch [System.ArgumentException]
        {
            throw $("Cannot find the virtual network {0} for VM {0}" -f $vm.VirtualNetworkName, $vm.Name)
        }

        $configuration = $vm.VM.ConfigurationSets | Where-Object {$_.ConfigurationSetType -eq 'NetworkConfiguration'}
        if ($configuration.Count -gt 0)
        {
            $networkConfiguration = $configuration[0]
            $subnetName = $networkConfiguration.SubnetNames[0]
            $classicSubnet = $virtualNetworkSite.Subnets | Where-Object {$_.Name -eq $subnetName}
        }
    }
    
	$currentVnet = AzureResourceManager\Get-AzureVirtualNetwork -Name $vnetName -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
    $subnets = @()
    $vnetAddressSpaces = @()
    
    # Does the resource manager have a virtual network we can use? If we have null, no.
    if ($currentVnet -eq $null)
    {
        # Does the source VM is on a virtual network? If the vnetname is the default virtual network name, that means no.
        if ($vnetName -eq $Global:asm2armVnetName)
        {
            # If we are here, that means no virtual network on the source VM and no virtual network on the target resource group.
            # Cust create a default virtual network with a default subnet.
            $vnetAddressSpaces += $Global:defaultAddressSpace

            Write-Verbose $("Adding a resource definition for '{0}' subnet - new default subnet" -f $Global:asm2armSubnet)

            $subnets += New-VirtualNetworkSubnet -Name $Global:asm2armSubnet -AddressPrefix $Global:defaultSubnetAddressSpace
            $vmSubnetName = $Global:asm2armSubnet 
        } else {
            # The source VM is on a virtual network. Copy all of the virtual network to ARM
            Write-Verbose $("Copying the classic virtual network specification")
            foreach ($addressSpace in $virtualNetworkSite.AddressSpacePrefixes)
            {
                $vnetAddressSpaces += $addressSpace
            }

            foreach ($subnet in $virtualNetworkSite.Subnets)
            {
                Write-Verbose $("Adding a resource definition for '{0}' subnet" -f $subnet.Name)
                $subnets += New-VirtualNetworkSubnet -Name $subnet.Name -AddressPrefix $subnet.AddressPrefix
            }
            $vmSubnetName = $classicSubnet.Name 
        }
    }
    else {
        # If we are here, that means we had previously made a cloning, or the virtual network we are trying to create exists.
        # We need to create the exact copy of the existing virtual network specification, and add a new subnet if the target
        # subnet does not exist.

        $subnetExists = $false
        foreach ($subnet in $currentVnet.Subnets)
        {
            $subnetExists = $($subnet.AddressPrefix -eq $classicSubnet.AddressPrefix -and $subnet.Name -eq $classicSubnet.Name)
            if ($subnetExists)
            {
                foreach ($addressPrefix in $currentVnet.AddressSpace.AddressPrefixes)
                {
                    if (Test-SubnetInAddressSpace -SubnetPrefix $classicSubnet.AddressPrefix -AddressSpace $addressPrefix)
                    {
                        $vnetAddressSpaces += $addressPrefix
                    }
                }

                $vmSubnetName = $classicSubnet.Name 
            }
            Write-Verbose $("Found a matching subnet, adding a resource definition for '{0}' subnet" -f $subnet.Name)
            $subnets += New-VirtualNetworkSubnet -Name $subnet.Name -AddressPrefix $subnet.AddressPrefix
        }

        if (-not $subnetExists)
        {       
            # We could not find a suitable subnet. This could be because a new VM that could be added after an initial
            # cloning process for another VM. Let's find a suitable address space and add a new subnet
            $existingSubnets = @()
            $currentVnet.Subnets | ForEach-Object {$existingSubnets += $_.AddressPrefix; $subnets += New-VirtualNetworkSubnet -Name $_.Name -AddressPrefix $_.AddressPrefix}

            $subnetAddressSpace = Get-AvailableAddressSpace $existingSubnets

            foreach ($addressPrefix in $currentVnet.AddressSpace.AddressPrefixes)
            {
                if (Test-SubnetInAddressSpace -SubnetPrefix $subnetAddressSpace -AddressSpace $addressPrefix)
                {
                    $vnetAddressSpaces += $addressPrefix
                }
            }

            $canonicalServiceName = Get-CanonicalString $vm.ServiceName
            $canonicalVmName = Get-CanonicalString $vm.Name

            $subnetName = 'subnet-{0}-{1}' -f $canonicalServiceName, $canonicalVmName

            Write-Verbose $("Could not find a matching subnet within the existing virtual network, adding the subnet '{0}'" -f $subnetName)

            $subnets += New-VirtualNetworkSubnet -Name $subnetName -AddressPrefix $subnetAddressSpace
            $vmSubnetName = $subnetName
        }
    }

    Write-Verbose $("Adding a resource definition for '{0}' virtual network" -f $vnetName)
    $vnetResource = New-VirtualNetworkResource -Name $vnetName -Location $resourceLocation -AddressSpacePrefixes $vnetAddressSpaces -Subnets $subnets
    $setupResources += $vnetResource

    # Availability set resource
    if ($VM.AvailabilitySetName)
    {
        Write-Verbose $("Adding a resource definition for '{0}' availability set" -f $VM.AvailabilitySetName)

        $availabilitySetResource = New-AvailabilitySetResource -Name $VM.AvailabilitySetName -Location $resourceLocation
        $setupResources += $availabilitySetResource
    }

    $actualParameters['location'] = $location
    $vmName = '{0}_{1}' -f $ServiceName, $Name

    # Public IP Address resource
    $ipAddressName = '{0}_armpublicip' -f $vmName

    Write-Verbose $("Adding a resource definition for '{0}' public IP address" -f $ipAddressName)

    $armDnsName = Get-AzureDnsName -ServiceName $ServiceName -Location $location
    $publicIPAddressResource = New-PublicIpAddressResource -Name $ipAddressName -Location $resourceLocation `
        -AllocationMethod 'Dynamic' -DnsName $armDnsName
    $resources += $publicIPAddressResource
    
    # NIC resource
    $nicName = '{0}_nic' -f $vmName
    $subnetRef = '[concat(resourceId(''Microsoft.Network/virtualNetworks'',''{0}''),''/subnets/{1}'')]' -f $vnetName, $vmSubnetName
    $ipAddressDependency = 'Microsoft.Network/publicIPAddresses/{0}' -f $ipAddressName
    $vnetDependency = 'Microsoft.Network/virtualNetworks/{0}' -f $vnetName

    Write-Verbose $("Adding a resource definition for '{0}' network interface" -f $nicName)
    
    $dependencies = @($ipAddressDependency)
    $nicResource = New-NetworkInterfaceResource -Name $nicName -Location $resourceLocation -PublicIpAddressName $ipAddressName -SubnetReference $subnetRef -Dependecies $dependencies
    $resources += $nicResource

    # VM
    $nicDependency = 'Microsoft.Network/networkInterfaces/{0}' -f $nicName

    $vmResource = New-VmResource -VM $VM -NetworkInterface $nicName -StorageAccountName $storageAccountName -Location $resourceLocation -LocationValue $location `
                    -ResourceGroupName $ResourceGroupName -DiskAction $DiskAction -KeyVaultResourceName $KeyVaultResourceName -KeyVaultVaultName $KeyVaultVaultName `
                    -CertificatesToInstall $CertificatesToInstall -WinRmCertificateName $WinRmCertificateName -Dependecies @($nicDependency)
    $resources += $vmResource

    # VM extensions (e.g. custom scripts)
    $imperativeScript = New-VmExtensionResources -VM $VM -ServiceLocation $location -ResourceGroupName $ResourceGroupName
    
    $setupTemplate = New-ArmTemplate -Parameters $parametersObject -Resources $setupResources
    $deployTemplate = New-ArmTemplate -Parameters $parametersObject -Resources $resources
    $parametersFile = New-ArmTemplateParameterFile -ParametersList $actualParameters
    
    $timestamp = ''
    if ($AppendTimeStampForFiles.IsPresent)
    {
        $timestamp = '-' + $(Get-Date -Format 'yyMMdd-hhmm')
    }

    # Construct output file names
    $fileNamePrefix ='{0}-{1}' -f $vm.ServiceName, $vm.Name
    $setupTemplateFileName = Join-Path -Path $OutputFileFolder -ChildPath $('{0}-setup{1}.json' -f $fileNamePrefix, $timestamp)
    $deployTemplateFileName = Join-Path -Path $OutputFileFolder -ChildPath $('{0}-deploy{1}.json' -f $fileNamePrefix, $timestamp)
    $parametersFileName = Join-Path -Path $OutputFileFolder -ChildPath $('{0}-parameters{1}.json' -f $fileNamePrefix, $timestamp)
    $imperativeScriptFileName = Join-Path -Path $OutputFileFolder -ChildPath $('{0}-setextensions{1}.ps1' -f $fileNamePrefix, $timestamp)

    if (-not (Test-Path -Path $OutputFileFolder))
    {
        New-Item -ItemType Directory -Path $OutputFileFolder
    }

    # Dumping the setup resource template content to a file
    Write-Verbose $("Generating ARM template with setup resources and writing output to {0}" -f $setupTemplateFileName)
    $setupTemplate = [regex]::replace($setupTemplate,'\\u[a-fA-F0-9]{4}',{[char]::ConvertFromUtf32(($args[0].Value -replace '\\u','0x'))})
    $setupTemplate | Out-File $setupTemplateFileName -Force

    # Dumping the deployment resource template content to a file
    Write-Verbose $("Generating ARM template with deployment resources and writing output to {0}" -f $deployTemplateFileName)
    $deployTemplate = [regex]::replace($deployTemplate,'\\u[a-fA-F0-9]{4}',{[char]::ConvertFromUtf32(($args[0].Value -replace '\\u','0x'))})
    $deployTemplate | Out-File $deployTemplateFileName -Force

    # Dumping the parameters template content to a file
    Write-Verbose $("Generating ARM template parameters file and writing output to {0}" -f $parametersFileName)
    $parametersFile | Out-File $parametersFileName -Force

    if ($imperativeScript -ne '')
    {
        # Dumping the imperative script content to a file
        Write-Verbose $("Generating imperative script file and writing output to {0}" -f $imperativeScriptFileName)
        $imperativeScript | Out-File $imperativeScriptFileName -Force
    }

    if($Deploy.IsPresent)
    {
        $resourceGroup = AzureResourceManager\Get-AzureResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue

        if ($resourceGroup -eq $null)
        {
            Write-Verbose $("Creating a new resource group '{0}'" -f $ResourceGroupName)
            AzureResourceManager\New-AzureResourceGroup -Name $ResourceGroupName -Location $location
        }
        else
        {
            $canonicalizedLocation = $location.Replace(' ', '').ToLower()
            if ($resourceGroup.Location -ne $canonicalizedLocation)
            {
                $message = "Cannot deploy the VM at location {0} to the resource group {1} at location {2}, please specifiy a new resource group name in the VMs region." -f $location, $ResourceGroupName, $resourceGroup.Location
                throw $message
            }
        }
        
        $deploymentName = "{0}_{1}" -f $ServiceName, $Name

        # Enter the setup phase
        Write-Verbose $("Setting up a new deployment '{0}' in the resource group '{1}' using template {2}" -f $deploymentName, $ResourceGroupName, $setupTemplateFileName)
        AzureResourceManager\New-AzureResourceGroupDeployment -ResourceGroupName $ResourceGroupName -Name $deploymentName -TemplateFile $setupTemplateFileName -TemplateParameterFile $parametersFileName -Location $location

        if ($DiskAction -eq 'CopyDisks')
        {
            Write-Verbose $("CopyDisks option was requested - all existing VHDs will now be copied to '{0}' storage account managed by ARM" -f $storageAccountName)
            Copy-VmDisks -VM $VM -StorageAccountName $storageAccountName -ResourceGroupName $ResourceGroupName
        }

        # Enter tha main deployment phase
        Write-Verbose $("Creating a new deployment '{0}' in the resource group '{1}' using template {2}" -f $deploymentName, $ResourceGroupName, $deployTemplateFileName)
        $deploymentResult = AzureResourceManager\New-AzureResourceGroupDeployment -ResourceGroupName $ResourceGroupName -Name $deploymentName -TemplateFile $deployTemplateFileName -TemplateParameterFile $parametersFileName -Location $location 

        if ($imperativeScript)
        {        
            # Wait for the deployment to stabilize to run the extensions
            Start-Sleep -Seconds 120

            Invoke-Expression -Command $imperativeScript
        }
    }
}

function Get-CanonicalString
{
    Param(
        [Parameter(Position=0)]
        $original
    )

    return ($($original -replace [regex]'^[0-9]*','') -replace [regex]'[^a-zA-Z0-9]','').ToLower()
}
