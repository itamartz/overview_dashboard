# Ping Agent

A lightweight PowerShell agent that monitors ICMP Ping status for a list of hosts and reports the results to the Overview Dashboard.

## Features

- Reads targets from a simple CSV/text file
- Evaluates severity based on ping success (`ok` = success, `error` = failure)
- Posts status, severity, and TTL to the Overview Dashboard API
- Supports `-DryRun` mode for testing without side-effects
- Supports `-MockRun` mode for simulating data

## Requirements

- Windows PowerShell 5.1 or PowerShell Core 7+
- Network access to target hosts (ICMP Echo Request)
- Network access to the Dashboard API

## Configuration

Targets are defined in `components.csv` in the same directory as the script. The file should contain one hostname or IP address per line:

```csv
google.com
8.8.8.8
myserver.local
```

## Usage

```powershell
# Run with default settings
.\Get-PingMetrics.ps1

# Run with custom parameters
.\Get-PingMetrics.ps1 -CsvPath "C:\custom_hosts.csv" -ApiUrl "https://dashboard.example.com/api/components" -DefaultTTL 120

# Run in DryRun mode (shows what would happen without sending API calls or making connections)
.\Get-PingMetrics.ps1 -DryRun

# Run in MockRun mode (sends fake random data to API for dashboard testing)
.\Get-PingMetrics.ps1 -MockRun
```

### Parameters

- `-CsvPath`: Path to the targets CSV file (default: `$PSScriptRoot\components.csv`)
- `-ApiUrl`: The Overview Dashboard API endpoint
- `-ProjectName`: The project grouping on the dashboard (default: "Ping Checks")
- `-SystemName`: The system grouping on the dashboard (default: "Network Monitoring")
- `-DefaultTTL`: Time-To-Live in seconds before marking offline (default: 60)
- `-TimeoutMs`: ICMP Ping timeout in milliseconds (default: 1000)
- `-DryRun`: Switch to enable DryRun mode
- `-MockRun`: Switch to enable MockRun mode
