# asm2arm

ASM2ARM
=========
Hello Azure expert! This is a PowerShell script module for migrating your Single VM from Azure Service Management stack to Azure Resource Manager stack.

What does it do?
-------------------
 1. Either copies the VMs disks over to an ARM storage account, or creates brand new ones (you are responsible to re-establish the state)
 2.  Creates a new virtual network, if the source VM is not in a VNET already, or uses the same name for the new VNET if it is in one. Same is for subnets
 3. It can either stop short of generating ARM templates and imperative script, or use those to deploy your new resources
 4. Creates an availability set if the VM is in one
 5. Creates a public IP if the VM is available on the internet
 6. Creates network security groups (NSG) for the source VMs public endpoints

What does it not do?
------------------------
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

Tested configurations
--------
The _Add-AzureSMVmToRM_ cmdlet was validated using the following test cases:

| Test Case ID | Description |
|:---|:---|
| 1	| Windows VM with an OS disk |
| 2	| Linux VM with an OS disk |
| 3	| Windows VM with an OS disk and multiple data disks	|
| 4	| Linux VM with an OS disk and multiple data disks |
| 5 | Windows VM with multiple public endpoints |
| 6 | Linux VM with multiple public endpoints |
| 7 | Windows VM with public endpoints and certs |
| 8 | Linux VM with public endpoints and certs |
| 9 | Windows VM in a Vnet and subnet |
| 10 | Linux VM in a Vnet and subnet |
| 11 | Windows VM with custom extensions |
| 12 | Windows VM in an availability set |
| 13 | Windows VM in an availability set, with multiple data disks, public endpoints, in a vnet and subnet, and with custom extensions |




