# NetApp Agent

This agent monitors NetApp ONTAP clusters via REST API, tracking cluster health, nodes, HA status, aggregates, volumes, LUNs, snapshots, disks, ethernet ports, and LIFs.

## Configuration

Edit `config.json` to define your targets and thresholds. The agent supports three credential methods: `plaintext`, `encrypted`, and `cyberark`.

Example `config.json`:
```json
{
  "apiUrl": "https://overview.tazone.net/api/components",
  "projectName": "NetApp Storage",
  "systemName": "Storage",
  "defaultTTL": 3600,
  "credentialMethod": "plaintext",
  "targets": [
    {
      "name": "netapp01",
      "host": "192.168.1.100",
      "username": "admin",
      "password": "plaintext_password_here",
      "enabled": true,
      "VolumeWarningThreshold": 80,
      "VolumeErrorThreshold": 90,
      "LunWarningThreshold": 80,
      "LunErrorThreshold": 90,
      "AggregateWarningThreshold": 80,
      "AggregateErrorThreshold": 90,
      "SnapshotsThreshold": 180
    }
  ]
}
```

## Running the Agent

You can run the agent in three modes:

1. **Normal**: Connects to targets and sends data to the API.
   `.\Get-NetappMetrics.ps1`

2. **Dry Run**: Previews actions without sending data or making connections.
   `.\Get-NetappMetrics.ps1 -DryRun`

3. **Mock Run**: Sends fake data to the dashboard for testing.
   `.\Get-NetappMetrics.ps1 -MockRun`

## Supported Metrics
- **Cluster Health**: Overall system health status
- **Nodes Up**: State of cluster nodes
- **HA Status**: HA and takeover state of nodes
- **Aggregates**: Space utilization against thresholds
- **Volumes**: Space utilization against thresholds
- **Snapshots**: Age of snapshots against threshold
- **LUNs**: Space utilization and online state
- **Disks**: Disk health status
- **Ethernet**: Ethernet port status
- **Interfaces**: LIF state and status
