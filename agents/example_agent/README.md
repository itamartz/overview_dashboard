# Example Monitoring Agent

A reference implementation of a monitoring agent for the **Overview Dashboard**, fully compliant with the architecture guidelines in [AGENT-DEVELOPMENT-GUIDE.md](../../AGENT-DEVELOPMENT-GUIDE.md).

It is provided in both **PowerShell** (`Get-ExampleMetrics.ps1`) and **Python** (`get_example_metrics.py`).

---

## Features

- **Architectural Reference**: Demonstrates all standard patterns required for Overview Dashboard agents.
- **Deterministic Component IDs**: Uses MD5 hashes (`SystemName|ProjectName|Name|Metric`) to prevent duplicate components on the dashboard.
- **Unified Credential Resolution**: Abstracted support for CyberArk CCP, local encrypted files, and plaintext configurations.
- **Severity Evaluation**: Dynamic severity determination (`ok`, `warning`, `error`) based on configurable per-metric thresholds.
- **Execution Modes**:
  - `DryRun`: Inspect targets and configurations without making network connections or API calls.
  - `MockRun`: Simulate metric collection with realistic sample data distributions and post to the Overview Dashboard API.

---

## Directory Structure

```text
agents/example_agent/
├── Get-ExampleMetrics.ps1     # PowerShell main script
├── get_example_metrics.py     # Python main script
├── config.json                # Standard JSON configuration schema
├── components.csv             # Example CSV target list
├── README.md                  # Agent documentation
└── credentials/
    └── .gitignore             # Ignores local credential files (*.enc, *.key, etc.)
```

---

## Configuration (`config.json`)

```json
{
  "apiUrl": "https://overview.tazone.net/api/components",
  "projectName": "Sample Project",
  "systemName": "Example Monitoring",
  "defaultTTL": 120,
  "credentialMethod": "plaintext",
  "cyberark": {
    "ccpUrl": "https://cyberark.company.com/AIMWebService/api/Accounts",
    "appId": "OverviewDashboardAgent",
    "verifySsl": true,
    "timeoutSeconds": 10,
    "cacheMinutes": 5
  },
  "targets": [
    {
      "name": "Web-Server-01",
      "host": "192.168.1.10",
      "port": 80,
      "username": "admin",
      "password": "sample_password",
      "cyberarkSafe": "AppVault",
      "cyberarkObject": "Web-Server-01-admin",
      "encryptedPasswordFile": "credentials/web_server_01.enc",
      "enabled": true,
      "metrics": [
        {
          "name": "CPU Usage",
          "warning": 80,
          "error": 95
        },
        {
          "name": "Memory Usage",
          "warning": 85,
          "error": 95
        }
      ]
    }
  ]
}
```

---

## Usage

### PowerShell

```powershell
# Dry Run (Preview configuration and targets without network calls)
.\Get-ExampleMetrics.ps1 -DryRun

# Mock Run (Generate fake data and post to Overview Dashboard API)
.\Get-ExampleMetrics.ps1 -MockRun

# Standard Execution
.\Get-ExampleMetrics.ps1
```

### Python

```bash
# Dry Run
python get_example_metrics.py --dry-run

# Mock Run
python get_example_metrics.py --mock

# Standard Execution
python get_example_metrics.py
```

---

## Credential Management

The agent supports three credential resolution methods via `credentialMethod` in `config.json`:
1. `cyberark`: Retrieves credentials on-demand via CyberArk CCP REST API (`AIMWebService`).
2. `encrypted`: Reads local encrypted files stored in `credentials/`.
3. `plaintext`: Reads `username` and `password` directly from `config.json`.
