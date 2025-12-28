
$baseUrl = "http://localhost:5203/api/components"

function Post-Component {
    param (
        [string]$system,
        [string]$project,
        [string]$name,
        [string]$severity
    )

    $payload = @{
        systemName = $system
        projectName = $project
        name = $name
        severity = $severity
        payload = (@{ status = $severity } | ConvertTo-Json)
    } | ConvertTo-Json

    try {
        Invoke-RestMethod -Uri $baseUrl -Method Post -Body $payload -ContentType "application/json" -ErrorAction Stop
    }
    catch {
        Write-Host "Failed to post to $baseUrl. Is the app running?" -ForegroundColor Red
    }
}

Write-Host "Generating Masonry Layout Test Data..." -ForegroundColor Cyan

# 1. ERROR Block - Medium length (15 items)
Write-Host "Creating 15 Projects with Errors..." -ForegroundColor Red
1..15 | ForEach-Object {
    Post-Component -system "MasonryTest" -project "Proj_Err_$_" -name "Comp_1" -severity "error"
}

# 2. WARNING Block - Short length (5 items)
Write-Host "Creating 5 Projects with Warnings..." -ForegroundColor Yellow
1..5 | ForEach-Object {
    Post-Component -system "MasonryTest" -project "Proj_Warn_$_" -name "Comp_1" -severity "warning"
}

# 3. OK Block - Very Long length (40 items)
Write-Host "Creating 40 Projects that are OK..." -ForegroundColor Green
1..40 | ForEach-Object {
    Post-Component -system "MasonryTest" -project "Proj_Ok_$_" -name "Comp_1" -severity "ok"
}

# 4. INFO Block - Very Short length (2 items)
Write-Host "Creating 2 Projects with Info..." -ForegroundColor Cyan
1..2 | ForEach-Object {
    Post-Component -system "MasonryTest" -project "Proj_Info_$_" -name "Comp_1" -severity "info"
}

# 5. OFFLINE Block - Medium length (10 items)
Write-Host "Creating 10 Projects that are Offline..." -ForegroundColor Gray
1..10 | ForEach-Object {
    Post-Component -system "MasonryTest" -project "Proj_Off_$_" -name "Comp_1" -severity "offline"
}

Write-Host "Done! Refresh the dashboard to see the Pinterest layout." -ForegroundColor Green
