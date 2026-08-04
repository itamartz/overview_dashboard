<#
.SYNOPSIS
    Monitors Veeam Backup & Replication 11 jobs using the Veeam.Backup.PowerShell module
    and reports their status to the Overview Dashboard.

.DESCRIPTION
    Connects to a Veeam Backup Server with Connect-VBRServer, enumerates jobs with Get-VBRJob,
    reads each job's last session, calculates a severity and posts one component per job to
    the Overview Dashboard API.

    This is the module-based alternative to the REST/Enterprise Manager agent. Use this
    version when the Veeam Backup & Replication console is installed on the machine running
    the agent; use the REST version when it is not.

    The backup server name and port are configurable in config.json (veeam.server /
    veeam.port) - the default console port is 9392.

.PARAMETER ConfigPath
    Path to the config.json file. Default: $PSScriptRoot\config.json

.PARAMETER DryRun
    Shows the configuration and what would be checked. No connection to Veeam is made and
    nothing is posted to the dashboard API.

.PARAMETER MockRun
    Generates realistic sample job data and posts it to the dashboard API without
    connecting to Veeam.

.EXAMPLE
    .\Get-VeeamMetrics.ps1
    Runs a live collection using config.json.

.EXAMPLE
    .\Get-VeeamMetrics.ps1 -DryRun
    Prints the configuration and exits without connecting or posting.

.EXAMPLE
    .\Get-VeeamMetrics.ps1 -MockRun
    Posts sample job data to the dashboard for UI preview.

.NOTES
    Requires : PowerShell 5.1 and the Veeam Backup & Replication 11 console installed
               locally (this is what provides the Veeam.Backup.PowerShell module - it is
               NOT available from the PowerShell Gallery).
               Also requires agents\shared\functions.psm1 next to this agent.
    Author   : Overview Dashboard agent guide - Pattern A (self contained)
#>

[CmdletBinding()]
param(
    [string]$ConfigPath = "$PSScriptRoot\config.json",
    [switch]$DryRun,
    [switch]$MockRun
)

# Shared functions: Send-ToApi, Get-CyberArkCredential, Get-EncryptedCredential,
# Resolve-Credential, Get-X509Certificate2Web, Install-ModuleIfNeeded
Import-Module (Join-Path $PSScriptRoot '..\shared\functions.psm1') -Force

#region Helper Functions

function Write-AgentLine {
    <#
    .SYNOPSIS
        Writes a colour-coded line to the console.

    .DESCRIPTION
        Console output helper for this agent. Deliberately NOT named Write-Log, because
        that name conflicts with the VMware PowerCLI module.

    .PARAMETER Message
        Text to display.

    .PARAMETER Severity
        One of ok, warning, error or info. Controls the console colour
        (Green / Yellow / Red / Gray).

    .EXAMPLE
        Write-AgentLine -Message "Daily-SQL succeeded" -Severity ok

    .OUTPUTS
        None. Writes to the host.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [ValidateSet('ok', 'warning', 'error', 'info')]
        [string]$Severity = 'info'
    )

    $color = switch ($Severity) {
        'ok'      { 'Green' }
        'warning' { 'Yellow' }
        'error'   { 'Red' }
        default   { 'Gray' }
    }

    Write-Host $Message -ForegroundColor $color
}

function Import-VeeamModule {
    <#
    .SYNOPSIS
        Loads the Veeam PowerShell module or snap-in.

    .DESCRIPTION
        Veeam Backup & Replication 11 ships the Veeam.Backup.PowerShell module with the
        console. Version 9.5 and 10 used the VeeamPSSnapIn snap-in instead, so both are
        attempted. Neither can be installed from the PowerShell Gallery - the console must
        be installed on this machine.

        The module writes a deprecation notice to the warning stream on import, which is
        suppressed here to keep the agent output readable.

    .EXAMPLE
        if (-not (Import-VeeamModule)) { exit 1 }

    .OUTPUTS
        System.Boolean. $true when a Veeam module or snap-in was loaded.
    #>
    [CmdletBinding()]
    param()

    if (Get-Command -Name 'Get-VBRJob' -ErrorAction SilentlyContinue) {
        return $true
    }

    if (Get-Module -ListAvailable -Name 'Veeam.Backup.PowerShell') {
        try {
            Import-Module -Name 'Veeam.Backup.PowerShell' -DisableNameChecking `
                -WarningAction SilentlyContinue -ErrorAction Stop
            return $true
        }
        catch {
            Write-AgentLine -Message "Failed to import Veeam.Backup.PowerShell: $_" -Severity error
            return $false
        }
    }

    # Fall back to the pre-v11 snap-in
    if (Get-PSSnapin -Registered -Name 'VeeamPSSnapIn' -ErrorAction SilentlyContinue) {
        try {
            Add-PSSnapin -Name 'VeeamPSSnapIn' -ErrorAction Stop
            return $true
        }
        catch {
            Write-AgentLine -Message "Failed to add VeeamPSSnapIn: $_" -Severity error
            return $false
        }
    }

    Write-AgentLine -Message 'Veeam PowerShell module not found. Install the Veeam Backup & Replication console on this machine.' -Severity error
    return $false
}

function Connect-VeeamBackupServer {
    <#
    .SYNOPSIS
        Opens a connection to a Veeam Backup Server.

    .DESCRIPTION
        Wraps Connect-VBRServer. When no credential is supplied the connection uses the
        Windows identity running the agent, which is the usual setup when the agent runs
        on the backup server itself under a service account.

    .PARAMETER Server
        Hostname, FQDN or IP address of the Veeam Backup Server. Use 'localhost' when the
        agent runs on the backup server.

    .PARAMETER Port
        Console service port. Default 9392.

    .PARAMETER Credential
        Optional PSCredential. Omit to connect with the current Windows account.

    .EXAMPLE
        $result = Connect-VeeamBackupServer -Server 'localhost' -Port 9392

    .EXAMPLE
        $result = Connect-VeeamBackupServer -Server 'vbr01' -Port 9392 -Credential $cred

    .OUTPUTS
        Hashtable with keys Success and Error.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Server,

        [int]$Port = 9392,

        [System.Management.Automation.PSCredential]$Credential
    )

    $result = @{ Success = $false; Error = '' }

    try {
        $params = @{
            Server      = $Server
            Port        = $Port
            ErrorAction = 'Stop'
        }
        if ($Credential) { $params.Credential = $Credential }

        Connect-VBRServer @params
        $result.Success = $true
    }
    catch {
        $result.Error = $_.Exception.Message
    }

    return $result
}

function Get-VeeamJobSeverity {
    <#
    .SYNOPSIS
        Maps a Veeam job result to a dashboard severity and status string.

    .DESCRIPTION
        Applies these rules, in order:
          running job                  -> info
          Failed                       -> error
          Warning                      -> warning
          never ran / no session        -> warning
          Success older than stale
          error threshold              -> error
          Success older than stale
          warning threshold            -> warning
          Success and fresh            -> ok

        The staleness override matters because Veeam keeps reporting the last result as
        Success even when the job has not run for days.

    .PARAMETER Result
        Last result: Success, Warning, Failed or None.

    .PARAMETER State
        Last state: Stopped, Working, Starting, Idle, Postprocessing, etc.

    .PARAMETER HoursSinceLastRun
        Age of the last completed run in hours. Pass $null when the job never ran.

    .PARAMETER StaleWarningHours
        Age at which a successful job becomes a warning.

    .PARAMETER StaleErrorHours
        Age at which a successful job becomes an error.

    .EXAMPLE
        Get-VeeamJobSeverity -Result 'Success' -State 'Stopped' -HoursSinceLastRun 30 `
            -StaleWarningHours 26 -StaleErrorHours 48

    .OUTPUTS
        Hashtable with keys Severity and Status.
    #>
    [CmdletBinding()]
    param(
        [string]$Result,

        [string]$State,

        $HoursSinceLastRun,

        [int]$StaleWarningHours = 26,

        [int]$StaleErrorHours = 48
    )

    if ($State -in @('Working', 'Starting', 'Postprocessing', 'WaitingRepository', 'WaitingTape', 'Resuming', 'Pausing')) {
        return @{ Severity = 'info'; Status = "Running ($State)" }
    }

    switch ($Result) {
        'Failed'  { return @{ Severity = 'error';   Status = 'Last run failed' } }
        'Warning' { return @{ Severity = 'warning'; Status = 'Last run finished with warnings' } }
    }

    if ($null -eq $HoursSinceLastRun) {
        return @{ Severity = 'warning'; Status = 'No session history found' }
    }

    $ageText = '{0:N1}h ago' -f $HoursSinceLastRun

    if ($Result -ne 'Success') {
        return @{ Severity = 'warning'; Status = "Unknown result '$Result' ($ageText)" }
    }

    if ($HoursSinceLastRun -ge $StaleErrorHours) {
        return @{ Severity = 'error';   Status = "Success but stale - last run $ageText" }
    }
    if ($HoursSinceLastRun -ge $StaleWarningHours) {
        return @{ Severity = 'warning'; Status = "Success but ageing - last run $ageText" }
    }

    return @{ Severity = 'ok'; Status = "Success ($ageText)" }
}

function Get-VeeamJobStatus {
    <#
    .SYNOPSIS
        Collects job status from the connected Veeam Backup Server.

    .DESCRIPTION
        Enumerates jobs with Get-VBRJob and reads the last session for each one via
        FindLastSession(). When that method is unavailable for a given job type, the
        job's own GetLastResult() and GetLastState() methods are used instead and the
        run timestamp is taken from LatestRunLocal.

        A job with no session history is still returned so that a job which has never run
        is visible on the dashboard rather than silently missing.

    .EXAMPLE
        $jobs = Get-VeeamJobStatus

    .OUTPUTS
        Array of PSCustomObject with JobName, JobType, ScheduleEnabled, Result, State,
        LastRun, DurationMinutes and HoursSinceLastRun.
    #>
    [CmdletBinding()]
    param()

    $now    = Get-Date
    $output = @()

    $jobs = @(Get-VBRJob -WarningAction SilentlyContinue | Sort-Object Name)

    foreach ($job in $jobs) {

        $result  = 'None'
        $state   = 'Unknown'
        $started = $null
        $ended   = $null

        $session = $null
        try { $session = $job.FindLastSession() } catch { $session = $null }

        if ($session) {
            $result  = [string]$session.Result
            $state   = [string]$session.State
            $started = $session.CreationTime
            $ended   = $session.EndTime
        }
        else {
            try { $result = [string]$job.GetLastResult() } catch { }
            try { $state  = [string]$job.GetLastState()  } catch { }
            try { $ended  = $job.LatestRunLocal          } catch { }
        }

        # Veeam returns 1/1/1900 for "never" rather than null
        if ($ended   -is [datetime] -and $ended.Year   -lt 1990) { $ended   = $null }
        if ($started -is [datetime] -and $started.Year -lt 1990) { $started = $null }

        $duration = $null
        if ($started -and $ended -and $ended -gt $started) {
            $duration = [math]::Round(($ended - $started).TotalMinutes, 1)
        }

        $reference  = if ($ended) { $ended } else { $started }
        $hoursSince = $null
        if ($reference) {
            $hoursSince = [math]::Round(($now - $reference).TotalHours, 2)
        }

        $scheduleEnabled = $true
        try { $scheduleEnabled = [bool]$job.IsScheduleEnabled() } catch { }

        $output += [pscustomobject]@{
            JobName           = $job.Name
            JobType           = [string]$job.JobType
            ScheduleEnabled   = $scheduleEnabled
            Result            = $result
            State             = $state
            LastRun           = $reference
            DurationMinutes   = $duration
            HoursSinceLastRun = $hoursSince
        }
    }

    return $output
}

function Get-VeeamMockJobStatus {
    <#
    .SYNOPSIS
        Produces sample job data for MockRun mode.

    .DESCRIPTION
        Returns a fixed set of jobs covering every severity path - success, warning, failure,
        currently running, stale success and never run - so dashboard rendering can be
        verified without a Veeam server.

    .EXAMPLE
        Get-VeeamMockJobStatus

    .OUTPUTS
        Array of PSCustomObject shaped exactly like Get-VeeamJobStatus output.
    #>
    [CmdletBinding()]
    param()

    $now = Get-Date

    return @(
        [pscustomobject]@{ JobName='Daily-SQL-Backup';    JobType='Backup';     ScheduleEnabled=$true;  Result='Success'; State='Stopped'; LastRun=$now.AddHours(-6);   DurationMinutes=42.5;  HoursSinceLastRun=6 }
        [pscustomobject]@{ JobName='Daily-FileServers';   JobType='Backup';     ScheduleEnabled=$true;  Result='Warning'; State='Stopped'; LastRun=$now.AddHours(-9);   DurationMinutes=88.0;  HoursSinceLastRun=9 }
        [pscustomobject]@{ JobName='Weekly-Archive-Copy'; JobType='BackupSync'; ScheduleEnabled=$true;  Result='Failed';  State='Stopped'; LastRun=$now.AddHours(-14);  DurationMinutes=12.3;  HoursSinceLastRun=14 }
        [pscustomobject]@{ JobName='Replica-DR-Site';     JobType='Replica';    ScheduleEnabled=$true;  Result='None';    State='Working'; LastRun=$now.AddMinutes(-25);DurationMinutes=$null; HoursSinceLastRun=0.4 }
        [pscustomobject]@{ JobName='Monthly-Legal-Hold';  JobType='Backup';     ScheduleEnabled=$true;  Result='Success'; State='Stopped'; LastRun=$now.AddHours(-72);  DurationMinutes=210.0; HoursSinceLastRun=72 }
        [pscustomobject]@{ JobName='Decommissioned-App';  JobType='Backup';     ScheduleEnabled=$false; Result='None';    State='Unknown'; LastRun=$null;               DurationMinutes=$null; HoursSinceLastRun=$null }
    )
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

$apiUrl      = $config.apiUrl
$projectName = $config.projectName
$systemName  = $config.systemName
$defaultTTL  = if ($config.defaultTTL) { $config.defaultTTL } else { 1200 }

$veeam                 = $config.veeam
$veeamServer           = $veeam.server
$veeamPort             = if ($veeam.port) { [int]$veeam.port } else { 9392 }
$useCurrentCredentials = [bool]$veeam.useCurrentCredentials

$staleWarningHours   = if ($config.staleWarningHours) { [int]$config.staleWarningHours } else { 26 }
$staleErrorHours     = if ($config.staleErrorHours)   { [int]$config.staleErrorHours }   else { 48 }
$includeDisabledJobs = [bool]$config.includeDisabledJobs
$jobNameFilter       = @($config.jobNameFilter)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Veeam Backup Jobs Agent (PS module)"      -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "API URL   : $apiUrl"
Write-Host "Project   : $projectName"
Write-Host "System    : $systemName"
Write-Host "VBR Server: ${veeamServer}:${veeamPort}"
Write-Host "Auth      : $(if ($useCurrentCredentials) { 'Current Windows account' } else { "Explicit ($($config.credentialMethod))" })"
Write-Host "TTL       : $defaultTTL s"
Write-Host "Stale     : warning >= ${staleWarningHours}h, error >= ${staleErrorHours}h"
Write-Host ""

if ($DryRun)  { Write-Host "[DRY RUN MODE - No connections or API calls]" -ForegroundColor Yellow }
if ($MockRun) { Write-Host "[MOCK RUN MODE - Sending sample data to API]" -ForegroundColor Magenta }

if ($DryRun) {
    Write-Host ""
    Write-Host "[DRY RUN] Would import Veeam.Backup.PowerShell"
    Write-Host "[DRY RUN] Would run Connect-VBRServer -Server $veeamServer -Port $veeamPort"
    Write-Host "[DRY RUN] Would enumerate jobs with Get-VBRJob and read each last session"
    Write-Host "[DRY RUN] Would post one component per job to $apiUrl"
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Completed (dry run)."                     -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    exit 0
}

$jobStatuses = @()
$connected   = $false

if ($MockRun) {
    $jobStatuses = Get-VeeamMockJobStatus
}
else {
    if (-not (Import-VeeamModule)) {
        Send-ToApi -ApiUrl $apiUrl -SystemName $systemName -ProjectName $projectName `
            -Name $veeamServer -Metric 'Backup Server' -Severity 'error' `
            -Status 'Veeam PowerShell module not available' -TTL $defaultTTL
        exit 1
    }

    $credential = $null

    if (-not $useCurrentCredentials) {
        $credMethod = if ($config.credentialMethod) { $config.credentialMethod } else { 'plaintext' }
        $cred       = Resolve-Credential -Method $credMethod -Target $veeam -CyberArkConfig $config.cyberark

        if (-not $cred.Success) {
            Write-AgentLine -Message "Failed to resolve credentials for $veeamServer" -Severity error
            Send-ToApi -ApiUrl $apiUrl -SystemName $systemName -ProjectName $projectName `
                -Name $veeamServer -Metric 'Backup Server' -Severity 'error' `
                -Status 'Failed to retrieve credentials' -TTL $defaultTTL
            exit 1
        }

        $securePassword = ConvertTo-SecureString $cred.Password -AsPlainText -Force
        $credential     = New-Object System.Management.Automation.PSCredential($cred.Username, $securePassword)
    }

    $connection = Connect-VeeamBackupServer -Server $veeamServer -Port $veeamPort -Credential $credential

    if (-not $connection.Success) {
        Write-AgentLine -Message "Connect-VBRServer failed: $($connection.Error)" -Severity error
        Send-ToApi -ApiUrl $apiUrl -SystemName $systemName -ProjectName $projectName `
            -Name $veeamServer -Metric 'Backup Server' -Severity 'error' `
            -Status "Connection failed: $($connection.Error)" -TTL $defaultTTL
        exit 1
    }

    $connected = $true

    try {
        $jobStatuses = Get-VeeamJobStatus

        Send-ToApi -ApiUrl $apiUrl -SystemName $systemName -ProjectName $projectName `
            -Name $veeamServer -Metric 'Backup Server' -Severity 'ok' `
            -Status "Connected - $($jobStatuses.Count) jobs" -TTL $defaultTTL
    }
    catch {
        Write-AgentLine -Message "Failed to collect job data: $_" -Severity error
        Send-ToApi -ApiUrl $apiUrl -SystemName $systemName -ProjectName $projectName `
            -Name $veeamServer -Metric 'Backup Server' -Severity 'error' `
            -Status "Collection failed: $($_.Exception.Message)" -TTL $defaultTTL

        Disconnect-VBRServer -ErrorAction SilentlyContinue
        exit 1
    }
}

# --- Filter, evaluate and report ---
$reported = 0

foreach ($job in $jobStatuses) {

    if (-not $includeDisabledJobs -and -not $job.ScheduleEnabled) {
        Write-AgentLine -Message "  Skipping disabled job: $($job.JobName)" -Severity info
        continue
    }

    if ($jobNameFilter.Count -gt 0) {
        $match = $false
        foreach ($pattern in $jobNameFilter) {
            if ($job.JobName -like $pattern) { $match = $true; break }
        }
        if (-not $match) { continue }
    }

    $eval = Get-VeeamJobSeverity -Result $job.Result -State $job.State `
                -HoursSinceLastRun $job.HoursSinceLastRun `
                -StaleWarningHours $staleWarningHours -StaleErrorHours $staleErrorHours

    $extra = @{
        JobType         = $job.JobType
        Result          = $job.Result
        State           = $job.State
        LastRun         = if ($job.LastRun) { $job.LastRun.ToString('yyyy-MM-dd HH:mm') } else { 'Never' }
        DurationMinutes = $job.DurationMinutes
        ScheduleEnabled = $job.ScheduleEnabled
        Server          = $veeamServer
    }

    Send-ToApi -ApiUrl $apiUrl -SystemName $systemName -ProjectName $projectName `
        -Name $job.JobName -Metric 'Backup Job' -Severity $eval.Severity `
        -Status $eval.Status -TTL $defaultTTL -ExtraData $extra

    Write-AgentLine -Message ("  {0,-32} {1,-8} {2}" -f $job.JobName, $eval.Severity.ToUpper(), $eval.Status) `
        -Severity $eval.Severity

    $reported++
}

if ($connected) {
    Disconnect-VBRServer -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Completed. $reported job(s) reported."    -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

#endregion
