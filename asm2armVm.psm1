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

    if ($ArmImageReference)
    {
        $imageReference = new-
    }
}
