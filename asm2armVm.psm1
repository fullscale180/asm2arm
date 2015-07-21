function New-VmStorageProfile 
{
	Param (
		$DiskAction,

		[Microsoft.WindowsAzure.Commands.ServiceManagement.Model.PersistentVMRoleContext]
		$VM,
		
		[string]
		$StorageAccountName,

		# Location to search the image reference in
		$Location,
        $ResourceGroupName        
	)

	$storageProfile = @{}
	$dataDisks = @()
	$osDiskCreateOption = "Attach"
	$dataDiskCreateOption = "Attach"

	# Construct a new URI for the OS disk, which will be placed in the new storage account
	$osDiskUri = Get-NewBlobLocation -SourceBlobUri $VM.VM.OSVirtualHardDisk.MediaLink.AbsoluteUri -StorageAccountName $StorageAccountName -ContainerName $Global:vhdContainerName

	# Use a vanilla VM disk image from the Azure gallery
	if ($DiskAction -eq "NewDisks")
	{
		# Find the VMs image on the catalog
		$vmImage = Azure\Get-AzureVMImage -ImageName $ImageName -ErrorAction SilentlyContinue -ErrorVariable $lastError

		if (-not $vmImage)
		{
			$message = "Disk image {0} cannot be found for the specified VM." -f $ImageName

			Write-Error $message
			throw $message
		}

		# Retrieve the ARM Image reference for a given ASM image
		$armImageReference = Get-AzureArmImageRef -Location $Location -Image $vmImage

		$imageReference =[PSCustomObject] @{'publisher' = $armImageReference.Publisher; `
											'offer'= $armImageReference.Offer;
											'sku'= $armImageReference.Skus;
											'version'= $armImageReference.Version;}  

		# Add the imageReference section to the resource metadata
		$storageProfile.Add('imageReference', $imageReference)    

		# Request that OS data disk is created from base image
		$dataDiskCreateOption = "FromImage"
		
		# Request that all data disks are created as empty
		$dataDiskCreateOption = "Empty"   
	}
	elseif ($DiskAction -eq "CopyDisks")
	{
		# Create a copy of the existing VM disk
		# Copy-VmDisks -VM $VM -StorageAccountName $StorageAccountName -ResourceGroupName $ResourceGroupName
	}
	elseif ($DiskAction -eq "KeepDisks")
	{
		# Reuse the existing OS disk image
		$osDiskUri = $VM.VM.OSVirtualHardDisk.MediaLink.AbsoluteUri
	}

	# Compose OS disk section
	$osDisk =[PSCustomObject] @{'name' = 'osdisk'; `
								'osType' = $VM.VM.OSVirtualHardDisk.OS;
								'vhd'= @{ 'uri' = $osDiskUri };
								'caching'= $vm.vm.OSVirtualHardDisk.HostCaching;
								'createOption'= $osDiskCreateOption;} 

	# Add the osDisk section to the resource metadata
	$storageProfile.Add('osDisk', $osDisk)                  

	# Compose data disk section
	foreach ($disk in $VM.VM.DataVirtualHardDisks)
	{
		# Modify data disk URI to point to a copy of the disk
		if ($DiskAction -eq "KeepDisks")
		{
			$dataDiskUri = $disk.MediaLink.AbsoluteUri
		}
		else
		{
			# Construct a new URI for the OS disk, which will be placed in the new storage account
			$dataDiskUri = Get-NewBlobLocation -SourceBlobUri $disk.MediaLink.AbsoluteUri -StorageAccountName $StorageAccountName -ContainerName $Global:vhdContainerName
		}

		$dataDisks += @{'name' = $disk.DiskName; `
						'diskSizeGB'= $disk.LogicalDiskSizeInGB;
						'lun'= $disk.Lun;
						'vhd'= @{ 'Uri' = $dataDiskUri };
						'caching'= $disk.HostCaching;
						'createOption'= $dataDiskCreateOption; }   
	}

	# Add the dataDisks section to the resource metadata
	$storageProfile.Add('dataDisks', [PSCustomObject] $dataDisks)  

	return $storageProfile
}


function Copy-VmDisks
{
	Param (
		[Microsoft.WindowsAzure.Commands.ServiceManagement.Model.PersistentVMRoleContext]
		$VM,

		[string]
		$StorageAccountName,
        $ResourceGroupName
	)
		$vmOsDiskStorageAccountName = ([System.Uri]$VM.VM.OSVirtualHardDisk.MediaLink).Host.Split('.')[0]
		$diskUrlsToCopy = @($VM.VM.OSVirtualHardDisk.MediaLink.AbsoluteUri)
		foreach ($disk in $VM.VM.DataVirtualHardDisks)
		{
			$diskUrlsToCopy += $disk.MediaLink.AbsoluteUri
		}
		
		# Prepare a context in case the source storage account is still the same
		$vmOsDiskStorageAccountKey = (Azure\Get-AzureStorageKey -StorageAccountName $vmOsDiskStorageAccountName).Primary
		$vmOsDiskStorageContext = Azure\New-AzureStorageContext -StorageAccountName $vmOsDiskStorageAccountName -StorageAccountKey $vmOsDiskStorageAccountKey

		# We are assuming we will be using the same storage account for all of the destination VM's disks.
		# However, please make sure to take the storage account's available throughput constraints into account.
		# Please see https://azure.microsoft.com/en-us/documentation/articles/storage-scalability-targets/ for details
		$destinationAccountKey = (AzureResourceManager\Get-AzureStorageAccountKey -Name $StorageAccountName -ResourceGroupName $ResourceGroupName).Key1 
		$destinationContext = AzureResourceManager\New-AzureStorageContext -StorageAccountName $StorageAccountName -StorageAccountKey $destinationAccountKey
		
		$previousStorageAccountName = ''
		$destContainerName = $Global:vhdContainerName

        # Create the destination container (if doesn't already exist)
        Azure\New-AzureStorageContainer -Context $destinationContext -Name $destContainerName -Permission Off -ErrorAction SilentlyContinue

		foreach ($srcVhdUrl in $diskUrlsToCopy)
		{
			$root, $rawContainerName, $srcBlobNameParts = ([System.Uri]$srcVhdUrl).Segments
			$srcAccountName = ([System.Uri]$srcVhdUrl).Host.Split('.')[0] 
            $srcContainerName = $rawContainerName.Replace("/", "")
            $destBlobName = $srcBlobNameParts -join ""

            # Compose an URL for the target blob
            $destVhdUrl = Get-NewBlobLocation -SourceBlobUri $srcVhdUrl -StorageAccountName $StorageAccountName -ContainerName $destContainerName

            # Set up the source storage account context in two cases: during the very first iteration and when storage account name changes between URLs
			if ($previousStorageAccountName -eq '' -or $previousStorageAccountName -ne $srcAccountName)
			{                
				$sourceAccountKey = (Azure\Get-AzureStorageKey -StorageAccountName $srcAccountName).Primary
                $sourceContext = Azure\New-AzureStorageContext -StorageAccountName $srcAccountName -StorageAccountKey $sourceAccountKey
			}  

            # Acquire a reference to the blob containing the source VHD
            $srcCloudBlob = Azure\Get-AzureStorageBlob -Context $sourceContext -Container $srcContainerName -Blob $destBlobName

            Write-Output $("Copying a VHD from {0} to {1}" -f $srcVhdUrl, $destVhdUrl)

            $blobCopy = AzureResourceManager\Start-AzureStorageBlobCopy -Context $sourceContext -ICloudBlob $srcCloudBlob.ICloudBlob -DestContext $destinationContext -DestContainer $destContainerName -DestBlob $destBlobName
			
            # Wait until the blob copy operation complete
            while(($blobCopy | Get-AzureStorageBlobCopyState).Status -eq "Pending")
            {
                Start-Sleep -s 10
            }

			$previousStorageAccountName = $srcAccountName
		}
}