[CmdletBinding()]
param(
    [string]$ConfigPath,
    [switch]$DryRun,
    [switch]$MockRun
)

if (-not $ConfigPath) {
    $ConfigPath = "config.json"
}


# Shared functions: Send-ToApi, Get-CyberArkCredential, Get-EncryptedCredential, Resolve-Credential
Import-Module (Join-Path $PSScriptRoot '..\shared\functions.psm1') -Force

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
        
        $extraData = @{ message = "system healthy is $($healthStatus.status)" }
        Send-ToApi -ApiUrl $apiUrl -SystemName $systemName -ProjectName 'Cluster' -Name "$($target.name) - Cluster Health" -Metric "Cluster" -Severity $status -Status "Health: $($healthStatus.status)" -TTL $defaultTTL -ExtraData $extraData
    } catch {
        Send-ToApi -ApiUrl $apiUrl -SystemName $systemName -ProjectName 'Cluster' -Name "$($target.name) - Cluster Health" -Metric "Cluster" -Severity "error" -Status $_.Exception.Message -TTL $defaultTTL
    }

    # 2. Nodes Up
    try {
        $endpoint = "/api/cluster/nodes?fields=state,uptime,ha"
        $nodes = Invoke-NetAppRestApi -ClusterIP $target.host -Endpoint $endpoint -Credential $credential
        $critical = @(); foreach ($node in $nodes.records) { if ($node.state -ne "up") { $critical += $node.name } }
        $status = if ($critical.Count -gt 0) { "error" } else { "ok" }
        $msg = if ($critical.Count -gt 0) { "Node issues: $($critical -join '; ')" } else { "All $($nodes.num_records) nodes healthy and online" }
        
        $extraData = @{ message = $msg }
        Send-ToApi -ApiUrl $apiUrl -SystemName $systemName -ProjectName 'Cluster' -Name "$($target.name) - Nodes" -Metric "Nodes" -Severity $status -Status $msg -TTL $defaultTTL -ExtraData $extraData
    } catch {
        Send-ToApi -ApiUrl $apiUrl -SystemName $systemName -ProjectName 'Cluster' -Name "$($target.name) - Nodes" -Metric "Nodes" -Severity "error" -Status $_.Exception.Message -TTL $defaultTTL
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
        $msg = if ($critical.Count -gt 0) { "$($critical -join '; ')" } elseif ($warnings.Count -gt 0) { "$($warnings.Count)" } else { "All $($nodes.num_records) nodes ha ok" }
        
        $extraData = @{ message = $msg }
        Send-ToApi -ApiUrl $apiUrl -SystemName $systemName -ProjectName 'Cluster' -Name "$($target.name) - HA Status" -Metric "HA" -Severity $status -Status "HA Status $status" -TTL $defaultTTL -ExtraData $extraData
    } catch {
        Send-ToApi -ApiUrl $apiUrl -SystemName $systemName -ProjectName 'Cluster' -Name "$($target.name) - HA Status" -Metric "HA" -Severity "error" -Status $_.Exception.Message -TTL $defaultTTL
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
            
            $extraData = @{
                NetApp = $target.host
                totalTB = [math]::Round($aggr.space.block_storage.size / 1TB, 2)
                usedTB = [math]::Round($aggr.space.block_storage.used / 1TB, 2)
                availableTB = [math]::Round($aggr.space.block_storage.available / 1TB, 2)
                '% Used' = $usedPercent
                state = $aggr.state
            }

            Send-ToApi -ApiUrl $apiUrl -SystemName $systemName -ProjectName 'Aggregates' -Name "$($aggr.name)" -Metric "Aggregate" -Severity $status -Status "$usedPercent% Used" -TTL $defaultTTL -ExtraData $extraData
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
            
            $extraData = @{
                NetApp = $target.host
                TotalGB = [math]::Round($vol.space.size / 1GB, 2)
                UsedGB = [math]::Round($vol.space.used / 1GB, 2)
                '% Used' = $usedPercent
            }
            
            Send-ToApi -ApiUrl $apiUrl -SystemName $systemName -ProjectName 'Volumes' -Name "$($vol.name)" -Metric "Volume" -Severity $status -Status "$usedPercent% Used" -TTL $defaultTTL -ExtraData $extraData
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
                    $extraData = @{
                        NetApp = $target.host
                        VolumeName = $vol.name
                        Snapshot = $snap.name
                    }
                    Send-ToApi -ApiUrl $apiUrl -SystemName $systemName -ProjectName 'Snapshots' -Name "$($snap.name)" -Metric "Snapshot" -Severity $status -Status "Aged $($age.Days) days" -TTL $defaultTTL -ExtraData $extraData
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
            
            $extraData = @{
                NetApp = $target.host
                state = $lun.status.state
                TotalGB = [math]::Round($lun.space.size / 1GB, 2)
                UsedGB = [math]::Round($lun.space.used / 1GB, 2)
                '% Used' = $usedPercent
            }
            Send-ToApi -ApiUrl $apiUrl -SystemName $systemName -ProjectName 'Luns' -Name "$($lun.location.logical_unit)" -Metric "LUN" -Severity $status -Status "$usedPercent% Used" -TTL $defaultTTL -ExtraData $extraData
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
            
            $extraData = @{ NetApp = $target.host }
            Send-ToApi -ApiUrl $apiUrl -SystemName $systemName -ProjectName 'Disks' -Name "$($disk.name)" -Metric "Disk" -Severity $status -Status "State: $($disk.state)" -TTL $defaultTTL -ExtraData $extraData
        }
    } catch {
        Write-Warning "Failed to process disks: $_"
    }

    # 9. Ethernet
    try {
        $endpoint = "/api/network/ethernet/ports?fields=enabled,state,name,node"
        $ethernet = Invoke-NetAppRestApi -ClusterIP $target.host -Endpoint $endpoint -Credential $credential
        foreach ($eth in $ethernet.records) {
            $status = if ($eth.enabled -and $eth.state -ne "up") { "error" } else { "ok" }
            
            $extraData = @{
                NetApp = $target.host
                Enabled = $eth.enabled
                State = $eth.state
                Node = $eth.node.name
            }
            Send-ToApi -ApiUrl $apiUrl -SystemName $systemName -ProjectName 'Ethernet' -Name "$($eth.name)" -Metric "Ethernet" -Severity $status -Status "State: $($eth.state)" -TTL $defaultTTL -ExtraData $extraData
        }
    } catch {
        Write-Warning "Failed to process ethernet ports: $_"
    }

    # 10. LIFs
    try {
        $endpoint = "/api/network/ip/interfaces?fields=state,location,svm,ip,enabled,name"
        $lifs = Invoke-NetAppRestApi -ClusterIP $target.host -Endpoint $endpoint -Credential $credential
        foreach ($lif in $lifs.records) {
            $status = if ($lif.enabled -and $lif.state -ne "up") { "error" } else { "ok" }
            
            $extraData = @{
                NetApp = $target.host
                Enabled = $lif.enabled
                State = $lif.state
                SVM = $lif.svm.name
            }
            Send-ToApi -ApiUrl $apiUrl -SystemName $systemName -ProjectName 'Interfaces' -Name "$($lif.name)" -Metric "LIF" -Severity $status -Status "State: $($lif.state)" -TTL $defaultTTL -ExtraData $extraData
        }
    } catch {
        Write-Warning "Failed to process LIFs: $_"
    }
}
Write-Host "Done."
