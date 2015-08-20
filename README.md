# ASM2ARM

Hello Azure expert! 

This is a PowerShell script module for migrating your **single** Virtual Machine (VM) from Azure Service Management (ASM) stack to Azure Resource Manager (ARM) stack. It exposes two commandlets: 
``` PowerShell
Add-AzureSMVmToRM
New-AzureSmToRMDeployment
```

The first commandlet can either generate a set of ARM templates and imperative PowerShell scripts (to copy the disk blobs and if the VM has VM Agent Extensions), given a VM, or after generating those, deploy the VM (with the -deploy flag), using the New-AzureSmToRMDeployment commandlet.

As for the VM, you have the option for either creating a clone of the given VM, with the blobs backing the disks (both OS and data) copied, or built one using the source as a recipe with completely new disks.

We recommend you to start without the -Deploy option, and look at the generated files. After looking at the generated files and you feel confident, run the scripts and deploy the templates using the New-AzureSmToRMDeployment commandlet. If the Add-AzureSMVmToRM is run without the -Deploy switch, it generates a line to run the New-AzureSMToRMDeployment commandlet.

## What does it do?
 1. Either copies the VMs disks over to an ARM storage account, or creates brand new ones (you are responsible to re-establish the state)
 2. Creates a new virtual network, if the source VM is not in a VNET already, or uses the same name for the new VNET if it is in one. Same is true for subnets.
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
2. You can load the module either from the command line or Windows Explorer by running bootstrap.cmd or from a PowerShell session by dot-sourcing the bootstrap.ps1 (i.e. ". .\bootstrap.ps1", notice the "." space and full path to the file)
3. The session you start (or initialize) with bootstrap loads in two of the Azure PowerShell modules, Azure and AzureResourceManager. The standard scoping rules for PowerShell apply here. If you want to access the ASM version of Get-AzureVm, you need to scope it like Azure\Get-AzureVm, if you want to access the ARM version, then, AzureResourceManager\Get-AzureVm
4. Run Add-AzureAccount to connect to your subscription
5. Either bring in a VM with Get-AzureVm, or directly use ServiceName & Name combination to give the VM to the Add-AzureSMVmToRM commandlet. 
 
Please see the examples below:
This PowerShell session is started running bootstrap.cmd
![bootstrap.cmd from Windows Explorer or command line](https://github.com/fullscale180/asm2arm/blob/master/docAssets/bootstrapcmd.gif) 

Whereas this one is started by dot-sourcing bootstrap.ps1 file from within an existing PowerShell session
![bootstrap.ps1 from a PowerShell session](https://github.com/fullscale180/asm2arm/blob/master/docAssets/bootstrapps1.gif)


## How does it work?
We can refer to that VM in two ways using the commandlet, ( -AppendTimeStampForFiles and -Deploy are optional flags)
* Using the Azure PowerShell VM object (PersistentVMRoleContext type as the result of *Get-AzureVm* commandlet, and pass it as the value of the parameter VM, e.g.
``` PowerShell
$vm = Azure\Get-AzureVm -ServiceName acloudservice -Name atestvm
 
 Add-AzureSMVmToRM -VM $vm -ResourceGroupName aresourcegroupname -DiskAction CopyDisks -OutputFileFolder D:\myarmtemplates -AppendTimeStampForFiles -Deploy
```
* Using the service name and VM name parameters directly
``` PowerShell
	Add-AzureSMVmToRM -ServiceName acloudservice -Name atestvm -ResourceGroupName aresourcegroupname -DiskAction CopyDisks -OutputFileFolder D:\myarmtemplates -AppendTimeStampForFiles -Deploy
```

The commandlet honors the -verbose option. Set that option to see the detailed diagnosis information.

The high-level operating principle of the commandlet is to go through steps for cloning the VM, and generate resources as custom PowerShell hash tables for Storage, Network and Compute resource providers.
Those hash tables representing the resources are appended to an array, later turned into a template by serialized to JSON, and written to a file.

The template creates files depending on the existence of VM agent extensions and DiskAction option value. Those are all placed in the directory specified by OutputFileFolder parameter. The files are:
1. `<ServiceName>-<VMName>-setup<optional timestamp>.json`: This file represents the resources that are needed to be prepared before the VM is cloned, and potentially be the same for any subsequent VMs (we do not maintain state between subsequent runs, but since a storage account needs to be provisioned before a blob copy operation happens, which is done imperatively, it was only logical to group like resources into one)

2.  `<ServiceName>-<VMName>-deploy<optional timestamp>.json`: Contains the template for the VM
3.  `<ServiceName>-<VMName>-parameters<optional timestamp>.json`: Contains the actual parameters passed to the templates
4.  `<ServiceName>-<VMName>-setextensions<optional timestamp>.json`: a set of PowerShell commandlets to be run for setting the VM agent extensions.
4.  `<ServiceName>-<VMName>-copydisks<optional timestamp>.json`: a set of PowerShell commandlets to be run for copying disk blobs, if CopyDisks option is specified.

If the -Deploy flag is set, after generating the files, the commandlet then deploys the <ServiceName>-<VMName>-setup.json template, copies the source VM disk blobs if the DiskAction parameter is set to CopyDisks and then deploys the <ServiceName>-<VMName>-deploy.json template, using the <ServiceName>-<VMName>-parameters.json file for parameters. Once the deployment of the VM is done, if there is an imperative script (for VM agent extensions), or a script for copying the disks, they are executed.

### Network details
The commandlet's intent is not to clone the ASM network settings to ARM. It utilizes the networking facilities in a way that is the most convenient for cloning the VM itself. Here is what happens on different conditions:

1.  No virtual network on the target resource group
    2. Source VM is not on a subnet: A default virtual network with 10.0.0.0/16 is created along with a subnet, with 10.0.0.0/22 address space.
    3. Source VM is on a subnet: The virtual network the VM is on is discovered, the specification of the virtual network, along with the subnets are copied over
2.  Target resource group has a virtual network with a name `<VM virtual network>arm` (the string 'arm' is appended)
    3. If the virtual network has a subnet with the same name and address space, use it
    4. If no suitable subnet is found, find an address block out of the existing subnets with 22 bits mask and use that one.
	
Tested configurations
--------
The _Add-AzureSMVmToRM_ commandlet was validated using the following test cases:

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

## Notes
1. If multiple VMs are cloned one after the other with short time intervals in between them, there might be DNS name conflicts for the public IP addresses, due to the DNS cache refresh time.
