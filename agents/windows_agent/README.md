# Windows Agent for Overview Dashboard

Windows system monitoring agent that gathers CPU, memory, disk, and service metrics and posts them to the Overview Dashboard API.

## Features

- **CPU Usage**: Real-time CPU utilization percentage (using Performance Counters)
- **Memory Usage**: Memory utilization percentage (using WMI)
- **Disk Usage**: Usage for all local fixed disks
- **Service Monitoring**: Detects stopped automatic services
- **Severity Calculation**: Automatic severity (ok/warning/error) based on configurable thresholds

## Requirements

- Windows PowerShell 5.1+ or PowerShell Core
- Administrator rights (recommended for full service monitoring)
- Network access to the Dashboard API

## Files

| File | Description |
|------|-------------|
| `Get-SystemMetrics.ps1` | Core metrics gathering script |
| `Post-SystemMetrics.ps1` | Posts metrics to the Dashboard API |
| `Install-ScheduledTask.ps1` | Helper script to set up Windows Task Scheduler |

## Quick Start

### 1. Test the Agent

```powershell
# Run the metrics gatherer standalone
.\Get-SystemMetrics.ps1

# Run with custom thresholds
.\Get-SystemMetrics.ps1 -ThresholdWarning 80 -ThresholdError 90
```

### 2. Post Metrics Manually

```powershell
.\Post-SystemMetrics.ps1
```

### 3. Install Scheduled Task

```powershell
# Install with default 5-minute interval
.\Install-ScheduledTask.ps1

# Install with custom interval (every 10 minutes)
.\Install-ScheduledTask.ps1 -IntervalMinutes 10

# Preview without installing
.\Install-ScheduledTask.ps1 -DryRun

# Remove the scheduled task
.\Install-ScheduledTask.ps1 -Remove
```

## Configuration Options

### Thresholds

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-ThresholdWarning` | 85 | Warning threshold (%) |
| `-ThresholdError` | 95 | Error threshold (%) |

### Payload Settings

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-ProjectName` | Workstations | Project name in the dashboard |
| `-SystemName` | Monitoring | System name in the dashboard |

### API Settings

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-ApiUrl` | `http://localhost:5000/api/components` | API endpoint |
| `-TimeoutSeconds` | 10 | Request timeout (seconds) |

### Ignored Services

By default, these services are ignored when checking for stopped automatic services:

- `edgeupdate`, `edgeupdatem` (Microsoft Edge Update)
- `GoogleUpdaterService*` (Google Update)
- `gupdate`, `gupdatem` (Google Update)
- `MapsBroker` (Windows Maps)
- `WslInstaller` (WSL)
- `sppsvc` (Software Protection)
- `RtkBtManServ` (Realtek Bluetooth)

Customize with `-IgnoreServices`:

```powershell
.\Get-SystemMetrics.ps1 -IgnoreServices @('MyService', 'AnotherService*')
```

## Example Usage

### Custom Project Configuration

```powershell
.\Post-SystemMetrics.ps1 -ApiUrl "http://myserver:5000/api/components"
```

### Direct Metrics with Custom Thresholds

```powershell
.\Get-SystemMetrics.ps1 -ThresholdWarning 80 -ThresholdError 90 -ProjectName "Production"
```

## Task Scheduler Options

The `Install-ScheduledTask.ps1` creates a task with:

| Setting | Value |
|---------|-------|
| Run on battery | Yes |
| Stop on battery | No |
| Start when available | Yes |
| Network required | Yes |
| Multiple instances | Ignore new |

## Output Format

The agent outputs JSON in the following format:

```json
{
  "projectName": "Workstations",
  "systemName": "Monitoring",
  "payload": {
    "Id": "DESKTOP-ABC123",
    "Name": "DESKTOP-ABC123",
    "CPU": "15.23%",
    "Memory": "45.67%",
    "Disks": "C: (32%), D: (55%)",
    "Services": "All Automatic Services Running",
    "Severity": "ok"
  }
}
```

## Troubleshooting

### Execution Policy Error

```powershell
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope CurrentUser
```

### Permission Issues

Run PowerShell as Administrator for:
- Full service monitoring
- Installing scheduled tasks for all users

### Task Not Running

1. Check Task Scheduler: `taskschd.msc`
2. Verify task status: `Get-ScheduledTask -TaskName "OverviewDashboard-SystemMetrics"`
3. Run manually: `Start-ScheduledTask -TaskName "OverviewDashboard-SystemMetrics"`

### Network Issues

Test API connectivity:

```powershell
Invoke-RestMethod -Uri "http://localhost:5000/api/components" -Method Get
```

## Comparison with Linux Agent

| Feature | Windows Agent | Linux Agent |
|---------|--------------|-------------|
| Language | PowerShell | Python 3 |
| CPU Metrics | Performance Counter | /proc/stat |
| Memory Metrics | WMI | /proc/meminfo |
| Disk Metrics | WMI | df command |
| Service Monitoring | Windows Services | systemd |
| Scheduling | Task Scheduler | cron |
