<#
.SYNOPSIS
    Monitors Cisco Redfish (CIMC) and reports metrics to the Overview Dashboard.

.DESCRIPTION
    Connects to Cisco Redfish API to collect metrics for ProcessorsHealth, StorageHealth,
    StorageDisks, PowerSupply, Temperatures, Fans, SystemHealth and reports to the Dashboard.

.PARAMETER ConfigPath
    Path to the config.json file. Default: $PSScriptRoot\config.json

.PARAMETER DryRun
    If specified, shows what would be reported without connecting or sending to API.

.PARAMETER MockRun
    If specified, generates sample data and sends to API without real connections.

.EXAMPLE
    .\Get-CiscoRedfishMetrics.ps1

.EXAMPLE
    .\Get-CiscoRedfishMetrics.ps1 -MockRun
#>

[CmdletBinding()]
param(
    [string]$ConfigPath = "$PSScriptRoot\config.json",
    [switch]$DryRun,
    [switch]$MockRun
)

#region Helper Functions

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

    if ($DryRun) {
        Write-Host "[DRY RUN] Would send to API: System='$SystemName', Project='$ProjectName', Name='$Name', Metric='$Metric', Severity='$Severity', Status='$Status'" -ForegroundColor Yellow
        return $true
    }

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
        Invoke-RestMethod -Uri $ApiUrl -Method Post -Body $body -ContentType "application/json" -ErrorAction Stop | Out-Null
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
        return @{
            Username = ""
            Password = ""
            Address  = ""
            Success  = $false
        }
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
        default {
            return @{
                Username = $Target.username
                Password = $Target.password
                Success  = ($null -ne $Target.password -and $Target.password -ne "")
            }
        }
    }
}

function Connect-Redfish {
    param([string]$ServerName, [string]$Username, [string]$Password)
    try {
        $JsonBody = @{ 'UserName' = $Username; 'Password' = $Password } | ConvertTo-Json -Compress
        [Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        
        $response = Invoke-WebRequest -Uri "https://$($ServerName)/redfish/v1/SessionService/Sessions" -Method Post -Body $JsonBody -ContentType 'application/json' -ErrorAction Stop
        
        $Global:RedfishConnection = [PSCustomObject]@{
            Server  = $ServerName
            Headers = @{
                'Accept'       = 'application/json'
                'Content-Type' = 'application/json'
                'X-Auth-Token' = $response.Headers['X-Auth-Token'] 
            }
            Sessions = ($response.Content | ConvertFrom-Json)
        }
        return @{ IsError = $false }
    }
    catch {
        return @{ IsError = $true; ErrorMessage = $_.Exception.Message }
    }
}

function Disconnect-Redfish {
    if ($Global:RedfishConnection) {
        try {
            Invoke-WebRequest -Uri "https://$($Global:RedfishConnection.Server)/redfish/v1/SessionService/Sessions/$($Global:RedfishConnection.Sessions.ID)" -Method Delete -ContentType 'application/json' -Headers $Global:RedfishConnection.Headers -ErrorAction Stop | Out-Null
        } catch {}
        $Global:RedfishConnection = $null
    }
}

function Invoke-RedfishGet {
    param([string]$URLSuffix)
    try {
        if ($URLSuffix -match '^/redfish/v1') { $URLSuffix = $URLSuffix -replace '^/redfish/v1', '' }
        $URL = "https://$($Global:RedfishConnection.Server)/redfish/v1$URLSuffix"
        $response = Invoke-WebRequest -Uri $URL -Method Get -ContentType 'application/json' -Headers $Global:RedfishConnection.Headers -ErrorAction Stop
        return @{ IsError = $false; ServerResponse = ($response.Content | ConvertFrom-Json) }
    }
    catch {
        return @{ IsError = $true; Message = $_.Exception.Message }
    }
}

#endregion

#region Main Script

if (-not (Test-Path $ConfigPath)) {
    Write-Error "Config file not found at $ConfigPath"
    exit 1
}

try {
    $config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
}
catch {
    Write-Error "Failed to parse config file: $_"
    exit 1
}

$apiUrl = $config.apiUrl
$projectName = $config.projectName
$systemName = $config.systemName
$defaultTTL = if ($config.defaultTTL) { $config.defaultTTL } else { 3600 }
$credMethod = if ($config.credentialMethod) { $config.credentialMethod } else { "plaintext" }

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Cisco Redfish Metrics Agent" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "API URL: $apiUrl"
Write-Host "Project: $projectName"
Write-Host "System:  $systemName"
Write-Host ""

if ($DryRun) { Write-Host "[DRY RUN MODE - No connections or API calls]" -ForegroundColor Yellow }
if ($MockRun) { Write-Host "[MOCK RUN MODE - Sending sample data to API]" -ForegroundColor Magenta }

foreach ($target in $config.targets) {
    if (-not $target.enabled) { continue }
    
    $serverName = $target.host
    Write-Host "Processing $serverName..."

    if ($MockRun) {
        $severity = if ((Get-Random -Max 100) -gt 90) { "error" } else { "ok" }
        Send-ToApi -ApiUrl $apiUrl -SystemName $systemName -ProjectName 'SystemHealth' -Name $serverName -Metric 'Health' -Severity $severity -Status "Mock Health" -TTL $defaultTTL
        continue
    }

    if (-not $DryRun) {
        $cred = Resolve-Credential -Method $credMethod -Target $target -CyberArkConfig $config.cyberark
        if (-not $cred.Success) {
            Send-ToApi -ApiUrl $apiUrl -SystemName $systemName -ProjectName $projectName -Name $serverName -Metric "Credential" -Severity "error" -Status "Failed to retrieve credentials" -TTL $defaultTTL
            continue
        }

        $conn = Connect-Redfish -ServerName $serverName -Username $cred.Username -Password $cred.Password
        if ($conn.IsError) {
            Send-ToApi -ApiUrl $apiUrl -SystemName $systemName -ProjectName $projectName -Name $serverName -Metric "Connection" -Severity "error" -Status "Connection failed" -TTL $defaultTTL
            continue
        }

        # 1. System Health
        $systems = Invoke-RedfishGet -URLSuffix "/Systems"
        if (-not $systems.IsError -and $systems.ServerResponse.Members.Count -gt 0) {
            $sysInfo = Invoke-RedfishGet -URLSuffix $systems.ServerResponse.Members[0].'@odata.id'
            if (-not $sysInfo.IsError) {
                $sysHealth = $sysInfo.ServerResponse.Status.Health
                $severity = if ($sysHealth -eq 'OK') { 'ok' } else { 'error' }
                Send-ToApi -ApiUrl $apiUrl -SystemName $systemName -ProjectName 'CIMC' -Name $serverName -Metric 'SystemHealth' -Severity $severity -Status "Health: $sysHealth" -TTL $defaultTTL
            }
        }

        # 2. Processors
        if ($sysInfo -and -not $sysInfo.IsError -and $sysInfo.ServerResponse.Processors) {
            $procs = Invoke-RedfishGet -URLSuffix $sysInfo.ServerResponse.Processors.'@odata.id'
            if (-not $procs.IsError) {
                foreach ($proc in $procs.ServerResponse.Members) {
                    $pInfo = Invoke-RedfishGet -URLSuffix $proc.'@odata.id'
                    if (-not $pInfo.IsError) {
                        $pHealth = $pInfo.ServerResponse.Status.Health
                        $severity = if ($pHealth -eq 'OK') { 'ok' } else { 'error' }
                        Send-ToApi -ApiUrl $apiUrl -SystemName $systemName -ProjectName 'Processor' -Name "$serverName-$($pInfo.ServerResponse.Id)" -Metric 'ProcessorHealth' -Severity $severity -Status "Health: $pHealth" -TTL $defaultTTL
                    }
                }
            }
        }

        # 3. Storage
        if ($sysInfo -and -not $sysInfo.IsError -and $sysInfo.ServerResponse.Storage) {
            $storages = Invoke-RedfishGet -URLSuffix $sysInfo.ServerResponse.Storage.'@odata.id'
            if (-not $storages.IsError) {
                foreach ($store in $storages.ServerResponse.Members) {
                    $sInfo = Invoke-RedfishGet -URLSuffix $store.'@odata.id'
                    if (-not $sInfo.IsError) {
                        $sHealth = if ($sInfo.ServerResponse.StorageControllers) { $sInfo.ServerResponse.StorageControllers.Status.Health } else { $sInfo.ServerResponse.Status.Health }
                        $severity = if ($sHealth -eq 'OK') { 'ok' } else { 'error' }
                        $scName = if ($sInfo.ServerResponse.StorageControllers) { $sInfo.ServerResponse.StorageControllers.MemberId } else { $sInfo.ServerResponse.Id }
                        Send-ToApi -ApiUrl $apiUrl -SystemName $systemName -ProjectName 'StorageController' -Name "$serverName-$scName" -Metric 'StorageHealth' -Severity $severity -Status "Health: $sHealth" -TTL $defaultTTL
                        
                        # Disks
                        foreach ($drive in $sInfo.ServerResponse.Drives) {
                            $dInfo = Invoke-RedfishGet -URLSuffix $drive.'@odata.id'
                            if (-not $dInfo.IsError) {
                                $dHealth = $dInfo.ServerResponse.Status.Health
                                $severity = if ($dHealth -eq 'OK') { 'ok' } else { 'error' }
                                Send-ToApi -ApiUrl $apiUrl -SystemName $systemName -ProjectName 'Disks' -Name "$serverName-$($sInfo.ServerResponse.Name)-$($dInfo.ServerResponse.Id)" -Metric 'DiskHealth' -Severity $severity -Status "Health: $dHealth" -TTL $defaultTTL
                            }
                        }
                    }
                }
            }
        }

        # 4. Thermal & Power
        $chassis = Invoke-RedfishGet -URLSuffix "/Chassis"
        if (-not $chassis.IsError -and $chassis.ServerResponse.Members.Count -gt 0) {
            $cInfo = Invoke-RedfishGet -URLSuffix $chassis.ServerResponse.Members[0].'@odata.id'
            if (-not $cInfo.IsError) {
                # Thermal (Temperatures and Fans)
                if ($cInfo.ServerResponse.Thermal) {
                    $thermal = Invoke-RedfishGet -URLSuffix $cInfo.ServerResponse.Thermal.'@odata.id'
                    if (-not $thermal.IsError) {
                        foreach ($temp in $thermal.ServerResponse.Temperatures) {
                            $tHealth = $temp.Status.Health
                            $severity = if ($tHealth -eq 'OK') { 'ok' } else { 'error' }
                            Send-ToApi -ApiUrl $apiUrl -SystemName $systemName -ProjectName 'Temperature' -Name "$serverName-$($temp.MemberId)" -Metric 'TempHealth' -Severity $severity -Status "$($temp.ReadingCelsius) C" -TTL $defaultTTL
                        }
                        foreach ($fan in $thermal.ServerResponse.Fans | Where-Object { $_.Status.Health }) {
                            $fHealth = $fan.Status.Health
                            $severity = if ($fHealth -eq 'OK') { 'ok' } else { 'error' }
                            Send-ToApi -ApiUrl $apiUrl -SystemName $systemName -ProjectName 'Fans' -Name "$serverName-$($fan.MemberId)" -Metric 'FanHealth' -Severity $severity -Status "$($fan.Reading) RPM" -TTL $defaultTTL
                        }
                    }
                }
                # Power
                if ($cInfo.ServerResponse.Power) {
                    $power = Invoke-RedfishGet -URLSuffix $cInfo.ServerResponse.Power.'@odata.id'
                    if (-not $power.IsError) {
                        foreach ($psu in $power.ServerResponse.PowerSupplies) {
                            $pHealth = $psu.Status.Health
                            $severity = if ($pHealth -eq 'OK') { 'ok' } else { 'error' }
                            Send-ToApi -ApiUrl $apiUrl -SystemName $systemName -ProjectName 'PowerSupply' -Name "$serverName-$($psu.MemberId)" -Metric 'PowerHealth' -Severity $severity -Status "$($psu.PowerInputWatts) W" -TTL $defaultTTL
                        }
                    }
                }
            }
        }

        Disconnect-Redfish
    }
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Completed." -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

#endregion
