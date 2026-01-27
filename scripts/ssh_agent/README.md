# SSH Monitoring Agent

PowerShell agent for collecting metrics from SSH-accessible devices and reporting to the Overview Dashboard.

## Requirements

- PowerShell 5.1 or later
- [Posh-SSH](https://github.com/darkoperator/Posh-SSH) module (auto-installed on first run)

## Quick Start

1. **Edit Configuration:**
   ```powershell
   notepad .\config.json
   ```
   Update targets with your device credentials and commands.

2. **Run the Agent:**
   ```powershell
   .\Get-SshMetrics.ps1
   ```

3. **Test Without Connecting:**
   ```powershell
   .\Get-SshMetrics.ps1 -DryRun
   ```

## Configuration

Edit `config.json` to define SSH targets and metrics. Credentials are stored in plain text.

```json
{
  "targets": [
    {
      "name": "Switch-01",
      "host": "192.168.1.1",
      "port": 22,
      "username": "admin",
      "password": "your_password",
      "enabled": true,
      "metrics": [
        {
          "name": "CPU Usage",
          "command": "show chassis routing-engine",
          "parser": "juniper_cpu",
          "thresholds": { "warning": 70, "error": 90 }
        }
      ]
    }
  ]
}
```

## Available Parsers

### Juniper Switches

| Parser | Command | Description |
|--------|---------|-------------|
| `juniper_cpu` | `show chassis routing-engine` | CPU utilization % |
| `juniper_memory` | `show chassis routing-engine` | Memory utilization % |
| `juniper_temperature` | `show chassis routing-engine` | Temperature in °C |

### Palo Alto Firewalls

| Parser | Command | Description |
|--------|---------|-------------|
| `paloalto_cpu` | `show system resources` | CPU usage % |
| `paloalto_memory` | `show system resources` | Memory usage % |
| `paloalto_disk` | `show system disk-space` | Disk usage % |
| `paloalto_sessions` | `show session info` | Active session count |
| `paloalto_session_util` | `show session info` | Session utilization % |

### Generic Parsers

| Parser | Description |
|--------|-------------|
| `generic_number` | Extracts first number from output |
| `generic_regex` | Custom regex (set `pattern` in metric config) |
| `raw` | Returns raw output as status text |

## Severity Calculation

- **ok**: Value < warning threshold
- **warning**: Value ≥ warning threshold AND < error threshold
- **error**: Value ≥ error threshold OR connection/parse failure

## Scheduling

Use Windows Task Scheduler to run periodically (external to script).

## Files

| File | Description |
|------|-------------|
| `Get-SshMetrics.ps1` | Main agent script |
| `parsers.ps1` | Output parsing functions |
| `config.json` | Device and metric configuration |
| `README.md` | This documentation |

## Additional Metrics to Consider

For network devices, you may also want to monitor:
- **Interface errors/drops** - packet errors on interfaces
- **BGP/OSPF neighbor status** - routing protocol health
- **HA status** - high availability state
- **License expiration** - days until license expires
- **VPN tunnel status** - IPsec tunnel up/down count
