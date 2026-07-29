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

# Shared functions: Send-ToApi, Get-CyberArkCredential, Resolve-Credential, Get-X509Certificate2Web
Import-Module (Join-Path $PSScriptRoot '..\shared\functions.psm1') -Force

#region Helper Functions

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
        Send-ToApi -ApiUrl $apiUrl -SystemName $systemName -ProjectName 'SystemHealth' -Name $serverName -Metric 'Health' -Severity $severity -Status "Mock Health" -TTL $defaultTTL -DryRun:$DryRun
        continue
    }

    if (-not $DryRun) {
        $cred = Resolve-Credential -Method $credMethod -Target $target -CyberArkConfig $config.cyberark
        if (-not $cred.Success) {
            Send-ToApi -ApiUrl $apiUrl -SystemName $systemName -ProjectName $projectName -Name $serverName -Metric "Credential" -Severity "error" -Status "Failed to retrieve credentials" -TTL $defaultTTL -DryRun:$DryRun
            continue
        }

        $conn = Connect-Redfish -ServerName $serverName -Username $cred.Username -Password $cred.Password
        if ($conn.IsError) {
            Send-ToApi -ApiUrl $apiUrl -SystemName $systemName -ProjectName $projectName -Name $serverName -Metric "Connection" -Severity "error" -Status "Connection failed" -TTL $defaultTTL -DryRun:$DryRun
            continue
        }

        # 1. System Health
        $systems = Invoke-RedfishGet -URLSuffix "/Systems"
        if (-not $systems.IsError -and $systems.ServerResponse.Members.Count -gt 0) {
            $sysInfo = Invoke-RedfishGet -URLSuffix $systems.ServerResponse.Members[0].'@odata.id'
            if (-not $sysInfo.IsError) {
                $sysHealth = $sysInfo.ServerResponse.Status.Health
                $severity = if ($sysHealth -eq 'OK') { 'ok' } else { 'error' }
                
                $certSeverity = 'ok'
                $certInfo = Get-X509Certificate2Web -ComputerName $serverName
                if ($certInfo) {
                    $TimeSpan = New-TimeSpan -Start (Get-Date) -End $certInfo.NotAfter
                    if ($TimeSpan.Days -le 30) {
                        $certSeverity = 'error'
                        $severity = 'error'
                    } elseif ($TimeSpan.Days -le 60) {
                        $certSeverity = 'warning'
                        if ($severity -eq 'ok') { $severity = 'warning' }
                    }
                }

                $powerState = $sysInfo.ServerResponse.PowerState
                if ($powerState -ne 'On') { $severity = 'error' }

                $memSummary = $sysInfo.ServerResponse.MemorySummary.Status.Health
                if ($memSummary -ne 'OK') { $severity = 'error' }

                $extraData = @{
                    CIMC = $serverName
                    StatusHealth = $sysHealth
                    PowerState = $powerState
                    MemorySummary = $memSummary
                    Certificate = $certSeverity
                }

                Send-ToApi -ApiUrl $apiUrl -SystemName $systemName -ProjectName 'CIMC' -Name $sysInfo.ServerResponse.Name -Metric 'SystemHealth' -Severity $severity -Status "Health: $sysHealth" -TTL $defaultTTL -ExtraData $extraData -DryRun:$DryRun
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

                        $extraData = @{
                            CIMC = $serverName
                            OperatingSpeedMHz = $pInfo.ServerResponse.OperatingSpeedMHz
                            TotalCores = $pInfo.ServerResponse.TotalCores
                            TotalEnabledCores = $pInfo.ServerResponse.TotalEnabledCores
                            TotalThreads = $pInfo.ServerResponse.TotalThreads
                            State = $pInfo.ServerResponse.Status.State
                            Health = $pHealth
                        }

                        Send-ToApi -ApiUrl $apiUrl -SystemName $systemName -ProjectName 'Processor' -Name $pInfo.ServerResponse.Name -Metric 'ProcessorHealth' -Severity $severity -Status "Health: $pHealth" -TTL $defaultTTL -ExtraData $extraData -DryRun:$DryRun
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
                        $sState = if ($sInfo.ServerResponse.StorageControllers) { $sInfo.ServerResponse.StorageControllers.Status.State } else { $sInfo.ServerResponse.Status.State }
                        
                        $severity = if ($sHealth -eq 'OK') { 'ok' } else { 'error' }
                        $scName = if ($sInfo.ServerResponse.StorageControllers) { $sInfo.ServerResponse.StorageControllers.MemberId } else { $sInfo.ServerResponse.Id }
                        
                        $extraDataSC = @{
                            CIMC = $serverName
                            State = $sState
                            Health = $sHealth
                        }
                        
                        $scDisplayName = if ($sInfo.ServerResponse.StorageControllers) { $sInfo.ServerResponse.StorageControllers.MemberId } else { $sInfo.ServerResponse.Id }
                        Send-ToApi -ApiUrl $apiUrl -SystemName $systemName -ProjectName 'StorageController' -Name $scDisplayName -Metric 'StorageHealth' -Severity $severity -Status "Health: $sHealth" -TTL $defaultTTL -ExtraData $extraDataSC -DryRun:$DryRun
                        
                        # Disks
                        foreach ($drive in $sInfo.ServerResponse.Drives) {
                            $dInfo = Invoke-RedfishGet -URLSuffix $drive.'@odata.id'
                            if (-not $dInfo.IsError) {
                                $dHealth = $dInfo.ServerResponse.Status.Health
                                $dState = $dInfo.ServerResponse.Status.State
                                $severity = if ($dHealth -eq 'OK') { 'ok' } else { 'error' }
                                
                                $predLife = if ($null -ne $dInfo.ServerResponse.PredictedMediaLifeLeftPercent) { $dInfo.ServerResponse.PredictedMediaLifeLeftPercent } else { 'N\A' }
                                if ($predLife -ne 'N\A') {
                                    if ($predLife -le 30) {
                                        $severity = 'error'
                                    } elseif ($predLife -le 50 -and $severity -eq 'ok') {
                                        $severity = 'warning'
                                    }
                                }

                                $extraDataDisk = @{
                                    CIMC = $serverName
                                    Manufacturer = $dInfo.ServerResponse.Manufacturer
                                    SerialNumber = $dInfo.ServerResponse.SerialNumber
                                    PredictedMediaLifeLeftPercent = $predLife
                                    State = $dState
                                    Health = $dHealth
                                }

                                Send-ToApi -ApiUrl $apiUrl -SystemName $systemName -ProjectName 'Disks' -Name $dInfo.ServerResponse.Name -Metric 'DiskHealth' -Severity $severity -Status "Health: $dHealth" -TTL $defaultTTL -ExtraData $extraDataDisk -DryRun:$DryRun
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
                            
                            $extraDataTemp = @{
                                CIMC = $serverName
                                Reading = $temp.ReadingCelsius
                                State = $temp.Status.State
                                Health = $tHealth
                            }
                            
                            Send-ToApi -ApiUrl $apiUrl -SystemName $systemName -ProjectName 'Temperature' -Name $temp.Name -Metric 'TempHealth' -Severity $severity -Status "$($temp.ReadingCelsius) C" -TTL $defaultTTL -ExtraData $extraDataTemp -DryRun:$DryRun
                        }
                        foreach ($fan in $thermal.ServerResponse.Fans | Where-Object { $_.Status.Health }) {
                            $fHealth = $fan.Status.Health
                            $severity = if ($fHealth -eq 'OK') { 'ok' } else { 'error' }
                            
                            $extraDataFan = @{
                                CIMC = $serverName
                                Reading = $fan.Reading
                                State = $fan.Status.State
                                Health = $fHealth
                            }

                            Send-ToApi -ApiUrl $apiUrl -SystemName $systemName -ProjectName 'Fans' -Name $fan.Name -Metric 'FanHealth' -Severity $severity -Status "$($fan.Reading) RPM" -TTL $defaultTTL -ExtraData $extraDataFan -DryRun:$DryRun
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
                            
                            $extraDataPower = @{
                                CIMC = $serverName
                                PowerInputWatts = $psu.PowerInputWatts
                                PowerOutputWatts = $psu.PowerOutputWatts
                                State = $psu.Status.State
                                Health = $pHealth
                            }

                            Send-ToApi -ApiUrl $apiUrl -SystemName $systemName -ProjectName 'PowerSupply' -Name $psu.Name -Metric 'PowerHealth' -Severity $severity -Status "$($psu.PowerInputWatts) W" -TTL $defaultTTL -ExtraData $extraDataPower -DryRun:$DryRun
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
