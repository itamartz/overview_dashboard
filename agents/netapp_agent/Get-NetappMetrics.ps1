[CmdletBinding()]
param(
    [string]$ConfigPath = "config.json",
    [switch]$DryRun,
    [switch]$MockRun
)

# -------------------------------------------------------------------
# Helper: Send-ToApi
# -------------------------------------------------------------------
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

# -------------------------------------------------------------------
# Helper: Credentials
# -------------------------------------------------------------------
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
        Write-Warning "Encrypted credential file not found: $EncryptedFilePath"
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
        Write-Warning "Failed to decrypt credential file '$EncryptedFilePath': $_"
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

# -------------------------------------------------------------------
# Helper: Invoke-NetAppRestApi
# -------------------------------------------------------------------
function Invoke-NetAppRestApi {
    param(
        [string]$ClusterIP,
        [string]$Endpoint,
        [string]$Method = "GET",
        [object]$Body,
        [PSCredential]$Credential
    )

    $uri = "https://$ClusterIP$Endpoint"
    $authString = "$($Credential.UserName):$($Credential.GetNetworkCredential().Password)"
    $authBytes = [System.Text.Encoding]::UTF8.GetBytes($authString)
    $authBase64 = [System.Convert]::ToBase64String($authBytes)

    $headers = @{
        "Authorization" = "Basic $authBase64"
        "Accept"        = "application/json"
        "Content-Type"  = "application/json"
    }

    if (-not ([System.Management.Automation.PSTypeName]'TrustAllCertsPolicy').Type) {
        Add-Type @"
using System.Net;
using System.Security.Cryptography.X509Certificates;
public class TrustAllCertsPolicy : ICertificatePolicy {
  public bool CheckValidationResult(ServicePoint srvPoint, X509Certificate certificate,
      WebRequest request, int certificateProblem) { return true; }
}
"@
    }
    [System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

    try {
        $params = @{
            Uri         = $uri
            Method      = $Method
            Headers     = $headers
            ErrorAction = "Stop"
        }

        if ($Body) {
            $params.Body = ($Body | ConvertTo-Json -Depth 10)
        }

        return Invoke-RestMethod @params
    }
    catch {
        throw "NetApp API call failed: $($_.Exception.Message)"
    }
}

# -------------------------------------------------------------------
# Main Logic
# -------------------------------------------------------------------
$fullConfigPath = Join-Path $PSScriptRoot $ConfigPath
if (-not (Test-Path $fullConfigPath)) {
    Write-Error "Configuration file not found: $fullConfigPath"
    exit 1
}

$config = Get-Content $fullConfigPath | ConvertFrom-Json
$apiUrl = $config.apiUrl
$projectName = $config.projectName
$systemName = $config.systemName
$defaultTTL = $config.defaultTTL
$credMethod = if ($config.credentialMethod) { $config.credentialMethod } else { "plaintext" }

Write-Host "========================================="
Write-Host " NetApp Monitoring Agent"
Write-Host "========================================="
if ($DryRun) { Write-Host " MODE: DryRun (No connections or API calls)" -ForegroundColor Yellow }
if ($MockRun) { Write-Host " MODE: MockRun (Fake data sent to API)" -ForegroundColor Cyan }

foreach ($target in $config.targets) {
    if (-not $target.enabled) {
        Write-Host "Skipping disabled target: $($target.name)"
        continue
    }

    if ($DryRun) {
        Write-Host "[DRY RUN] Would process NetApp cluster: $($target.name) at $($target.host)"
        continue
    }

    if ($MockRun) {
        Write-Host "[MOCK RUN] Sending fake data for $($target.name)"
        
        $mockSeverity = @("ok", "ok", "ok", "warning", "error") | Get-Random
        Send-ToApi -ApiUrl $apiUrl -SystemName $systemName -ProjectName $projectName `
            -Name "$($target.name) - Cluster Health" -Metric "Cluster" -Severity $mockSeverity `
            -Status "Mock Status: $mockSeverity" -TTL $defaultTTL
        continue
    }

    # Resolve Credentials
    $credInfo = Resolve-Credential -Method $credMethod -Target $target -CyberArkConfig $config.cyberark
    if (-not $credInfo.Success) {
        Write-Warning "Failed to retrieve credentials for $($target.name)"
        Send-ToApi -ApiUrl $apiUrl -SystemName $systemName -ProjectName $projectName `
            -Name "$($target.name) - Credential" -Metric "Credential" -Severity "error" `
            -Status "Failed to retrieve credentials" -TTL $defaultTTL
        continue
    }

    $secureString = ConvertTo-SecureString $credInfo.Password -AsPlainText -Force
    $credential = New-Object System.Management.Automation.PSCredential($credInfo.Username, $secureString)

    # 1. Cluster Health
    try {
        $healthEndpoint = "/api/private/cli/system/health/status?fields=status"
        $healthStatus = Invoke-NetAppRestApi -ClusterIP $target.host -Endpoint $healthEndpoint -Credential $credential
        $status = if ($healthStatus.status -eq 'ok') { "ok" } else { "error" }
        Send-ToApi -ApiUrl $apiUrl -SystemName $systemName -ProjectName $projectName -Name "$($target.name) - Cluster Health" -Metric "Cluster" -Severity $status -Status "Health: $($healthStatus.status)" -TTL $defaultTTL
    } catch {
        Send-ToApi -ApiUrl $apiUrl -SystemName $systemName -ProjectName $projectName -Name "$($target.name) - Cluster Health" -Metric "Cluster" -Severity "error" -Status $_.Exception.Message -TTL $defaultTTL
    }

    # 2. Nodes Up
    try {
        $endpoint = "/api/cluster/nodes?fields=state,uptime,ha"
        $nodes = Invoke-NetAppRestApi -ClusterIP $target.host -Endpoint $endpoint -Credential $credential
        $critical = @(); foreach ($node in $nodes.records) { if ($node.state -ne "up") { $critical += $node.name } }
        $status = if ($critical.Count -gt 0) { "error" } else { "ok" }
        $msg = if ($critical.Count -gt 0) { "Nodes down: $($critical -join ', ')" } else { "All nodes up" }
        Send-ToApi -ApiUrl $apiUrl -SystemName $systemName -ProjectName $projectName -Name "$($target.name) - Nodes" -Metric "Nodes" -Severity $status -Status $msg -TTL $defaultTTL
    } catch {
        Send-ToApi -ApiUrl $apiUrl -SystemName $systemName -ProjectName $projectName -Name "$($target.name) - Nodes" -Metric "Nodes" -Severity "error" -Status $_.Exception.Message -TTL $defaultTTL
    }

    # 3. Node HA Status
    try {
        $endpoint = "/api/cluster/nodes?fields=state,uptime,ha"
        $nodes = Invoke-NetAppRestApi -ClusterIP $target.host -Endpoint $endpoint -Credential $credential
        $critical = @(); $warnings = @()
        foreach ($node in $nodes.records) {
            if ($node.ha.enabled) {
                if (-not $node.ha.auto_giveback) { $warnings += "no_auto_giveback" }
                if ($node.ha.takeover -and $node.ha.takeover.state -ne "not_in_takeover" -and $node.ha.takeover.state -ne "not_attempted") {
                    $critical += "takeover_state_$($node.ha.takeover.state)"
                }
            } else {
                $critical += "ha_disabled"
            }
        }
        $status = if ($critical.Count -gt 0) { "error" } elseif ($warnings.Count -gt 0) { "warning" } else { "ok" }
        Send-ToApi -ApiUrl $apiUrl -SystemName $systemName -ProjectName $projectName -Name "$($target.name) - HA Status" -Metric "HA" -Severity $status -Status "HA Status $status" -TTL $defaultTTL
    } catch {
        Send-ToApi -ApiUrl $apiUrl -SystemName $systemName -ProjectName $projectName -Name "$($target.name) - HA Status" -Metric "HA" -Severity "error" -Status $_.Exception.Message -TTL $defaultTTL
    }

    # 4. Aggregates
    try {
        $endpoint = "/api/storage/aggregates?fields=space,state,node"
        $aggregates = Invoke-NetAppRestApi -ClusterIP $target.host -Endpoint $endpoint -Credential $credential
        foreach ($aggr in $aggregates.records) {
            $usedPercent = 0
            if ($aggr.space.block_storage.size -gt 0) {
                $usedPercent = [math]::Round(($aggr.space.block_storage.used / $aggr.space.block_storage.size) * 100, 1)
            }
            if ($aggr.state -eq "online") {
                $status = if ($usedPercent -ge $target.AggregateErrorThreshold) { "error" } elseif ($usedPercent -ge $target.AggregateWarningThreshold) { "warning" } else { "ok" }
            } else {
                $status = "error"
            }
            Send-ToApi -ApiUrl $apiUrl -SystemName $systemName -ProjectName $projectName -Name "$($target.name) - Aggr: $($aggr.name)" -Metric "Aggregate" -Severity $status -Status "$usedPercent% Used" -TTL $defaultTTL
        }
    } catch {
        Write-Warning "Failed to process aggregates: $_"
    }

    # 5. Volumes
    try {
        $endpoint = "/api/storage/volumes?fields=space,state,svm,type&max_records=500"
        $volumes = Invoke-NetAppRestApi -ClusterIP $target.host -Endpoint $endpoint -Credential $credential
        foreach ($vol in $volumes.records) {
            $usedPercent = 0
            if ($vol.space.size -gt 0) {
                $usedPercent = [math]::Round(($vol.space.used / $vol.space.size) * 100, 1)
            }
            $status = if ($usedPercent -ge $target.VolumeErrorThreshold) { "error" } elseif ($usedPercent -ge $target.VolumeWarningThreshold) { "warning" } else { "ok" }
            Send-ToApi -ApiUrl $apiUrl -SystemName $systemName -ProjectName $projectName -Name "$($target.name) - Vol: $($vol.name)" -Metric "Volume" -Severity $status -Status "$usedPercent% Used" -TTL $defaultTTL
        }
    } catch {
        Write-Warning "Failed to process volumes: $_"
    }

    # 6. Snapshots
    try {
        $endpoint = "/api/storage/volumes?fields=space,state,svm,type&max_records=500"
        $volumes = Invoke-NetAppRestApi -ClusterIP $target.host -Endpoint $endpoint -Credential $credential
        foreach ($vol in $volumes.records) {
            $snapEndpoint = "/api/storage/volumes/$($vol.uuid)/snapshots?fields=name,create_time,size"
            $snapshots = Invoke-NetAppRestApi -ClusterIP $target.host -Endpoint $snapEndpoint -Credential $credential
            foreach ($snap in $snapshots.records) {
                $createTime = [datetime]::MinValue
                $status = "ok"
                if ([datetime]::TryParse($snap.create_time, [ref]$createTime)) {
                    $age = (Get-Date) - $createTime
                    if ($age.Days -ge $target.SnapshotsThreshold) { $status = "error" }
                } else {
                    $status = "error"
                }
                if ($status -ne "ok") {
                    Send-ToApi -ApiUrl $apiUrl -SystemName $systemName -ProjectName $projectName -Name "$($target.name) - Snap: $($snap.name)" -Metric "Snapshot" -Severity $status -Status "Aged $($age.Days) days" -TTL $defaultTTL
                }
            }
        }
    } catch {
        Write-Warning "Failed to process snapshots: $_"
    }

    # 7. LUNs
    try {
        $endpoint = "/api/storage/luns?fields=space,status,location"
        $luns = Invoke-NetAppRestApi -ClusterIP $target.host -Endpoint $endpoint -Credential $credential
        foreach ($lun in $luns.records) {
            $usedPercent = 0
            if ($lun.space.size -gt 0) {
                $usedPercent = [math]::Round(($lun.space.used / $lun.space.size) * 100, 1)
            }
            if ($lun.status.state -eq "online") {
                $status = if ($usedPercent -ge $target.LunErrorThreshold) { "error" } elseif ($usedPercent -ge $target.LunWarningThreshold) { "warning" } else { "ok" }
            } else {
                $status = "error"
            }
            Send-ToApi -ApiUrl $apiUrl -SystemName $systemName -ProjectName $projectName -Name "$($target.name) - LUN: $($lun.location.logical_unit)" -Metric "LUN" -Severity $status -Status "$usedPercent% Used" -TTL $defaultTTL
        }
    } catch {
        Write-Warning "Failed to process LUNs: $_"
    }

    # 8. Disks
    try {
        $endpoint = "/api/storage/disks?fields=state,name,serial_number"
        $disks = Invoke-NetAppRestApi -ClusterIP $target.host -Endpoint $endpoint -Credential $credential
        $problemStates = @("broken", "failed", "missing", "reconstructing", "unfail")
        foreach ($disk in $disks.records) {
            $status = if ($disk.state -in $problemStates) { "error" } else { "ok" }
            Send-ToApi -ApiUrl $apiUrl -SystemName $systemName -ProjectName $projectName -Name "$($target.name) - Disk: $($disk.name)" -Metric "Disk" -Severity $status -Status "State: $($disk.state)" -TTL $defaultTTL
        }
    } catch {
        Write-Warning "Failed to process disks: $_"
    }

    # 9. Ethernet
    try {
        $endpoint = "/api/network/ethernet/ports?fields=enabled,state,name"
        $ethernet = Invoke-NetAppRestApi -ClusterIP $target.host -Endpoint $endpoint -Credential $credential
        foreach ($eth in $ethernet.records) {
            $status = if ($eth.enabled -and $eth.state -ne "up") { "error" } else { "ok" }
            Send-ToApi -ApiUrl $apiUrl -SystemName $systemName -ProjectName $projectName -Name "$($target.name) - Eth: $($eth.name)" -Metric "Ethernet" -Severity $status -Status "State: $($eth.state)" -TTL $defaultTTL
        }
    } catch {
        Write-Warning "Failed to process ethernet ports: $_"
    }

    # 10. LIFs
    try {
        $endpoint = "/api/network/ip/interfaces?fields=state,enabled,name"
        $lifs = Invoke-NetAppRestApi -ClusterIP $target.host -Endpoint $endpoint -Credential $credential
        foreach ($lif in $lifs.records) {
            $status = if ($lif.enabled -and $lif.state -ne "up") { "error" } else { "ok" }
            Send-ToApi -ApiUrl $apiUrl -SystemName $systemName -ProjectName $projectName -Name "$($target.name) - LIF: $($lif.name)" -Metric "LIF" -Severity $status -Status "State: $($lif.state)" -TTL $defaultTTL
        }
    } catch {
        Write-Warning "Failed to process LIFs: $_"
    }
}
Write-Host "Done."
