function New-VmStorageProfile 
{
	Param (
		[Parameter(Mandatory=$true, ParameterSetName='Virtual Machine')]
		[ValidateNotNull()]
		[ValidateNotNullOrEmpty()]
		[Microsoft.WindowsAzure.Commands.ServiceManagement.Model.PersistentVMRoleContext]
		$VM,

		[Parameter(Mandatory=$false, ParameterSetName='Storage Account')]
		[ValidateNotNull()]
		[ValidateNotNullOrEmpty()]
		[string]
		$StorageAccountName,

		[Parameter(Mandatory=$false, ParameterSetName='Gallery Image')]
		$ImageName,

		# Location to search the image reference in
		[Parameter(Mandatory=$false, ParameterSetName='Gallery Image')]
		$Location
	)

	$storageProfile = @{}
	$dataDisks = @()

	if ($ImageName)
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
	}

	# Compose OS disk section
	$osDisk =[PSCustomObject] @{'name' = 'osdisk'; `
								'vhd'= @{ 'uri' = $VM.VM.OSVirtualHardDisk.MediaLink.AbsoluteUri};
								'caching'= 'ReadWrite';
								'createOption'= 'FromImage';} 

	# Add the osDisk section to the resource metadata
	$storageProfile.Add('osDisk', $osDisk)                  

	# Compose data disk section
	foreach ($disk in $VM.VM.DataVirtualHardDisks)
	{
		$dataDisks += @{'name' = $disk.DiskName; `
						'diskSizeGB'= $disk.LogicalDiskSizeInGB;
						'lun'= $disk.Lun;
						'vhd'= @{ 'Uri' = $disk.MediaLink.AbsoluteUri};
						'caching'= 'ReadWrite';
						'createOption'= 'FromImage';}   
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
		$StorageAccountName
	)

	 $copyScriptBlock = {
			param($srcUrl, $srcContext, $srcContainer, $srcBlob, $destContainer, $destBlob, $destContext)

			
			if ($srcUrl -ne "" -and $srcContext -eq $null)
			{
				# We are doing this for each disk url, since they can be on different storage accounts.
				# Get the source storage account name from the URL the format on the 
				# blob store should be <storage account name>..blob.core.windows.net
				$sourceStorageAccountName = ([System.Uri]$srcUrl).Host.Split('.')[0]

				$sourceAccountKey = (Azure\Get-AzureStorageKey -StorageAccountName $sourceStorageAccountName).Primary
				$srcContext = Azure\New-AzureStorageContext -StorageAccountName $sourceStorageAccountName -StorageAccountKey $sourceAccountKey
				$root, $container, $blobName = ([System.Uri]$srcUrl).Segments            

				$srcContainer = $container.Replace("/", "")

				# Put the blob name back together again
				$srcBlob = $blobName -join ""
			}

			$srcICloudBlob = Azure\Get-AzureStorageBlob -Context $srcContext -Container $srcContainer -Blob $srcBlob

			AzureResourceManager\Start-AzureStorageBlobCopy -Context $srcContext -ICloudBlob $srcICloudBlob.ICloudBlob -DestContext $destContext -DestContainer $destContainer -DestBlob $destBlob

			Get-AzureStorageBlobCopyState -Container $destContainer -Blob $destBlob -WaitForComplete

			Write-Output $("Copying blob {0} to container {1}, " -f $destBlob, $destContainer)
		}

		# We are assuming we will be using the same storage account for all of the destination VM's disks.
		# However, please make sure to take the storage account's available throughput constraints into account.
		# Please see https://azure.microsoft.com/en-us/documentation/articles/storage-scalability-targets/ for details
		$destinationAccountKey = (AzureResourceManager\Get-AzureStorageAccountKey -Name $StorageAccountName).Key1
		$destinationContext = AzureResourceManager\New-AzureStorageContext -StorageAccountName $sourceStorageAccountName -StorageAccountKey $destinationAccountKey

		$vmOsDiskStorageAccountName = ([System.Uri]$VM.VM.OSVirtualHardDisk.MediaLink).Host.Split('.')[0]
		$diskUrlsToCopy = @($VM.VM.OSVirtualHardDisk.MediaLink.AbsoluteUri)
		foreach ($disk in $VM.VM.DataVirtualHardDisks)
		{
			$diskUrlsToCopy += $disk.MediaLink.AbsoluteUri
		}
		
		# Prepare a context in case the source storage account is still the same
		$vmOsDiskStorageAccountKey = (Azure\Get-AzureStorageKey -StorageAccountName $vmOsDiskStorageAccountName).Primary
		$vmOsDiskStorageContext = Azure\New-AzureStorageContext -StorageAccountName $vmOsDiskStorageAccountName -StorageAccountKey $vmOsDiskStorageAccountKey
		$root, $container, $blobName = ([System.Uri]$srcUrl).Segments 

		# Prepare destination context 

		$previousStorageAccountName = ""
		$copyJobs = @()
		$destContainerName = "vhds"

		foreach ($url in $diskUrlsToCopy)
		{
			$root, $container, $blobName = ([System.Uri]$srcUrl).Segments

			$storageAccountName = ([System.Uri]$url).Host.Split('.')[0] 
			$parameterList = @()
			if ($previousStorageAccountName -ne "" -and $StorageAccountName -ne $previousStorageAccountName)
			{                
				$parameterList = @($url, $null, "", "", $destContainerName, $blobName, $destinationContext)
			}  
			else {
				$parameterList = @("", $vmOsDiskStorageContext, $container, $blobName, $destContainerName, $blobName, $destinationContext)
			}

			$jobName = "Copy blob {0} on container {1}" -f $blobName, $container

			$previousStorageAccountName = $StorageAccountName

			$copyJobs += Start-Job -ScriptBlock $copyScriptBlock -Name $jobName -ArgumentList $parameterList
		}

		Wait-Job -Job $copyJobs
		Receive-Job -Job $copyJobs
		Remove-Job -Job $copyJobs
}