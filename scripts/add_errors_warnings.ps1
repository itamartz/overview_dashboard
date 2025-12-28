
$baseUrl = "http://localhost:5203/api/components"

function Post-Component {
    param (
        [string]$system,
        [string]$project,
        [string]$name,
        [string]$severity
    )

    $innerPayload = @{
        Name      = $name
        Severity  = $severity
        Message   = "Generated event"
        Timestamp = (Get-Date)
    }

    $payload = @{
        systemName  = $system
        projectName = $project
        payload     = ($innerPayload | ConvertTo-Json)
    } | ConvertTo-Json

    try {
        Invoke-RestMethod -Uri $baseUrl -Method Post -Body $payload -ContentType "application/json" -ErrorAction Stop
    }
    catch {
        Write-Host "Failed to post to $baseUrl. Is the app running?" -ForegroundColor Red
    }
}

Write-Host "Injecting Errors and Warnings into existing projects..." -ForegroundColor Cyan

$sys = "MixedLayoutTest"

# 1. Inject Massive Errors into one project to force it to the top
Write-Host "Flooding 'CriticalApp' with 50 more ERRORS..." -ForegroundColor Red
1..50 | ForEach-Object {
    Post-Component -system $sys -project "CriticalApp" -name "Extra_Err_$_" -severity "error"
}

# 2. Add some Errors to StableCore (which was mostly OK)
Write-Host "Corrupting 'StableCore' with 5 ERRORS..." -ForegroundColor Magenta
1..5 | ForEach-Object {
    Post-Component -system $sys -project "StableCore" -name "New_Err_$_" -severity "error"
}

# 3. Create a NEW project with huge WARNINGS
Write-Host "Creating 'WarningsGalore' with 30 WARNINGS..." -ForegroundColor Yellow
1..30 | ForEach-Object {
    Post-Component -system $sys -project "WarningsGalore" -name "Warn_$_" -severity "warning"
}

# 4. Add mixed bag to OmniProject
Write-Host "Updating 'OmniProject' with more mixed events..." -ForegroundColor Gray
1..10 | ForEach-Object { Post-Component -system $sys -project "OmniProject" -name "Mix_Err_$_" -severity "error" }
1..10 | ForEach-Object { Post-Component -system $sys -project "OmniProject" -name "Mix_Warn_$_" -severity "warning" }

Write-Host "Done! Data injected." -ForegroundColor Green
