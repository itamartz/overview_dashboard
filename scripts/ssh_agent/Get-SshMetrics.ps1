<#
.SYNOPSIS
    Monitors SSH-accessible devices and reports metrics to the Overview Dashboard.

.DESCRIPTION
    Connects to multiple SSH targets defined in config.json, executes commands,
    parses output to extract metrics, calculates severity based on thresholds,
    and reports to the Overview Dashboard API.

.PARAMETER ConfigPath
    Path to the config.json file. Default: $PSScriptRoot\config.json

.PARAMETER DryRun
    If specified, shows what would be reported without actually connecting or sending to API.

.PARAMETER MockRun
    If specified, generates random sample data and sends to API without connecting to SSH.
    Use this to preview how metrics will look on the dashboard.

.PARAMETER Verbose
    Shows detailed output during execution.

.EXAMPLE
    .\Get-SshMetrics.ps1

.EXAMPLE
    .\Get-SshMetrics.ps1 -DryRun

.EXAMPLE
    .\Get-SshMetrics.ps1 -MockRun

.EXAMPLE
    .\Get-SshMetrics.ps1 -ConfigPath "C:\custom\config.json"

.NOTES
    Requires: Posh-SSH module (Install-Module -Name Posh-SSH)
#>

[CmdletBinding()]
param(
    [string]$ConfigPath = "$PSScriptRoot\config.json",
    [switch]$DryRun,
    [switch]$MockRun
)

# Import parsers
. "$PSScriptRoot\parsers.ps1"

#region Helper Functions

function Test-PoshSSHInstalled {
    $module = Get-Module -ListAvailable -Name Posh-SSH
    return $null -ne $module
}

function Install-PoshSSHIfNeeded {
    if (-not (Test-PoshSSHInstalled)) {
        Write-Host "Posh-SSH module not found. Attempting to install..." -ForegroundColor Yellow
        try {
            Install-Module -Name Posh-SSH -Force -Scope CurrentUser -AllowClobber
            Import-Module Posh-SSH -Force
            Write-Host "Posh-SSH installed successfully." -ForegroundColor Green
            return $true
        }
        catch {
            Write-Error "Failed to install Posh-SSH module: $_"
            Write-Error "Please run: Install-Module -Name Posh-SSH -Force -Scope CurrentUser"
            return $false
        }
    }
    Import-Module Posh-SSH -Force
    return $true
}

function Get-SshCredential {
    param(
        [string]$Username,
        [string]$Password
    )
    
    $securePassword = ConvertTo-SecureString $Password -AsPlainText -Force
    return New-Object System.Management.Automation.PSCredential($Username, $securePassword)
}

function Connect-SshTarget {
    param(
        [string]$TargetHost,
        [int]$Port,
        [PSCredential]$Credential,
        [int]$TimeoutSeconds
    )
    
    try {
        $session = New-SSHSession -ComputerName $TargetHost -Port $Port -Credential $Credential `
            -AcceptKey -Force -ConnectionTimeout $TimeoutSeconds -ErrorAction Stop
        return $session
    }
    catch {
        Write-Warning "Failed to connect to ${TargetHost}:${Port}: $_"
        return $null
    }
}

function Get-SshCommandOutput {
    param(
        [object]$Session,
        [string]$Command,
        [int]$TimeoutSeconds = 30,
        [int]$RetryCount = 1
    )
    
    $attempt = 0
    $lastError = $null
    
    while ($attempt -le $RetryCount) {
        try {
            $result = Invoke-SSHCommand -SSHSession $Session -Command $Command -TimeOut $TimeoutSeconds -ErrorAction Stop
            return @{
                Success    = $true
                Output     = $result.Output -join "`n"
                ExitStatus = $result.ExitStatus
            }
        }
        catch {
            $lastError = $_.Exception.Message
            $attempt++
            
            # Log retry attempt
            if ($attempt -le $RetryCount) {
                Write-Host "    [RETRY] Command failed, retrying ($attempt/$RetryCount)..." -ForegroundColor Yellow
                Start-Sleep -Seconds 2
            }
        }
    }
    
    return @{
        Success    = $false
        Output     = $lastError
        ExitStatus = -1
    }
}

# Create shell stream for Cisco devices (call once per target)
function New-SshShellStreamWrapper {
    param(
        [object]$Session
    )
    
    try {
        $stream = New-SSHShellStream -SSHSession $Session -ErrorAction Stop
        
        # Wait for prompt
        Start-Sleep -Milliseconds 1000
        $null = $stream.Read()
        
        # Send terminal length 0 to disable paging (Cisco specific)
        $stream.WriteLine("terminal length 0")
        Start-Sleep -Milliseconds 1000
        $null = $stream.Read()
        
        return $stream
    }
    catch {
        Write-Warning "Failed to create shell stream: $_"
        return $null
    }
}

# Execute command using existing shell stream (for Cisco and similar devices)
function Get-SshShellOutput {
    param(
        [object]$Stream,
        [string]$Command,
        [int]$InitialWaitMs = 2000,
        [int]$ReadTimeoutMs = 10000
    )
    
    try {
        # Clear any pending output
        $null = $Stream.Read()
        
        # Send the command
        $Stream.WriteLine($Command)
        
        # Wait for initial response
        Start-Sleep -Milliseconds $InitialWaitMs
        
        # Read output in loop until no more data
        $allOutput = ""
        $readAttempts = 0
        $maxAttempts = [math]::Ceiling($ReadTimeoutMs / 500)
        
        do {
            $chunk = $Stream.Read()
            if ($chunk) {
                $allOutput += $chunk
                $readAttempts = 0  # Reset counter on successful read
            }
            else {
                $readAttempts++
                Start-Sleep -Milliseconds 500
            }
        } while ($readAttempts -lt 3 -and $readAttempts -lt $maxAttempts)
        
        return @{
            Success    = $true
            Output     = $allOutput
            ExitStatus = 0
        }
    }
    catch {
        return @{
            Success    = $false
            Output     = $_.Exception.Message
            ExitStatus = -1
        }
    }
}

function Get-Severity {
    param(
        [object]$Value,
        [hashtable]$Thresholds
    )
    
    # If value is null or not a number, return error
    if ($null -eq $Value) {
        return "error"
    }
    
    # If value is a string (from raw parser), return ok
    if ($Value -is [string]) {
        return "ok"
    }
    
    # Numeric threshold comparison
    $numValue = [double]$Value
    $errorThreshold = if ($Thresholds.error) { [double]$Thresholds.error } else { [double]::MaxValue }
    $warningThreshold = if ($Thresholds.warning) { [double]$Thresholds.warning } else { [double]::MaxValue }
    
    if ($numValue -ge $errorThreshold) {
        return "error"
    }
    elseif ($numValue -ge $warningThreshold) {
        return "warning"
    }
    else {
        return "ok"
    }
}

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
    
    # Generate deterministic ID from key fields (same metric always gets same ID)
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

function Get-MockValue {
    param(
        [string]$MetricName,
        [hashtable]$Thresholds
    )
    
    # Generate realistic mock values based on metric type
    $warningThreshold = if ($Thresholds.warning) { [double]$Thresholds.warning } else { 70 }
    $errorThreshold = if ($Thresholds.error) { [double]$Thresholds.error } else { 90 }
    
    # Random distribution: 70% ok, 20% warning, 10% error
    $rand = Get-Random -Minimum 0 -Maximum 100
    
    if ($rand -lt 70) {
        # OK range: 10% to just below warning
        $minVal = 10
        $maxVal = [math]::Max($minVal + 1, $warningThreshold - 5)
        return Get-Random -Minimum $minVal -Maximum $maxVal
    }
    elseif ($rand -lt 90) {
        # Warning range
        $minVal = $warningThreshold
        $maxVal = [math]::Max($minVal + 1, $errorThreshold - 1)
        return Get-Random -Minimum $minVal -Maximum $maxVal
    }
    else {
        # Error range
        $minVal = $errorThreshold
        $maxVal = [math]::Min(100, $errorThreshold + 10)
        return Get-Random -Minimum $minVal -Maximum $maxVal
    }
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

# Extract global settings
$apiUrl = $config.apiUrl
$projectName = $config.projectName
$systemName = $config.systemName
$defaultTTL = if ($config.defaultTTL) { $config.defaultTTL } else { 120 }
$connectionTimeout = if ($config.connectionTimeoutSeconds) { $config.connectionTimeoutSeconds } else { 30 }

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "SSH Metrics Agent" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "API URL: $apiUrl"
Write-Host "Project: $projectName"
Write-Host "System:  $systemName"
Write-Host ""

if ($DryRun) {
    Write-Host "[DRY RUN MODE - No connections or API calls will be made]" -ForegroundColor Yellow
    Write-Host ""
}

if ($MockRun) {
    Write-Host "[MOCK RUN MODE - Sending sample data to API without SSH connections]" -ForegroundColor Magenta
    Write-Host ""
}

# Install/Import Posh-SSH if not in dry run or mock run mode
if (-not $DryRun -and -not $MockRun) {
    if (-not (Install-PoshSSHIfNeeded)) {
        exit 1
    }
}

# Get enabled targets
$targets = $config.targets | Where-Object { $_.enabled -eq $true }

if ($targets.Count -eq 0) {
    Write-Warning "No enabled targets found in configuration."
    exit 0
}

Write-Host "Found $($targets.Count) enabled target(s).`n"

# Process each target
foreach ($target in $targets) {
    $targetName = $target.name
    $host_ = $target.host
    $port = if ($target.port) { $target.port } else { 22 }
    $username = $target.username
    $password = $target.password
    $shellMode = if ($target.shellMode -eq $true) { $true } else { $false }  # Use shell stream for Cisco devices
    
    Write-Host "----------------------------------------" -ForegroundColor DarkGray
    Write-Host "Target: $targetName ($host_`:$port)" -ForegroundColor White
    Write-Host "----------------------------------------" -ForegroundColor DarkGray
    
    $session = $null
    $shellStream = $null
    $connectionFailed = $false
    
    if ($MockRun) {
        Write-Host "  [MOCK] Simulating connection to $host_`:$port" -ForegroundColor Magenta
    }
    elseif (-not $DryRun) {
        # Connect to target
        $credential = Get-SshCredential -Username $username -Password $password
        $session = Connect-SshTarget -TargetHost $host_ -Port $port -Credential $credential -TimeoutSeconds $connectionTimeout
        
        if ($null -eq $session) {
            $connectionFailed = $true
            Write-Host "  [FAILED] Could not establish SSH connection" -ForegroundColor Red
        }
        else {
            Write-Host "  [OK] Connected" -ForegroundColor Green
            
            # Create shell stream for Cisco devices (once per target)
            if ($shellMode) {
                $shellStream = New-SshShellStreamWrapper -Session $session
                if ($null -eq $shellStream) {
                    $connectionFailed = $true
                    Write-Host "  [FAILED] Could not create shell stream" -ForegroundColor Red
                }
                else {
                    Write-Host "  [OK] Shell stream ready" -ForegroundColor Green
                }
            }
        }
    }
    else {
        Write-Host "  [DRY RUN] Would connect to $host_`:$port as $username"
    }
    
    # Process each metric for this target
    foreach ($metric in $target.metrics) {
        $metricName = $metric.name
        $command = $metric.command
        $parserName = $metric.parser
        $thresholds = @{}
        if ($metric.thresholds) {
            if ($metric.thresholds.warning) { $thresholds.warning = $metric.thresholds.warning }
            if ($metric.thresholds.error) { $thresholds.error = $metric.thresholds.error }
        }
        
        if ($connectionFailed) {
            # Report connection failure
            $severity = "error"
            $status = "Connection failed"
            
            Write-Host "  Metric: $metricName -> $severity ($status)" -ForegroundColor Red
            
            if (-not $DryRun) {
                $sent = Send-ToApi -ApiUrl $apiUrl -SystemName $systemName -ProjectName $projectName `
                    -Name $targetName -Metric $metricName -Severity $severity -Status $status -TTL $defaultTTL
                if ($sent) {
                    Write-Host "    -> Reported to Dashboard" -ForegroundColor Gray
                }
            }
            continue
        }
        
        if ($DryRun) {
            Write-Host "  Metric: $metricName"
            Write-Host "    Command: $command"
            Write-Host "    Parser: $parserName"
            Write-Host "    Thresholds: warning=$($thresholds.warning), error=$($thresholds.error)"
            continue
        }
        
        if ($MockRun) {
            # Generate mock data
            $mockValue = Get-MockValue -MetricName $metricName -Thresholds $thresholds
            $severity = Get-Severity -Value $mockValue -Thresholds $thresholds
            
            $status = "$mockValue"
            if ($metricName -match 'Usage|Memory|CPU|Load|Disk|Utilization') {
                if ($mockValue -le 100) {
                    $status = "$mockValue%"
                }
            }
            elseif ($metricName -match 'Sessions') {
                $status = "$mockValue sessions"
            }
            elseif ($metricName -match 'Temperature') {
                $status = "${mockValue}°C"
            }
            
            $color = switch ($severity) {
                'ok' { 'Green' }
                'warning' { 'Yellow' }
                'error' { 'Red' }
                default { 'White' }
            }
            Write-Host "  Metric: $metricName -> $severity ($status)" -ForegroundColor $color
            
            # Send mock data to API
            $sent = Send-ToApi -ApiUrl $apiUrl -SystemName $systemName -ProjectName $projectName `
                -Name $targetName -Metric $metricName -Severity $severity -Status $status -TTL $defaultTTL
            if ($sent) {
                Write-Host "    -> Reported to Dashboard" -ForegroundColor Gray
            }
            continue
        }
        
        # Execute command (use shell stream for Cisco devices)
        if ($shellMode) {
            $result = Get-SshShellOutput -Stream $shellStream -Command $command
        }
        else {
            $result = Get-SshCommandOutput -Session $session -Command $command
        }
        
        if (-not $result.Success) {
            $severity = "error"
            $status = "Command failed: $($result.Output)"
            Write-Host "  Metric: $metricName -> $severity" -ForegroundColor Red
        }
        else {
            # Parse the output
            $metricConfig = @{}
            if ($metric.pattern) { $metricConfig.pattern = $metric.pattern }
            
            $parsedValue = Invoke-Parser -ParserName $parserName -Output $result.Output -MetricConfig $metricConfig
            
            if ($null -eq $parsedValue) {
                $severity = "warning"
                $status = "Could not parse metric value"
                Write-Host "  Metric: $metricName -> $severity (parse failed)" -ForegroundColor Yellow
            }
            else {
                # Calculate severity
                $severity = Get-Severity -Value $parsedValue -Thresholds $thresholds
                
                if ($parsedValue -is [string]) {
                    $status = $parsedValue
                }
                else {
                    $status = "$parsedValue"
                    # Add unit suffix if it's a percentage-like metric
                    if ($metricName -match 'Usage|Memory|CPU|Load') {
                        if ($parsedValue -le 100) {
                            $status = "$parsedValue%"
                        }
                    }
                }
                
                $color = switch ($severity) {
                    'ok' { 'Green' }
                    'warning' { 'Yellow' }
                    'error' { 'Red' }
                    default { 'White' }
                }
                Write-Host "  Metric: $metricName -> $severity ($status)" -ForegroundColor $color
            }
        }
        
        # Send to API
        $sent = Send-ToApi -ApiUrl $apiUrl -SystemName $systemName -ProjectName $projectName `
            -Name $targetName -Metric $metricName -Severity $severity -Status $status -TTL $defaultTTL
        if ($sent) {
            Write-Host "    -> Reported to Dashboard" -ForegroundColor Gray
        }
    }
    
    # Cleanup shell stream if used
    if ($null -ne $shellStream) {
        try {
            $shellStream.Close()
            $shellStream.Dispose()
        }
        catch {
            # Ignore cleanup errors
        }
    }
    
    # Disconnect session
    if ($null -ne $session) {
        try {
            Remove-SSHSession -SSHSession $session -ErrorAction SilentlyContinue | Out-Null
            Write-Host "  [OK] Disconnected" -ForegroundColor Green
        }
        catch {
            # Ignore disconnect errors
        }
    }
    
    Write-Host ""
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Completed." -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

#endregion
