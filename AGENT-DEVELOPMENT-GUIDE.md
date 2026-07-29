# Overview Dashboard — Agent Development Guide

> **Purpose**: This document is a complete, self-contained instruction set for AI agents (Gemini GEMs, Copilot, Claude, etc.) to understand how to create new monitoring agents for the **Overview Dashboard** project.  
> Read this file in its entirety before writing any agent code.

---

## Table of Contents

1. [System Overview](#1-system-overview)
2. [Architecture & Data Flow](#2-architecture--data-flow)
3. [The Dashboard API Contract](#3-the-dashboard-api-contract)
4. [Agent Design Patterns](#4-agent-design-patterns)
5. [Step-by-Step: Creating a New Agent](#5-step-by-step-creating-a-new-agent)
6. [Configuration File Design](#6-configuration-file-design)
7. [Credential Management](#7-credential-management)
8. [Severity Calculation Rules](#8-severity-calculation-rules)
9. [The `Send-ToApi` / `post_to_api` Function](#9-the-send-toapi--post_to_api-function)
10. [Deterministic Component IDs](#10-deterministic-component-ids)
11. [TTL (Time-To-Live) Strategy](#11-ttl-time-to-live-strategy)
12. [Mock / Dry-Run Modes](#12-mock--dry-run-modes)
13. [Output Parsers (SSH Agent Pattern)](#13-output-parsers-ssh-agent-pattern)
14. [Scheduling & Automation](#14-scheduling--automation)
15. [File & Folder Structure Convention](#15-file--folder-structure-convention)
16. [Language-Specific Templates](#16-language-specific-templates)
17. [Existing Agent Reference Catalog](#17-existing-agent-reference-catalog)
18. [Complete Working Examples](#18-complete-working-examples)
19. [Common Pitfalls & Troubleshooting](#19-common-pitfalls--troubleshooting)

---

## 1. System Overview

The **Overview Dashboard** is an IT infrastructure monitoring system built with Blazor Server, ASP.NET Core, and SQLite. Agents are lightweight scripts that:

1. **Collect** metrics from infrastructure (servers, switches, firewalls, databases, containers, etc.)
2. **Evaluate** severity based on configurable thresholds
3. **Report** results to the Dashboard API via HTTP POST
4. **Repeat** on a schedule (cron, Task Scheduler, systemd timer, or loop)

The dashboard then displays all reported data in real-time with color-coded severity (OK, Warning, Error, Info, Offline).

### Key Terms

| Term | Definition |
|------|-----------|
| **System** | Top-level grouping (e.g., `"Monitoring"`, `"Network Monitoring"`, `"OpenShift"`) |
| **Project** | Sub-grouping within a system (e.g., `"Workstations"`, `"Ping Checks"`, `"Firewalls"`) |
| **Component** | A single monitored item within a project (e.g., one server, one database, one switch) |
| **Payload** | A JSON object attached to a component containing its metrics and severity |
| **Severity** | One of: `"ok"`, `"warning"`, `"error"`, `"info"` |
| **TTL** | Time-To-Live in seconds — if a component is not updated within this window, the dashboard marks it as **Offline** |

---

## 2. Architecture & Data Flow

```
┌─────────────────────────────────────────────────────────────┐
│                     MONITORING AGENTS                       │
│                                                             │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────────────┐ │
│  │ PowerShell   │ │ Python       │ │ Any Language          │ │
│  │ (Windows)    │ │ (Linux)      │ │ (HTTP POST capable)  │ │
│  └──────┬───────┘ └──────┬───────┘ └──────────┬───────────┘ │
└─────────┼────────────────┼────────────────────┼─────────────┘
          │                │                    │
          ▼                ▼                    ▼
    ┌─────────────────────────────────────────────────┐
    │            HTTP POST to /api/components         │
    │   Body: { systemName, projectName, payload }    │
    └───────────────────────┬─────────────────────────┘
                            │
                            ▼
    ┌─────────────────────────────────────────────────┐
    │              OVERVIEW DASHBOARD                 │
    │                                                 │
    │  ┌──────────────┐  ┌─────────────────────────┐  │
    │  │ REST API     │  │ Blazor Server UI        │  │
    │  │ Controller   │──│  • Masonry card layout   │  │
    │  │              │  │  • Severity color coding │  │
    │  └──────┬───────┘  │  • Real-time SignalR     │  │
    │         │          │  • Table drill-down      │  │
    │         ▼          └─────────────────────────┘  │
    │  ┌──────────────┐                               │
    │  │ SQLite DB    │                               │
    │  │ (Components) │                               │
    │  └──────────────┘                               │
    └─────────────────────────────────────────────────┘
```

---

## 3. The Dashboard API Contract

### Endpoint

```
POST /api/components
Content-Type: application/json
```

### Request Body Structure

```json
{
  "systemName": "string (required)",
  "projectName": "string (required)",
  "payload": "string (required) — a JSON-encoded string OR a JSON object"
}
```

> **IMPORTANT**: The `payload` field is typically a **JSON string** (escaped JSON inside a string). The API also accepts a raw JSON object, but **string is the safest and most compatible format**.

### Payload Fields (inside the `payload` JSON)

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `Id` | string | **Recommended** | Deterministic unique identifier. Used for upsert matching. If provided, existing components with the same `Id` (within the same system+project) are **updated** instead of duplicated. |
| `Name` | string | **Yes** | Display name of the component. Also used for upsert matching if `Id` is not provided. |
| `Severity` | string | **Yes** | One of: `"ok"`, `"warning"`, `"error"`, `"info"`. This determines the color and grouping on the dashboard. |
| `TTL` | integer | Recommended | Time-To-Live in seconds. If the component is not updated within this period, the dashboard marks it **Offline**. Default is 3600 (1 hour) if omitted. |
| `Status` | string | No | Human-readable status message (e.g., `"45%"`, `"Ping OK"`, `"Connection failed"`) |
| `Metric` | string | No | The metric name (e.g., `"CPU Usage"`, `"Last Backup"`, `"State"`) |
| `Namespace` | string | No | Used for further deduplication (e.g., Kubernetes namespace). Matching uses `Name` + `Namespace` when both are present. |
| `Database` | string | No | Used in SQL agent for database-level metrics |
| *Any other field* | any | No | **Any additional fields are stored and displayed dynamically** on the dashboard as extra columns |

### Upsert Logic (Deduplication)

The API uses this priority for matching existing components within the same `systemName` + `projectName`:

1. **Match by `Id`** — If the payload contains an `Id` field, the API looks for an existing component with the same `Id`.
2. **Match by `Name` + `Namespace`** — If `Id` is not provided, it matches by `Name` (and `Namespace` if present).
3. **No match** — A new component record is created.

When a match is found, the existing component's payload and timestamp are **updated** (upsert behavior).

### Response

- **200 OK** — Component updated successfully
- **201 Created** — New component created
- **400 Bad Request** — Missing required fields

### Other API Endpoints (Reference)

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/api/components` | Get all components |
| `GET` | `/api/components/{id}` | Get specific component |
| `DELETE` | `/api/components/{id}` | Delete a component |
| `DELETE` | `/api/components/system/{systemName}/project/{projectName}` | Delete all components in a project |

---

## 4. Agent Design Patterns

All existing agents follow one of two patterns:

### Pattern A: Self-Contained Agent (Simpler)

Used by: `ping_agent`, `tcp_agent`, `windows_agent`, `sql_agent`

```
┌──────────────────────────────────┐
│        Single Script File        │
│                                  │
│  1. Read config / CSV            │
│  2. Collect metrics              │
│  3. Calculate severity           │
│  4. POST to API                  │
│  5. Print status to console      │
└──────────────────────────────────┘
```

### Pattern B: Modular Agent (More Complex)

Used by: `ssh_agent`, `linux_agent`, `checkpoint_fw_agent`, `ocp`

```
┌──────────────────────────────────┐
│  Main Script (orchestrator)      │
│  + Parsers/Helpers (separate)    │
│  + Config file (JSON)            │
│  + Poster script (optional)      │
│  + Scheduler installer           │
└──────────────────────────────────┘
```

### When to Use Which

| Use Pattern A When | Use Pattern B When |
|--------------------|--------------------|
| Simple binary check (up/down, pass/fail) | Multiple metric types per target |
| Single data source type | Complex output parsing needed |
| Few configuration options | Many configurable targets |
| Flat target list (CSV is enough) | Hierarchical config (JSON needed) |

---

## 5. Step-by-Step: Creating a New Agent

Follow these steps exactly when creating a new monitoring agent:

### Step 1: Create the Agent Directory

```
scripts/
└── {agent_name}_agent/       # Use snake_case, end with _agent
    ├── Get-{Type}Metrics.ps1  # PowerShell main script (Windows)
    │   — OR —
    ├── get_{type}_metrics.py  # Python main script (Linux)
    ├── config.json            # Configuration file
    ├── README.md              # Documentation
    └── (optional extras)      # parsers.ps1, post script, installer, etc.
```

### Step 2: Define the Configuration

Create a `config.json` with these standard fields:

```json
{
  "apiUrl": "https://your-dashboard-url/api/components",
  "projectName": "Your Project Name",
  "systemName": "Your System Name",
  "defaultTTL": 120,
  // ... agent-specific settings (targets, thresholds, etc.)
}
```

### Step 3: Write the Main Script

The main script must implement this flow:

```
1. PARSE ARGUMENTS     — Accept ConfigPath, DryRun, MockRun flags
2. LOAD CONFIGURATION  — Read and validate config.json
3. PRINT BANNER        — Show agent name, settings, mode
4. CHECK DEPENDENCIES  — Verify required modules/tools are available
5. COLLECT DATA        — Query the target system(s) for metrics
6. PARSE RESULTS       — Extract numeric/string values from raw output
7. CALCULATE SEVERITY  — Apply threshold rules to determine ok/warning/error
8. FORMAT STATUS       — Create human-readable status string
9. SEND TO API         — POST each component to the dashboard API
10. LOG RESULTS        — Print results to console with color coding
```

### Step 4: Implement Severity Calculation

```
IF value >= error_threshold   → severity = "error"
ELIF value >= warning_threshold → severity = "warning"
ELSE                           → severity = "ok"
```

For non-numeric checks (service status, connection tests, etc.):
```
IF check_failed → severity = "error"
ELIF degraded   → severity = "warning"
ELSE            → severity = "ok"
```

### Step 5: Implement the API Call

Build the payload and POST it. See Section 8 for the exact function templates.

### Step 6: Add Mock/DryRun Modes

- **DryRun** — Shows what would be reported without connecting or sending to API
- **MockRun** — Generates realistic sample data and sends to API (for dashboard preview)

### Step 7: Write the README

Document: requirements, quick start, configuration, metrics collected, severity logic, and file descriptions. Follow the format of existing agent READMEs.

### Step 8: Test

```bash
# Test without connecting to anything
.\Get-YourMetrics.ps1 -DryRun

# Test with sample data sent to API
.\Get-YourMetrics.ps1 -MockRun

# Run for real
.\Get-YourMetrics.ps1
```

---

## 6. Configuration File Design

### Standard Fields (Always Include)

```json
{
  "apiUrl": "https://overview.tazone.net/api/components",
  "projectName": "Descriptive Project Name",
  "systemName": "System Category Name",
  "defaultTTL": 120
}
```

### Per-Agent Configuration Patterns

**Simple Target List (Ping/TCP style):**
Use a CSV file for flat lists:
```csv
google.com,443
8.8.8.8,53
myserver.local,22
```

**Single Server (SQL Agent style):**
```json
{
  "apiUrl": "...",
  "projectName": "SQL Databases",
  "systemName": "SQL Monitoring",
  "defaultTTL": 300,
  "backupWarningHours": 24,
  "backupErrorHours": 48,
  "serverName": "SQL-Server-01",
  "instance": "localhost",
  "databases": []
}
```

**Multiple Targets with Per-Target Metrics (SSH Agent style):**
```json
{
  "apiUrl": "...",
  "projectName": "Network Devices",
  "systemName": "SSH Monitoring",
  "defaultTTL": 120,
  "connectionTimeoutSeconds": 30,
  "targets": [
    {
      "name": "Device-Display-Name",
      "host": "192.168.1.1",
      "port": 22,
      "username": "admin",
      "password": "password",
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

### Design Rules for Configuration

1. **Always include `apiUrl`** — Never hardcode the API URL in the script
2. **Always include `projectName` and `systemName`** — These define where data appears on the dashboard
3. **Always include `defaultTTL`** — Defines offline detection interval
4. **Use `enabled: true/false`** on targets — Allows disabling without deletion
5. **Use per-metric thresholds** when different metrics have different acceptable ranges
6. **Use empty arrays `[]`** to mean "all" (e.g., empty `databases` = monitor all databases)
7. **Credential storage** — Three options are supported: CyberArk CCP, local encrypted, or plaintext. See [Section 7: Credential Management](#7-credential-management) for full details.

---

## 7. Credential Management

Agents that connect to remote systems (SSH, SQL, APIs, etc.) need credentials. This project supports **three credential storage strategies**, listed from most secure to least secure. Every agent that handles credentials **must** implement a `Get-Credential` / `get_credential` helper function that abstracts the retrieval method, so the rest of the agent code never cares where the password came from.

### Credential Strategy Overview

| Strategy | Security Level | Best For | Requirements |
|----------|---------------|----------|-------------|
| **Option A: CyberArk CCP** | 🔒 Highest | Enterprise / production environments | CyberArk PAM infrastructure, CCP (AIMWebService) deployed, client certificate or IP whitelisting |
| **Option B: Local Encrypted** | 🔐 Medium | Standalone servers without PAM | Windows: DPAPI (built-in). Linux: `gpg` or `openssl` |
| **Option C: Plaintext** | ⚠️ Lowest | Lab / dev / quick testing | None — credentials stored in `config.json` as-is |

### How to Choose

```
Do you have CyberArk PAM in your organization?
  ├── YES  →  Use Option A (CyberArk CCP)
  └── NO
        ├── Is this a production environment?
        │     ├── YES  →  Use Option B (Local Encrypted)
        │     └── NO   →  Option C (Plaintext) is acceptable
        └── Is this a lab or dev environment?
              └── YES  →  Option C (Plaintext) is fine
```

### Config.json Credential Format

The `credentialMethod` field in `config.json` tells the agent which strategy to use. If omitted, the agent defaults to `"plaintext"` for backward compatibility.

```json
{
  "apiUrl": "https://overview.tazone.net/api/components",
  "projectName": "Network Devices",
  "systemName": "SSH Monitoring",
  "defaultTTL": 120,
  "credentialMethod": "cyberark | encrypted | plaintext",
  "targets": [
    {
      "name": "Switch-01",
      "host": "192.168.1.1",
      "port": 22,
      "username": "admin",

      "password": "plaintext_password_here",

      "cyberarkSafe": "NetworkDevices",
      "cyberarkObject": "Switch-01-admin",

      "encryptedPasswordFile": "credentials\\switch01.enc",

      "enabled": true
    }
  ]
}
```

> **Convention**: Include all three credential fields in config examples. The agent reads only the fields relevant to the active `credentialMethod`. Unused fields are ignored.

---

### Option A: CyberArk CCP (Central Credential Provider)

CyberArk CCP exposes a REST API (`AIMWebService`) that agents call to retrieve credentials at runtime. Passwords are **never stored locally** — they are fetched on demand from the CyberArk Vault.

**This project uses CCP with IP whitelisting (no client certificate).** The agent's server IP is registered as an allowed machine in CyberArk PVWA, so the CCP call is a simple `GET` request — no certificates needed.

#### How CCP Works

```
┌─────────────┐    HTTPS GET     ┌──────────────────┐     Vault Query    ┌───────────────┐
│  Agent      │ ───────────────► │  CCP Web Service │ ──────────────────► │  CyberArk     │
│  Script     │ ◄─────────────── │  (AIMWebService) │ ◄────────────────── │  Password     │
│             │   JSON Response  │                  │   Password         │  Vault (PAM)  │
└─────────────┘   with password  └──────────────────┘                    └───────────────┘

  Authentication: The CCP server validates the request based on:
   • AppID in the query string
   • Source IP of the calling machine (whitelisted in CyberArk PVWA)
```

#### CCP Configuration in `config.json`

```json
{
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
      "name": "Switch-01",
      "host": "192.168.1.1",
      "username": "admin",
      "cyberarkSafe": "NetworkDevices",
      "cyberarkObject": "OS-Switch01-admin"
    }
  ]
}
```

| Field | Description |
|-------|------------|
| `ccpUrl` | Base URL of the CCP AIMWebService REST API |
| `appId` | Application ID registered in CyberArk (used for authentication/authorization) |
| `verifySsl` | Set to `false` only for testing with self-signed certificates |
| `timeoutSeconds` | HTTP request timeout for CCP calls |
| `cacheMinutes` | How long to cache retrieved credentials in memory (avoids excessive CCP calls). Set to `0` to disable caching. |
| `cyberarkSafe` | *(per-target)* The CyberArk Safe name where the credential is stored |
| `cyberarkObject` | *(per-target)* The object name (Account Name) in the CyberArk Safe |

> **CyberArk PVWA Setup**: Register the `AppID` under **Applications**, add the agent server's IP address under **Allowed Machines**, and grant the application access to the relevant safe(s).

#### CCP Query Parameters

The CCP REST API accepts these query parameters:

| Parameter | Description | Example |
|-----------|-------------|--------|
| `AppID` | Application ID | `OverviewDashboardAgent` |
| `Safe` | Safe name | `NetworkDevices` |
| `Object` | Account/Object name | `OS-Switch01-admin` |
| `Folder` | *(Optional)* Folder in the safe | `Root` |
| `UserName` | *(Optional)* Filter by username | `admin` |
| `Address` | *(Optional)* Filter by address/hostname | `192.168.1.1` |
| `Reason` | *(Optional)* Reason for access (for audit) | `Monitoring agent credential retrieval` |

#### PowerShell Implementation

```powershell
function Get-CyberArkCredential {
    param(
        [string]$CcpUrl,
        [string]$AppId,
        [string]$Safe,
        [string]$ObjectName,
        [bool]$VerifySsl = $true,
        [int]$TimeoutSeconds = 10
    )

    # Build CCP query URL
    $queryParams = @(
        "AppID=$([uri]::EscapeDataString($AppId))",
        "Safe=$([uri]::EscapeDataString($Safe))",
        "Object=$([uri]::EscapeDataString($ObjectName))"
    )
    $fullUrl = "$CcpUrl`?$($queryParams -join '&')"

    $invokeParams = @{
        Uri         = $fullUrl
        Method      = 'GET'
        ContentType = 'application/json'
        TimeoutSec  = $TimeoutSeconds
        ErrorAction = 'Stop'
    }

    # Handle SSL verification (set to $false only for self-signed CCP certs)
    if (-not $VerifySsl) {
        # PowerShell 7+
        $invokeParams.SkipCertificateCheck = $true
    }

    try {
        # No client certificate needed — CCP authenticates by AppID + source IP
        $response = Invoke-RestMethod @invokeParams

        # CCP returns JSON with these key fields:
        # Content    = the password
        # UserName   = the username
        # Address    = the target address
        return @{
            Username = $response.UserName
            Password = $response.Content
            Address  = $response.Address
            Success  = $true
        }
    }
    catch {
        Write-Warning "CyberArk CCP lookup failed for '$ObjectName' in safe '$Safe': $_"
        return @{
            Username = ""
            Password = ""
            Address  = ""
            Success  = $false
        }
    }
}

# --- Usage in agent ---
$cyberarkConfig = $config.cyberark

$cred = Get-CyberArkCredential `
    -CcpUrl $cyberarkConfig.ccpUrl `
    -AppId $cyberarkConfig.appId `
    -Safe $target.cyberarkSafe `
    -ObjectName $target.cyberarkObject `
    -VerifySsl $cyberarkConfig.verifySsl `
    -TimeoutSeconds $cyberarkConfig.timeoutSeconds

if ($cred.Success) {
    $username = $cred.Username
    $password = $cred.Password
} else {
    Write-Error "Failed to retrieve credential from CyberArk for $($target.name)"
    # Report failure to dashboard and continue to next target
}
```

#### Python Implementation

```python
import requests

def get_cyberark_credential(ccp_url, app_id, safe, object_name,
                            verify_ssl=True, timeout=10):
    """
    Retrieve a credential from CyberArk CCP (AIMWebService).
    Authentication is handled by IP whitelisting — no client certificate needed.

    Args:
        ccp_url: Base URL of CCP (e.g., https://cyberark.company.com/AIMWebService/api/Accounts)
        app_id: CyberArk Application ID
        safe: Safe name containing the credential
        object_name: Object/Account name in the safe
        verify_ssl: Whether to verify SSL certificates
        timeout: Request timeout in seconds

    Returns:
        dict with keys: username, password, address, success
    """
    params = {
        'AppID': app_id,
        'Safe': safe,
        'Object': object_name
    }

    try:
        # No client certificate — CCP authenticates by AppID + source IP
        response = requests.get(ccp_url, params=params, verify=verify_ssl, timeout=timeout)
        response.raise_for_status()
        data = response.json()

        return {
            'username': data.get('UserName', ''),
            'password': data.get('Content', ''),
            'address': data.get('Address', ''),
            'success': True
        }
    except Exception as e:
        print(f"CyberArk CCP lookup failed for '{object_name}' in safe '{safe}': {e}")
        return {
            'username': '',
            'password': '',
            'address': '',
            'success': False
        }


# --- Usage in agent ---
cyberark_config = config['cyberark']

cred = get_cyberark_credential(
    ccp_url=cyberark_config['ccpUrl'],
    app_id=cyberark_config['appId'],
    safe=target['cyberarkSafe'],
    object_name=target['cyberarkObject'],
    verify_ssl=cyberark_config.get('verifySsl', True),
    timeout=cyberark_config.get('timeoutSeconds', 10)
)

if cred['success']:
    username = cred['username']
    password = cred['password']
else:
    print(f"Failed to retrieve credential from CyberArk for {target['name']}")
    # Report failure to dashboard and continue
```

#### CyberArk CCP Authentication Methods

This project uses **IP whitelisting** (no client certificate). Other methods are documented for reference:

| Method | How It Works | This Project |
|--------|-------------|-------------|
| **IP Whitelisting** ✅ | CyberArk allows requests only from specific IP addresses. Set up in CyberArk PVWA under the Application's **Allowed Machines**. | **Default — used by all agents** |
| **OS User** | CyberArk validates the OS user running the agent process | Supported — configure in PVWA if needed |
| **Client Certificate** | Agent presents a TLS client certificate that CyberArk trusts | Not used — see optional section below if needed |
| **Combination** | Any mix of the above | Depends on security requirements |

> **Setup in CyberArk PVWA**:
> 1. Go to **Applications** → Create application with your `AppID` (e.g., `OverviewDashboardAgent`)
> 2. Under **Allowed Machines** → Add the IP address of each server running an agent
> 3. Under **Safe Permissions** → Grant the application access to the required safe(s)
> 4. No certificate configuration is needed on the agent side

#### Optional: Client Certificate Authentication

If your organization requires mutual TLS in addition to (or instead of) IP whitelisting, add these optional fields to the `cyberark` config block:

```json
{
  "cyberark": {
    "ccpUrl": "https://cyberark.yourcompany.com/AIMWebService/api/Accounts",
    "appId": "OverviewDashboardAgent",
    "verifySsl": true,
    "timeoutSeconds": 10,
    "cacheMinutes": 5,
    "certificatePath": "C:\\certs\\agent-cert.pfx",
    "certificatePassword": "optional-pfx-password"
  }
}
```

Then add certificate handling to the `Get-CyberArkCredential` function:

```powershell
# Add this block before the Invoke-RestMethod call:
if ($CertificatePath -and (Test-Path $CertificatePath)) {
    if ($CertificatePassword) {
        $certSecure = ConvertTo-SecureString $CertificatePassword -AsPlainText -Force
        $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2(
            $CertificatePath, $certSecure
        )
    } else {
        $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($CertificatePath)
    }
    $invokeParams.Certificate = $cert
}
```

#### Credential Caching

To avoid calling CCP on every metric collection cycle, implement in-memory caching:

```powershell
# Simple credential cache (PowerShell)
$script:CredentialCache = @{}

function Get-CachedCredential {
    param(
        [string]$CacheKey,
        [int]$CacheMinutes,
        [scriptblock]$FetchBlock
    )

    $cached = $script:CredentialCache[$CacheKey]
    if ($cached -and $cached.ExpiresAt -gt (Get-Date)) {
        return $cached.Value
    }

    # Fetch fresh credential
    $value = & $FetchBlock

    $script:CredentialCache[$CacheKey] = @{
        Value     = $value
        ExpiresAt = (Get-Date).AddMinutes($CacheMinutes)
    }

    return $value
}
```

---

### Option B: Local Encrypted Storage

Passwords are encrypted and stored in local files. The agent decrypts them at runtime. This is suitable when CyberArk is not available but plaintext passwords in config files are unacceptable.

#### Windows: DPAPI (Data Protection API)

Windows DPAPI encrypts data using the **current user's Windows credentials**. The encrypted file can **only be decrypted by the same user on the same machine**.

**One-Time Setup — Encrypt a password:**

```powershell
# Run this once, interactively, to create the encrypted file
$password = Read-Host -Prompt "Enter password" -AsSecureString
$password | ConvertFrom-SecureString | Set-Content "credentials\switch01.enc"

Write-Host "Encrypted credential saved to credentials\switch01.enc"
```

**Agent reads it at runtime:**

```powershell
function Get-EncryptedCredential {
    param(
        [string]$EncryptedFilePath,
        [string]$Username
    )

    if (-not (Test-Path $EncryptedFilePath)) {
        Write-Warning "Encrypted credential file not found: $EncryptedFilePath"
        return @{ Username = $Username; Password = ""; Success = $false }
    }

    try {
        $secureString = Get-Content $EncryptedFilePath | ConvertTo-SecureString
        $credential = New-Object System.Management.Automation.PSCredential($Username, $secureString)
        return @{
            Username = $Username
            Password = $credential.GetNetworkCredential().Password
            Success  = $true
        }
    }
    catch {
        Write-Warning "Failed to decrypt credential file '$EncryptedFilePath': $_"
        return @{ Username = $Username; Password = ""; Success = $false }
    }
}

# --- Usage in agent ---
$cred = Get-EncryptedCredential `
    -EncryptedFilePath (Join-Path $PSScriptRoot $target.encryptedPasswordFile) `
    -Username $target.username

if ($cred.Success) {
    $password = $cred.Password
}
```

**Config example:**

```json
{
  "credentialMethod": "encrypted",
  "targets": [
    {
      "name": "Switch-01",
      "host": "192.168.1.1",
      "username": "admin",
      "encryptedPasswordFile": "credentials\\switch01.enc"
    }
  ]
}
```

#### Windows: AES Key File (Machine-Portable)

DPAPI ties encryption to one user on one machine. If you need the encrypted file to be **portable across machines** (e.g., copied via deployment), use an AES key file instead:

**One-Time Setup:**

```powershell
# Generate a 256-bit AES key and save it
$key = New-Object byte[] 32
[System.Security.Cryptography.RNGCryptoServiceProvider]::Create().GetBytes($key)
$key | Set-Content "credentials\aes.key" -Encoding Byte

# Encrypt the password using the AES key
$password = Read-Host -Prompt "Enter password" -AsSecureString
$password | ConvertFrom-SecureString -Key $key | Set-Content "credentials\switch01.enc"

Write-Host "AES key saved to credentials\aes.key"
Write-Host "Encrypted credential saved to credentials\switch01.enc"
Write-Host "IMPORTANT: Protect aes.key with filesystem ACLs!"
```

**Agent reads it at runtime:**

```powershell
function Get-AesEncryptedCredential {
    param(
        [string]$EncryptedFilePath,
        [string]$KeyFilePath,
        [string]$Username
    )

    try {
        $key = Get-Content $KeyFilePath -Encoding Byte
        $secureString = Get-Content $EncryptedFilePath | ConvertTo-SecureString -Key $key
        $credential = New-Object System.Management.Automation.PSCredential($Username, $secureString)
        return @{
            Username = $Username
            Password = $credential.GetNetworkCredential().Password
            Success  = $true
        }
    }
    catch {
        Write-Warning "Failed to decrypt with AES key: $_"
        return @{ Username = $Username; Password = ""; Success = $false }
    }
}
```

> **Security Note**: The `aes.key` file must be protected with strict filesystem ACLs. Anyone who can read the key file can decrypt all passwords.

#### Linux: GPG Encryption

**One-Time Setup:**

```bash
# Encrypt a password file with GPG (symmetric)
echo -n "my_secret_password" | gpg --batch --yes --symmetric \
    --cipher-algo AES256 --passphrase "agent-master-key" \
    -o credentials/switch01.enc

# Or using a GPG key pair (asymmetric — more secure)
echo -n "my_secret_password" | gpg --encrypt --recipient agent@company.com \
    -o credentials/switch01.enc
```

**Python reads it at runtime:**

```python
import subprocess

def get_encrypted_credential(encrypted_file_path, username, gpg_passphrase=None):
    """
    Decrypt a GPG-encrypted credential file.

    Args:
        encrypted_file_path: Path to .enc file
        username: Username to pair with the decrypted password
        gpg_passphrase: Passphrase for symmetric GPG encryption (None for key-based)
    """
    try:
        cmd = ['gpg', '--batch', '--quiet', '--decrypt']
        if gpg_passphrase:
            cmd.extend(['--passphrase', gpg_passphrase])
        cmd.append(encrypted_file_path)

        result = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
        if result.returncode == 0:
            return {
                'username': username,
                'password': result.stdout.strip(),
                'success': True
            }
        else:
            print(f"GPG decryption failed: {result.stderr}")
            return {'username': username, 'password': '', 'success': False}
    except Exception as e:
        print(f"Failed to decrypt credential: {e}")
        return {'username': username, 'password': '', 'success': False}
```

#### Linux: OpenSSL Encryption (Alternative)

**One-Time Setup:**

```bash
# Encrypt
echo -n "my_secret_password" | openssl enc -aes-256-cbc -pbkdf2 \
    -pass pass:agent-master-key -out credentials/switch01.enc
```

**Decrypt at runtime:**

```python
def get_openssl_credential(encrypted_file_path, username, master_key):
    try:
        result = subprocess.run(
            ['openssl', 'enc', '-aes-256-cbc', '-d', '-pbkdf2',
             '-pass', f'pass:{master_key}', '-in', encrypted_file_path],
            capture_output=True, text=True, timeout=10
        )
        if result.returncode == 0:
            return {'username': username, 'password': result.stdout.strip(), 'success': True}
        return {'username': username, 'password': '', 'success': False}
    except Exception as e:
        return {'username': username, 'password': '', 'success': False}
```

---

### Option C: Plaintext (Current Default)

Credentials are stored directly in `config.json`. This is the simplest approach and the current default for all existing agents.

```json
{
  "credentialMethod": "plaintext",
  "targets": [
    {
      "name": "Switch-01",
      "host": "192.168.1.1",
      "username": "admin",
      "password": "my_actual_password"
    }
  ]
}
```

**Reading plaintext credentials (trivial):**

```powershell
# PowerShell
$username = $target.username
$password = $target.password
```

```python
# Python
username = target['username']
password = target['password']
```

> ⚠️ **Warning**: Plaintext credentials should only be used in isolated lab/dev environments. For production, use CyberArk CCP or local encrypted storage. If you must use plaintext, ensure `config.json` has strict filesystem permissions and is **excluded from version control** (add to `.gitignore`).

---

### Unified Credential Resolver

Every agent should implement a **single function** that resolves credentials regardless of the chosen method. This keeps the main agent code clean and method-agnostic.

#### PowerShell

```powershell
function Resolve-Credential {
    param(
        [string]$Method,          # "cyberark", "encrypted", "plaintext"
        [object]$Target,          # The target object from config
        [object]$CyberArkConfig   # The cyberark config block (if applicable)
    )

    switch ($Method.ToLower()) {
        'cyberark' {
            return Get-CyberArkCredential `
                -CcpUrl $CyberArkConfig.ccpUrl `
                -AppId $CyberArkConfig.appId `
                -Safe $Target.cyberarkSafe `
                -ObjectName $Target.cyberarkObject `
                -VerifySsl $CyberArkConfig.verifySsl `
                -TimeoutSeconds $CyberArkConfig.timeoutSeconds
        }
        'encrypted' {
            $encPath = Join-Path $PSScriptRoot $Target.encryptedPasswordFile
            return Get-EncryptedCredential -EncryptedFilePath $encPath -Username $Target.username
        }
        default {
            # Plaintext fallback
            return @{
                Username = $Target.username
                Password = $Target.password
                Success  = ($null -ne $Target.password -and $Target.password -ne "")
            }
        }
    }
}

# --- Usage in the main agent loop ---
$credMethod = if ($config.credentialMethod) { $config.credentialMethod } else { "plaintext" }

foreach ($target in $targets) {
    $cred = Resolve-Credential -Method $credMethod -Target $target -CyberArkConfig $config.cyberark

    if (-not $cred.Success) {
        # Report credential failure to dashboard
        Send-ToApi -ApiUrl $apiUrl -SystemName $systemName -ProjectName $projectName `
            -Name $target.name -Metric "Credential" -Severity "error" `
            -Status "Failed to retrieve credentials" -TTL $defaultTTL
        continue
    }

    $username = $cred.Username
    $password = $cred.Password
    # ... proceed with connection using $username and $password
}
```

#### Python

```python
def resolve_credential(method, target, cyberark_config=None):
    """
    Resolve credentials using the configured method.

    Args:
        method: 'cyberark', 'encrypted', or 'plaintext'
        target: Target dict from config
        cyberark_config: CyberArk config block (required if method is 'cyberark')

    Returns:
        dict with keys: username, password, success
    """
    method = (method or 'plaintext').lower()

    if method == 'cyberark':
        return get_cyberark_credential(
            ccp_url=cyberark_config['ccpUrl'],
            app_id=cyberark_config['appId'],
            safe=target['cyberarkSafe'],
            object_name=target['cyberarkObject'],
            cert_path=cyberark_config.get('certificatePath'),
            verify_ssl=cyberark_config.get('verifySsl', True),
            timeout=cyberark_config.get('timeoutSeconds', 10)
        )
    elif method == 'encrypted':
        return get_encrypted_credential(
            encrypted_file_path=target['encryptedPasswordFile'],
            username=target['username']
        )
    else:
        # Plaintext fallback
        return {
            'username': target.get('username', ''),
            'password': target.get('password', ''),
            'success': bool(target.get('password'))
        }


# --- Usage in the main agent loop ---
cred_method = config.get('credentialMethod', 'plaintext')

for target in targets:
    cred = resolve_credential(cred_method, target, config.get('cyberark'))

    if not cred['success']:
        post_to_api(api_url, system_name, project_name, {
            'Name': target['name'], 'Metric': 'Credential',
            'Severity': 'error', 'Status': 'Failed to retrieve credentials',
            'TTL': default_ttl
        })
        continue

    username = cred['username']
    password = cred['password']
    # ... proceed with connection
```

---

### Credential Storage File Structure

When using encrypted credentials, store encrypted files in a `credentials/` subdirectory within the agent folder:

```
scripts/ssh_agent/
├── Get-SshMetrics.ps1
├── parsers.ps1
├── config.json
├── README.md
└── credentials/              # Encrypted credential files
    ├── .gitignore             # Contains: *
    ├── switch01.enc
    ├── switch02.enc
    └── aes.key                # (if using AES key method)
```

> **Critical**: The `credentials/` directory must have its own `.gitignore` containing `*` to ensure no credential files are ever committed to version control.

### Security Recommendations Summary

| Aspect | Recommendation |
|--------|---------------|
| **Version control** | Add `credentials/`, `*.enc`, `*.key`, `*.pfx`, `*.pem` to `.gitignore` |
| **File permissions** | Windows: Restrict ACL to agent service account. Linux: `chmod 600` on credential files |
| **CyberArk AppID** | Use a dedicated AppID per agent type, not a shared one |
| **Credential rotation** | CyberArk handles this automatically. For encrypted files, re-run the encryption setup after password changes |
| **Audit logging** | CyberArk logs all credential retrievals. For encrypted files, add logging in your `Resolve-Credential` function |
| **Mock/DryRun modes** | Never attempt credential retrieval in DryRun mode. MockRun may skip it too (use fake credentials). |

---

## 8. Severity Calculation Rules

### Standard Threshold-Based (Numeric Values)

```
Severity Logic for percentage-based metrics (CPU, Memory, Disk):

    value >= error_threshold  →  "error"    (Red)
    value >= warning_threshold →  "warning"  (Yellow/Orange)
    value < warning_threshold  →  "ok"       (Green)

Common Default Thresholds:
    CPU/Memory/Disk:  warning = 85%, error = 95%
    Network devices:  warning = 70%, error = 90%
    Temperature:      warning = 65°C, error = 75°C
    Sessions:         warning = 200000, error = 250000
```

### State-Based (Non-Numeric Values)

```
Database State:
    ONLINE           →  "ok"
    RESTORING        →  "warning"
    RECOVERING       →  "warning"
    RECOVERY_PENDING →  "warning"
    SUSPECT          →  "error"
    EMERGENCY        →  "error"
    OFFLINE          →  "error"

Connectivity Check:
    Connected / Reachable  →  "ok"
    Timeout                →  "error"
    Refused                →  "error"

Cluster State:
    Active   →  "ok"
    Standby  →  "ok"
    Down     →  "error"
    Unknown  →  "error"

Kubernetes/OpenShift:
    Running (current >= desired) →  "ok"
    Degraded (0 < current < desired) →  "warning"
    Down (current == 0) →  "error"
    ScaledDown (desired == 0) →  "warning"
```

### Compound Severity (Multiple Metrics per Component)

When a single component has multiple metrics (e.g., Windows Agent reports CPU + Memory + Disk + Services), use the **worst severity** as the overall:

```
overall = "ok"
FOR each metric:
    IF metric_severity == "error":
        overall = "error"
    ELIF metric_severity == "warning" AND overall != "error":
        overall = "warning"
```

### When to Report Each Metric Separately vs. Combined

| Approach | When to Use | Example |
|----------|-------------|---------|
| **Separate** (one API call per metric) | When each metric should be its own row in the dashboard | SSH Agent: CPU, Memory, Temperature each as separate components |
| **Combined** (one API call per host) | When all metrics describe the same host's overall health | Windows Agent: CPU + Memory + Disks + Services as one component row |

---

## 9. The `Send-ToApi` / `post_to_api` Function

### PowerShell Template

```powershell
function Send-ToApi {
    param(
        [string]$ApiUrl,
        [string]$SystemName,
        [string]$ProjectName,
        [string]$Name,
        [string]$Metric,
        [string]$Severity,
        [string]$Status,
        [int]$TTL
    )

    # Generate deterministic ID from key fields
    $idSource = "$SystemName|$ProjectName|$Name|$Metric"
    $md5 = [System.Security.Cryptography.MD5]::Create()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($idSource)
    $hash = $md5.ComputeHash($bytes)
    $componentId = [System.BitConverter]::ToString($hash) -replace '-', ''

    $componentPayload = @{
        Id       = $componentId
        Name     = $Name
        Metric   = $Metric
        Severity = $Severity
        Status   = $Status
        TTL      = $TTL
    } | ConvertTo-Json -Compress

    $body = @{
        systemName  = $SystemName
        projectName = $ProjectName
        payload     = $componentPayload
    } | ConvertTo-Json -Compress

    try {
        Invoke-RestMethod -Uri $ApiUrl -Method Post -Body $body `
            -ContentType "application/json" -ErrorAction Stop | Out-Null
        return $true
    }
    catch {
        Write-Warning "Failed to send to API: $_"
        return $false
    }
}
```

### Python Template

```python
import hashlib
import json
import requests

def post_to_api(api_url, system_name, project_name, payload_dict, timeout=10):
    """
    Post a component to the Overview Dashboard API.

    Args:
        api_url: The API endpoint URL
        system_name: System name for grouping
        project_name: Project name for grouping
        payload_dict: Dictionary with at minimum: Name, Severity.
                      Recommended: Id, TTL, Status, and any other metric fields.
        timeout: HTTP request timeout in seconds
    """
    body = {
        "systemName": system_name,
        "projectName": project_name,
        "payload": json.dumps(payload_dict)
    }

    try:
        response = requests.post(api_url, json=body, timeout=timeout)
        response.raise_for_status()
        return True
    except Exception as e:
        print(f"Failed to post to API: {e}")
        return False
```

### Simplified PowerShell (for simple agents without per-metric IDs)

```powershell
# Build Component Payload
$componentPayload = @{
    Name     = "Ping $hostName"
    Severity = $severity
    Status   = $status
    TTL      = 60
} | ConvertTo-Json -Compress

# Build API Body
$body = @{
    systemName  = $SystemName
    projectName = $ProjectName
    payload     = $componentPayload
} | ConvertTo-Json -Compress

# Send to API
Invoke-RestMethod -Uri $ApiUrl -Method Post -Body $body `
    -ContentType "application/json" -ErrorAction Stop | Out-Null
```

---

## 10. Deterministic Component IDs

To ensure the dashboard updates existing components instead of creating duplicates, generate a **deterministic ID** from the component's identity fields:

### The Formula

```
ID = MD5( "SystemName|ProjectName|Name|Metric" )
```

- The same component will always produce the same ID
- Different metrics on the same device get different IDs
- Removes the `-` characters from the MD5 hex string

### PowerShell Implementation

```powershell
$idSource = "$SystemName|$ProjectName|$Name|$Metric"
$md5 = [System.Security.Cryptography.MD5]::Create()
$bytes = [System.Text.Encoding]::UTF8.GetBytes($idSource)
$hash = $md5.ComputeHash($bytes)
$componentId = [System.BitConverter]::ToString($hash) -replace '-', ''
```

### Python Implementation

```python
import hashlib

id_source = f"{system_name}|{project_name}|{name}|{metric}"
component_id = hashlib.md5(id_source.encode()).hexdigest().upper()
```

### When to Include `Metric` in the ID

- **Include** `Metric` when reporting multiple metrics per target (SSH Agent: CPU, Memory, Temp are separate rows)
- **Omit** `Metric` when reporting one combined entry per target (Windows Agent: one row per host)
- Some agents also include `Database` in the ID source (SQL Agent: `"SystemName|ProjectName|ServerName|DatabaseName|Metric"`)

---

## 11. TTL (Time-To-Live) Strategy

TTL tells the dashboard how long a component should be considered "alive" after its last update. If no update arrives within the TTL window, the component is marked **Offline**.

### Choosing the Right TTL

| Agent Run Frequency | Recommended TTL | Reasoning |
|---------------------|-----------------|-----------|
| Every 1 minute | 120 seconds (2 min) | 2× the interval allows for one missed run |
| Every 5 minutes | 600 seconds (10 min) | 2× the interval |
| Every 10 minutes | 1200 seconds (20 min) | 2× the interval |
| Every 30 minutes | 3600 seconds (1 hr) | 2× the interval |
| Hourly | 7200 seconds (2 hrs) | 2× the interval |

**Rule of thumb**: Set TTL to **2× the scheduled run interval**.

### TTL in Existing Agents

| Agent | Default TTL | Typical Run Interval |
|-------|-------------|---------------------|
| SSH Agent | 120s | Every 1-2 minutes |
| Ping Agent | 60s | Every 1 minute |
| TCP Agent | 60s | Every 1 minute |
| SQL Agent | 300s | Every 5 minutes |
| Windows Agent | 3600s (default) | Every 5 minutes |

---

## 12. Mock / Dry-Run Modes

Every agent should support these operational modes:

### DryRun Mode

- **Purpose**: Preview what the agent would do without any side effects
- **Behavior**: No connections made, no API calls sent
- **Output**: Shows configuration, target list, and what would be checked

```powershell
# PowerShell implementation pattern
param(
    [switch]$DryRun
)

if ($DryRun) {
    Write-Host "[DRY RUN] Would connect to $host_:$port as $username"
    Write-Host "[DRY RUN] Would check metric: $metricName (parser: $parserName)"
    continue  # Skip to next item
}
```

### MockRun Mode

- **Purpose**: Test the full pipeline (including API calls) with fake data
- **Behavior**: Generates realistic random data, sends it to the API
- **Output**: Dashboard shows realistic-looking data without real infrastructure

```powershell
# PowerShell mock value generator pattern
function Get-MockValue {
    param(
        [hashtable]$Thresholds
    )
    
    $warningThreshold = $Thresholds.warning
    $errorThreshold = $Thresholds.error
    
    # Distribution: 70% ok, 20% warning, 10% error
    $rand = Get-Random -Minimum 0 -Maximum 100
    
    if ($rand -lt 70) {
        return Get-Random -Minimum 10 -Maximum ($warningThreshold - 5)
    } elseif ($rand -lt 90) {
        return Get-Random -Minimum $warningThreshold -Maximum ($errorThreshold - 1)
    } else {
        return Get-Random -Minimum $errorThreshold -Maximum ($errorThreshold + 10)
    }
}
```

```python
# Python mock mode pattern
parser.add_argument('--mock', action='store_true', help='Use mock data for testing')

if args.mock:
    cpu_usage = random.uniform(10, 95)
    memory_usage = random.uniform(30, 90)
    # ... generate other mock values
```

---

## 13. Output Parsers (SSH Agent Pattern)

When collecting metrics via CLI commands (SSH, local shell, etc.), you need parsers to extract numeric values from text output.

### Parser Architecture

```
Raw Command Output  →  Parser Function  →  Numeric Value (or null)
                                           ↓
                                    Severity Calculation
```

### Parser Dispatcher Pattern

```powershell
function Invoke-Parser {
    param(
        [string]$ParserName,
        [string]$Output,
        [hashtable]$MetricConfig = @{}
    )

    switch ($ParserName.ToLower()) {
        'juniper_cpu'       { return Parse-JuniperCpu -Output $Output }
        'paloalto_memory'   { return Parse-PaloAltoMemory -Output $Output }
        'generic_number'    { return Parse-GenericNumber -Output $Output }
        'generic_regex'     { return Parse-GenericRegex -Output $Output -Pattern $MetricConfig.pattern }
        'raw'               { return Parse-Raw -Output $Output }
        default {
            Write-Warning "Unknown parser: $ParserName. Using generic_number."
            return Parse-GenericNumber -Output $Output
        }
    }
}
```

### Writing a New Parser

Each parser function:
1. Receives the raw text output as a string
2. Uses regex to find the relevant number
3. Returns a `[double]` value or `$null` if parsing fails

```powershell
# Example: Custom parser for "show system health"
# Output: "System Health Score: 87/100"
function Parse-CustomHealthScore {
    param([string]$Output)

    if ($Output -match 'Health Score:\s*(\d+)') {
        return [double]$Matches[1]
    }
    return $null
}
```

### Built-In Generic Parsers

| Parser | Description | Use When |
|--------|-------------|----------|
| `generic_number` | Extracts the first number from output | Simple commands that return a single number |
| `generic_regex` | Uses a custom regex from config | When you need a specific pattern without writing code |
| `raw` | Returns cleaned-up text (truncated to 200 chars) | For status display only (no numeric thresholds) |

### Adding a Custom Parser to the SSH Agent

1. Add the parser function to `parsers.ps1`
2. Add a case to the `Invoke-Parser` switch block
3. Reference the parser name in `config.json`:

```json
{
  "name": "Health Score",
  "command": "show system health",
  "parser": "custom_health",
  "thresholds": { "warning": 50, "error": 25 }
}
```

> **Note**: For the health score example, lower values are worse. Adjust your severity logic accordingly (reverse the comparison operators).

---

## 14. Scheduling & Automation

### Windows: Task Scheduler

```powershell
# Create a scheduled task to run every 5 minutes
$action = New-ScheduledTaskAction -Execute "PowerShell.exe" `
    -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptPath`"" `
    -WorkingDirectory $scriptDir

$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) `
    -RepetitionInterval (New-TimeSpan -Minutes 5) `
    -RepetitionDuration (New-TimeSpan -Days 9999)

$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -RunOnlyIfNetworkAvailable `
    -MultipleInstances IgnoreNew

Register-ScheduledTask -TaskName "OverviewDashboard-AgentName" `
    -Action $action -Trigger $trigger -Settings $settings
```

### Linux: Cron

```bash
# Run every 5 minutes
*/5 * * * * /usr/bin/python3 /opt/monitoring/post_system_metrics.py --quiet >> /var/log/agent.log 2>&1
```

### Linux: systemd Timer

```ini
# /etc/systemd/system/monitor-agent.timer
[Unit]
Description=Run monitoring agent every 5 minutes

[Timer]
OnBootSec=1min
OnUnitActiveSec=5min

[Install]
WantedBy=timers.target
```

```ini
# /etc/systemd/system/monitor-agent.service
[Unit]
Description=Monitoring Agent

[Service]
Type=oneshot
ExecStart=/usr/bin/python3 /opt/monitoring/post_system_metrics.py --quiet
```

---

## 15. File & Folder Structure Convention

### Naming Conventions

| Element | Convention | Examples |
|---------|-----------|----------|
| Agent folder | `{technology}_agent` (snake_case) | `sql_agent`, `ssh_agent`, `windows_agent`, `ping_agent` |
| PowerShell main script | `Get-{Type}Metrics.ps1` (PascalCase verb-noun) | `Get-SqlMetrics.ps1`, `Get-SshMetrics.ps1`, `Get-PingMetrics.ps1` |
| Python main script | `get_{type}_metrics.py` (snake_case) | `get_system_metrics.py`, `get_checkpoint_metrics.py` |
| Python poster script | `post_system_metrics.py` | Always this name for consistency |
| PowerShell poster | `Post-SystemMetrics.ps1` | Always this name |
| Config file | `config.json` | Always this name |
| Simple target list | `components.csv` | Always this name |
| Parser file | `parsers.ps1` | Only when needed |
| Scheduler installer | `Install-ScheduledTask.ps1` (Win) or `install_cron.sh` (Linux) | |
| Documentation | `README.md` | Always include |

### Minimal Agent (3 files)

```
scripts/new_agent/
├── Get-NewMetrics.ps1     # Main script
├── config.json            # Configuration
└── README.md              # Documentation
```

### Full Agent (6+ files)

```
scripts/new_agent/
├── Get-NewMetrics.ps1          # Main collection script
├── Post-NewMetrics.ps1         # API posting wrapper
├── Install-ScheduledTask.ps1   # Scheduler setup
├── parsers.ps1                 # Output parsers (if needed)
├── config.json                 # Configuration
└── README.md                   # Documentation
```

---

## 16. Language-Specific Templates

### PowerShell Agent Template (Windows)

```powershell
<#
.SYNOPSIS
    Monitors [TECHNOLOGY] and reports metrics to the Overview Dashboard.

.DESCRIPTION
    [Detailed description of what the agent monitors and how]

.PARAMETER ConfigPath
    Path to the config.json file. Default: $PSScriptRoot\config.json

.PARAMETER DryRun
    If specified, shows what would be reported without connecting or sending to API.

.PARAMETER MockRun
    If specified, generates sample data and sends to API without real connections.

.EXAMPLE
    .\Get-[Type]Metrics.ps1

.EXAMPLE
    .\Get-[Type]Metrics.ps1 -MockRun

.NOTES
    Requires: [list prerequisites]
#>

[CmdletBinding()]
param(
    [string]$ConfigPath = "$PSScriptRoot\config.json",
    [switch]$DryRun,
    [switch]$MockRun
)

#region Helper Functions

function Send-ToApi {
    param(
        [string]$ApiUrl,
        [string]$SystemName,
        [string]$ProjectName,
        [string]$Name,
        [string]$Metric,
        [string]$Severity,
        [string]$Status,
        [int]$TTL
    )

    $idSource = "$SystemName|$ProjectName|$Name|$Metric"
    $md5 = [System.Security.Cryptography.MD5]::Create()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($idSource)
    $hash = $md5.ComputeHash($bytes)
    $componentId = [System.BitConverter]::ToString($hash) -replace '-', ''

    $componentPayload = @{
        Id       = $componentId
        Name     = $Name
        Metric   = $Metric
        Severity = $Severity
        Status   = $Status
        TTL      = $TTL
    } | ConvertTo-Json -Compress

    $body = @{
        systemName  = $SystemName
        projectName = $ProjectName
        payload     = $componentPayload
    } | ConvertTo-Json -Compress

    try {
        Invoke-RestMethod -Uri $ApiUrl -Method Post -Body $body `
            -ContentType "application/json" -ErrorAction Stop | Out-Null
        return $true
    }
    catch {
        Write-Warning "Failed to send to API: $_"
        return $false
    }
}

# TODO: Add your metric collection functions here
# function Get-YourMetric { ... }

# TODO: Add your severity calculation function here
# function Get-YourSeverity { ... }

#endregion

#region Main Script

# Check config file exists
if (-not (Test-Path $ConfigPath)) {
    Write-Error "Config file not found at $ConfigPath"
    exit 1
}

# Read configuration
try {
    $config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
}
catch {
    Write-Error "Failed to parse config file: $_"
    exit 1
}

# Extract settings
$apiUrl = $config.apiUrl
$projectName = $config.projectName
$systemName = $config.systemName
$defaultTTL = if ($config.defaultTTL) { $config.defaultTTL } else { 120 }

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "[Agent Name] Metrics Agent" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "API URL: $apiUrl"
Write-Host "Project: $projectName"
Write-Host "System:  $systemName"
Write-Host ""

if ($DryRun) {
    Write-Host "[DRY RUN MODE - No connections or API calls]" -ForegroundColor Yellow
}
if ($MockRun) {
    Write-Host "[MOCK RUN MODE - Sending sample data to API]" -ForegroundColor Magenta
}

# TODO: Implement your data collection loop here
# foreach ($target in $targets) {
#     1. Collect metric
#     2. Calculate severity
#     3. Send-ToApi
# }

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Completed." -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

#endregion
```

### Python Agent Template (Linux)

```python
#!/usr/bin/env python3
"""
[Technology] Monitoring Agent

Gathers metrics from [technology] and reports to the Overview Dashboard API.

Usage:
    python3 get_[type]_metrics.py
    python3 get_[type]_metrics.py --mock
    python3 get_[type]_metrics.py --json-only
"""

import argparse
import hashlib
import json
import os
import socket
import subprocess
import sys
from typing import Dict, List, Any


def get_hostname() -> str:
    """Get the system hostname."""
    try:
        return socket.gethostname()
    except Exception:
        return "unknown"


def calculate_severity(value: float, warning_threshold: int, error_threshold: int) -> str:
    """Calculate severity based on thresholds."""
    if value >= error_threshold:
        return "error"
    elif value >= warning_threshold:
        return "warning"
    return "ok"


def generate_component_id(system_name: str, project_name: str, name: str, metric: str = "") -> str:
    """Generate a deterministic component ID."""
    id_source = f"{system_name}|{project_name}|{name}|{metric}"
    return hashlib.md5(id_source.encode()).hexdigest().upper()


def post_to_api(api_url: str, system_name: str, project_name: str, payload_dict: dict, timeout: int = 10) -> bool:
    """Post a component to the Dashboard API."""
    import requests

    body = {
        "systemName": system_name,
        "projectName": project_name,
        "payload": json.dumps(payload_dict)
    }

    try:
        response = requests.post(api_url, json=body, timeout=timeout)
        response.raise_for_status()
        return True
    except Exception as e:
        print(f"Failed to post to API: {e}", file=sys.stderr)
        return False


def print_colored(text: str, color: str):
    """Print colored text to terminal."""
    colors = {
        'red': '\033[91m', 'green': '\033[92m',
        'yellow': '\033[93m', 'cyan': '\033[96m',
        'reset': '\033[0m'
    }
    if sys.stdout.isatty():
        print(f"{colors.get(color, '')}{text}{colors['reset']}")
    else:
        print(text)


# TODO: Add your metric collection functions here
# def get_your_metric() -> float: ...


def build_payload(metrics: dict, severity: str, project_name: str, system_name: str) -> dict:
    """Build the JSON payload for API posting."""
    hostname = get_hostname()
    payload = {
        'projectName': project_name,
        'systemName': system_name,
        'payload': {
            'Id': hostname,
            'Name': hostname,
            'Severity': severity,
            **metrics  # Merge in all collected metrics
        }
    }
    return payload


def main():
    parser = argparse.ArgumentParser(description='[Technology] monitoring agent')
    parser.add_argument('--api-url', default='https://overview.tazone.net/api/components')
    parser.add_argument('--project-name', default='YourProject')
    parser.add_argument('--system-name', default='YourSystem')
    parser.add_argument('--threshold-warning', type=int, default=85)
    parser.add_argument('--threshold-error', type=int, default=95)
    parser.add_argument('--ttl', type=int, default=120)
    parser.add_argument('--json-only', action='store_true')
    parser.add_argument('--mock', action='store_true')
    parser.add_argument('--quiet', action='store_true')

    args = parser.parse_args()

    # TODO: Collect metrics, calculate severity, build payload, post to API
    pass


if __name__ == '__main__':
    main()
```

---

## 17. Existing Agent Reference Catalog

| Agent | Language | Pattern | Targets | Key Metrics | Unique Features |
|-------|----------|---------|---------|-------------|-----------------|
| **ping_agent** | PowerShell | A (CSV) | Hosts from CSV | ICMP reachability (up/down) | Simplest agent — good starting template |
| **tcp_agent** | PowerShell | A (CSV) | Host:Port pairs from CSV | TCP port connectivity | Groups ports by host, combined status |
| **windows_agent** | PowerShell | B (modular) | Local machine | CPU, Memory, Disk, Services | Includes scheduler installer, posts all metrics as one combined component |
| **linux_agent** | Python | B (modular) | Local machine | CPU, Memory, Disk, systemd services | Python equivalent of windows_agent |
| **sql_agent** | PowerShell | A (config) | Local SQL Server | Database state, backup age | Uses `dbatools` module, auto-installs dependencies |
| **ssh_agent** | PowerShell | B (modular) | Remote devices via SSH | Vendor-specific (Juniper, Palo Alto, Cisco) | Parser architecture, shell stream for Cisco, most complex agent |
| **checkpoint_fw_agent** | Python | B (modular) | Local Checkpoint FW | CPU, Memory, Cluster, Errors, Heavy Connections | Parses `cpstat` and `cphaprob` commands, mock mode |
| **ocp** | Python | A (simple) | OpenShift cluster | Deployments, StatefulSets, DaemonSets | Uses `oc` CLI, Kubernetes-style status logic |

### Which Agent to Base Your New Agent On

| Your Scenario | Base Your Agent On |
|---------------|--------------------|
| Simple up/down check | `ping_agent` |
| Port/connectivity check | `tcp_agent` |
| Local Windows metrics | `windows_agent` |
| Local Linux metrics | `linux_agent` |
| Database monitoring | `sql_agent` |
| Remote device via SSH/CLI | `ssh_agent` |
| Appliance with custom CLI | `checkpoint_fw_agent` |
| Kubernetes/container platform | `ocp` |

---

## 18. Complete Working Examples

### Example 1: Minimal Ping-Style Agent (PowerShell)

**Scenario**: Monitor a list of URLs for HTTP availability.

```powershell
# Get-HttpMetrics.ps1
param(
    [string]$CsvPath = "$PSScriptRoot\urls.csv",
    [string]$ApiUrl = "https://overview.tazone.net/api/components",
    [string]$ProjectName = "HTTP Checks",
    [string]$SystemName = "Web Monitoring",
    [int]$TimeoutSec = 10
)

$urls = Get-Content $CsvPath | Where-Object { $_.Trim() -ne "" }

foreach ($url in $urls) {
    $url = $url.Trim()
    Write-Host "Checking $url..." -NoNewline

    try {
        $response = Invoke-WebRequest -Uri $url -TimeoutSec $TimeoutSec `
            -UseBasicParsing -ErrorAction Stop
        $statusCode = $response.StatusCode
        $severity = if ($statusCode -eq 200) { "ok" } else { "warning" }
        $status = "HTTP $statusCode"
        Write-Host " $status" -ForegroundColor Green
    }
    catch {
        $severity = "error"
        $status = "Unreachable"
        Write-Host " $status" -ForegroundColor Red
    }

    $componentPayload = @{
        Name     = $url
        Severity = $severity
        Status   = $status
        TTL      = 120
    } | ConvertTo-Json -Compress

    $body = @{
        systemName  = $SystemName
        projectName = $ProjectName
        payload     = $componentPayload
    } | ConvertTo-Json -Compress

    try {
        Invoke-RestMethod -Uri $ApiUrl -Method Post -Body $body `
            -ContentType "application/json" -ErrorAction Stop | Out-Null
        Write-Host "  -> Reported"
    }
    catch {
        Write-Warning "Failed to report: $_"
    }
}
```

### Example 2: Minimal API Call (Any Language)

**cURL** (works from any OS):
```bash
curl -X POST https://overview.tazone.net/api/components \
  -H "Content-Type: application/json" \
  -d '{
    "systemName": "My System",
    "projectName": "My Project",
    "payload": "{\"Name\": \"Server-01\", \"Severity\": \"ok\", \"Status\": \"Running\", \"TTL\": 300}"
  }'
```

### Example 3: Python One-Liner Heartbeat

```python
import requests, json, socket
requests.post("https://overview.tazone.net/api/components", json={
    "systemName": "Heartbeat",
    "projectName": "Services",
    "payload": json.dumps({
        "Name": socket.gethostname(),
        "Severity": "ok",
        "Status": "Alive",
        "TTL": 120
    })
})
```

---

## 19. Common Pitfalls & Troubleshooting

### ❌ Duplicate Components Appearing

**Cause**: No `Id` field in payload and `Name` varies between runs.  
**Fix**: Either use a deterministic `Id` (see Section 9) or ensure `Name` is consistent.

### ❌ Components Going Offline Immediately

**Cause**: TTL is too short for the agent's run interval.  
**Fix**: Set TTL to at least 2× your scheduled interval.

### ❌ Payload Stored as String Instead of Parsed

**Cause**: Double-encoding the payload JSON.  
**Fix**: The `payload` field should be a JSON string (one level of encoding). Don't call `ConvertTo-Json` on the entire body if the payload is already a string.

```powershell
# CORRECT: payload is a JSON string inside the body
$body = @{
    systemName  = "Test"
    projectName = "Test"
    payload     = ($payloadObject | ConvertTo-Json -Compress)  # String
} | ConvertTo-Json -Compress

# WRONG: This double-encodes the payload
$body = @{
    systemName  = "Test"
    projectName = "Test"
    payload     = $payloadObject  # Object — will be serialized again by outer ConvertTo-Json
} | ConvertTo-Json -Compress -Depth 10
```

> **Note**: In the Windows Agent, the payload is passed as an object (not a pre-serialized string) and this still works because the API accepts both formats. However, the string approach is more explicit and safer.

### ❌ Module Not Found Errors

**Cause**: Required PowerShell module not installed.  
**Fix**: Auto-install in the script:

```powershell
function Install-ModuleIfNeeded {
    param([string]$ModuleName)
    if (-not (Get-Module -ListAvailable -Name $ModuleName)) {
        Install-Module -Name $ModuleName -Force -Scope CurrentUser -AllowClobber
    }
    Import-Module $ModuleName -Force
}
```

### ❌ SSH Connection Timeout

**Cause**: Device unreachable or wrong credentials.  
**Fix**: Report the connection failure as an error component so it's visible on the dashboard:

```powershell
if ($null -eq $session) {
    Send-ToApi -ApiUrl $apiUrl -SystemName $systemName -ProjectName $projectName `
        -Name $targetName -Metric $metricName `
        -Severity "error" -Status "Connection failed" -TTL $defaultTTL
}
```

### ❌ Parser Returns Null

**Cause**: Command output format changed or device returned unexpected output.  
**Fix**: Report as warning (not error) so it's visible but distinct from real failures:

```powershell
if ($null -eq $parsedValue) {
    $severity = "warning"
    $status = "Could not parse metric value"
}
```

### ❌ API Returns 400 Bad Request

**Cause**: Missing `systemName`, `projectName`, or `payload`.  
**Fix**: Verify all three fields are present and non-empty in the request body.

### ❌ Large Number of API Calls Slow

**Cause**: Each component is a separate HTTP POST.  
**Fix**: This is by design (the API accepts one component per call). For large deployments, consider batching with a small delay between calls to avoid overwhelming the server.

---

## Summary Checklist for Creating a New Agent

- [ ] Created agent directory under `scripts/` with `_agent` suffix
- [ ] Created `config.json` with `apiUrl`, `projectName`, `systemName`, `defaultTTL`
- [ ] Main script accepts `-ConfigPath`, `-DryRun`, `-MockRun` parameters
- [ ] Script reads and validates configuration on startup
- [ ] Script prints a banner with agent name and settings
- [ ] Script auto-installs dependencies if needed
- [ ] Data collection handles errors gracefully (reports failures to dashboard)
- [ ] Severity is calculated from thresholds (not hardcoded)
- [ ] Each component has a deterministic `Id` for upsert behavior
- [ ] Payload includes `Name`, `Severity`, `TTL`, and `Status`
- [ ] API call uses correct body structure: `{ systemName, projectName, payload }`
- [ ] Console output uses color coding (Green=ok, Yellow=warning, Red=error)
- [ ] DryRun mode shows config and targets without side effects
- [ ] MockRun mode sends realistic fake data to the API
- [ ] `README.md` documents requirements, usage, configuration, and metrics
- [ ] Tested with `-DryRun`, `-MockRun`, and live run
