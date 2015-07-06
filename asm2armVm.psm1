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
        $url = $VM.VM.OSVirtualHardDisk.MediaLink

        # Get the source storage account name from the URL the format on the 
        # blob store should be <storage account name>..blob.core.windows.net
        $sourceStorageAccountName = ([System.Uri]$url).Host.Split('.')[0]

        $sourceAccountKey = (Azure\Get-AzureStorageKey -StorageAccountName $sourceStorageAccountName).Primary
        $sourceContext = Azure\New-AzureStorageContext -StorageAccountName $sourceStorageAccountName -StorageAccountKey $sourceAccountKey




    }

}
