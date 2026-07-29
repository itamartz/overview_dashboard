<#
.SYNOPSIS
    Installs or removes a Windows Scheduled Task for the system metrics agent.

.DESCRIPTION
    Creates a scheduled task to run Post-SystemMetrics.ps1 at regular intervals.
    Default: Every 5 minutes.

.PARAMETER IntervalMinutes
    Interval in minutes between each run (default: 5)

.PARAMETER TaskName
    Name of the scheduled task (default: "OverviewDashboard-SystemMetrics")

.PARAMETER Remove
    If specified, removes the existing scheduled task

.PARAMETER DryRun
    If specified, shows what would be done without making changes

.EXAMPLE
    .\Install-ScheduledTask.ps1
    # Installs with default 5-minute interval

.EXAMPLE
    .\Install-ScheduledTask.ps1 -IntervalMinutes 10
    # Runs every 10 minutes

.EXAMPLE
    .\Install-ScheduledTask.ps1 -Remove
    # Removes the scheduled task
#>

param(
    [int]$IntervalMinutes = 5,
    [string]$TaskName = "OverviewDashboard-SystemMetrics",
    [switch]$Remove,
    [switch]$DryRun
)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$AgentScript = Join-Path $ScriptDir "Post-SystemMetrics.ps1"

# Check if running as administrator
function Test-Administrator {
    $currentUser = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $currentUser.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Remove-ExistingTask {
    Write-Host "Removing scheduled task: $TaskName" -ForegroundColor Cyan
    
    if ($DryRun) {
        Write-Host "[DRY RUN] Would remove task: $TaskName" -ForegroundColor Yellow
        return
    }
    
    try {
        $existingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        if ($existingTask) {
            Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
            Write-Host "[SUCCESS] Task removed successfully." -ForegroundColor Green
        }
        else {
            Write-Host "[INFO] Task '$TaskName' does not exist." -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "[ERROR] Failed to remove task: $_" -ForegroundColor Red
        exit 1
    }
}

function Install-MetricsTask {
    Write-Host "Installing scheduled task: $TaskName" -ForegroundColor Cyan
    Write-Host "Interval: Every $IntervalMinutes minutes" -ForegroundColor Cyan
    Write-Host "Script: $AgentScript" -ForegroundColor Cyan
    
    # Verify the agent script exists
    if (-not (Test-Path $AgentScript)) {
        Write-Host "[ERROR] Agent script not found: $AgentScript" -ForegroundColor Red
        exit 1
    }
    
    if ($DryRun) {
        Write-Host ""
        Write-Host "[DRY RUN] Would create scheduled task with:" -ForegroundColor Yellow
        Write-Host "  Task Name: $TaskName"
        Write-Host "  Trigger: Every $IntervalMinutes minutes"
        Write-Host "  Action: PowerShell -ExecutionPolicy Bypass -File `"$AgentScript`""
        return
    }
    
    try {
        # Remove existing task if present
        $existingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        if ($existingTask) {
            Write-Host "Removing existing task..." -ForegroundColor Yellow
            Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        }
        
        # Create the action
        $action = New-ScheduledTaskAction -Execute "PowerShell.exe" `
            -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$AgentScript`"" `
            -WorkingDirectory $ScriptDir
        
        # Create the trigger (repetition interval)
        $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) `
            -RepetitionInterval (New-TimeSpan -Minutes $IntervalMinutes) `
            -RepetitionDuration (New-TimeSpan -Days 9999)
        
        # Create settings
        $settings = New-ScheduledTaskSettingsSet `
            -AllowStartIfOnBatteries `
            -DontStopIfGoingOnBatteries `
            -StartWhenAvailable `
            -RunOnlyIfNetworkAvailable `
            -MultipleInstances IgnoreNew
        
        # Create principal (run as current user)
        $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType S4U -RunLevel Limited
        
        # Register the task
        Register-ScheduledTask `
            -TaskName $TaskName `
            -Action $action `
            -Trigger $trigger `
            -Settings $settings `
            -Principal $principal `
            -Description "Collects and posts system metrics to Overview Dashboard API" | Out-Null
        
        Write-Host ""
        Write-Host "[SUCCESS] Scheduled task created successfully!" -ForegroundColor Green
        Write-Host ""
        Write-Host "Task Details:" -ForegroundColor Cyan
        Get-ScheduledTask -TaskName $TaskName | Format-List TaskName, State, Description
        
        Write-Host "Next Steps:" -ForegroundColor Cyan
        Write-Host "  1. Test manually: .\Post-SystemMetrics.ps1"
        Write-Host "  2. Run task now: Start-ScheduledTask -TaskName '$TaskName'"
        Write-Host "  3. View in Task Scheduler: taskschd.msc"
        Write-Host "  4. Remove task: .\Install-ScheduledTask.ps1 -Remove"
    }
    catch {
        Write-Host "[ERROR] Failed to create scheduled task: $_" -ForegroundColor Red
        exit 1
    }
}

# Main execution
Write-Host ""
Write-Host "=== Overview Dashboard - Windows Agent Installer ===" -ForegroundColor Cyan
Write-Host ""

# Check for administrator rights (recommended but not required for user-level tasks)
if (-not (Test-Administrator)) {
    Write-Host "[WARNING] Not running as Administrator. Task will be created for current user only." -ForegroundColor Yellow
    Write-Host ""
}

if ($Remove) {
    Remove-ExistingTask
}
else {
    Install-MetricsTask
}
