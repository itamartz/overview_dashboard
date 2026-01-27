<#
.SYNOPSIS
    Output parsers for SSH metric collection.

.DESCRIPTION
    Contains functions to parse command output from various network devices
    and extract numeric metrics for severity calculation.
    
    Supported devices:
    - Juniper switches (show chassis routing-engine)
    - Palo Alto firewalls (show system resources, show system disk-space)
#>

#region Juniper Parsers

# Juniper CPU Parser
# Parses output from "show chassis routing-engine" command
function Parse-JuniperCpu {
    param([string]$Output)
    
    # Example output line: "CPU utilization:     5 percent"
    if ($Output -match 'CPU utilization[:\s]+(\d+)\s*percent') {
        return [double]$Matches[1]
    }
    
    # Alternative format: "Idle                    95 percent"
    # In this case, CPU usage = 100 - Idle
    if ($Output -match 'Idle\s+(\d+)\s*percent') {
        return [double](100 - [int]$Matches[1])
    }
    
    return $null
}

# Juniper Memory Parser
# Parses output from "show chassis routing-engine" command
function Parse-JuniperMemory {
    param([string]$Output)
    
    # Example: "Memory utilization:  45 percent"
    if ($Output -match 'Memory utilization[:\s]+(\d+)\s*percent') {
        return [double]$Matches[1]
    }
    
    return $null
}

# Juniper Temperature Parser
function Parse-JuniperTemperature {
    param([string]$Output)
    
    # Example: "Temperature          45 degrees C / 113 degrees F"
    if ($Output -match 'Temperature\s+(\d+)\s*degrees\s*C') {
        return [double]$Matches[1]
    }
    
    return $null
}

#endregion

#region Palo Alto Parsers

# Palo Alto CPU Parser
# Parses output from "show system resources" command
function Parse-PaloAltoCpu {
    param([string]$Output)
    
    # Example: "%Cpu(s):  2.3 us,  1.2 sy,  0.0 ni, 96.2 id,  0.3 wa"
    # CPU usage = 100 - idle
    if ($Output -match '%Cpu\(s\):[^,]+,[^,]+,[^,]+,\s*(\d+\.?\d*)\s*id') {
        return [double](100 - [double]$Matches[1])
    }
    
    # Alternative: look for "load average:" line
    # Example: "load average: 0.12, 0.08, 0.06"
    if ($Output -match 'load average:\s*(\d+\.?\d*)') {
        # Convert load to percentage (rough estimate based on 1 core = 100%)
        return [double]([double]$Matches[1] * 100)
    }
    
    return $null
}

# Palo Alto Memory Parser
# Parses output from "show system resources" command
function Parse-PaloAltoMemory {
    param([string]$Output)
    
    # Example: "Mem:   8052732k total,  7845632k used,   207100k free"
    if ($Output -match 'Mem:\s*(\d+)k\s*total,\s*(\d+)k\s*used') {
        $total = [double]$Matches[1]
        $used = [double]$Matches[2]
        if ($total -gt 0) {
            return [math]::Round(($used / $total) * 100, 1)
        }
    }
    
    # Alternative format with different units
    if ($Output -match 'KiB Mem\s*:\s*(\d+)\s*total.*?(\d+)\s*used') {
        $total = [double]$Matches[1]
        $used = [double]$Matches[2]
        if ($total -gt 0) {
            return [math]::Round(($used / $total) * 100, 1)
        }
    }
    
    return $null
}

# Palo Alto Disk Parser
# Parses output from "show system disk-space" command
function Parse-PaloAltoDisk {
    param([string]$Output)
    
    # Example output:
    # Filesystem      Size  Used Avail Use% Mounted on
    # /dev/sda3       7.8G  4.2G  3.2G  57% /
    # Look for root partition (/) or highest usage
    
    $maxUsage = 0
    $lines = $Output -split "`n"
    
    foreach ($line in $lines) {
        # Match lines with percentage: "57%"
        if ($line -match '\s+(\d+)%\s+(/|/opt)') {
            $usage = [int]$Matches[1]
            if ($usage -gt $maxUsage) {
                $maxUsage = $usage
            }
        }
    }
    
    if ($maxUsage -gt 0) {
        return [double]$maxUsage
    }
    
    # Fallback: find any percentage
    if ($Output -match '\s+(\d+)%\s+/') {
        return [double]$Matches[1]
    }
    
    return $null
}

# Palo Alto Session Count Parser
# Parses output from "show session info" command
function Parse-PaloAltoSessions {
    param([string]$Output)
    
    # Example: "num-active:  12345"
    if ($Output -match 'num-active:\s*(\d+)') {
        return [double]$Matches[1]
    }
    
    # Alternative: "Number of sessions:  12345"
    if ($Output -match 'Number of sessions:\s*(\d+)') {
        return [double]$Matches[1]
    }
    
    return $null
}

# Palo Alto Session Utilization (% of max)
# Parses output from "show session info" command
function Parse-PaloAltoSessionUtil {
    param([string]$Output)
    
    # Example: 
    # "num-max:     262144"
    # "num-active:   12345"
    if ($Output -match 'num-max:\s*(\d+)' -and $Output -match 'num-active:\s*(\d+)') {
        $max = [double]($Output | Select-String -Pattern 'num-max:\s*(\d+)' | ForEach-Object { $_.Matches.Groups[1].Value })
        $active = [double]($Output | Select-String -Pattern 'num-active:\s*(\d+)' | ForEach-Object { $_.Matches.Groups[1].Value })
        
        if ($max -gt 0) {
            return [math]::Round(($active / $max) * 100, 1)
        }
    }
    
    return $null
}

#endregion

#region Generic Parsers

# Generic Number Parser
# Extracts the first number from the output (for simple commands)
function Parse-GenericNumber {
    param([string]$Output)
    
    $trimmed = $Output.Trim()
    
    # Try to parse as a pure number first
    $value = 0
    if ([double]::TryParse($trimmed, [ref]$value)) {
        return $value
    }
    
    # Extract first number from text
    if ($trimmed -match '(\d+\.?\d*)') {
        return [double]$Matches[1]
    }
    
    return $null
}

# Generic Regex Parser
# Uses a custom regex pattern from the metric config
function Parse-GenericRegex {
    param(
        [string]$Output,
        [string]$Pattern
    )
    
    if ([string]::IsNullOrWhiteSpace($Pattern)) {
        return $null
    }
    
    if ($Output -match $Pattern) {
        if ($Matches[1]) {
            $value = 0
            if ([double]::TryParse($Matches[1], [ref]$value)) {
                return $value
            }
        }
    }
    
    return $null
}

# Raw Output Parser
# Returns the full output as a string (for status display only)
function Parse-Raw {
    param([string]$Output)
    
    # Truncate long output and clean up newlines
    $clean = $Output -replace '[\r\n]+', ' '
    if ($clean.Length -gt 200) {
        $clean = $clean.Substring(0, 197) + "..."
    }
    return $clean.Trim()
}

#endregion

#region Parser Dispatcher

# Main parser dispatcher
function Invoke-Parser {
    param(
        [string]$ParserName,
        [string]$Output,
        [hashtable]$MetricConfig = @{}
    )
    
    switch ($ParserName.ToLower()) {
        # Juniper parsers
        'juniper_cpu' {
            return Parse-JuniperCpu -Output $Output
        }
        'juniper_memory' {
            return Parse-JuniperMemory -Output $Output
        }
        'juniper_temperature' {
            return Parse-JuniperTemperature -Output $Output
        }
        
        # Palo Alto parsers
        'paloalto_cpu' {
            return Parse-PaloAltoCpu -Output $Output
        }
        'paloalto_memory' {
            return Parse-PaloAltoMemory -Output $Output
        }
        'paloalto_disk' {
            return Parse-PaloAltoDisk -Output $Output
        }
        'paloalto_sessions' {
            return Parse-PaloAltoSessions -Output $Output
        }
        'paloalto_session_util' {
            return Parse-PaloAltoSessionUtil -Output $Output
        }
        
        # Generic parsers
        'generic_number' {
            return Parse-GenericNumber -Output $Output
        }
        'generic_regex' {
            $pattern = $MetricConfig.pattern
            return Parse-GenericRegex -Output $Output -Pattern $pattern
        }
        'raw' {
            return Parse-Raw -Output $Output
        }
        
        default {
            Write-Warning "Unknown parser: $ParserName. Using generic_number."
            return Parse-GenericNumber -Output $Output
        }
    }
}

#endregion
