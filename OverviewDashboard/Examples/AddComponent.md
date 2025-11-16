# How to Add New Components to the Dashboard

## Method 1: Using PowerShell (Windows)

Run the provided PowerShell script:
```powershell
cd Examples
.\AddComponent.ps1
```

Or use this one-liner:
```powershell
$body = @{
    name = "My Server"
    severity = "ok"  # ok, warning, error, or info
    value = 95.5
    metric = "Uptime %"
    description = "Server running normally"
    projectName = "Infrastructure"
    systemName = "Production Environment"
} | ConvertTo-Json

Invoke-RestMethod -Uri "http://localhost:5203/api/components" -Method Post -Body $body -ContentType "application/json"
```

## Method 2: Using cURL

```bash
curl -X POST http://localhost:5203/api/components \
  -H "Content-Type: application/json" \
  -d '{
    "name": "My Server",
    "severity": "ok",
    "value": 95.5,
    "metric": "Uptime %",
    "description": "Server running normally",
    "projectName": "Infrastructure",
    "systemName": "Production Environment"
  }'
```

## Method 3: Using Swagger UI

1. Open: http://localhost:5203/swagger
2. Find the `POST /api/components` endpoint
3. Click "Try it out"
4. Enter your JSON data
5. Click "Execute"

## Method 4: Using C# Code

```csharp
using System.Net.Http.Json;

var client = new HttpClient();
var component = new ComponentDto
{
    Name = "My Server",
    Severity = "ok",
    Value = 95.5,
    Metric = "Uptime %",
    Description = "Server running normally",
    ProjectName = "Infrastructure",
    SystemName = "Production Environment"
};

var response = await client.PostAsJsonAsync(
    "http://localhost:5203/api/components",
    component
);
```

## Component Properties

| Property | Type | Required | Description | Example Values |
|----------|------|----------|-------------|----------------|
| name | string | Yes | Component name | "Web Server 01" |
| severity | string | Yes | Status level | "ok", "warning", "error", "info" |
| value | number | Yes | Metric value | 99.5, 85.0, 2.5 |
| metric | string | Yes | Metric type | "Uptime %", "CPU %", "Response Time (ms)" |
| description | string | Yes | Status description | "Running normally" |
| projectName | string | Yes | Project name (auto-created if new) | "Infrastructure", "Applications" |
| systemName | string | Yes | System name (auto-created if new) | "Production Environment" |

## Important Notes

- **Auto-Creation**: If the system or project doesn't exist, it will be created automatically
- **Update Existing**: If a component with the same name exists in the same project, it will be updated instead of creating a duplicate
- **Refresh Dashboard**: The dashboard updates automatically when you refresh or select the system/project
- **Delete**: Use the 🗑️ button in the dashboard UI to delete components

## Testing the API

Try adding a test component:

```powershell
# Test: Add a new component
$test = @{
    name = "Test Server"
    severity = "info"
    value = 100
    metric = "Test Metric"
    description = "This is a test component"
    projectName = "Testing"
    systemName = "Test Environment"
} | ConvertTo-Json

Invoke-RestMethod -Uri "http://localhost:5203/api/components" -Method Post -Body $test -ContentType "application/json"
```

Then check the dashboard - you should see a new "Test Environment" system!
