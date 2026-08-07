<#
.SYNOPSIS
    Monitors TLS/SSL certificate expiry for a list of endpoints and static certificate files,
    reporting each certificate immediately to the Overview Dashboard.

.DESCRIPTION
    For each enabled target in config.json this agent opens a TLS connection, reads the
    certificate presented by the host, calculates the number of days until it expires and
    posts the component immediately to the Overview Dashboard API.

    In addition, it scans a directory of static certificate files (.cer, .crt, .pem, .pfx, etc.),
    parses each file, calculates expiration metrics, and sends each certificate immediately to the API.

    Certificate retrieval uses Get-X509Certificate2Web from the shared module, which
    performs the TLS handshake and accepts the presented certificate regardless of trust
    so that an expiring or self-signed certificate can still be inspected and reported.

    Severity is derived from the time remaining until the certificate's NotAfter date,
    with configurable warning/error day thresholds. Certificates that are already expired,
    not yet valid, or unreachable are reported as errors.

.PARAMETER ConfigPath
    Path to the config.json file. Default: $PSScriptRoot\config.json

.PARAMETER DryRun
    Shows the configuration and which endpoints/file certificates would be checked.
    No TLS connections are made and nothing is posted to the dashboard API.

.PARAMETER MockRun
    Generates realistic sample certificate data and posts each sample immediately to the dashboard API.

.EXAMPLE
    .\Get-CertificateMetrics.ps1
    Runs a live collection using config.json.

.EXAMPLE
    .\Get-CertificateMetrics.ps1 -DryRun
    Prints the configuration and the targets/files that would be checked, then exits.

.EXAMPLE
    .\Get-CertificateMetrics.ps1 -MockRun
    Posts sample certificate data to the dashboard for UI preview.

.NOTES
    Requires : PowerShell 5.1+ and agents\shared\functions.psm1 next to this agent.
    Author   : Overview Dashboard agent guide - Pattern A (self contained)
#>

[CmdletBinding()]
param(
    [string]$ConfigPath,
    [switch]$DryRun,
    [switch]$MockRun
)

if (-not $ConfigPath) {
    $ConfigPath = Join-Path $PSScriptRoot "config.json"
}


# Shared functions: Send-ToApi, Get-X509Certificate2Web
Import-Module (Join-Path $PSScriptRoot '..\shared\functions.psm1') -Force

#region Helper Functions

function Write-AgentLine {
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

function Process-AndReportCertificate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Check,

        [string]$ApiUrl,
        [string]$SystemName,
        [string]$ProjectName,
        [int]$DefaultTTL,
        [int]$WarningDays,
        [int]$ErrorDays,
        [string]$SelfSignedSeverity
    )

    if (-not $Check.Reachable) {
        Send-ToApi -ApiUrl $ApiUrl -SystemName $SystemName -ProjectName $ProjectName `
            -Name $Check.Name -Metric 'TLS Certificate' -Severity 'error' `
            -Status "Unable to retrieve certificate from $($Check.Host):$($Check.Port)" `
            -TTL $DefaultTTL -ExtraData @{ Host = $Check.Host; Port = $Check.Port; Source = $Check.Source }

        Write-AgentLine -Message ("  {0,-28} {1,-8} {2}" -f $Check.Name, 'ERROR', 'Unreachable') -Severity error
        return
    }

    $eval = Get-CertificateSeverity -DaysRemaining $Check.DaysRemaining `
                -NotYetValid $Check.NotYetValid -WarningDays $WarningDays -ErrorDays $ErrorDays

    $severity = $eval.Severity
    $status   = $eval.Status

    if ($Check.SelfSigned) {
        $status = "$status (self-signed)"

        $rank = @{ ok = 0; warning = 1; error = 2 }
        if ($rank[$SelfSignedSeverity] -gt $rank[$severity]) {
            $severity = $SelfSignedSeverity
        }
    }

    $extra = @{
        Source        = $Check.Source
        Host          = $Check.Host
        Port          = $Check.Port
        Subject       = $Check.Subject
        Issuer        = $Check.Issuer
        NotBefore     = if ($Check.NotBefore) { $Check.NotBefore.ToString('yyyy-MM-dd') } else { 'Unknown' }
        NotAfter      = if ($Check.NotAfter)  { $Check.NotAfter.ToString('yyyy-MM-dd') }  else { 'Unknown' }
        DaysRemaining = $Check.DaysRemaining
        SelfSigned    = $Check.SelfSigned
    }

    Send-ToApi -ApiUrl $ApiUrl -SystemName $SystemName -ProjectName $ProjectName `
        -Name $Check.Name -Metric 'TLS Certificate' -Severity $severity `
        -Status $status -TTL $DefaultTTL -ExtraData $extra
}


function Get-CertificateMockData {
    [CmdletBinding()]
    param()

    $now = Get-Date

    return @(
        [pscustomobject]@{ Name='www.example.com';  Host='www.example.com';  Port=443; Reachable=$true;  NotBefore=$now.AddDays(-30);  NotAfter=$now.AddDays(180); DaysRemaining=180; NotYetValid=$false; Subject='CN=www.example.com'; Issuer='CN=Example CA'; SelfSigned=$false; Source='endpoint' }
        [pscustomobject]@{ Name='portal.internal';  Host='portal.internal';  Port=443; Reachable=$true;  NotBefore=$now.AddDays(-300); NotAfter=$now.AddDays(20);  DaysRemaining=20;  NotYetValid=$false; Subject='CN=portal.internal'; Issuer='CN=Internal CA'; SelfSigned=$false; Source='endpoint' }
        [pscustomobject]@{ Name='vpn.contoso.com';  Host='vpn.contoso.com';  Port=443; Reachable=$true;  NotBefore=$now.AddDays(-360); NotAfter=$now.AddDays(5);   DaysRemaining=5;   NotYetValid=$false; Subject='CN=vpn.contoso.com'; Issuer='CN=Contoso CA'; SelfSigned=$false; Source='endpoint' }
        [pscustomobject]@{ Name='legacy.contoso';   Host='legacy.contoso';   Port=443; Reachable=$true;  NotBefore=$now.AddDays(-400); NotAfter=$now.AddDays(-3);  DaysRemaining=-3;  NotYetValid=$false; Subject='CN=legacy.contoso'; Issuer='CN=Contoso CA'; SelfSigned=$false; Source='endpoint' }
        [pscustomobject]@{ Name='staging.new';      Host='staging.new';      Port=443; Reachable=$true;  NotBefore=$now.AddDays(2);    NotAfter=$now.AddDays(367); DaysRemaining=367; NotYetValid=$true;  Subject='CN=staging.new'; Issuer='CN=Internal CA'; SelfSigned=$false; Source='endpoint' }
        [pscustomobject]@{ Name='appliance.local';  Host='appliance.local';  Port=443; Reachable=$true;  NotBefore=$now.AddDays(-10);  NotAfter=$now.AddDays(90);  DaysRemaining=90;  NotYetValid=$false; Subject='CN=appliance.local'; Issuer='CN=appliance.local'; SelfSigned=$true; Source='endpoint' }
        [pscustomobject]@{ Name='dead.host';        Host='dead.host';        Port=443; Reachable=$false; NotBefore=$null;              NotAfter=$null;             DaysRemaining=0;   NotYetValid=$false; Subject=$null; Issuer=$null; SelfSigned=$false; Source='endpoint' }
        [pscustomobject]@{ Name='File: static_cert.cer'; Host='File';        Port=0;   Reachable=$true;  NotBefore=$now.AddDays(-60);  NotAfter=$now.AddDays(120); DaysRemaining=120; NotYetValid=$false; Subject='CN=static.local'; Issuer='CN=static.local'; SelfSigned=$true; Source='file' }
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

$selfSignedSeverity = if ($config.selfSignedSeverity) { [string]$config.selfSignedSeverity } else { 'ok' }
if ($selfSignedSeverity -notin @('ok', 'warning', 'error')) { $selfSignedSeverity = 'ok' }

$certsDirRel = if ($config.certsDir) { $config.certsDir } else { 'certs' }
$certsDirPath = if ([System.IO.Path]::IsPathRooted($certsDirRel)) { $certsDirRel } else { Join-Path $PSScriptRoot $certsDirRel }

$targets = @($config.targets)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Certificate Expiry Agent"                 -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "API URL   : $apiUrl"
Write-Host "Project   : $projectName"
Write-Host "System    : $systemName"
Write-Host "Targets   : $($targets.Count)"
Write-Host "Certs Dir : $certsDirPath"
Write-Host "TTL       : $defaultTTL s"
Write-Host "Thresholds: warning <= ${warningDays}d, error <= ${errorDays}d"
Write-Host "Self-signed: reported as '$selfSignedSeverity'"
Write-Host ""

if ($DryRun)  { Write-Host "[DRY RUN MODE - No connections or API calls]" -ForegroundColor Yellow }
if ($MockRun) { Write-Host "[MOCK RUN MODE - Sending sample data to API]" -ForegroundColor Magenta }

if ($DryRun) {
    Write-Host ""
    Write-Host "--- Target Endpoints ---" -ForegroundColor Cyan
    foreach ($t in $targets) {
        $enabled = if ($null -ne $t.enabled) { [bool]$t.enabled } else { $true }
        if (-not $enabled) { continue }
        $port = if ($t.port) { [int]$t.port } else { 443 }
        $name = if ($t.name) { $t.name } else { $t.host }
        Write-Host "[DRY RUN] Would check TLS certificate for endpoint: $name ($($t.host):$port)"
    }

    Write-Host ""
    Write-Host "--- Static Certificate Files ---" -ForegroundColor Cyan
    if (Test-Path $certsDirPath) {
        $certFiles = Get-ChildItem -Path $certsDirPath -File | Where-Object { $_.Extension -in @('.cer', '.crt', '.pem', '.der', '.pfx') }
        foreach ($f in $certFiles) {
            Write-Host "[DRY RUN] Would inspect certificate file: $($f.Name)"
        }
    } else {
        Write-Host "[DRY RUN] Certificate directory does not exist: $certsDirPath"
    }

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Completed (dry run)."                     -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    exit 0
}

$reported = 0

if ($MockRun) {
    $mockChecks = Get-CertificateMockData
    foreach ($check in $mockChecks) {
        Process-AndReportCertificate -Check $check -ApiUrl $apiUrl -SystemName $systemName `
            -ProjectName $projectName -DefaultTTL $defaultTTL -WarningDays $warningDays `
            -ErrorDays $errorDays -SelfSignedSeverity $selfSignedSeverity
        $reported++
    }
}
else {
    $now = Get-Date

    # 1. Process target endpoints immediately
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
            $check = [pscustomobject]@{
                Name          = $name
                Host          = $targetHost
                Port          = $port
                Reachable     = $false
                NotBefore     = $null
                NotAfter      = $null
                DaysRemaining = 0
                NotYetValid   = $false
                Subject       = $null
                Issuer        = $null
                SelfSigned    = $false
                Source        = 'endpoint'
            }
        }
        else {
            $notBefore     = $cert.NotBefore
            $notAfter      = $cert.NotAfter
            $daysRemaining = [int][math]::Floor(($notAfter - $now).TotalDays)
            $notYetValid   = $notBefore -gt $now
            $selfSigned    = ($cert.Subject -eq $cert.Issuer)

            $check = [pscustomobject]@{
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
                SelfSigned    = $selfSigned
                Source        = 'endpoint'
            }
        }

        Process-AndReportCertificate -Check $check -ApiUrl $apiUrl -SystemName $systemName `
            -ProjectName $projectName -DefaultTTL $defaultTTL -WarningDays $warningDays `
            -ErrorDays $errorDays -SelfSignedSeverity $selfSignedSeverity
        $reported++
    }

    # 2. Process static certificate files immediately
    if (Test-Path $certsDirPath) {
        $certFiles = Get-ChildItem -Path $certsDirPath -File | Where-Object { $_.Extension -in @('.cer', '.crt', '.pem', '.der', '.pfx') }

        foreach ($file in $certFiles) {
            try {
                $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($file.FullName)
                $notBefore     = $cert.NotBefore
                $notAfter      = $cert.NotAfter
                $daysRemaining = [int][math]::Floor(($notAfter - $now).TotalDays)
                $notYetValid   = $notBefore -gt $now
                $selfSigned    = ($cert.Subject -eq $cert.Issuer)
                $displayName   = "File: $($file.Name)"

                $check = [pscustomobject]@{
                    Name          = $displayName
                    Host          = $file.Name
                    Port          = 0
                    Reachable     = $true
                    NotBefore     = $notBefore
                    NotAfter      = $notAfter
                    DaysRemaining = $daysRemaining
                    NotYetValid   = $notYetValid
                    Subject       = $cert.Subject
                    Issuer        = $cert.Issuer
                    SelfSigned    = $selfSigned
                    Source        = 'file'
                }
            }
            catch {
                Write-Warning "Failed to parse certificate file $($file.Name): $_"
                $check = [pscustomobject]@{
                    Name          = "File: $($file.Name)"
                    Host          = $file.Name
                    Port          = 0
                    Reachable     = $false
                    NotBefore     = $null
                    NotAfter      = $null
                    DaysRemaining = 0
                    NotYetValid   = $false
                    Subject       = $null
                    Issuer        = $null
                    SelfSigned    = $false
                    Source        = 'file'
                }
            }

            Process-AndReportCertificate -Check $check -ApiUrl $apiUrl -SystemName $systemName `
                -ProjectName $projectName -DefaultTTL $defaultTTL -WarningDays $warningDays `
                -ErrorDays $errorDays -SelfSignedSeverity $selfSignedSeverity
            $reported++
        }
    }
    else {
        Write-AgentLine -Message "Certificate directory not found: $certsDirPath" -Severity info
    }
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Completed. $reported certificate(s) reported." -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

#endregion

