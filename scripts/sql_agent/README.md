# SQL Monitoring Agent

PowerShell agent for monitoring SQL Server database backup status and state using dbatools.

## Requirements

- PowerShell 5.1 or later
- [dbatools](https://dbatools.io/) module (auto-installed on first run)
- Run on SQL Server host or machine with network access to SQL instances

## Quick Start

1. **Edit Configuration:**
   ```powershell
   notepad .\config.json
   ```
   Update with your SQL Server instances.

2. **Run the Agent:**
   ```powershell
   .\Get-SqlMetrics.ps1
   ```

3. **Test Without Connecting:**
   ```powershell
   .\Get-SqlMetrics.ps1 -MockRun
   ```

## Configuration

```json
{
  "apiUrl": "https://overview.526443026.xyz/api/components",
  "projectName": "SQL Databases",
  "systemName": "SQL Monitoring",
  "defaultTTL": 300,
  "backupWarningHours": 24,
  "backupErrorHours": 48,
  "servers": [
    {
      "name": "SQL-Server-01",
      "instance": "localhost",
      "enabled": true,
      "databases": []
    }
  ]
}
```

| Setting | Description |
|---------|-------------|
| `backupWarningHours` | Hours since backup to trigger warning |
| `backupErrorHours` | Hours since backup to trigger error |
| `databases` | Empty = all databases, or list specific names |

## Metrics Collected

| Metric | Description | Severity Logic |
|--------|-------------|----------------|
| **State** | Database state (ONLINE, OFFLINE, etc.) | ONLINE=ok, RESTORING=warning, OFFLINE/SUSPECT=error |
| **Last Backup** | Time since last full backup | Based on configured thresholds |

## Files

| File | Description |
|------|-------------|
| `Get-SqlMetrics.ps1` | Main agent script |
| `config.json` | SQL Server configuration |
| `README.md` | This documentation |
