# asm2arm

Testing Approach
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

Notes, Known Issues & Limitations
--------
- Load balanced endpoints are not currently supported. These must be migrated manually for now.
- To migrate multiple VMs, invoke the _Add-AzureSMVmToRM_ cmdlet iteratively from within a loop.
