$baseUri = "http://localhost:5203/api/components"

function Post-Component {
    param (
        [string]$system,
        [string]$project,
        [string]$name,
        [string]$severity,
        [string]$message,
        [int]$ttl
    )

    $timestamp = (Get-Date).ToString("o")
    
    # Construct the JSON payload with the new TTL field
    $payload = @{
        Name      = $name
        Severity  = $severity
        Message   = $message
        TTL       = $ttl
        Timestamp = $timestamp
    } | ConvertTo-Json -Depth 10

    $body = @{
        systemName  = $system
        projectName = $project
        createdAt   = $timestamp
        payload     = $payload
    } | ConvertTo-Json -Depth 10

    try {
        Invoke-RestMethod -Uri $baseUri -Method Post -Body $body -ContentType "application/json"
        Write-Host "Posted: $name (TTL: ${ttl}s) - $severity" -ForegroundColor Green
    }
    catch {
        Write-Host "Error posting $name : $_" -ForegroundColor Red
    }
}

Write-Host "Injecting Data with Varying TTLs..."

# Project 1: Fast TTL (1 Minute / 60s)
# These will go offline very quickly if not updated.
for ($i = 1; $i -le 5; $i++) {
    Post-Component -system "TTL_Test_System" -project "Fast_TTL_Project" -name "FastComp_$i" -severity "ok" -message "I expire in 1 min" -ttl 60
}

# Project 2: Medium TTL (5 Minutes / 300s)
for ($i = 1; $i -le 5; $i++) {
    Post-Component -system "TTL_Test_System" -project "Medium_TTL_Project" -name "MedComp_$i" -severity "warning" -message "I expire in 5 mins" -ttl 300
}

# Project 3: Long TTL (30 Minutes / 1800s)
for ($i = 1; $i -le 5; $i++) {
    Post-Component -system "TTL_Test_System" -project "Long_TTL_Project" -name "LongComp_$i" -severity "error" -message "I expire in 30 mins" -ttl 1800
}

# Project 4: Mixed TTLs in one project
Post-Component -system "TTL_Test_System" -project "Mixed_TTL_Project" -name "Mix_1_Min" -severity "ok" -message "1 min TTL" -ttl 60
Post-Component -system "TTL_Test_System" -project "Mixed_TTL_Project" -name "Mix_10_Min" -severity "ok" -message "10 min TTL" -ttl 600
Post-Component -system "TTL_Test_System" -project "Mixed_TTL_Project" -name "Mix_Default" -severity "info" -message "No TTL sent (default 60m)" -ttl 3600 # Explicitly sending 60m to verify

Write-Host "Done! All components created fresh (Online)."
