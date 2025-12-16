# Generate 5000 components for performance testing
# Usage: .\generate-5000-components.ps1

$baseUrl = "http://localhost:5203/api/components"
$systemName = "Performance Test System"
$projectName = "Load Test Project"
$totalComponents = 1000

$severities = @("ok", "warning", "error", "info")
$metrics = @("CPU %", "Memory %", "Disk %", "Network Mbps", "Response ms", "Uptime %")

Write-Host "Starting to create $totalComponents components..." -ForegroundColor Cyan
Write-Host "System: $systemName" -ForegroundColor Yellow
Write-Host "Project: $projectName" -ForegroundColor Yellow
Write-Host ""

$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$successCount = 0
$errorCount = 0

# Process in batches for progress reporting
$batchSize = 100

for ($i = 1; $i -le $totalComponents; $i++) {
    $severity = $severities[$i % $severities.Count]
    $metric = $metrics[$i % $metrics.Count]
    $value = [math]::Round((Get-Random -Minimum 0 -Maximum 100), 2)

    $body = @{
        systemName = $systemName
        projectName = $projectName
        payload = @{
            Id = "component-$i"
            Name = "Test Component $i"
            Severity = $severity
            Value = $value
            Metric = $metric
            Description = "Performance test component number $i"
        }
    } | ConvertTo-Json -Depth 3

    try {
        $null = Invoke-RestMethod -Uri $baseUrl -Method Post -Body $body -ContentType "application/json" -ErrorAction Stop
        $successCount++
    }
    catch {
        $errorCount++
        if ($errorCount -le 5) {
            Write-Host "Error on component $i : $_" -ForegroundColor Red
        }
    }

    # Progress update every batch
    if ($i % $batchSize -eq 0) {
        $elapsed = $stopwatch.Elapsed.TotalSeconds
        $rate = [math]::Round($i / $elapsed, 1)
        $percent = [math]::Round(($i / $totalComponents) * 100, 1)
        Write-Host "Progress: $i / $totalComponents ($percent%) - Rate: $rate/sec" -ForegroundColor Green
    }
}

$stopwatch.Stop()
$totalSeconds = [math]::Round($stopwatch.Elapsed.TotalSeconds, 2)
$avgRate = [math]::Round($totalComponents / $totalSeconds, 1)

Write-Host ""
Write-Host "======================================" -ForegroundColor Cyan
Write-Host "Completed!" -ForegroundColor Green
Write-Host "Total time: $totalSeconds seconds" -ForegroundColor Yellow
Write-Host "Average rate: $avgRate components/second" -ForegroundColor Yellow
Write-Host "Success: $successCount" -ForegroundColor Green
Write-Host "Errors: $errorCount" -ForegroundColor Red
Write-Host "======================================" -ForegroundColor Cyan
