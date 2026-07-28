# OpenShift Agent

Monitors OpenShift / Kubernetes deployments, statefulsets, and daemonsets, evaluating their scaling status and reporting to the Overview Dashboard.

## Usage

```bash
# Run normally (will look for config.json in the same directory)
python3 monitor_ocp.py

# Run in mock mode for testing without an oc client
python3 monitor_ocp.py --mock

# Run in dry-run mode (fetches real data but does not post to API)
python3 monitor_ocp.py --dry-run

# Override arguments
python3 monitor_ocp.py --api-url "https://dashboard/api/components" --project-name "K8s"
```

## Configuration (config.json)

```json
{
  "apiUrl": "https://dashboard/api/components",
  "projectName": "OpenShift Workloads",
  "systemName": "OpenShift",
  "defaultTTL": 300,
  "namespaces": []
}
```

* Leave `namespaces` empty `[]` to monitor all namespaces.
