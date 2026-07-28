# TCP Agent

A lightweight PowerShell agent that monitors TCP port connectivity for a list of hosts and reports the results to the Overview Dashboard.

## Features

- Reads targets from a CSV file (Host, Port)
- Evaluates severity based on TCP connection success (`ok` = all ports connected, `error` = any port failed)
- Posts status, severity, and TTL to the Overview Dashboard API
- Groups multiple ports under the same host component
- Supports `-DryRun` mode for testing without side-effects
- Supports `-MockRun` mode for simulating data

## Requirements

- Windows PowerShell 5.1 or PowerShell Core 7+
- Network access to target hosts and ports
- Network access to the Dashboard API

## Configuration

Targets are defined in `components.csv` in the same directory as the script. The file format is `Host,Port` or `Host,Port,Name` (no header row):

```csv
google.com,443,Google Web
8.8.8.8,53,Google DNS
myserver.local,22,My Server SSH
myserver.local,80,My Server HTTP
```
*(If the 3rd `Name` column is missing, the host field is used as the component name.)*

## Usage

```powershell
# Run with default settings
.\Get-TcpMetrics.ps1

# Run with custom parameters
.\Get-TcpMetrics.ps1 -CsvPath "C:\tcp_targets.csv" -ApiUrl "https://dashboard.example.com/api/components" -DefaultTTL 120

# Run in DryRun mode (shows what would happen without sending API calls or making connections)
.\Get-TcpMetrics.ps1 -DryRun

# Run in MockRun mode (sends fake random data to API for dashboard testing)
.\Get-TcpMetrics.ps1 -MockRun
```

### Parameters

- `-CsvPath`: Path to the targets CSV file (default: `$PSScriptRoot\components.csv`)
- `-ApiUrl`: The Overview Dashboard API endpoint
- `-ProjectName`: The project grouping on the dashboard (default: "TCP Checks")
- `-SystemName`: The system grouping on the dashboard (default: "Network Monitoring")
- `-DefaultTTL`: Time-To-Live in seconds before marking offline (default: 60)
- `-TimeoutMs`: TCP connection timeout in milliseconds (default: 1000)
- `-DryRun`: Switch to enable DryRun mode
- `-MockRun`: Switch to enable MockRun mode
