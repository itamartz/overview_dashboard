<#
.SYNOPSIS
    Posts system metrics to the monitoring API.

.DESCRIPTION
    Wrapper script for Get-SystemMetrics.ps1 to maintain backward compatibility.
#>
param(
    [string]$ConfigPath = "$PSScriptRoot\config.json",
    [switch]$DryRun,
    [switch]$MockRun
)

$args = @("-ConfigPath", "`"$ConfigPath`"")
if ($DryRun) { $args += "-DryRun" }
if ($MockRun) { $args += "-MockRun" }

Invoke-Expression "& `"$PSScriptRoot\Get-SystemMetrics.ps1`" $args"
