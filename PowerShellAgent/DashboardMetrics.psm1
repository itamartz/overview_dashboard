function Send-DashboardMetric {
    <#
    .SYNOPSIS
        Collects system metrics and sends them to the Dashboard API.
    
    .DESCRIPTION
        This function collects various system metrics (CPU, Memory, Disk, Services) from the local 
        or remote Windows machine and sends them to the IT Infrastructure Dashboard API.
        
        Designed for PowerShell 5.1 and works in air-gapped environments.
    
    .PARAMETER ApiUrl
        The base URL of the Dashboard API endpoint (e.g., http://dashboard-server:5000)
    
    .PARAMETER ComponentId
        The unique identifier for this component as registered in the dashboard database.
    
    .PARAMETER ComputerName
        The name of the computer to collect metrics from. Defaults to local computer.
    
    .PARAMETER MetricTypes
        Array of metric types to collect. Valid values: CPU, Memory, Disk, Services, All
        Default: All
    
    .PARAMETER UseBasicParsing
        Use basic parsing for Invoke-RestMethod (useful for Server Core installations)
    
    .EXAMPLE
        Send-DashboardMetric -ApiUrl "http://dashboard-server:5000" -ComponentId "COMP001"
        
        Collects all metrics from local computer and sends to the API.
    
    .EXAMPLE
        Send-DashboardMetric -ApiUrl "http://10.0.0.100:5000" -ComponentId "COMP001" -MetricTypes @("CPU", "Memory")
        
        Collects only CPU and Memory metrics.
    
    .EXAMPLE
        Send-DashboardMetric -ApiUrl "http://dashboard-server:5000" -ComponentId "COMP002" -ComputerName "SERVER02"
        
        Collects metrics from remote computer SERVER02.
    
    .NOTES
        Author: IT Operations Team
        Version: 1.0
        Requires: PowerShell 5.1 or higher
        
        This script can be scheduled to run every few minutes using Windows Task Scheduler.
    #>
    
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Dashboard API base URL")]
        [ValidateNotNullOrEmpty()]
        [string]$ApiUrl,
        
        [Parameter(Mandatory = $true, HelpMessage = "Component ID registered in dashboard")]
        [ValidateNotNullOrEmpty()]
        [string]$ComponentId,
        
        [Parameter(Mandatory = $false)]
        [string]$ComputerName = $env:COMPUTERNAME,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet("CPU", "Memory", "Disk", "Services", "All")]
        [string[]]$MetricTypes = @("All"),
        
        [Parameter(Mandatory = $false)]
        [switch]$UseBasicParsing
    )
    
    begin {
        Write-Verbose "Starting metric collection for component: $ComponentId"
        
        # Normalize API URL
        $ApiUrl = $ApiUrl.TrimEnd('/')
        $MetricsEndpoint = "$ApiUrl/api/metrics/batch"
        
        # Initialize metrics collection
        $metrics = @()
        
        # Determine which metrics to collect
        $collectAll = $MetricTypes -contains "All"
        $collectCPU = $collectAll -or ($MetricTypes -contains "CPU")
        $collectMemory = $collectAll -or ($MetricTypes -contains "Memory")
        $collectDisk = $collectAll -or ($MetricTypes -contains "Disk")
        $collectServices = $collectAll -or ($MetricTypes -contains "Services")
    }
    
    process {
        try {
            # ===== CPU Metrics =====
            if ($collectCPU) {
                Write-Verbose "Collecting CPU metrics..."
                try {
                    $cpu = Get-CimInstance -ClassName Win32_Processor -ComputerName $ComputerName -ErrorAction Stop
                    $cpuLoad = ($cpu | Measure-Object -Property LoadPercentage -Average).Average
                    
                    $severity = "ok"
                    if ($cpuLoad -gt 90) { $severity = "error" }
                    elseif ($cpuLoad -gt 75) { $severity = "warning" }
                    
                    $metrics += @{
                        ComponentId = $ComponentId
                        Severity = $severity
                        Value = "$([math]::Round($cpuLoad, 2))"
                        Metric = "%"
                        RawValue = $cpuLoad
                        Description = "CPU utilization - $($cpu.Name)"
                    }
                    
                    Write-Verbose "CPU: $cpuLoad%"
                }
                catch {
                    Write-Warning "Failed to collect CPU metrics: $_"
                }
            }
            
            # ===== Memory Metrics =====
            if ($collectMemory) {
                Write-Verbose "Collecting Memory metrics..."
                try {
                    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ComputerName $ComputerName -ErrorAction Stop
                    $totalMemoryGB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
                    $freeMemoryGB = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
                    $usedMemoryGB = $totalMemoryGB - $freeMemoryGB
                    $memoryPercent = [math]::Round(($usedMemoryGB / $totalMemoryGB) * 100, 2)
                    
                    $severity = "ok"
                    if ($memoryPercent -gt 95) { $severity = "error" }
                    elseif ($memoryPercent -gt 85) { $severity = "warning" }
                    
                    $metrics += @{
                        ComponentId = $ComponentId
                        Severity = $severity
                        Value = "$usedMemoryGB / $totalMemoryGB"
                        Metric = "GB"
                        RawValue = $memoryPercent
                        Description = "Memory utilization: $memoryPercent% used"
                    }
                    
                    Write-Verbose "Memory: $usedMemoryGB GB / $totalMemoryGB GB ($memoryPercent%)"
                }
                catch {
                    Write-Warning "Failed to collect Memory metrics: $_"
                }
            }
            
            # ===== Disk Metrics =====
            if ($collectDisk) {
                Write-Verbose "Collecting Disk metrics..."
                try {
                    $disks = Get-CimInstance -ClassName Win32_LogicalDisk -ComputerName $ComputerName -Filter "DriveType=3" -ErrorAction Stop
                    
                    foreach ($disk in $disks) {
                        if ($disk.Size -gt 0) {
                            $totalGB = [math]::Round($disk.Size / 1GB, 2)
                            $freeGB = [math]::Round($disk.FreeSpace / 1GB, 2)
                            $usedGB = $totalGB - $freeGB
                            $diskPercent = [math]::Round(($usedGB / $totalGB) * 100, 2)
                            
                            $severity = "ok"
                            if ($diskPercent -gt 95) { $severity = "error" }
                            elseif ($diskPercent -gt 85) { $severity = "warning" }
                            
                            $metrics += @{
                                ComponentId = $ComponentId
                                Severity = $severity
                                Value = "$usedGB / $totalGB"
                                Metric = "GB"
                                RawValue = $diskPercent
                                Description = "Disk $($disk.DeviceID) utilization: $diskPercent% used"
                            }
                            
                            Write-Verbose "Disk $($disk.DeviceID): $usedGB GB / $totalGB GB ($diskPercent%)"
                        }
                    }
                }
                catch {
                    Write-Warning "Failed to collect Disk metrics: $_"
                }
            }
            
            # ===== Service Metrics =====
            if ($collectServices) {
                Write-Verbose "Collecting Service metrics..."
                try {
                    $services = Get-Service -ComputerName $ComputerName -ErrorAction Stop | 
                                Where-Object { $_.StartType -eq 'Automatic' }
                    
                    $stoppedServices = $services | Where-Object { $_.Status -ne 'Running' }
                    $stoppedCount = ($stoppedServices | Measure-Object).Count
                    $totalAutoServices = ($services | Measure-Object).Count
                    
                    $severity = "ok"
                    if ($stoppedCount -gt 5) { $severity = "error" }
                    elseif ($stoppedCount -gt 2) { $severity = "warning" }
                    elseif ($stoppedCount -gt 0) { $severity = "info" }
                    
                    $metrics += @{
                        ComponentId = $ComponentId
                        Severity = $severity
                        Value = "$stoppedCount"
                        Metric = "stopped"
                        RawValue = $stoppedCount
                        Description = "$stoppedCount automatic services stopped out of $totalAutoServices total"
                    }
                    
                    Write-Verbose "Services: $stoppedCount stopped automatic services"
                    
                    # List stopped services if any
                    if ($stoppedCount -gt 0 -and $stoppedCount -le 10) {
                        $stoppedList = ($stoppedServices | Select-Object -ExpandProperty Name) -join ", "
                        Write-Verbose "Stopped services: $stoppedList"
                    }
                }
                catch {
                    Write-Warning "Failed to collect Service metrics: $_"
                }
            }
            
            # ===== Send Metrics to API =====
            if ($metrics.Count -gt 0) {
                Write-Verbose "Sending $($metrics.Count) metrics to API..."
                
                $body = @{
                    Metrics = $metrics
                } | ConvertTo-Json -Depth 10
                
                $params = @{
                    Uri = $MetricsEndpoint
                    Method = 'POST'
                    Body = $body
                    ContentType = 'application/json'
                    ErrorAction = 'Stop'
                }
                
                if ($UseBasicParsing) {
                    $params.Add('UseBasicParsing', $true)
                }
                
                try {
                    $response = Invoke-RestMethod @params
                    
                    if ($response.Success) {
                        Write-Verbose "Successfully sent metrics to API"
                        Write-Output "✓ Metrics sent successfully for $ComponentId"
                        return $response
                    }
                    else {
                        Write-Warning "API returned error: $($response.Message)"
                        return $response
                    }
                }
                catch {
                    Write-Error "Failed to send metrics to API: $_"
                    Write-Error "Endpoint: $MetricsEndpoint"
                    
                    # Return error object
                    return @{
                        Success = $false
                        Message = $_.Exception.Message
                        ComponentId = $ComponentId
                    }
                }
            }
            else {
                Write-Warning "No metrics collected"
                return @{
                    Success = $false
                    Message = "No metrics were collected"
                    ComponentId = $ComponentId
                }
            }
        }
        catch {
            Write-Error "Error in Send-DashboardMetric: $_"
            throw
        }
    }
}

# Export the function
Export-ModuleMember -Function Send-DashboardMetric
