# RabbitMQ Monitoring Agent

This agent monitors RabbitMQ queues by querying its Management HTTP API. It validates the number of consumers on specific queues to ensure workers are actively consuming messages.

## Features
- Checks active consumers per queue against configured expected values.
- Retrieves metrics via RabbitMQ Management API (`/api/queues`).
- Supports CyberArk, encrypted, and plaintext credential storage.
- Standard DryRun and MockRun support.

## Configuration (`config.json`)
```json
{
  "apiUrl": "https://overview.tazone.net/api/components",
  "projectName": "Queues",
  "systemName": "RabbitMQ",
  "defaultTTL": 300,
  "credentialMethod": "cyberark",
  "cyberark": {
    "ccpUrl": "https://cyberark.yourcompany.com/AIMWebService/api/Accounts",
    "appId": "OverviewDashboardAgent",
    "verifySsl": true,
    "timeoutSeconds": 10,
    "cacheMinutes": 5
  },
  "targets": [
    {
      "name": "rabbitmq01",
      "host": "rabbitmq01",
      "prefix": "http",
      "port": 15672,
      "username": "rabbitadmin",
      "cyberarkSafe": "RabbitMQ",
      "cyberarkObject": "rabbitmq01-rabbitadmin",
      "password": "Password",
      "enabled": true,
      "queues": {
        "action_types_management": {
          "consumers": 2
        },
        "statuses_relays": {
          "consumers": 3
        }
      }
    }
  ]
}
```

## Running the Agent

**Dry Run** (preview what would happen):
```powershell
.\Get-RabbitMqMetrics.ps1 -DryRun
```

**Mock Run** (send fake data to dashboard):
```powershell
.\Get-RabbitMqMetrics.ps1 -MockRun
```

**Real Run**:
```powershell
.\Get-RabbitMqMetrics.ps1
```
