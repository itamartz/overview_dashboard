# Checkpoint Firewall Agent

This agent collects metrics from Checkpoint Firewalls (Gaia OS) and formats them for the Overview Dashboard.

## Features

- **CPU/Memory**: Uses `cpstat os -f multi_cpu` to get per-core utilization and identifies heavy load CPUs.
- **Cluster State**: Checks `cphaprob state` for High Availability status.
- **Errors**: Checks for critical device errors using `cphaprob list`.
- **Heavy Connections**: Checks for heavy connections from today using `fw ctl multik print_heavy_conn`.

## Requirements

- Python 3
- Checkpoint Gaia OS (or Linux with access to Checkpoint commands)
- Access to `cpstat` and `cphaprob` commands (usually requires root or admin privileges)

## Files

| File | Description |
|------|-------------|
| `get_checkpoint_metrics.py` | Core metrics gathering module |
| `post_system_metrics.py` | Posts metrics to the Dashboard API |

## Usage

### 1. Test the Agent

```bash
# Run the metrics gatherer standalone
python3 get_checkpoint_metrics.py

# Run with JSON output only
python3 get_checkpoint_metrics.py --json-only
```

### 2. Post Metrics Manually

```bash
python3 post_system_metrics.py
```

### 3. Install Cron Job

You can set up a cron job to run `post_system_metrics.py` periodically.

```cron
*/5 * * * * /usr/bin/python3 /path/to/checkpoint_fw_agent/post_system_metrics.py --quiet >> /var/log/checkpoint_agent.log 2>&1
```

### Custom Thresholds

```bash
python3 post_system_metrics.py --threshold-warning 80 --threshold-error 90
```

### Testing (Mock Mode)

If you are not running on a Checkpoint device, you can use the `--mock` flag to simulate output:

```bash
python3 post_system_metrics.py --mock
```

## Output Format

```json
{
  "projectName": "Firewalls",
  "systemName": "Checkpoint",
  "payload": {
    "Id": "checkpoint-fw",
    "Name": "checkpoint-fw",
    "CPU": "15.0%",
    "Memory": "50.0%",
    "Cluster State": "Active",
    "Errors": "No Errors",
    "Severity": "ok"
  }
}
```
