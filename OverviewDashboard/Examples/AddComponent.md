# How to Add New Components to the Dashboard

## Method 1: Using PowerShell (Windows)

The API expects a JSON payload containing `systemName`, `projectName`, and a stringified `payload` field (which itself contains the component details).

### Basic Example (Default TTL):

```powershell
$baseUri = "http://localhost:5203/api/components"

# 1. Define the component data
$componentData = @{
    Name = "Web Server 01"
    Severity = "ok"         # ok, warning, error, info
    Message = "Running normally"
    Metric = "CPU: 45%"
    Timestamp = (Get-Date).ToString("o")
} | ConvertTo-Json -Depth 5

# 2. Wrap it in the API envelope
$body = @{
    systemName = "Production"
    projectName = "WebStack"
    payload = $componentData
} | ConvertTo-Json -Depth 5

# 3. Post to API
Invoke-RestMethod -Uri $baseUri -Method Post -Body $body -ContentType "application/json"
```

### Advanced Example with Custom TTL (Time-To-Live):

You can specify a `TTL` (in seconds) in the component payload. If the component is not updated within this timeframe, the dashboard will automatically mark it as **Offline**.

```powershell
$baseUri = "http://localhost:5203/api/components"

$componentData = @{
    Name = "Critical Process"
    Severity = "ok"
    Message = "Heartbeat - I expire in 30 seconds"
    TTL = 30  # Component turns 'Offline' if no update in 30s
} | ConvertTo-Json

$body = @{
    systemName = "CoreSystems"
    projectName = "BackgroundJobs"
    payload = $componentData
} | ConvertTo-Json

Invoke-RestMethod -Uri $baseUri -Method Post -Body $body -ContentType "application/json"
```

## Method 2: Using cURL

```bash
curl -X POST http://localhost:5203/api/components \
  -H "Content-Type: application/json" \
  -d '{
    "systemName": "Production",
    "projectName": "Database",
    "payload": "{\"Name\": \"DB-01\", \"Severity\": \"warning\", \"Message\": \"High Latency\", \"TTL\": 300}"
  }'
```

*Note: The `payload` field must be a JSON string (escaped quotes) or a JSON object if the server handles it (currently requires robust parsing, string is safest).*

## Method 3: Using C# Code

```csharp
using System.Net.Http.Json;

var client = new HttpClient();

var requestBody = new 
{
    systemName = "Production",
    projectName = "AuthService",
    payload = JsonSerializer.Serialize(new 
    {
        Name = "LoginEndpoint",
        Severity = "error",
        Message = "500 Internal Server Error",
        TTL = 60
    })
};

var response = await client.PostAsJsonAsync(
    "http://localhost:5203/api/components",
    requestBody
);
```

## Component Properties (Inside `payload`)

| Property | Type | Required | Description | Example Values |
|----------|------|----------|-------------|----------------|
| Name     | string | Yes | Component name | "Web Server 01" |
| Severity | string | Yes | Status level | "ok", "warning", "error", "info" |
| Message  | string | No  | Status description | "Running normally", "Disk Full" |
| TTL      | int    | No  | **New!** Time-to-live in seconds. Defaults to 3600 (1h) if omitted. | 30, 60, 300 |
| Timestamp| string | No  | ISO 8601 Date String | "2023-12-01T12:00:00Z" |
| *Any*    | any    | No  | Any other fields are displayed dynamically | "CPU": 99, "Version": "1.0" |

## Important Notes

- **Auto-Creation**: Systems and Projects are created automatically on the first POST.
- **Deduplication**: Components are identified by `Name` (and `Id` if provided) within a Project. Posting again updates the existing record.
- **Offline Logic**:
  - Default Offline threshold: 60 minutes (configurable in `appsettings.json`).
  - **Dynamic TTL**: Use the `TTL` field (seconds) to override this per component.

