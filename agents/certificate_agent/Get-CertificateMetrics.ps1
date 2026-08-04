<#
.SYNOPSIS
    Monitors TLS/SSL certificate expiry for a list of endpoints and reports their
    status to the Overview Dashboard.

.DESCRIPTION
    For each enabled target in config.json this agent opens a TLS connection, reads the
    certificate presented by the host, calculates the number of days until it expires and
    posts one component per endpoint to the Overview Dashboard API.

    Certificate retrieval uses Get-X509Certificate2Web from the shared module, which
    performs the TLS handshake and accepts the presented certificate regardless of trust
    so that an expiring or self-signed certificate can still be inspected and reported.

    Severity is derived from the time remaining until the certificate's NotAfter date,
    with configurable warning/error day thresholds. Certificates that are already expired,
    not yet valid, or unreachable are reported as errors.

.PARAMETER ConfigPath
    Path to the config.json file. Default: $PSScriptRoot\config.json

.PARAMETER DryRun
    Shows the configuration and which endpoints would be checked. No TLS connections are
    made and nothing is posted to the dashboard API.

.PARAMETER MockRun
    Generates realistic sample certificate data and posts it to the dashboard API without
    connecting to any endpoint.

.EXAMPLE
    .\Get-CertificateMetrics.ps1
    Runs a live collection using config.json.

.EXAMPLE
    .\Get-CertificateMetrics.ps1 -DryRun
    Prints the configuration and the endpoints that would be checked, then exits.

.EXAMPLE
    .\Get-CertificateMetrics.ps1 -MockRun
    Posts sample certificate data to the dashboard for UI preview.

.NOTES
    Requires : PowerShell 5.1+ and agents\shared\functions.psm1 next to this agent.
    Author   : Overview Dashboard agent guide - Pattern A (self contained)
#>

[CmdletBinding()]
param(
    [string]$ConfigPath = "$PSScriptRoot\config.json",
    [switch]$DryRun,
    [switch]$MockRun
)

# Shared functions: Send-ToApi, Get-X509Certificate2Web
Import-Module (Join-Path $PSScriptRoot '..\shared\functions.psm1') -Force

#region Helper Functions

function Write-AgentLine {
    <#
    .SYNOPSIS
        Writes a colour-coded line to the console.

    .PARAMETER Message
        Text to display.

    .PARAMETER Severity
        One of ok, warning, error or info. Controls the console colour
        (Green / Yellow / Red / Gray).

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

function Get-CertificateSeverity {
    <#
    .SYNOPSIS
        Maps a certificate's validity window to a dashboard severity and status string.

    .DESCRIPTION
        Applies these rules, in order:
          not yet valid (NotBefore in the future) -> warning
          already expired (NotAfter in the past)  -> error
          expires within error threshold           -> error
          expires within warning threshold         -> warning
          otherwise                                -> ok

    .PARAMETER DaysRemaining
        Whole days until NotAfter. Negative when the certificate has already expired.

    .PARAMETER NotYetValid
        $true when NotBefore is still in the future.

    .PARAMETER WarningDays
        Days remaining at or below which the certificate becomes a warning.

    .PARAMETER ErrorDays
        Days remaining at or below which the certificate becomes an error.

    .OUTPUTS
        Hashtable with keys Severity and Status.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [int]$DaysRemaining,

        [bool]$NotYetValid = $false,

        [int]$WarningDays = 30,

        [int]$ErrorDays = 7
    )

    if ($NotYetValid) {
        return @{ Severity = 'warning'; Status = 'Certificate is not yet valid' }
    }

    if ($DaysRemaining -lt 0) {
        return @{ Severity = 'error'; Status = "Expired $([math]::Abs($DaysRemaining)) day(s) ago" }
    }

    if ($DaysRemaining -le $ErrorDays) {
        return @{ Severity = 'error'; Status = "Expires in $DaysRemaining day(s)" }
    }

    if ($DaysRemaining -le $WarningDays) {
        return @{ Severity = 'warning'; Status = "Expires in $DaysRemaining day(s)" }
    }

    return @{ Severity = 'ok'; Status = "Valid - expires in $DaysRemaining day(s)" }
}

function Get-CertificateMockData {
    <#
    .SYNOPSIS
        Produces sample certificate data for MockRun mode.

    .DESCRIPTION
        Returns a fixed set of endpoints covering every severity path - healthy, ageing,
        near expiry, expired, not yet valid and unreachable - so dashboard rendering can be
        verified without reaching any real endpoint.

    .OUTPUTS
        Array of PSCustomObject shaped like the result of a live certificate check.
    #>
    [CmdletBinding()]
    param()

    $now = Get-Date

    return @(
        [pscustomobject]@{ Name='www.example.com';  Host='www.example.com';  Port=443; Reachable=$true;  NotBefore=$now.AddDays(-30);  NotAfter=$now.AddDays(180); DaysRemaining=180; NotYetValid=$false; Subject='CN=www.example.com'; Issuer='CN=Example CA' }
        [pscustomobject]@{ Name='portal.internal';  Host='portal.internal';  Port=443; Reachable=$true;  NotBefore=$now.AddDays(-300); NotAfter=$now.AddDays(20);  DaysRemaining=20;  NotYetValid=$false; Subject='CN=portal.internal'; Issuer='CN=Internal CA' }
        [pscustomobject]@{ Name='vpn.contoso.com';  Host='vpn.contoso.com';  Port=443; Reachable=$true;  NotBefore=$now.AddDays(-360); NotAfter=$now.AddDays(5);   DaysRemaining=5;   NotYetValid=$false; Subject='CN=vpn.contoso.com'; Issuer='CN=Contoso CA' }
        [pscustomobject]@{ Name='legacy.contoso';   Host='legacy.contoso';   Port=443; Reachable=$true;  NotBefore=$now.AddDays(-400); NotAfter=$now.AddDays(-3);  DaysRemaining=-3;  NotYetValid=$false; Subject='CN=legacy.contoso'; Issuer='CN=Contoso CA' }
        [pscustomobject]@{ Name='staging.new';      Host='staging.new';      Port=443; Reachable=$true;  NotBefore=$now.AddDays(2);    NotAfter=$now.AddDays(367); DaysRemaining=367; NotYetValid=$true;  Subject='CN=staging.new'; Issuer='CN=Internal CA' }
        [pscustomobject]@{ Name='dead.host';        Host='dead.host';        Port=443; Reachable=$false; NotBefore=$null;              NotAfter=$null;             DaysRemaining=0;   NotYetValid=$false; Subject=$null; Issuer=$null }
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
$defaultTTL  = if ($config.defaultTTL) { $config.defaultTTL } else { 3600 }

$warningDays = if ($config.warningDays) { [int]$config.warningDays } else { 30 }
$errorDays   = if ($config.errorDays)   { [int]$config.errorDays }   else { 7 }

$targets = @($config.targets)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Certificate Expiry Agent"                 -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "API URL   : $apiUrl"
Write-Host "Project   : $projectName"
Write-Host "System    : $systemName"
Write-Host "Targets   : $($targets.Count)"
Write-Host "TTL       : $defaultTTL s"
Write-Host "Thresholds: warning <= ${warningDays}d, error <= ${errorDays}d"
Write-Host ""

if ($DryRun)  { Write-Host "[DRY RUN MODE - No connections or API calls]" -ForegroundColor Yellow }
if ($MockRun) { Write-Host "[MOCK RUN MODE - Sending sample data to API]" -ForegroundColor Magenta }

if ($DryRun) {
    Write-Host ""
    foreach ($t in $targets) {
        $enabled = if ($null -ne $t.enabled) { [bool]$t.enabled } else { $true }
        if (-not $enabled) { continue }
        $port = if ($t.port) { [int]$t.port } else { 443 }
        $name = if ($t.name) { $t.name } else { $t.host }
        Write-Host "[DRY RUN] Would check TLS certificate for $name ($($t.host):$port)"
    }
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Completed (dry run)."                     -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    exit 0
}

# --- Collect certificate data ---
$checks = @()

if ($MockRun) {
    $checks = Get-CertificateMockData
}
else {
    $now = Get-Date

    foreach ($t in $targets) {
        $enabled = if ($null -ne $t.enabled) { [bool]$t.enabled } else { $true }
        if (-not $enabled) {
            Write-AgentLine -Message "  Skipping disabled target: $($t.name)" -Severity info
            continue
        }

        $targetHost = $t.host
        $port        = if ($t.port) { [int]$t.port } else { 443 }
        $name        = if ($t.name) { $t.name } else { $targetHost }

        $cert = Get-X509Certificate2Web -ComputerName $targetHost -Port $port

        if ($null -eq $cert) {
            $checks += [pscustomobject]@{
                Name=$name; Host=$targetHost; Port=$port; Reachable=$false
                NotBefore=$null; NotAfter=$null; DaysRemaining=0; NotYetValid=$false
                Subject=$null; Issuer=$null
            }
            continue
        }

        $notBefore     = $cert.NotBefore
        $notAfter      = $cert.NotAfter
        $daysRemaining = [int][math]::Floor(($notAfter - $now).TotalDays)
        $notYetValid   = $notBefore -gt $now

        $checks += [pscustomobject]@{
            Name          = $name
            Host          = $targetHost
            Port          = $port
            Reachable     = $true
            NotBefore     = $notBefore
            NotAfter      = $notAfter
            DaysRemaining = $daysRemaining
            NotYetValid   = $notYetValid
            Subject       = $cert.Subject
            Issuer        = $cert.Issuer
        }
    }
}

# --- Evaluate and report ---
$reported = 0

foreach ($check in $checks) {

    if (-not $check.Reachable) {
        Send-ToApi -ApiUrl $apiUrl -SystemName $systemName -ProjectName $projectName `
            -Name $check.Name -Metric 'TLS Certificate' -Severity 'error' `
            -Status "Unable to retrieve certificate from $($check.Host):$($check.Port)" `
            -TTL $defaultTTL -ExtraData @{ Host = $check.Host; Port = $check.Port }

        Write-AgentLine -Message ("  {0,-28} {1,-8} {2}" -f $check.Name, 'ERROR', 'Unreachable') -Severity error
        $reported++
        continue
    }

    $eval = Get-CertificateSeverity -DaysRemaining $check.DaysRemaining `
                -NotYetValid $check.NotYetValid -WarningDays $warningDays -ErrorDays $errorDays

    $extra = @{
        Host          = $check.Host
        Port          = $check.Port
        Subject       = $check.Subject
        Issuer        = $check.Issuer
        NotBefore     = if ($check.NotBefore) { $check.NotBefore.ToString('yyyy-MM-dd') } else { 'Unknown' }
        NotAfter      = if ($check.NotAfter)  { $check.NotAfter.ToString('yyyy-MM-dd') }  else { 'Unknown' }
        DaysRemaining = $check.DaysRemaining
    }

    Send-ToApi -ApiUrl $apiUrl -SystemName $systemName -ProjectName $projectName `
        -Name $check.Name -Metric 'TLS Certificate' -Severity $eval.Severity `
        -Status $eval.Status -TTL $defaultTTL -ExtraData $extra

    Write-AgentLine -Message ("  {0,-28} {1,-8} {2}" -f $check.Name, $eval.Severity.ToUpper(), $eval.Status) `
        -Severity $eval.Severity

    $reported++
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Completed. $reported endpoint(s) reported." -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

#endregion
