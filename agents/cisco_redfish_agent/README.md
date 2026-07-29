# Cisco Redfish Agent

Monitors Cisco CIMC devices via the Redfish API and reports health metrics to the Overview Dashboard.

## Features

- **System Health**: Monitors overall system health, power state, and memory status.
- **Processors**: Monitors health of all CPUs.
- **Storage & Disks**: Monitors storage controllers and individual drive health.
- **Power Supplies**: Monitors PSU health and wattage.
- **Thermal**: Monitors temperatures and fans.
- **CyberArk CCP Integration**: Retrieves credentials securely via CyberArk AIMWebService.

## Requirements

- PowerShell 5.1+
- Network access to the Cisco CIMC Redfish API (TCP 443)
- Appropriate Redfish credentials (preferably via CyberArk)

## Configuration

Edit the `config.json` file to configure your targets.

```json
{
  "apiUrl": "https://overview.tazone.net/api/components",
  "projectName": "CIMC",
  "systemName": "Cisco CIMC",
  "defaultTTL": 3600,
  "credentialMethod": "cyberark",
  "cyberark": {
    "ccpUrl": "https://pamweb/AIMWebService/api/Accounts",
    "appId": "OverviewDashboardAgent",
    "verifySsl": false,
    "timeoutSeconds": 10,
    "cacheMinutes": 5
  },
  "targets": [
    {
      "name": "SERVER01",
      "host": "SERVER01",
      "username": "admin",
      "cyberarkSafe": "RedfishSafe",
      "cyberarkObject": "SERVER01-admin",
      "enabled": true
    }
  ]
}
```

## Usage

### Test Configuration (Dry Run)
Validates configuration without connecting or sending data.
```powershell
.\Get-CiscoRedfishMetrics.ps1 -DryRun
```

### Test API (Mock Run)
Sends mock data to the Dashboard API to verify connectivity.
```powershell
.\Get-CiscoRedfishMetrics.ps1 -MockRun
```

### Normal Execution
Runs the agent, retrieves credentials, queries devices, and posts to the API.
```powershell
.\Get-CiscoRedfishMetrics.ps1
```
