param(
    [string]$ConfigPath = "$PSScriptRoot\config.json",
    [switch]$DryRun,
    [switch]$MockRun
)

# 1. LOAD CONFIGURATION
if (-not (Test-Path $ConfigPath)) {
    Write-Error "Configuration file not found: $ConfigPath"
    exit 1
}

$config = Get-Content $ConfigPath | ConvertFrom-Json

$apiUrl = $config.apiUrl
$systemName = $config.systemName
$projectName = $config.projectName
$defaultTTL = $config.defaultTTL

# Print Banner
Write-Host "=========================================="
Write-Host " RabbitMQ Monitoring Agent"
Write-Host "=========================================="
Write-Host "System:  $systemName"
Write-Host "Project: $projectName"
if ($DryRun) { Write-Host "Mode:    [DRY RUN]" -ForegroundColor Yellow }
if ($MockRun) { Write-Host "Mode:    [MOCK RUN]" -ForegroundColor Yellow }
Write-Host "------------------------------------------"

# Shared functions: Send-ToApi, Get-CyberArkCredential, Get-EncryptedCredential, Resolve-Credential
Import-Module (Join-Path $PSScriptRoot '..\shared\functions.psm1') -Force

$credMethod = if ($config.credentialMethod) { $config.credentialMethod } else { "plaintext" }

foreach ($target in $config.targets) {
    if (-not $target.enabled) {
        Write-Host "Skipping $($target.name) (disabled)"
        continue
    }

    Write-Host "Processing $($target.name)..."

    $cred = $null
    if ($MockRun -or $DryRun) {
        $username = "mockuser"
        $password = "mockpass"
    }
    else {
        $cred = Resolve-Credential -Method $credMethod -Target $target -CyberArkConfig $config.cyberark

        if (-not $cred.Success) {
            Send-ToApi -ApiUrl $apiUrl -SystemName $systemName -ProjectName $projectName `
                -Name $target.name -Metric "Credential" -Severity "error" `
                -Status "Failed to retrieve credentials" -TTL $defaultTTL -DryRun:$DryRun
            continue
        }

        $username = $cred.Username
        $password = $cred.Password
    }

    if ($MockRun) {
        foreach ($queueName in $target.queues.PSObject.Properties.Name) {
            $expectedConsumers = $target.queues.$queueName.consumers
            $actualConsumers = if ((Get-Random -Minimum 0 -Maximum 10) -gt 2) { $expectedConsumers } else { $expectedConsumers - 1 }
            
            $severity = if ($actualConsumers -eq $expectedConsumers) { "ok" } else { "error" }
            $status = "Consumers: $actualConsumers / $expectedConsumers"
            $metricName = "$($target.name)-$queueName"

            Send-ToApi -ApiUrl $apiUrl -SystemName $systemName -ProjectName $projectName `
                -Name $queueName -Metric $metricName -Severity $severity -Status $status -TTL $defaultTTL -DryRun:$DryRun
        }
        continue
    }

    if ($DryRun) {
        foreach ($queueName in $target.queues.PSObject.Properties.Name) {
            Write-Host "[DRY RUN] Would check queue '$queueName' expecting $($target.queues.$queueName.consumers) consumers."
        }
        continue
    }

    # Actual processing
    $securePassword = ConvertTo-SecureString $password -AsPlainText -Force
    $credential = New-Object System.Management.Automation.PSCredential($username, $securePassword)

    $URI = "$($target.prefix)://$($target.host):$($target.port)/api/queues"
    
    try {
        $Response = Invoke-WebRequest -Uri $URI -Credential $credential -UseBasicParsing -ErrorAction Stop
        
        if ($Response.StatusCode -eq 200) {
            $Queues = $Response.Content | ConvertFrom-Json
            
            foreach ($Queue in $Queues) {
                if ($target.queues.PSObject.Properties.Name -contains $Queue.name) {
                    $expectedConsumers = $target.queues.$($Queue.name).consumers
                    $actualConsumers = $Queue.consumers
                    
                    $severity = "ok"
                    if ($actualConsumers -ne $expectedConsumers) {
                        $severity = "error"
                    }
                    
                    $status = "Consumers: $actualConsumers (Expected: $expectedConsumers), Msgs: $($Queue.messages)"
                    $metricName = "$($target.name)-$($Queue.name)"

                    Send-ToApi -ApiUrl $apiUrl -SystemName $systemName -ProjectName $projectName `
                        -Name $Queue.name -Metric $metricName -Severity $severity -Status $status -TTL $defaultTTL -DryRun:$DryRun
                    
                    Write-Host "  -> Queue $($Queue.name): $status [$severity]" -ForegroundColor (if ($severity -eq 'ok') { 'Green' } else { 'Red' })
                }
            }
        }
    }
    catch {
        $errMsg = $_.Exception.Message
        Write-Warning "Failed to connect to RabbitMQ api on $($target.host): $errMsg"
        Send-ToApi -ApiUrl $apiUrl -SystemName $systemName -ProjectName $projectName `
            -Name $target.name -Metric "Connection" -Severity "error" -Status "Connection failed" -TTL $defaultTTL -DryRun:$DryRun
    }
}
Write-Host "Done."
