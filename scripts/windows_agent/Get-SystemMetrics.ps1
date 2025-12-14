<#
.SYNOPSIS
    Gathers system metrics and formats them for API posting.

.DESCRIPTION
    Collects CPU usage, memory usage, disk usage, and checks for services that should be running.
    Computes severity (ok/warning/error) based on thresholds (>85% for warning/error).
    Outputs JSON formatted for API consumption.

.PARAMETER ThresholdWarning
    Warning threshold percentage (default: 85)

.PARAMETER ThresholdError
    Error threshold percentage (default: 95)

.PARAMETER ProjectName
    Name of the project for the payload (default: "Monitoring")

.PARAMETER SystemName
    Name of the system for the payload (default: "Workstations")

.PARAMETER IgnoreServices
    Array of service names or patterns to ignore when checking for stopped automatic services

.EXAMPLE
    .\Get-SystemMetrics.ps1
    
.EXAMPLE
    .\Get-SystemMetrics.ps1 -ThresholdWarning 80 -ThresholdError 90 -ProjectName "MyProject"
#>

param(
    [int]$ThresholdWarning = 85,
    [int]$ThresholdError = 95,
    [string]$ProjectName = "Workstations",
    [string]$SystemName = "Monitoring",
    [string[]]$IgnoreServices = @(
        'edgeupdate',
        'edgeupdatem',
        'GoogleUpdaterInternalService*',
        'GoogleUpdaterService*',
        'gupdate',
        'gupdatem',
        'MapsBroker',
        'WslInstaller',
        'sppsvc',  # Software Protection Platform Service
        'RtkBtManServ'  # Realtek Bluetooth
    )
)

function Get-CPUUsage {
    $cpuUsage = Get-Counter '\Processor(_Total)\% Processor Time' -SampleInterval 1 -MaxSamples 2 | 
    Select-Object -ExpandProperty CounterSamples | 
    Select-Object -Last 1 -ExpandProperty CookedValue
    return [math]::Round($cpuUsage, 2)
}

function Get-MemoryUsage {
    $os = Get-CimInstance Win32_OperatingSystem
    $totalMemory = $os.TotalVisibleMemorySize
    $freeMemory = $os.FreePhysicalMemory
    $usedMemory = $totalMemory - $freeMemory
    $memoryUsagePercent = [math]::Round(($usedMemory / $totalMemory) * 100, 2)
    return $memoryUsagePercent
}

function Get-DiskUsage {
    $disks = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" | 
    Select-Object DeviceID, 
    @{Name = "UsedPercent"; Expression = {
            if ($_.Size -gt 0) {
                [math]::Round((($_.Size - $_.FreeSpace) / $_.Size) * 100, 2)
            }
            else {
                0
            }
        }
    }
    return $disks
}

function Get-StoppedAutoServices {
    param(
        [string[]]$IgnoreList = @()
    )
    
    $stoppedServices = Get-Service | 
    Where-Object { 
        $_.StartType -eq 'Automatic' -and 
        $_.Status -ne 'Running' 
    } | 
    Select-Object -ExpandProperty Name
    
    # Filter out ignored services
    if ($IgnoreList.Count -gt 0) {
        $filteredServices = @()
        foreach ($service in $stoppedServices) {
            $shouldIgnore = $false
            foreach ($pattern in $IgnoreList) {
                if ($service -like $pattern) {
                    $shouldIgnore = $true
                    break
                }
            }
            if (-not $shouldIgnore) {
                $filteredServices += $service
            }
        }
        return $filteredServices
    }
    
    return $stoppedServices
}

function Get-OverallSeverity {
    param(
        [double]$CpuUsage,
        [double]$MemoryUsage,
        [array]$Disks,
        [array]$StoppedServices,
        [int]$WarningThreshold,
        [int]$ErrorThreshold
    )
    
    $severity = "ok"
    
    # Check CPU
    if ($CpuUsage -ge $ErrorThreshold) {
        $severity = "error"
    }
    elseif ($CpuUsage -ge $WarningThreshold -and $severity -ne "error") {
        $severity = "warning"
    }
    
    # Check Memory
    if ($MemoryUsage -ge $ErrorThreshold) {
        $severity = "error"
    }
    elseif ($MemoryUsage -ge $WarningThreshold -and $severity -ne "error") {
        $severity = "warning"
    }
    
    # Check Disks
    foreach ($disk in $Disks) {
        if ($disk.UsedPercent -ge $ErrorThreshold) {
            $severity = "error"
        }
        elseif ($disk.UsedPercent -ge $WarningThreshold -and $severity -ne "error") {
            $severity = "warning"
        }
    }
    
    # Check Services
    if ($StoppedServices.Count -gt 0) {
        $severity = "error"
    }
    
    return $severity
}

function Build-DataString {
    param(
        [double]$CpuUsage,
        [double]$MemoryUsage,
        [array]$Disks,
        [array]$StoppedServices
    )
    
    $dataParts = @()
    
    # Add CPU
    $dataParts += "CPU ($CpuUsage%)"
    
    # Add Memory
    $dataParts += "Memory ($MemoryUsage%)"
    
    # Add Disks
    foreach ($disk in $Disks) {
        $dataParts += "Disk $($disk.DeviceID) ($($disk.UsedPercent)%)"
    }
    
    # Add Stopped Services
    if ($StoppedServices.Count -gt 0) {
        $servicesList = $StoppedServices -join ", "
        $dataParts += "Services Down: $servicesList"
    }
    
    return $dataParts -join ", "
}

# Main execution
try {
    Write-Host "Gathering system metrics..." -ForegroundColor Cyan
    
    # Collect metrics
    $cpuUsage = Get-CPUUsage
    $memoryUsage = Get-MemoryUsage
    $disks = Get-DiskUsage
    $stoppedServices = Get-StoppedAutoServices -IgnoreList $IgnoreServices
    
    # Calculate severity
    $severity = Get-OverallSeverity -CpuUsage $cpuUsage `
        -MemoryUsage $memoryUsage `
        -Disks $disks `
        -StoppedServices $stoppedServices `
        -WarningThreshold $ThresholdWarning `
        -ErrorThreshold $ThresholdError
    
    # Format Disks String
    $diskStrings = @()
    foreach ($disk in $disks) {
        $diskStrings += "$($disk.DeviceID) ($($disk.UsedPercent)%)"
    }
    $disksString = $diskStrings -join ", "
    
    # Format Services String
    if ($stoppedServices.Count -gt 0) {
        $servicesString = "Down: " + ($stoppedServices -join ", ")
    }
    else {
        $servicesString = "All Automatic Services Running"
    }
    
    # Build JSON payload
    $payload = @{
        projectName = $ProjectName
        systemName  = $SystemName
        payload     = @{
            Id       = $env:COMPUTERNAME
            Name     = $env:COMPUTERNAME
            CPU      = "$cpuUsage%"
            Memory   = "$memoryUsage%"
            Disks    = $disksString
            Services = $servicesString
            Severity = $severity
        }
    }
    
    # Convert to JSON
    $jsonOutput = $payload | ConvertTo-Json -Depth 10
    
    # Display results
    Write-Host "`nSystem Metrics Summary:" -ForegroundColor Green
    Write-Host "CPU Usage: $cpuUsage%" -ForegroundColor $(if ($cpuUsage -ge $ThresholdError) { "Red" } elseif ($cpuUsage -ge $ThresholdWarning) { "Yellow" } else { "Green" })
    Write-Host "Memory Usage: $memoryUsage%" -ForegroundColor $(if ($memoryUsage -ge $ThresholdError) { "Red" } elseif ($memoryUsage -ge $ThresholdWarning) { "Yellow" } else { "Green" })
    
    foreach ($disk in $disks) {
        Write-Host "Disk $($disk.DeviceID) Usage: $($disk.UsedPercent)%" -ForegroundColor $(if ($disk.UsedPercent -ge $ThresholdError) { "Red" } elseif ($disk.UsedPercent -ge $ThresholdWarning) { "Yellow" } else { "Green" })
    }
    
    if ($stoppedServices.Count -gt 0) {
        Write-Host "Stopped Auto Services: $($stoppedServices.Count)" -ForegroundColor Red
        $stoppedServices | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    }
    else {
        Write-Host "All automatic services are running (or ignored)" -ForegroundColor Green
    }
    
    Write-Host "`nOverall Severity: $severity" -ForegroundColor $(if ($severity -eq "error") { "Red" } elseif ($severity -eq "warning") { "Yellow" } else { "Green" })
    
    Write-Host "`nJSON Output:" -ForegroundColor Cyan
    Write-Host $jsonOutput
    
    # Return the JSON object for further use (e.g., posting to API)
    return $payload
    
}
catch {
    Write-Error "An error occurred while gathering metrics: $_"
    exit 1
}
