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

    
    $properties = @{}
    if ($vm.AvailabilitySetName -ne "")
    {
        $availabilitySet = [PSCustomObject] @{'id' = '[resourceId(''Microsoft.Compute/availabilitySets'',''{0}'')]' -f $vm.AvailabilitySetName;}
        $properties.Add('availabilitySet', $availabilitySet)
    }

    $vmSize = Get-AzureArmVmSize -Size $VM.InstanceSize
    $vmStorageProfile = New-VmStorageProfile -DiskAction $DiskAction -VM $VM -StorageAccountName $storageAccountName

    if ($vmStorageProfile -eq $null)
    {
        throw "Cannot build storage profile"
    }

    $osProfile = @{'computerName' = $vm.Name; 'adminUsername' = $Credentials.UserName; 'adminPassword' = $Credentials.Password}
    
    $endpoints = $VM | Azure\Get-AzureEndpoint

    if ($VM.vm.OSVirtualHardDisk.OS -eq "Windows")
    {
        
        $winRMListeners = @()
        $winRmEndpoint = $endpoints | Where-Object {$_.Name -eq "PowerShell"}
        if ($winRmEndpoint -ne $null)
        {
            $wimRmUrlScheme = ($VM | Azure\Get-AzureWinRMUri).Scheme
            
          
            $listener = 

        }
        
        $windowsConfiguration = @{
                'provisionVMAgent' = $vm.vm.ProvisionGuestAgent;
                'winRM' = @{
                    'listeners' = '';
                }
            }
    }
}

function Get-AzureArmVmSize 
{
	Param 
	(
		$Size
	)

	$sizes = @{
	   "ExtraSmall" = "Standard_A0  ";
	"Small" = "Standard_A1  ";
	"Medium" = "Standard_A2  ";
	"Large" = "Standard_A3  ";
	"ExtraLarge" = "Standard_A4  ";
	"Basic_A0" = "Basic_A0     ";
	"Basic_A1" = "Basic_A1     ";
	"Basic_A2" = "Basic_A2     ";
	"Basic_A3" = "Basic_A3     ";
	"Basic_A4" = "Basic_A4     ";
	"A5" = "Standard_A5  ";
	"A6" = "Standard_A6  ";
	"A7" = "Standard_A7  ";
	"A8" = "Standard_A8";
	"A9" = "Standard_A9";
	"A10" = "Standard_A10";
	"A11" = "Standard_A11";
	"Standard_D1" = "Standard_D1  ";
	"Standard_D2" = "Standard_D2  ";
	"Standard_D3" = "Standard_D3  ";
	"Standard_D4" = "Standard_D4  ";
	"Standard_D11" = "Standard_D11 ";
	"Standard_D12" = "Standard_D12 ";
	"Standard_D13" = "Standard_D13 ";
	"Standard_D14" = "Standard_D14 ";
	"Standard_G1  " = "Standard_G1  ";
	"Standard_G2  " = "Standard_G2  ";
	"Standard_G3  " = "Standard_G3  ";
	"Standard_G4  " = "Standard_G4  ";
	"Standard_G5  " = "Standard_G5  ";
	"Standard_DS1 " = "Standard_DS1 ";
	"Standard_DS2 " = "Standard_DS2 ";
	"Standard_DS3 " = "Standard_DS3 ";
	"Standard_DS4 " = "Standard_DS4 ";
	"Standard_DS11" = "Standard_DS11";
	"Standard_DS12" = "Standard_DS12";
	"Standard_DS13" = "Standard_DS13";
	"Standard_DS14" = "Standard_DS14";
	"Basic_D1" = "Basic_D1";
	"Basic_D11" = "Basic_D11";
	"Basic_D12" = "Basic_D12";
	"Basic_D13" = "Basic_D13";
	"Basic_D2" = "Basic_D2";
	"Basic_D3" = "Basic_D3";
	"Basic_D4" = "Basic_D4";
	"Basic_D5" = "Basic_D5";
	}

	return $sizes[$Size]

}