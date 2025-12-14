<#
.SYNOPSIS
    Posts system metrics to the monitoring API.

.DESCRIPTION
    Gathers system metrics using Get-SystemMetrics.ps1 and posts them to the API endpoint.

.PARAMETER ApiUrl
    The API endpoint URL (default: http://localhost:5000/api/components)

.PARAMETER TimeoutSeconds
    Request timeout in seconds (default: 10)

.EXAMPLE
    .\Post-SystemMetrics.ps1
    
.EXAMPLE
    .\Post-SystemMetrics.ps1 -ApiUrl "http://localhost:5000/api/components" -TimeoutSeconds 30
#>

param(
    [string]$ApiUrl = "http://localhost:5000/api/components",
    [int]$TimeoutSeconds = 10
)

try {
    # Get metrics
    Write-Host "Collecting system metrics..." -ForegroundColor Cyan
    $metrics = & "$PSScriptRoot\Get-SystemMetrics.ps1"
    
    if (-not $metrics) {
        throw "Failed to collect metrics"
    }
    
    # Convert to JSON
    $json = $metrics | ConvertTo-Json -Depth 10 -Compress
    
    Write-Host "`nPosting to API: $ApiUrl" -ForegroundColor Cyan
    Write-Host "Timeout: $TimeoutSeconds seconds" -ForegroundColor Gray
    
    # Post to API
    $response = Invoke-RestMethod -Uri $ApiUrl `
        -Method Post `
        -Body $json `
        -ContentType "application/json" `
        -TimeoutSec $TimeoutSeconds `
        -ErrorAction Stop
    
    Write-Host "`n[SUCCESS] Metrics posted successfully." -ForegroundColor Green
    Write-Host "`nAPI Response:" -ForegroundColor Cyan
    $response | ConvertTo-Json -Depth 10
    
    return $response
    
}
catch [System.Net.WebException] {
    Write-Host "`n[NETWORK ERROR]" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    
    if ($_.Exception.Response) {
        $statusCode = [int]$_.Exception.Response.StatusCode
        Write-Host "HTTP Status Code: $statusCode" -ForegroundColor Red
        
        # Try to read response body
        try {
            $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
            $responseBody = $reader.ReadToEnd()
            Write-Host "Response Body: $responseBody" -ForegroundColor Yellow
        }
        catch {
            # Ignore if we cannot read the response
        }
    }
    
    exit 1
    
}
catch {
    Write-Host "`n[ERROR]" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    $exceptionType = $_.Exception.GetType().FullName
    Write-Host "Type: $exceptionType" -ForegroundColor Yellow
    
    exit 1
}
