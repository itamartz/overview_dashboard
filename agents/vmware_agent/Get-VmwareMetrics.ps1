[CmdletBinding()]
param(
    [string]$ConfigPath = "config.json",
    [switch]$DryRun,
    [switch]$MockRun
)

# --- Common Functions ---
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

function Send-ToApi {
    param(
        [string]$ApiUrl,
        [string]$SystemName,
        [string]$ProjectName,
        [object]$Payload,
        [switch]$DryRun
    )

    $body = @{
        systemName  = $SystemName
        projectName = $ProjectName
        payload     = $Payload
    }

    $jsonBody = $body | ConvertTo-Json -Depth 10

    if ($DryRun) {
        Write-Host "[DRY-RUN] Would send to $ApiUrl" -ForegroundColor Cyan
        Write-Host "Project: $ProjectName | Component: $($Payload.Name) | Severity: $($Payload.Severity)" -ForegroundColor Gray
        return
    }

    try {
        Invoke-RestMethod -Uri $ApiUrl -Method Post -Body $jsonBody -ContentType "application/json" -TimeoutSec 15 | Out-Null
        Write-Host "Successfully posted $($Payload.Name) to $ProjectName" -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to post to API: $_"
    }
}

function Compare-Severity {
    param([String]$Current, [String]$New)
    $dicSeverity = @{ Info=0; Ok=1; Warning=2; Error=3 }
    return ($dicSeverity.GetEnumerator() | Where-Object {$_.Value -eq [math]::Max($dicSeverity[$New],$dicSeverity[$Current])}).Key
}

# --- VMware Helper Functions ---
function Connect-VCenter {
    param([String]$VCenter, [String]$UserName, [String]$Password)
    Set-PowerCLIConfiguration -Scope User -ParticipateInCEIP $false -WarningAction SilentlyContinue -DefaultVIServerMode Single -InvalidCertificateAction Ignore -Confirm:$false | Out-Null
    $VmwareCredential = [pscredential]::new($UserName, ($Password | ConvertTo-SecureString -AsPlainText -Force))
    Connect-VIServer $VCenter -Credential $VmwareCredential | Out-Null
}

function Disconnect-VCenter {
    if ($global:DefaultVIServer) {
        Disconnect-VIServer -Server $global:DefaultVIServer -Confirm:$false -Force
        $global:DefaultVIServer = $null
    }
}

function Get-X509Certificate2Web {
    param([String]$ComputerName, [String]$HttpsPort = '443')
    try {
        $tcpClinet = [System.Net.Sockets.TcpClient]::new($ComputerName, $HttpsPort)
        $sslStram  = [System.Net.Security.SslStream]::new($tcpClinet.GetStream(), $false, {param ($s,$c,$ch,$e)return $true})
        $sslStram.AuthenticateAsClient($ComputerName)
        $cert = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($sslStram.RemoteCertificate)
        $sslStram.Dispose()
        $tcpClinet.Dispose()
        Write-Output $cert
    } catch { }
}

function Get-TimeAgoString {
    param ([DateTime]$LastCommunication)
    $now = Get-Date
    $timespan = $now - $LastCommunication
    $parts = @()

    if ($timespan.Days -gt 0) {
        $s = if ($timespan.Days -ne 1) { "s" } else { "" }
        $parts += "$($timespan.Days) day$s"
    }
    if ($timespan.Hours -gt 0) {
        $s = if ($timespan.Hours -ne 1) { "s" } else { "" }
        $parts += "$($timespan.Hours) hour$s"
    }
    if ($timespan.Minutes -gt 0) {
        $s = if ($timespan.Minutes -ne 1) { "s" } else { "" }
        $parts += "$($timespan.Minutes) minute$s"
    }
    
    if ($parts.Count -eq 0) { return "just now" }
    return ($parts -join ' ') + " ago"
}

function Test-CertificateState {
    param([System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate)
    if (-not $Certificate) { return "Error" }
    $TimeSpan = New-TimeSpan -Start (Get-Date) -End $Certificate.NotAfter
    if ($TimeSpan.Days -le 30) { return "Error" }
    elseif ($TimeSpan.Days -le 60) { return "Warning" }
    else { return "Ok" }
}

function Get-ApplianceArchivePartitionSize {
    param([String]$VCenter, [String]$UserName, [String]$Password)
    $Base64 = [convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("$($UserName):$($Password)"))
    $Headers = @{ 'Authorization' = "Basic $($Base64)" }
    if (-not ([System.Management.Automation.PSTypeName]'TrustAllCertsPolicy').Type) {
        Add-Type @"
        using System.Net;
        using System.Security.Cryptography.X509Certificates;
        public class TrustAllCertsPolicy : ICertificatePolicy {
            public bool CheckValidationResult(ServicePoint srvPoint, X509Certificate certificate, WebRequest request, int certificateProblem) { return true; }
        }
"@
    }
    [System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

    try {
        $Response = Invoke-RestMethod -Uri "https://$VCenter/rest/com/vmware/cis/session" -Method Post -Headers $Headers
        $SessionHeaders = @{ 'vmware-api-session-id' = $Response.value; 'Content-type' = 'application/json' }
        $queryInterval = 'DAY1'; $queryFunction = 'MAX'
        $queryStartTime = ((Get-Date).AddDays(-1)).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss') + ".000Z"
        $queryEndTime = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss') + ".000Z"
        $querySpecs = "&interval=$queryInterval&function=$queryFunction&start_time=$queryStartTime&end_time=$queryEndTime"

        $used = (Invoke-RestMethod -Uri "https://$VCenter/api/appliance/monitoring/query?names=storage.used.filesystem.archive$querySpecs" -Method Get -Headers $SessionHeaders).data
        $totalsize = (Invoke-RestMethod -Uri "https://$VCenter/api/appliance/monitoring/query?names=storage.totalsize.filesystem.archive$querySpecs" -Method Get -Headers $SessionHeaders).data
        if ($totalsize -gt 0) { return [int](($used / $totalsize) * 100) }
    } catch { }
    return 100
}

function Get-VcenterApplianceLastBackupJobDays {
    param([String]$VCenter, [String]$UserName, [String]$Password)
    $Base64 = [convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("$($UserName):$($Password)"))
    $Headers = @{ 'Authorization' = "Basic $($Base64)" }
    try {
        $Response = Invoke-RestMethod -Uri "https://$VCenter/rest/com/vmware/cis/session" -Method Post -Headers $Headers
        $SessionHeaders = @{ 'vmware-api-session-id' = $Response.value; 'Content-type' = 'application/json' }
        $jobsId = Invoke-RestMethod -Uri "https://$VCenter/api/appliance/recovery/backup/job/" -Method Get -Headers $SessionHeaders
        $jobId = $jobsId | Sort-Object -Descending | Select-Object -First 1
        $Details = Invoke-RestMethod -Uri "https://$VCenter/api/appliance/recovery/backup/job/details?jobs=$jobId" -Method Get -Headers $SessionHeaders
        $datetime_end_time = [datetime]::MinValue
        if (($Details.$jobId.status.ToLower() -eq 'succeeded') -and [datetime]::TryParse($Details.$jobId.end_time, [ref]$datetime_end_time)) {
            return (New-TimeSpan -Start $datetime_end_time -End (Get-Date)).Days
        }
    } catch { }
    return 999
}

function Get-VcenterApplianceHealthEndpoint {
    param([String]$VCenter, [String]$UserName, [String]$Password)
    $Base64 = [convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("$($UserName):$($Password)"))
    $Headers = @{ 'Authorization' = "Basic $($Base64)" }
    try {
        $Response = Invoke-RestMethod -Uri "https://$VCenter/rest/com/vmware/cis/session" -Method Post -Headers $Headers
        $SessionHeaders = @{ 'vmware-api-session-id' = $Response.value; 'Content-type' = 'application/json' }
        $healthEndpoints = @(
            "api/appliance/health/system", "api/appliance/health/database-storage",
            "api/appliance/health/load", "api/appliance/health/mem",
            "api/appliance/health/storage", "api/appliance/health/swap"
        )
        $warnings = @(); $critical = @()
        foreach ($ep in $healthEndpoints) {
            $status = Invoke-RestMethod -Uri "https://$VCenter/$ep" -Method Get -Headers $SessionHeaders
            if ($status -eq "red") { $critical += $ep }
            elseif ($status -in @("yellow", "orange")) { $warnings += $ep }
        }
        if ($critical.Count -gt 0) { return 'Error' }
        if ($warnings.Count -gt 0) { return 'Warning' }
    } catch { return 'Error' }
    return 'Ok'
}

function Test-VcenterApplianceService {
    param([String]$VCenter, [String]$UserName, [String]$Password)
    $Base64 = [convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("$($UserName):$($Password)"))
    $Headers = @{ 'Authorization' = "Basic $($Base64)" }
    try {
        $Response = Invoke-RestMethod -Uri "https://$VCenter/rest/com/vmware/cis/session" -Method Post -Headers $Headers
        $SessionHeaders = @{ 'vmware-api-session-id' = $Response.value; 'Content-type' = 'application/json' }
        $services = Invoke-RestMethod -Uri "https://$VCenter/api/vcenter/services" -Method Get -Headers $SessionHeaders
        $critical = @()
        foreach ($serviceName in $services.psobject.Properties.Name) {
            if ($services.$serviceName.startup_type -eq 'startup_type' -and $services.$serviceName.health -ne 'HEALTHY') {
                $critical += $serviceName
            }
        }
        if ($critical.Count -gt 0) { return 'Error' }
    } catch { return 'Error' }
    return 'Ok'
}

function Test-LicenseManagerUsed {
    param([int]$Threshold)
    $Severity = 'Ok'
    $licMgr = Get-View LicenseManager
    foreach ($license in $licMgr.Licenses | Where-Object {$_.EditionKey -ne 'eval'}) {
        if ($license.Total -gt 0) {
            $Precent = (($license.Used / $license.Total) * 100) -as [int]
            if ($Precent -ge $Threshold) { $Severity = 'Error' }
        }
    }
    return $Severity
}

function Test-DatastoreUse {
    param([int]$Threshold)
    $Severity = 'Ok'
    $AllDatastore = Get-Datacenter | Get-Datastore
    foreach ($Datastore in $AllDatastore) {
        if ($Datastore.CapacityGB -gt 0) {
            $UsePercent = [math]::Floor(($Datastore.FreeSpaceGB / $Datastore.CapacityGB) * 100)
            if ($UsePercent -le $Threshold) { $Severity = 'Error' }
        }
    }
    return $Severity
}

function Get-VCenterAllIssues {
    param($DatacenterImpl)
    $dc = $DatacenterImpl | Where-Object {$_.ExtensionData.TriggeredAlarmState}
    $redIssues = ($dc.ExtensionData.TriggeredAlarmState | Where-Object {$_.OverallStatus -eq 'red'})
    if ($redIssues) { return 'Error' }
    return 'Ok'
}

function Get-ESXIVMnicStatus {
    param($VMHost)
    try {
        $EsxCli = Get-EsxCli -VMHost $VMHost -V2
        $Uplinks = @($EsxCli.network.vswitch.standard.list.Invoke().Uplinks)
        $Uplinks += @($EsxCli.network.vswitch.dvs.vmware.list.Invoke().Uplinks)
        $PhysicalAdapters = $EsxCli.network.nic.list.Invoke()
        foreach ($Uplink in $Uplinks) {
            $PhysicalAdapter = $PhysicalAdapters | Where-Object {$_.Name -eq $Uplink}
            if ($PhysicalAdapter.LinkStatus -eq 'Down') { return 'Error' }
        }
    } catch { return 'Error' }
    return 'Ok'
}

# --- Main Logic ---

if (-not (Test-Path $ConfigPath)) {
    $ConfigPath = Join-Path $PSScriptRoot $ConfigPath
    if (-not (Test-Path $ConfigPath)) {
        Write-Error "Config file not found at $ConfigPath"
        exit 1
    }
}

$config = Get-Content $ConfigPath | ConvertFrom-Json

Write-Host "====================================="
Write-Host "VMware Monitoring Agent v2.0"
Write-Host "====================================="

if ($MockRun) {
    Write-Host "[MOCK RUN] Generating mock data" -ForegroundColor Yellow
    $payload = @{
        Id = "vcenter-mock"
        Name = "VCENTER01 (Mock)"
        Severity = "ok"
        TTL = $config.defaultTTL
        Status = "All systems operational"
        LastBackup = "Ok"
        ArchivePartition = "Ok"
        Services = "Ok"
        HealthEndpoint = "Ok"
        LicenseUsed = "Ok"
        DatastoreUse = "Ok"
        CertificateState = "Ok"
    }
    Send-ToApi -ApiUrl $config.apiUrl -SystemName $config.systemName -ProjectName "vCenter" -Payload $payload -DryRun:$DryRun
    exit 0
}

foreach ($target in $config.targets) {
    if (-not $target.enabled) { continue }
    
    Write-Host "Processing Target: $($target.name)" -ForegroundColor Cyan
    
    $password = ""
    if ($config.credentialMethod -eq "cyberark") {
        $cred = Get-CyberArkCredential -CcpUrl $config.cyberark.ccpUrl -AppId $config.cyberark.appId -Safe $target.cyberarkSafe -ObjectName $target.cyberarkObject -VerifySsl $config.cyberark.verifySsl -TimeoutSeconds $config.cyberark.timeoutSeconds
        if ($cred.Success) {
            $password = $cred.Password
        } else {
            Write-Error "Failed to retrieve credential for $($target.name) from CyberArk"
            continue
        }
    } else {
        # Fallback or other methods
        $password = $target.password
    }

    try {
        Connect-VCenter -VCenter $target.host -UserName $target.username -Password $password
        
        $vCenterObj = @{
            Id = $target.name
            Name = $target.name
            TTL = $config.defaultTTL
        }

        # 1. Archive Partition
        $partSize = Get-ApplianceArchivePartitionSize -VCenter $target.host -UserName $target.username -Password $password
        $vCenterObj.ArchivePartition = if ($partSize -ge $target.archivePartition) { 'Error' } else { 'Ok' }

        # 2. Last Backup
        $jobDays = Get-VcenterApplianceLastBackupJobDays -VCenter $target.host -UserName $target.username -Password $password
        $vCenterObj.LastBackup = if ($jobDays -ge $target.backupsDays) { 'Error' } else { 'Ok' }

        # 3. Health Endpoint
        $vCenterObj.HealthEndpoint = Get-VcenterApplianceHealthEndpoint -VCenter $target.host -UserName $target.username -Password $password

        # 4. Services
        $vCenterObj.Services = Test-VcenterApplianceService -VCenter $target.host -UserName $target.username -Password $password

        # 5. Licenses
        $vCenterObj.LicenseUsed = Test-LicenseManagerUsed -Threshold $target.licensesThreshold

        # 6. Datastore
        $vCenterObj.DatastoreUse = Test-DatastoreUse -Threshold $target.datastoresThreshold

        # 7. Certificate
        $cert = Get-X509Certificate2Web -ComputerName $target.host
        $vCenterObj.CertificateState = Test-CertificateState -Certificate $cert

        # Aggregate Severity
        $aggSeverity = 'Info'
        foreach ($prop in @("LastBackup", "CertificateState", "ArchivePartition", "Services", "HealthEndpoint", "LicenseUsed", "DatastoreUse")) {
            $aggSeverity = Compare-Severity -Current $aggSeverity -New $vCenterObj.$prop
        }
        $vCenterObj.Severity = $aggSeverity.ToLower()
        
        Send-ToApi -ApiUrl $config.apiUrl -SystemName $config.systemName -ProjectName "vCenter" -Payload $vCenterObj -DryRun:$DryRun

        # --- Datacenters ---
        $datacenters = Get-Datacenter
        foreach ($dc in $datacenters) {
            $dcObj = @{
                Id = "$($target.name)-$($dc.Name)"
                Name = $dc.Name
                TTL = $config.defaultTTL
                Alarms = Get-VCenterAllIssues -DatacenterImpl $dc
            }
            $dcObj.Severity = $dcObj.Alarms.ToLower()
            Send-ToApi -ApiUrl $config.apiUrl -SystemName $config.systemName -ProjectName "Datacenter" -Payload $dcObj -DryRun:$DryRun
        }

        # --- ESXi Hosts ---
        $hosts = Get-VMHost
        foreach ($esxi in $hosts) {
            $esxiObj = @{
                Id = "$($target.name)-$($esxi.Name)"
                Name = $esxi.Name
                TTL = $config.defaultTTL
                ConnectionState = $esxi.ConnectionState.ToString()
            }
            
            $esxiCert = Get-X509Certificate2Web -ComputerName $esxi.Name
            $esxiObj.CertificateState = Test-CertificateState -Certificate $esxiCert
            $esxiObj.VMnicStatus = Get-ESXIVMnicStatus -VMHost $esxi

            $esxiSev = 'Ok'
            if ($esxiObj.CertificateState -ne 'Ok') { $esxiSev = Compare-Severity -Current $esxiSev -New $esxiObj.CertificateState }
            if ($esxiObj.ConnectionState -ne 'Connected') { $esxiSev = 'Error' }
            if ($esxiObj.VMnicStatus -ne 'Ok') { $esxiSev = 'Error' }
            
            $esxiObj.Severity = $esxiSev.ToLower()
            Send-ToApi -ApiUrl $config.apiUrl -SystemName $config.systemName -ProjectName "ESXI" -Payload $esxiObj -DryRun:$DryRun
        }

        # --- VMs ---
        $vms = Get-VM | Where-Object { $_.PowerState -eq 'PoweredOn' }
        foreach ($exc in $target.excludedVMsFromBackup) {
            $vms = $vms | Where-Object { -not $_.Name.Contains($exc) }
        }

        $now = Get-Date
        foreach ($vm in $vms) {
            $vmObj = @{
                Id = "$($target.name)-$($vm.Name)"
                Name = $vm.Name
                TTL = $config.defaultTTL
            }
            
            $AllTags = ($vm | Get-TagAssignment).Tag
            $AllTagsJoin = ($AllTags | ForEach-Object { "$($_.Name)/$($_.Category)" }) -join ','
            
            $ann = $vm | Get-Annotation | Where-Object { $_.Name -eq 'Backup Status' }
            $isBackedUp = $false
            $lastBackupWas = "N/A"
            if ($ann -and -not [string]::IsNullOrEmpty($ann.Value) -and ($ann.Value -match '([0-9/]+\s[0-9:]+)')) {
                $lastBackupTime = [datetime]::ParseExact($Matches[0], 'dd/MM/yyyy HH:mm:ss', [System.Globalization.CultureInfo]::InvariantCulture)
                $isBackedUp = $now.AddDays(-1) -le $lastBackupTime
                $lastBackupWas = Get-TimeAgoString -LastCommunication $lastBackupTime
            }
            
            $vmObj.AllTags = $AllTagsJoin
            $vmObj.ISBackupInLast24Hours = $isBackedUp
            $vmObj.LastBackupWas = $lastBackupWas
            $vmObj.Severity = if ($isBackedUp) { 'ok' } else { 'error' }
            Send-ToApi -ApiUrl $config.apiUrl -SystemName $config.systemName -ProjectName "VMs" -Payload $vmObj -DryRun:$DryRun
        }

        # --- Snapshots ---
        $allSnaps = Get-VM | Get-Snapshot
        $snapsByVm = $allSnaps | Group-Object -Property VM
        foreach ($group in $snapsByVm) {
            $vmName = $group.Name
            $snapCount = $group.Count
            $snapNames = ($group.Group | ForEach-Object { $_.Name }) -join ','
            $totalSizeGB = [math]::Round((($group.Group | Measure-Object -Property SizeGB -Sum).Sum), 2)
            
            $snapSev = 'ok'
            if ($totalSizeGB -gt 1000) {
                $snapSev = 'error'
            } elseif ($totalSizeGB -gt 300) {
                $snapSev = 'warning'
            }
            
            $snapObj = @{
                Id = "$($target.name)-$vmName-snapshots"
                Name = $vmName
                count = $snapCount
                snapshots = $snapNames
                totalsizegb = $totalSizeGB
                Severity = $snapSev
                TTL = $config.defaultTTL
            }
            Send-ToApi -ApiUrl $config.apiUrl -SystemName $config.systemName -ProjectName "Snapshots" -Payload $snapObj -DryRun:$DryRun
        }

    }
    catch {
        Write-Error "Error processing target $($target.name): $_"
    }
    finally {
        Disconnect-VCenter
    }
}
