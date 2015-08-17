# ASM2ARM

Hello Azure expert! 

This is a PowerShell script module for migrating your Single Virtual Machine (VM) from Azure Service Management (ASM) stack to Azure Resource Manager (ARM) stack. It exposes only one single cmdlet: 
``` PowerShell
Add-AzureSMVmToRM
```

The cmdlet can either generate a set of ARM templates and imperative PowerShell scripts (if the VM has VM Agent Extensions), given a VM, or after generating those, deploy the VM (with the -deploy flag).

As for the VM, you have the option for either creating a clone of the given VM, with the blobs backing the disks (both OS and data) copied, or built one using the source as a recipe with completely new disks.

We recommend you to start without the -Deploy option, and look at the generated files. After looking at the generated files and you feel confident, run the scripts and deploy the templates.

## What does it do?
 1. Either copies the VMs disks over to an ARM storage account, or creates brand new ones (you are responsible to re-establish the state)
 2.  Creates a new virtual network, if the source VM is not in a VNET already, or uses the same name for the new VNET if it is in one. Same is true for subnets.
 3. It can either stop short of generating ARM templates and imperative script, or use those to deploy your new resources
 4. Creates an availability set if the VM is in one
 5. Creates a public IP if the VM is available on the internet
 6. Creates network security groups (NSG) for the source VMs public endpoints

## What does it not do?
**Following are not in the scope of these scripts**
 1. Stops a running VM 
 2. Changes your data/disks
 3. Migrates running VMs
 4. Migrates multiple VMs in a complex scenario automagically
 5. Migrates the entire ASM network configuration
 6. Creates load balanced VMs. We assume this is a configuration the Azure expert needs to handle explicitly
 
How to use it?
-----------------
 1. Start with bringing in the code with "git clone https://github.com/fullscale180/asm2arm.git"
 2. Either open a "Windows Azure PowerShell" session (shell or ISE) and dot-source "bootstrap.ps1" i.e. ". .\bootstrap.ps1", or start "bootstrap.cmd". This will create a new PS Session
 3. Run Add-AzureAccount to connect to your subscription
 4. Stay in AzureServiceManagement mode
 5. Either bring in a VM with Get-AzureVm, or directly use ServiceName & Name combination to give the VM to the Add-AzureSMVmToRM cmdlet.
 6. The session you start (or initialize) with bootstrap loads in two of the Azure PowerShell modules, Azure and AzureResourceManager. The standard scoping rules for PowerShell apply here. If you want to access the ASM version of Get-AzureVm, you need to scope it like Azure\Get-AzureVm, if you want to access the ARM version, then, AzureResourceManager\Get-AzureVm

## How does it work?
Let's start with an example, assume we have a VM, named *atestvm* deployed on a cloud service *acloudservice*.

This VM has
* Size Basic_A3
* Multiple data disks
* RDP port is open, public port is N, local port is 3389
* Not on a Vnet
* Not a member of availability set
 

We can refer to that VM in two ways using the cmdlet, ( -AppendTimeStampForFiles and -Deploy are optional flags)
* Using the Azure PowerShell VM object (PersistentVMRoleContext type as the result of *Get-AzureVm* cmdlet, and pass it as the value of the parameter VM, e.g.
``` PowerShell
$vm = Azure\Get-AzureVm -ServiceName acloudservice -Name atestvm
 
 Add-AzureSMVmToRM -VM $vm -ResourceGroupName aresourcegroupname -DiskAction CopyDisks -OutputFileFolder D:\myarmtemplates -OutputFileNameBase abasename -AppendTimeStampForFiles -Deploy
```
* Using the service name and VM name parameters directly
``` PowerShell
	Add-AzureSMVmToRM -ServiceName acloudservice -Name atestvm -ResourceGroupName aresourcegroupname -DiskAction CopyDisks -OutputFileFolder D:\myarmtemplates -OutputFileNameBase abasename -AppendTimeStampForFiles -Deploy
```



Tested configurations
--------
The _Add-AzureSMVmToRM_ cmdlet was validated using the following test cases:

| Test Case ID | Description |
|:---|:---|
| 1	| Windows VM with an existing OS disk |
| 2	| Linux VM with an existing OS disk |
| 3	| Windows VM with existing OS and data disks |
| 4	| Linux VM with existing OS and data disks |
| 5	| Windows VM with a new OS disk matched from Image Gallery |
| 6	| Linux VM with a new OS disk matched from Image Gallery |
| 7	| Windows VM with a new OS disk and empty data disks |
| 8	| Linux VM with a new OS disk and empty data disks |
| 9 | Windows VM with public endpoints |
| 10 | Linux VM with public endpoints |
| 11 | Windows VM with a WinRM certificate |
| 12 | Windows VM in a Vnet and subnet |
| 13 | Linux VM in a Vnet and subnet |
| 14 | Windows VM with custom extensions |
| 15 | Windows VM in an availability set |
| 16 | Windows VM in an availability set, with multiple data disks, public endpoints, in a vnet and subnet, and with custom extensions |
| 17 | Linux VM in an availability set, with multiple data disks, public endpoints, in a vnet and subnet, and with custom extensions |