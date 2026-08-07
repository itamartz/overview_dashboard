# VMware Monitoring Agent

The VMware Monitoring Agent connects to vCenter servers to collect health metrics, parse them, and report their status to the Overview Dashboard API.

## Architecture

This agent uses **Pattern A: Self-Contained Agent** design:
- `Get-VmwareMetrics.ps1`: The main script that queries vCenter, parses results, calculates severity, and posts to the API.
- `config.json`: The configuration file storing endpoints, thresholds, and target vCenter instances.

## Prerequisites

- **PowerShell 7+** or Windows PowerShell 5.1
- **VMware PowerCLI** module installed (`Install-Module -Name VMware.PowerCLI -Scope CurrentUser`)
- Access to the target vCenter instances (port 443)
- CyberArk CCP configured for `Get-CyberArkCredential` resolution (if using CyberArk)

## Configuration (`config.json`)

```json
{
  "apiUrl": "https://overview.tazone.net/api/components",
  "systemName": "VMWare",
  "defaultTTL": 3600,
  "credentialMethod": "cyberark",
  "cyberark": {
    "ccpUrl": "https://pamweb.COMPANY.DOMAIN/AIMWebService/api/Accounts",
    "appId": "OverviewDashboardAgent",
    "verifySsl": false,
    "timeoutSeconds": 10,
    "cacheMinutes": 5
  },
  "targets": [
    {
      "name": "VCENTER01",
      "host": "VCENTER01",
      "username": "administrator@COMPANY.vsphere.local",
      "cyberarkSafe": "VMware-Admins",
      "cyberarkObject": "VCENTER01-admin",
      "datastoresThreshold": 10,
      "licensesThreshold": 90,
      "backupsDays": 7,
      "archivePartition": 70,
      "excludedVMsFromBackup": [
        "vCLS",
        "vSAN File Service Node"
      ],
      "enabled": true
    }
  ]
}
```

### Metrics & Thresholds Explained

- `datastoresThreshold`: Warns if free datastore capacity falls below this percentage.
- `licensesThreshold`: Warns if license utilization exceeds this percentage.
- `backupsDays`: Reports error if appliance backup hasn't succeeded within this many days.
- `archivePartition`: Reports error if archive partition use exceeds this percentage.
- `excludedVMsFromBackup`: Names (or parts of names) of VMs to ignore during backup status checks.

## Usage

Test without API connection (Dry Run):
```powershell
.\Get-VmwareMetrics.ps1 -DryRun
```

Test with mock data generation (Mock Run):
```powershell
.\Get-VmwareMetrics.ps1 -MockRun
```

Run fully:
```powershell
.\Get-VmwareMetrics.ps1
```

## Collected Projects

The agent pushes data to the Dashboard categorized into the following `projectName` categories under the `VMWare` system:

1. **vCenter**: Core appliance health, backup jobs, archive partition, certificates, and license usage.
2. **Datacenter**: Datacenter alarms.
3. **ESXI**: Host connectivity, VMnic statuses, host certificate expiration, and CPU & Memory usage percentage thresholds.
4. **VMs**: Individual VM backup status verification via VM tags/annotations.

