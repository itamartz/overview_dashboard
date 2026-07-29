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

# Helper functions
function Send-ToApi {
    param(
        [string]$ApiUrl,
        [string]$SystemName,
        [string]$ProjectName,
        [string]$Name,
        [string]$Metric,
        [string]$Severity,
        [string]$Status,
        [int]$TTL
    )

    $idSource = "$SystemName|$ProjectName|$Name|$Metric"
    $md5 = [System.Security.Cryptography.MD5]::Create()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($idSource)
    $hash = $md5.ComputeHash($bytes)
    $componentId = [System.BitConverter]::ToString($hash) -replace '-', ''

    $componentPayload = @{
        Id       = $componentId
        Name     = $Name
        Metric   = $Metric
        Severity = $Severity
        Status   = $Status
        TTL      = $TTL
    } | ConvertTo-Json -Compress

    $body = @{
        systemName  = $SystemName
        projectName = $ProjectName
        payload     = $componentPayload
    } | ConvertTo-Json -Compress

    if ($DryRun) {
        Write-Host "[DRY RUN API POST] Name: $Name | Metric: $Metric | Severity: $Severity | Status: $Status"
        return $true
    }

    try {
        Invoke-RestMethod -Uri $ApiUrl -Method Post -Body $body `
            -ContentType "application/json" -ErrorAction Stop | Out-Null
        return $true
    }
    catch {
        Write-Warning "Failed to send to API: $_"
        return $false
    }
}

function Get-CyberArkCredential {
    param(
        [string]$CcpUrl,
        [string]$AppId,
        [string]$Safe,
        [string]$ObjectName,
        [bool]$VerifySsl = $true,
        [int]$TimeoutSeconds = 10
    )

    $queryParams = @(
        "AppID=$([uri]::EscapeDataString($AppId))",
        "Safe=$([uri]::EscapeDataString($Safe))",
        "Object=$([uri]::EscapeDataString($ObjectName))"
    )
    $fullUrl = "$CcpUrl`?$($queryParams -join '&')"

    $invokeParams = @{
        Uri         = $fullUrl
        Method      = 'GET'
        ContentType = 'application/json'
        TimeoutSec  = $TimeoutSeconds
        ErrorAction = 'Stop'
    }

    if (-not $VerifySsl) {
        # PowerShell 7+ skip SSL checks for self-signed certificates
        $invokeParams.SkipCertificateCheck = $true
    }

    try {
        $response = Invoke-RestMethod @invokeParams
        return @{
            Username = $response.UserName
            Password = $response.Content
            Address  = $response.Address
            Success  = $true
        }
    }
    catch {
        Write-Warning "CyberArk CCP lookup failed for '$ObjectName' in safe '$Safe': $_"
        return @{ Username = ""; Password = ""; Address = ""; Success = $false }
    }
}

function Get-EncryptedCredential {
    param(
        [string]$EncryptedFilePath,
        [string]$Username
    )
    if (-not (Test-Path $EncryptedFilePath)) {
        return @{ Username = $Username; Password = ""; Success = $false }
    }
    try {
        $secureString = Get-Content $EncryptedFilePath | ConvertTo-SecureString
        $credential = New-Object System.Management.Automation.PSCredential($Username, $secureString)
        return @{
            Username = $Username
            Password = $credential.GetNetworkCredential().Password
            Success  = $true
        }
    }
    catch {
        return @{ Username = $Username; Password = ""; Success = $false }
    }
}

function Resolve-Credential {
    param(
        [string]$Method,
        [object]$Target,
        [object]$CyberArkConfig
    )

    switch ($Method.ToLower()) {
        'cyberark' {
            return Get-CyberArkCredential `
                -CcpUrl $CyberArkConfig.ccpUrl `
                -AppId $CyberArkConfig.appId `
                -Safe $Target.cyberarkSafe `
                -ObjectName $Target.cyberarkObject `
                -VerifySsl $CyberArkConfig.verifySsl `
                -TimeoutSeconds $CyberArkConfig.timeoutSeconds
        }
        'encrypted' {
            $encPath = Join-Path $PSScriptRoot $Target.encryptedPasswordFile
            return Get-EncryptedCredential -EncryptedFilePath $encPath -Username $Target.username
        }
        default {
            return @{
                Username = $Target.username
                Password = $Target.password
                Success  = ($null -ne $Target.password -and $Target.password -ne "")
            }
        }
    }
}

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
                -Status "Failed to retrieve credentials" -TTL $defaultTTL
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
                -Name $queueName -Metric $metricName -Severity $severity -Status $status -TTL $defaultTTL
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
                        -Name $Queue.name -Metric $metricName -Severity $severity -Status $status -TTL $defaultTTL
                    
                    Write-Host "  -> Queue $($Queue.name): $status [$severity]" -ForegroundColor (if ($severity -eq 'ok') { 'Green' } else { 'Red' })
                }
            }
        }
    }
    catch {
        $errMsg = $_.Exception.Message
        Write-Warning "Failed to connect to RabbitMQ api on $($target.host): $errMsg"
        Send-ToApi -ApiUrl $apiUrl -SystemName $systemName -ProjectName $projectName `
            -Name $target.name -Metric "Connection" -Severity "error" -Status "Connection failed" -TTL $defaultTTL
    }
}
Write-Host "Done."
