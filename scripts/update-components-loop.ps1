$baseUrl = 'http://localhost:5203/api/components'
$systemName = 'Performance Test System'
$projects = @('Load Test Project', 'Second Project')
$severities = @('ok', 'warning', 'error', 'info')
$metrics = @('CPU %', 'Memory %', 'Disk %', 'Network Mbps', 'Response ms', 'Uptime %')

# Random project names for creating new ones
$randomProjectNames = @('Alpha Service', 'Beta Platform', 'Gamma API', 'Delta DB', 'Epsilon Cache', 'Zeta Queue', 'Eta Worker', 'Theta Gateway')

Write-Host "Starting continuous updates every 5 seconds... (Press Ctrl+C to stop)"
Write-Host "- Updating both existing projects"
Write-Host "- Creating random new projects"
Write-Host ""
$counter = 0

while ($true) {
    $counter++

    # Update Load Test Project (5 components)
    for ($i = 1; $i -le 5; $i++) {
        $componentId = Get-Random -Minimum 1 -Maximum 5000
        $severity = $severities | Get-Random
        $value = [math]::Round((Get-Random -Minimum 0 -Maximum 100), 2)

        $body = @{
            systemName = $systemName
            projectName = 'Load Test Project'
            payload = @{
                Id = "component-$componentId"
                Name = "Test Component $componentId"
                Severity = $severity
                Value = $value
                Metric = $metrics | Get-Random
                Description = "Updated at $(Get-Date -Format 'HH:mm:ss')"
            }
        } | ConvertTo-Json -Depth 3

        $null = Invoke-RestMethod -Uri $baseUrl -Method Post -Body $body -ContentType 'application/json' -ErrorAction SilentlyContinue
    }

    # Update Second Project (5 components)
    for ($i = 1; $i -le 5; $i++) {
        $componentId = Get-Random -Minimum 1 -Maximum 500
        $severity = $severities | Get-Random
        $value = [math]::Round((Get-Random -Minimum 0 -Maximum 100), 2)

        $body = @{
            systemName = $systemName
            projectName = 'Second Project'
            payload = @{
                Id = "second-$componentId"
                Name = "Second Project Component $componentId"
                Severity = $severity
                Value = $value
                Metric = $metrics | Get-Random
                Description = "Updated at $(Get-Date -Format 'HH:mm:ss')"
            }
        } | ConvertTo-Json -Depth 3

        $null = Invoke-RestMethod -Uri $baseUrl -Method Post -Body $body -ContentType 'application/json' -ErrorAction SilentlyContinue
    }

    # Every 3rd cycle, create a new component in a random project
    if ($counter % 3 -eq 0) {
        $randomProject = $randomProjectNames | Get-Random
        $randomId = Get-Random -Minimum 1000 -Maximum 9999
        $severity = $severities | Get-Random
        $value = [math]::Round((Get-Random -Minimum 0 -Maximum 100), 2)

        $body = @{
            systemName = $systemName
            projectName = $randomProject
            payload = @{
                Id = "random-$randomId"
                Name = "$randomProject Server $randomId"
                Severity = $severity
                Value = $value
                Metric = $metrics | Get-Random
                Description = "Created at $(Get-Date -Format 'HH:mm:ss')"
            }
        } | ConvertTo-Json -Depth 3

        $null = Invoke-RestMethod -Uri $baseUrl -Method Post -Body $body -ContentType 'application/json' -ErrorAction SilentlyContinue
        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Cycle $counter - Updated both projects + NEW: $randomProject"
    }
    else {
        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Cycle $counter - Updated both projects"
    }

    Start-Sleep -Seconds 5
}
