# Certificate Expiry Agent

The Certificate Expiry Agent connects to a list of TLS endpoints, reads the certificate each host presents, calculates the days remaining until expiry, and reports one component per endpoint to the Overview Dashboard API.

## Architecture

This agent uses **Pattern A: Self-Contained Agent** design:
- `Get-CertificateMetrics.ps1`: The main script that opens a TLS connection to each target, evaluates certificate validity, calculates severity, and posts to the API.
- `config.json`: The configuration file storing the API endpoint, day thresholds, and the list of endpoints to check.

Certificate retrieval uses `Get-X509Certificate2Web` from the shared module (`agents/shared/functions.psm1`), imported via the relative path `..\shared\functions.psm1`. That helper performs the TLS handshake and **accepts whatever certificate the host presents regardless of trust**, so expiring, self-signed, or otherwise untrusted certificates can still be inspected and reported.

## Prerequisites

- **PowerShell 5.1+** (Windows PowerShell or PowerShell 7)
- Network access to each target host/port (TLS handshake only — no credentials required)

## Configuration (`config.json`)

```json
{
  "apiUrl": "https://overview.tazone.net/api/components",
  "projectName": "Certificates",
  "systemName": "Certificate Monitoring",
  "defaultTTL": 3600,

  "warningDays": 30,
  "errorDays": 7,

  "targets": [
    {
      "name": "Public Website",
      "host": "www.example.com",
      "port": 443,
      "enabled": true
    },
    {
      "name": "LDAPS Directory",
      "host": "dc01.contoso.com",
      "port": 636,
      "enabled": false
    }
  ]
}
```

### Settings Explained

- `warningDays`: A certificate becomes a **warning** once its remaining validity is at or below this many days (default 30).
- `errorDays`: A certificate becomes an **error** once its remaining validity is at or below this many days (default 7).
- `targets[].name`: Display name for the component on the dashboard.
- `targets[].host` / `targets[].port`: The endpoint whose presented certificate is inspected. `port` defaults to 443 — set it explicitly for other TLS services (e.g. 636 for LDAPS, 993 for IMAPS, 5671 for AMQPS).
- `targets[].enabled`: Set to `false` to skip a target without removing it.

## Usage

Show configuration and the endpoints that would be checked, without connecting or posting (Dry Run):
```powershell
.\Get-CertificateMetrics.ps1 -DryRun
```

Post realistic sample certificate data to the dashboard without connecting to any endpoint (Mock Run):
```powershell
.\Get-CertificateMetrics.ps1 -MockRun
```

Run a live collection:
```powershell
.\Get-CertificateMetrics.ps1
```

## Reported Components

Under the `Certificate Monitoring` system / `Certificates` project (both configurable), one **TLS Certificate** component per target, with severity derived from the certificate's validity window:

- `error` — endpoint unreachable / handshake failed, certificate already expired, or expiry within `errorDays`.
- `warning` — certificate not yet valid (`NotBefore` in the future), or expiry within `warningDays`.
- `ok` — certificate valid with more than `warningDays` remaining.

Each component also carries extra data: `Host`, `Port`, `Subject`, `Issuer`, `NotBefore`, `NotAfter`, and `DaysRemaining`.
