function New-AvailabilitySetResource
{
    Param
    (
        $Name,
        $Location
    )

    $createProperties = [PSCustomObject] @{}

    $resource = New-ResourceTemplate -Type "Microsoft.Compute/availabilitySets" -Name $Name `
        -Location $Location -ApiVersion $Global:apiVersion -Properties $createProperties

    return $resource
 }

function New-VmResource 
{
    Param 
    (
        [Microsoft.WindowsAzure.Commands.ServiceManagement.Model.PersistentVMRoleContext]
        $VM,
        
        [PSCredential]
        $Credentials, 
        
        $NetworkInterfaceName,
        $DiskAction
    )


    $vmStorageProfile = $null

    if ($DiskAction -eq "NewDisks")
    {
		# Use a vanilla VM disk image from the Azure gallery
		$vmStorageProfile = New-VmStorageProfile -VM $VM -ImageName $VM.VM.OSVirtualHardDisk.SourceImageName -Location $location
    }
    elseif ($DiskAction -eq "KeepDisks")
    {
		# Use the existing VM disk images "as is"
        $vmStorageProfile = New-VmStorageProfile -VM $VM
    }
	elseif ($DiskAction -eq "CopyDisks")
    {
		# Create a copy of the existing VM disk
		Copy-VmDisks -VM $VM -StorageAccountName $StorageAccountName

		# Use copies of the existing VM disk images
        $vmStorageProfile = New-VmStorageProfile -VM $VM
    }

    if ($vmStorageProfile -eq $null)
    {
        throw "Cannot build storage profile"
    }
    
    $properties = @{}
    if ($vm.AvailabilitySetName -ne "")
    {

	}
}