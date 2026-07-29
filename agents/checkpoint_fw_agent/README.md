# Checkpoint Firewall Agent

Monitors Checkpoint Gaia OS Firewalls. Extracts CPU, memory, cluster state, errors, and heavy connections, reporting them back to the Overview Dashboard API.

## Usage

```bash
# Run normally (will look for config.json in the same directory)
python3 get_checkpoint_metrics.py

# Run in mock mode for testing without real hardware
python3 get_checkpoint_metrics.py --mock

# Run in dry-run mode (fetches real data but does not post to API)
python3 get_checkpoint_metrics.py --dry-run

# Override arguments
python3 get_checkpoint_metrics.py --api-url "https://dashboard/api/components" --project-name "FW"
```

## Configuration (config.json)

```json
{
  "apiUrl": "https://overview/api/components",
  "projectName": "Firewalls",
  "systemName": "Checkpoint",
  "defaultTTL": 120,
  "thresholds": {
    "warning": 80,
    "error": 90
  }
}
```

Note: `post_system_metrics.py` is included for backwards compatibility and acts as a wrapper around `get_checkpoint_metrics.py`.
