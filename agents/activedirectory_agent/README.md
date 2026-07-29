# Active Directory Monitoring Agent

This agent runs locally on a Domain Controller to monitor the health of Active Directory.

## What it does
1. **Checks Mandatory Services**: Verifies that required AD services are running (e.g., `NTDS`, `Netlogon`, `DNS`, `Kdc`, `W32Time`, `SamSs`, `RpcSs`).
2. **Runs DCDiag**: Executes `dcdiag /q` to run quiet tests (checking connectivity, replication, sysvol, etc.).
3. **Compound Severity**: If any service is down or if `dcdiag` reports failures, the agent reports an `error` status to the Overview Dashboard.

## Prerequisites
- Must be run directly on a Domain Controller.
- Requires standard Active Directory Domain Services role installed (which provides `dcdiag.exe`).

## Configuration
Edit `config.json` to adjust the API URL, system name, or the list of services to monitor.

```json
{
  "apiUrl": "https://overview.tazone.net/api/components",
  "projectName": "Active Directory",
  "systemName": "Infrastructure Monitoring",
  "defaultTTL": 3600,
  "credentialMethod": "plaintext",
  "services": [
    "NTDS",
    "Netlogon",
    "DNS",
    "Kdc",
    "W32Time",
    "SamSs",
    "RpcSs"
  ]
}
```

## Running the Agent

Run safely without sending API requests:
```powershell
.\Get-ActiveDirectoryMetrics.ps1 -DryRun
```

Run with mock data to test the API dashboard connection:
```powershell
.\Get-ActiveDirectoryMetrics.ps1 -MockRun
```

Run normally (ideal for Task Scheduler):
```powershell
.\Get-ActiveDirectoryMetrics.ps1
```
