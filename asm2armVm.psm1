function New-VmStorageProfile 
{
    Param (

        [PsCustomObject]
        $ArmImageReference,

        [Microsoft.WindowsAzure.Commands.ServiceManagement.Model.PersistentVMRoleContext]
        $VM,

        [switch]
        $KeepDisks,

        [string]
        $StorageAccountName,

        [switch]
        $CopyDisks
    )

    $storageProfile = @{}
    if ($ArmImageReference)
    {
        $imageReference =[PSCustomObject] @{'publisher' = $ArmImageReference.Publisher; `
                                            'offer'= $ArmImageReference.Offer;
                                            'sku'= $ArmImageReference.Skus;
                                            'version'= $ArmImageReference.Version;}  
        $storageProfile.Add('imageReference', $imageReference)                  
    }

    $osDisk = @{}
    $dataDisks = @()

    if ($CopyDisks.IsPresent)
    {

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
        $diskUrlsToCopy = @($VM.VM.OSVirtualHardDisk.MediaLink)
        
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

}
