# Veeam Backup Jobs Agent

The Veeam Backup Jobs Agent connects to a **Veeam Backup & Replication** server, enumerates backup jobs, evaluates each job's last session, and reports one component per job to the Overview Dashboard API.

## Architecture

This agent uses **Pattern A: Self-Contained Agent** design:
- `Get-VeeamMetrics.ps1`: The main script that connects to the Veeam Backup Server, reads each job's last session, calculates severity (including staleness), and posts to the API.
- `config.json`: The configuration file storing the API endpoint, target backup server, credentials, and staleness thresholds.

It relies on the shared helper module at `agents/shared/functions.psm1` (`Send-ToApi`, `Resolve-Credential`, etc.), imported via the relative path `..\shared\functions.psm1`.

## Prerequisites

- **Windows PowerShell 5.1**
- **Veeam Backup & Replication 11 console installed locally** — this provides the `Veeam.Backup.PowerShell` module (v9.5/v10 use the `VeeamPSSnapIn` snap-in, which is also supported). This module is **not** available from the PowerShell Gallery; the console must be installed on the machine running the agent.
- Network access to the Veeam Backup Server console port (default **9392**).
- CyberArk CCP configured for `Resolve-Credential` (only if using CyberArk credentials).

Because the Veeam module ships with the console, the agent is normally run **on the backup server itself** under a service account, using the current Windows identity.

## Configuration (`config.json`)

```json
{
  "apiUrl": "https://overview.tazone.net/api/components",
  "projectName": "Veeam Backup Jobs",
  "systemName": "Backup Monitoring",
  "defaultTTL": 1200,

  "staleWarningHours": 26,
  "staleErrorHours": 48,
  "includeDisabledJobs": false,
  "jobNameFilter": [],

  "credentialMethod": "plaintext",

  "veeam": {
    "name": "Veeam Backup Server",
    "server": "localhost",
    "port": 9392,
    "useCurrentCredentials": true,

    "username": "CONTOSO\\svc-veeam-ro",
    "password": "plaintext_password_here",

    "cyberarkSafe": "BackupInfrastructure",
    "cyberarkObject": "OS-VBR01-svc-veeam-ro",

    "encryptedPasswordFile": "credentials\\vbr01.enc",

    "enabled": true
  }
}
```

### Settings Explained

- `staleWarningHours`: A job whose last result is *Success* becomes a **warning** once its last run is older than this many hours (default 26). This catches jobs that stopped running while Veeam still reports the old *Success* result.
- `staleErrorHours`: The same successful-but-stale job becomes an **error** past this age (default 48).
- `includeDisabledJobs`: When `false`, jobs with a disabled schedule are skipped.
- `jobNameFilter`: Optional list of wildcard patterns (e.g. `"Daily-*"`). When non-empty, only matching job names are reported.
- `useCurrentCredentials`: When `true`, connect with the Windows account running the agent (recommended when running on the backup server). When `false`, credentials are resolved via `credentialMethod` (`plaintext`, `cyberark`, or an encrypted file).

## Usage

Show configuration and exit without connecting or posting (Dry Run):
```powershell
.\Get-VeeamMetrics.ps1 -DryRun
```

Post realistic sample job data to the dashboard without connecting to Veeam (Mock Run):
```powershell
.\Get-VeeamMetrics.ps1 -MockRun
```

Run a live collection:
```powershell
.\Get-VeeamMetrics.ps1
```

## Reported Components

Under the `Backup Monitoring` system / `Veeam Backup Jobs` project (both configurable):

1. **Backup Server** — one component for the Veeam server itself, reporting connectivity and the total job count.
2. **Backup Job** — one component per job, with severity derived from the last session:
   - `info` — job currently running.
   - `error` — last run failed, or a successful job is stale past `staleErrorHours`.
   - `warning` — last run finished with warnings, never ran, or a successful job is ageing past `staleWarningHours`.
   - `ok` — last run succeeded and is fresh.

   Each job component also carries extra data: `JobType`, `Result`, `State`, `LastRun`, `DurationMinutes`, `ScheduleEnabled`, and `Server`.
