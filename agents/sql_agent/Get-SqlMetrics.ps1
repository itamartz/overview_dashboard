<#
.SYNOPSIS
    Monitors local SQL Server databases and reports backup status to the Overview Dashboard.

.DESCRIPTION
    Uses dbatools to check database backup status and state for the local SQL Server instance,
    calculates severity based on backup age, and reports to the Overview Dashboard API.
    
    This agent is designed to run on the SQL Server host itself.

.PARAMETER ConfigPath
    Path to the config.json file. Default: $PSScriptRoot\config.json

.PARAMETER DryRun
    If specified, shows what would be reported without sending to API.

.PARAMETER MockRun
    If specified, generates sample data and sends to API without querying SQL.

.EXAMPLE
    .\Get-SqlMetrics.ps1

.EXAMPLE
    .\Get-SqlMetrics.ps1 -MockRun

.NOTES
    Requires: dbatools module (Install-Module -Name dbatools)
    Run on: The SQL Server host machine (localhost connection)
#>

[CmdletBinding()]
param(
    [string]$ConfigPath = "$PSScriptRoot\config.json",
    [switch]$DryRun,
    [switch]$MockRun
)

# Shared functions: Send-ToApi, Get-CyberArkCredential, Get-EncryptedCredential, Resolve-Credential, Install-ModuleIfNeeded
Import-Module (Join-Path $PSScriptRoot '..\shared\functions.psm1') -Force

#region Helper Functions

function Get-BackupSeverity {
    param(
        [datetime]$LastBackup,
        [int]$WarningHours,
        [int]$ErrorHours
    )
    
    $hoursSinceBackup = ((Get-Date) - $LastBackup).TotalHours
    
    if ($hoursSinceBackup -ge $ErrorHours) {
        return "error"
    }
    elseif ($hoursSinceBackup -ge $WarningHours) {
        return "warning"
    }
    else {
        return "ok"
    }
}

function Get-StateSeverity {
    param([string]$State)
    
    switch ($State.ToUpper()) {
        'ONLINE' { return "ok" }
        'RESTORING' { return "warning" }
        'RECOVERING' { return "warning" }
        'RECOVERY_PENDING' { return "warning" }
        'SUSPECT' { return "error" }
        'EMERGENCY' { return "error" }
        'OFFLINE' { return "error" }
        default { return "warning" }
    }
}

function Format-BackupAge {
    param([datetime]$LastBackup)
    
    $timeSpan = (Get-Date) - $LastBackup
    
    if ($timeSpan.TotalDays -ge 1) {
        return "$([math]::Floor($timeSpan.TotalDays))d $($timeSpan.Hours)h ago"
    }
    elseif ($timeSpan.TotalHours -ge 1) {
        return "$([math]::Floor($timeSpan.TotalHours))h $($timeSpan.Minutes)m ago"
    }
    else {
        return "$([math]::Floor($timeSpan.TotalMinutes))m ago"
    }
}

function Get-MockDatabases {
    $dbNames = @("AppDB", "ReportingDB", "UserData", "Inventory", "CRM", "LegacyDB")
    $states = @("ONLINE", "ONLINE", "ONLINE", "ONLINE", "RESTORING", "SUSPECT")
    $results = @()
    
    foreach ($i in 0..($dbNames.Count - 1)) {
        $hoursAgo = Get-Random -Minimum 1 -Maximum 72
        $lastBackup = (Get-Date).AddHours(-$hoursAgo)
        
        $results += [PSCustomObject]@{
            Name           = $dbNames[$i]
            State          = $states[$i]
            LastFullBackup = $lastBackup
        }
    }
    
    return $results
}

#endregion

#region Main Script

# Check config file exists
if (-not (Test-Path $ConfigPath)) {
    Write-Error "Config file not found at $ConfigPath"
    exit 1
}

# Read configuration
try {
    $config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
}
catch {
    Write-Error "Failed to parse config file: $_"
    exit 1
}

# Extract settings
$apiUrl = $config.apiUrl
$projectName = $config.projectName
$systemName = $config.systemName
$defaultTTL = if ($config.defaultTTL) { $config.defaultTTL } else { 300 }
$backupWarningHours = if ($config.backupWarningHours) { $config.backupWarningHours } else { 24 }
$backupErrorHours = if ($config.backupErrorHours) { $config.backupErrorHours } else { 48 }
$serverName = if ($config.serverName) { $config.serverName } else { $env:COMPUTERNAME }
$instance = if ($config.instance) { $config.instance } else { "localhost" }
$filterDatabases = $config.databases
$credentialMethod = if ($config.credentialMethod) { $config.credentialMethod } else { "plaintext" }
$useSqlAuth = if ($config.sqlAuthentication) { $config.sqlAuthentication } else { $false }

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "SQL Metrics Agent (Local)" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Server:  $serverName"
Write-Host "Instance: $instance"
Write-Host "API URL: $apiUrl"
Write-Host "Backup Warning: ${backupWarningHours}h | Error: ${backupErrorHours}h"
if ($useSqlAuth) {
    Write-Host "Auth:     SQL Authentication ($credentialMethod)"
} else {
    Write-Host "Auth:     Windows Integrated"
}
Write-Host ""

if ($DryRun) {
    Write-Host "[DRY RUN MODE - No API calls will be made]" -ForegroundColor Yellow
    Write-Host ""
}

if ($MockRun) {
    Write-Host "[MOCK RUN MODE - Sending sample data to API]" -ForegroundColor Magenta
    Write-Host ""
}

# Install/Import dbatools if not in dry run or mock run mode
if (-not $DryRun -and -not $MockRun) {
    if (-not (Install-ModuleIfNeeded -ModuleName dbatools)) {
        exit 1
    }
}

$databases = $null

if ($MockRun) {
    Write-Host "Generating sample database data..." -ForegroundColor Magenta
    $databases = Get-MockDatabases
}
elseif ($DryRun) {
    Write-Host "[DRY RUN] Would query databases from $instance"
    Write-Host "[DRY RUN] Using simulated databases for dry-run output"
    $databases = Get-MockDatabases
}
else {
    # Query local SQL Server
    try {
        Write-Host "Querying local databases..." -ForegroundColor Gray
        
        # Get database info (exclude system databases: master, msdb, model, tempdb)
        # Build connection parameters
        $dbaParams = @{
            SqlInstance  = $instance
            ExcludeSystem = $true
            ErrorAction  = 'Stop'
        }
        $dbaHistoryParams = @{
            SqlInstance = $instance
            Last        = $true
            ErrorAction = 'SilentlyContinue'
        }

        # Add SQL Authentication credentials if configured
        if ($useSqlAuth) {
            $resolvedCred = Resolve-Credential -Method $credentialMethod -Config $config -CyberArkConfig $config.cyberark
            if (-not $resolvedCred.Success) {
                Write-Host "[FAILED] Could not retrieve SQL credentials" -ForegroundColor Red
                $sent = Send-ToApi -ApiUrl $apiUrl -SystemName $systemName -ProjectName $projectName `
                    -Name $serverName -Database "N/A" -Metric "Connection" -Severity "error" -Status "Credential retrieval failed" -TTL $defaultTTL
                exit 1
            }
            $securePassword = ConvertTo-SecureString $resolvedCred.Password -AsPlainText -Force
            $sqlCredential = New-Object System.Management.Automation.PSCredential($resolvedCred.Username, $securePassword)
            $dbaParams.SqlCredential = $sqlCredential
            $dbaHistoryParams.SqlCredential = $sqlCredential
        }

        $dbInfo = Get-DbaDatabase @dbaParams
        
        # Get backup history
        $backupHistory = Get-DbaDbBackupHistory @dbaHistoryParams
        
        # Build database list
        $databases = foreach ($db in $dbInfo) {
            $lastFull = ($backupHistory | Where-Object { $_.Database -eq $db.Name -and $_.Type -eq 'Full' } | 
                Sort-Object -Property End -Descending | Select-Object -First 1).End
            
            [PSCustomObject]@{
                Name           = $db.Name
                State          = $db.Status
                LastFullBackup = $lastFull
            }
        }
        
        Write-Host "[OK] Found $($databases.Count) databases" -ForegroundColor Green
    }
    catch {
        Write-Host "[FAILED] Could not connect to $instance`: $_" -ForegroundColor Red
        
        # Report connection failure
        $sent = Send-ToApi -ApiUrl $apiUrl -SystemName $systemName -ProjectName $projectName `
            -Name $serverName -Database "N/A" -Metric "Connection" -Severity "error" -Status "Connection failed" -TTL $defaultTTL
        exit 1
    }
}

# Filter databases if specified
if ($filterDatabases -and $filterDatabases.Count -gt 0) {
    $databases = $databases | Where-Object { $filterDatabases -contains $_.Name }
}

Write-Host ""

# Process each database
foreach ($db in $databases) {
    $dbName = $db.Name
    $dbState = $db.State
    
    # Report Database State
    $stateSeverity = Get-StateSeverity -State $dbState
    $stateColor = switch ($stateSeverity) {
        'ok' { 'Green' }
        'warning' { 'Yellow' }
        'error' { 'Red' }
        default { 'White' }
    }
    
    Write-Host "DB: $dbName" -ForegroundColor White
    Write-Host "  State: $dbState -> $stateSeverity" -ForegroundColor $stateColor
    
    if (-not $DryRun) {
        $sent = Send-ToApi -ApiUrl $apiUrl -SystemName $systemName -ProjectName $projectName `
            -Name $serverName -Database $dbName -Metric "State" -Severity $stateSeverity -Status $dbState -TTL $defaultTTL
        if ($sent) {
            Write-Host "    -> Reported" -ForegroundColor Gray
        }
    }
    
    # Report Last Backup
    if ($db.LastFullBackup) {
        $backupSeverity = Get-BackupSeverity -LastBackup $db.LastFullBackup `
            -WarningHours $backupWarningHours -ErrorHours $backupErrorHours
        $backupAge = Format-BackupAge -LastBackup $db.LastFullBackup
        
        $backupColor = switch ($backupSeverity) {
            'ok' { 'Green' }
            'warning' { 'Yellow' }
            'error' { 'Red' }
            default { 'White' }
        }
        
        Write-Host "  Backup: $backupAge -> $backupSeverity" -ForegroundColor $backupColor
        
        if (-not $DryRun) {
            $sent = Send-ToApi -ApiUrl $apiUrl -SystemName $systemName -ProjectName $projectName `
                -Name $serverName -Database $dbName -Metric "Last Backup" -Severity $backupSeverity -Status $backupAge -TTL $defaultTTL
            if ($sent) {
                Write-Host "    -> Reported" -ForegroundColor Gray
            }
        }
    }
    else {
        Write-Host "  Backup: No backup found -> error" -ForegroundColor Red
        
        if (-not $DryRun) {
            $sent = Send-ToApi -ApiUrl $apiUrl -SystemName $systemName -ProjectName $projectName `
                -Name $serverName -Database $dbName -Metric "Last Backup" -Severity "error" -Status "No backup" -TTL $defaultTTL
            if ($sent) {
                Write-Host "    -> Reported" -ForegroundColor Gray
            }
        }
    }
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Completed." -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

#endregion
