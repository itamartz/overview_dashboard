
$baseUrl = "http://localhost:5203/api/components"

function Post-Component {
    param (
        [string]$system,
        [string]$project,
        [string]$name,
        [string]$severity
    )

    $payload = @{
        systemName  = $system
        projectName = $project
        name        = $name
        severity    = $severity
        payload     = (@{ status = $severity; timestamp = (Get-Date) } | ConvertTo-Json)
    } | ConvertTo-Json

    try {
        Invoke-RestMethod -Uri $baseUrl -Method Post -Body $payload -ContentType "application/json" -ErrorAction Stop
    }
    catch {
        Write-Host "Failed to post to $baseUrl. Is the app running?" -ForegroundColor Red
    }
}

Write-Host "Generating Mixed Severity Masonry Test Data..." -ForegroundColor Cyan

$sys = "MixedLayoutTest"

# 1. Project with EVERYTHING (Should appear in all 4 blocks)
Write-Host "Creating 'OmniProject' (Appears in all blocks)..." -ForegroundColor Magenta
Post-Component -system $sys -project "OmniProject" -name "Comp_Err" -severity "error"
Post-Component -system $sys -project "OmniProject" -name "Comp_Warn" -severity "warning"
Post-Component -system $sys -project "OmniProject" -name "Comp_Info" -severity "info"
Post-Component -system $sys -project "OmniProject" -name "Comp_OK" -severity "ok"

# 2. Project with High ERROR count (Should make Error block taller)
Write-Host "Creating 'CriticalApp' (Many Errors)..." -ForegroundColor Red
1..10 | ForEach-Object {
    Post-Component -system $sys -project "CriticalApp" -name "Err_$_" -severity "error"
}

# 3. Project with High WARNING count
Write-Host "Creating 'DegradedSvc' (Many Warnings)..." -ForegroundColor Yellow
1..8 | ForEach-Object {
    Post-Component -system $sys -project "DegradedSvc" -name "Warn_$_" -severity "warning"
}

# 4. Project with High INFO count
Write-Host "Creating 'ChattyApp' (Many Infos)..." -ForegroundColor Cyan
1..12 | ForEach-Object {
    Post-Component -system $sys -project "ChattyApp" -name "Info_$_" -severity "info"
}

# 5. Project with High OK count
Write-Host "Creating 'StableCore' (Many OKs)..." -ForegroundColor Green
1..25 | ForEach-Object {
    Post-Component -system $sys -project "StableCore" -name "Ok_$_" -severity "ok"
}

# 6. Random mixed noise
Write-Host "Creating Random Noise..." -ForegroundColor Gray
1..5 | ForEach-Object { Post-Component -system $sys -project "WebFront_$_" -name "Status" -severity "ok" }
1..3 | ForEach-Object { Post-Component -system $sys -project "Backend_$_" -name "Status" -severity "error" }

Write-Host "Done! detailed mixed data generated." -ForegroundColor Green
