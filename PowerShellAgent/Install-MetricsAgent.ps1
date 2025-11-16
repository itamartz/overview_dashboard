<#
.SYNOPSIS
    Creates a Windows Scheduled Task to run the dashboard metrics agent

.DESCRIPTION
    This script creates a scheduled task that runs the Dashboard Metrics agent
    every specified interval to collect and send system metrics.

.PARAMETER ApiUrl
    The Dashboard API server URL

.PARAMETER ComponentId
    The component ID for this server

.PARAMETER IntervalMinutes
    How often to run the agent (in minutes). Default: 5

.PARAMETER TaskName
    Name for the scheduled task. Default: DashboardMetricsAgent

.EXAMPLE
    .\Install-MetricsAgent.ps1 -ApiUrl "http://dashboard-server:5000" -ComponentId "COMP001"

.NOTES
    Must be run as Administrator
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ApiUrl,
    
    [Parameter(Mandatory = $true)]
    [string]$ComponentId,
    
    [Parameter(Mandatory = $false)]
    [int]$IntervalMinutes = 5,
    
    [Parameter(Mandatory = $false)]
    [string]$TaskName = "DashboardMetricsAgent"
)

# Check if running as Administrator
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Error "This script must be run as Administrator"
    exit 1
}

Write-Host "Installing Dashboard Metrics Agent..." -ForegroundColor Cyan
Write-Host "API URL: $ApiUrl" -ForegroundColor Yellow
Write-Host "Component ID: $ComponentId" -ForegroundColor Yellow
Write-Host "Interval: Every $IntervalMinutes minutes" -ForegroundColor Yellow

# Get script directory
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path

# Create the PowerShell command to run
$psCommand = @"
Import-Module '$scriptPath\DashboardMetrics.psm1' -Force
Send-DashboardMetric -ApiUrl '$ApiUrl' -ComponentId '$ComponentId' -ErrorAction Continue
"@

# Save command to a script file
$taskScriptPath = Join-Path $scriptPath "Run-MetricsAgent.ps1"
$psCommand | Out-File -FilePath $taskScriptPath -Encoding ASCII -Force

Write-Host "`nCreated agent script: $taskScriptPath" -ForegroundColor Green

# Create scheduled task action
$action = New-ScheduledTaskAction -Execute "PowerShell.exe" `
    -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$taskScriptPath`""

# Create trigger (repeat every X minutes)
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes $IntervalMinutes)

# Create task settings
$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -RunOnlyIfNetworkAvailable `
    -MultipleInstances IgnoreNew

# Create principal (run as SYSTEM)
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

# Check if task already exists
$existingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue

if ($existingTask) {
    Write-Host "`nScheduled task '$TaskName' already exists. Removing..." -ForegroundColor Yellow
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
}

# Register the scheduled task
try {
    Register-ScheduledTask `
        -TaskName $TaskName `
        -Action $action `
        -Trigger $trigger `
        -Settings $settings `
        -Principal $principal `
        -Description "Collects system metrics and sends to Dashboard API every $IntervalMinutes minutes" `
        -ErrorAction Stop
    
    Write-Host "`n✓ Scheduled task '$TaskName' created successfully!" -ForegroundColor Green
    Write-Host "`nThe agent will run every $IntervalMinutes minutes starting now." -ForegroundColor Cyan
    
    # Run the task immediately for testing
    Write-Host "`nRunning task immediately for testing..." -ForegroundColor Yellow
    Start-ScheduledTask -TaskName $TaskName
    
    Start-Sleep -Seconds 3
    
    # Check task status
    $task = Get-ScheduledTask -TaskName $TaskName
    $taskInfo = Get-ScheduledTaskInfo -TaskName $TaskName
    
    Write-Host "`nTask Status:" -ForegroundColor Cyan
    Write-Host "  State: $($task.State)" -ForegroundColor White
    Write-Host "  Last Run: $($taskInfo.LastRunTime)" -ForegroundColor White
    Write-Host "  Last Result: $($taskInfo.LastTaskResult)" -ForegroundColor White
    Write-Host "  Next Run: $($taskInfo.NextRunTime)" -ForegroundColor White
    
    Write-Host "`n✓ Installation complete!" -ForegroundColor Green
    Write-Host "`nTo uninstall, run:" -ForegroundColor Yellow
    Write-Host "  Unregister-ScheduledTask -TaskName '$TaskName' -Confirm:`$false" -ForegroundColor Gray
}
catch {
    Write-Error "Failed to create scheduled task: $_"
    exit 1
}
