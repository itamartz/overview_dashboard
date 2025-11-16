# Example: Add a new component to the dashboard via API
# This script demonstrates how to POST data to the OverviewDashboard API

$apiUrl = "http://localhost:5203/api/components"

# Example 1: Add a new component to an existing system/project
$newComponent = @{
    name = "Database Server 01"
    severity = "ok"
    value = 99.5
    metric = "Uptime %"
    description = "Database running normally"
    projectName = "Infrastructure"
    systemName = "Production Environment"
} | ConvertTo-Json

# Send the request
$response = Invoke-RestMethod -Uri $apiUrl -Method Post -Body $newComponent -ContentType "application/json"

Write-Host "Component added successfully!" -ForegroundColor Green
Write-Host "Response: $($response | ConvertTo-Json -Depth 3)"

# Example 2: Add a component to a NEW system (it will be created automatically)
$newSystemComponent = @{
    name = "Web Server 01"
    severity = "warning"
    value = 85.0
    metric = "CPU %"
    description = "High CPU usage detected"
    projectName = "Web Servers"
    systemName = "Staging Environment"
} | ConvertTo-Json

$response2 = Invoke-RestMethod -Uri $apiUrl -Method Post -Body $newSystemComponent -ContentType "application/json"

Write-Host "`nNew system and component added!" -ForegroundColor Green
Write-Host "Response: $($response2 | ConvertTo-Json -Depth 3)"


$newSystemComponent3 = @{
    name = "Web Server 02"
    severity = "Error"
    value = 98.0
    metric = "CPU %"
    description = "High CPU usage detected"
    projectName = "vCenter"
    systemName = "ESXI"
} | ConvertTo-Json

$response3 = Invoke-RestMethod -Uri $apiUrl -Method Post -Body $newSystemComponent3 -ContentType "application/json"
