# Linux Agent for Overview Dashboard

Linux system monitoring agent that gathers CPU, memory, disk, and service metrics and posts them to the Overview Dashboard API.

## Features

- **CPU Usage**: Real-time CPU utilization percentage (using `/proc/stat`)
- **Memory Usage**: Memory utilization percentage (using `/proc/meminfo`)
- **Disk Usage**: Usage for all mounted filesystems (excluding virtual filesystems)
- **Service Monitoring**: Detects failed systemd services
- **Severity Calculation**: Automatic severity (ok/warning/error) based on configurable thresholds

## Requirements

- Python 3.6+
- Linux with systemd (for service monitoring)
- Network access to the Dashboard API

## Files

| File | Description |
|------|-------------|
| `get_system_metrics.py` | Core metrics gathering module |
| `post_system_metrics.py` | Posts metrics to the Dashboard API |
| `install_cron.sh` | Helper script to set up cron job |

## Quick Start

### 1. Test the Agent

```bash
# Run the metrics gatherer standalone
python3 get_system_metrics.py

# Run with JSON output only
python3 get_system_metrics.py --json-only
```

### 2. Post Metrics Manually

```bash
python3 post_system_metrics.py
```

### 3. Install Cron Job

```bash
# Install with default 5-minute interval
./install_cron.sh

# Install with custom interval (every 10 minutes)
./install_cron.sh --interval 10

# Preview without installing
./install_cron.sh --dry-run

# Remove the cron job
./install_cron.sh --remove
```

## Configuration Options

### Thresholds

| Parameter | Default | Description |
|-----------|---------|-------------|
| `--threshold-warning` | 85 | Warning threshold (%) |
| `--threshold-error` | 95 | Error threshold (%) |

### Payload Settings

| Parameter | Default | Description |
|-----------|---------|-------------|
| `--project-name` | Workstations | Project name in the dashboard |
| `--system-name` | Monitoring | System name in the dashboard |

### API Settings

| Parameter | Default | Description |
|-----------|---------|-------------|
| `--api-url` | `http://localhost:5000/api/components` | API endpoint |
| `--timeout` | 10 | Request timeout (seconds) |

### Service Monitoring

| Parameter | Description |
|-----------|-------------|
| `--ignore-services` | List of services to ignore (supports wildcards) |
| `--check-stopped` | Also check for stopped enabled services |

## Example Usage

### Custom Project Configuration

```bash
python3 post_system_metrics.py \
    --project-name "Production" \
    --system-name "WebServers" \
    --threshold-warning 80 \
    --threshold-error 90
```

### Local API Testing

```bash
python3 post_system_metrics.py \
    --api-url "http://localhost:5000/api/components"
```

### Quiet Mode (for cron)

```bash
python3 post_system_metrics.py --quiet
```

## Cron Examples

### Every 5 Minutes
```cron
*/5 * * * * /usr/bin/python3 /path/to/post_system_metrics.py --quiet >> /var/log/linux_agent.log 2>&1
```

### Every Hour
```cron
0 * * * * /usr/bin/python3 /path/to/post_system_metrics.py --quiet >> /var/log/linux_agent.log 2>&1
```

### Every Minute with Custom Settings
```cron
* * * * * /usr/bin/python3 /path/to/post_system_metrics.py --quiet --project-name "Critical" >> /var/log/linux_agent.log 2>&1
```

## Output Format

The agent outputs JSON in the following format:

```json
{
  "projectName": "Workstations",
  "systemName": "Monitoring",
  "payload": {
    "Id": "server-hostname",
    "Name": "server-hostname",
    "CPU": "15.23%",
    "Memory": "45.67%",
    "Disks": "/ (32%), /home (55%)",
    "Services": "All Enabled Services Running",
    "Severity": "ok"
  }
}
```

## Troubleshooting

### Permission Issues

If running as a non-root user, ensure the user has:
- Read access to `/proc/stat` and `/proc/meminfo`
- Permission to run `systemctl` commands
- Network access to the API

### Service Detection Not Working

- Ensure systemd is available: `which systemctl`
- Test manually: `systemctl list-units --state=failed`

### Network Issues

- Test API connectivity: `curl -X POST <api-url> -H "Content-Type: application/json" -d '{}'`
- Check firewall rules for outbound HTTP

## Comparison with Windows Agent

| Feature | Windows Agent | Linux Agent |
|---------|--------------|-------------|
| Language | PowerShell | Python 3 |
| CPU Metrics | Performance Counter | /proc/stat |
| Memory Metrics | WMI | /proc/meminfo |
| Disk Metrics | WMI | df command |
| Service Monitoring | Windows Services | systemd |
| Scheduling | Task Scheduler | cron |
