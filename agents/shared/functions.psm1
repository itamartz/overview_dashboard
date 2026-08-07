<#
.SYNOPSIS
    Shared helper functions for Overview Dashboard PowerShell agents.

.DESCRIPTION
    Common functions used by all PowerShell agents. Import from an agent script with:

        Import-Module (Join-Path $PSScriptRoot '..\shared\functions.psm1') -Force

    Exported functions:
      - Send-ToApi              Posts a component payload to the dashboard API
      - Get-CyberArkCredential  Retrieves credentials from CyberArk CCP
      - Get-EncryptedCredential Reads a DPAPI-encrypted password file
      - Resolve-Credential      Dispatches to the configured credential method
      - Get-X509Certificate2Web Fetches the TLS certificate from a remote host
      - Install-ModuleIfNeeded  Installs and imports a required PowerShell module
#>

function Send-ToApi {
    <#
    .SYNOPSIS
        Sends a component payload to the Overview Dashboard API.

    .DESCRIPTION
        Two modes:

        Fields mode (default) - builds the payload from individual fields.
        A deterministic component Id is generated with MD5 over
        "SystemName|ProjectName|Name|Metric" (Database is included between
        Name and Metric when supplied). The request body is:

            {
              "systemName":  "<SystemName>",
              "projectName": "<ProjectName>",
              "payload":     "{\"Id\":\"<md5>\",\"Name\":\"...\",\"Metric\":\"...\",\"Severity\":\"...\",\"Status\":\"...\",\"TTL\":123,...extra fields...}"
            }

        Returns $true on success, $false on failure.

        RawPayload mode - sends a caller-built payload object as-is (used by the
        VMware agent). Does not generate an Id and does not return a value.

    .PARAMETER ExtraData
        Optional hashtable or PSObject whose properties are merged into the
        payload (existing keys are not overwritten). Alias: ExtraFields.

    .PARAMETER DryRun
        Prints the JSON body that would be sent instead of calling the API.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Fields')]
    param(
        [string]$ApiUrl,
        [string]$SystemName,
        [string]$ProjectName,

        [Parameter(ParameterSetName = 'Fields')][string]$Name,
        [Parameter(ParameterSetName = 'Fields')][string]$Metric,
        [Parameter(ParameterSetName = 'Fields')][string]$Severity,
        [Parameter(ParameterSetName = 'Fields')][string]$Status,
        [Parameter(ParameterSetName = 'Fields')][int]$TTL,
        [Parameter(ParameterSetName = 'Fields')][string]$Database,
        [Parameter(ParameterSetName = 'Fields')][Alias('ExtraFields')][object]$ExtraData,

        [Parameter(ParameterSetName = 'RawPayload', Mandatory)][object]$Payload,

        [switch]$DryRun
    )

    if ($PSCmdlet.ParameterSetName -eq 'RawPayload') {
        $body = @{
            systemName  = $SystemName
            projectName = $ProjectName
            payload     = $Payload
        }
        $jsonBody = $body | ConvertTo-Json -Depth 10

        if ($DryRun) {
            Write-Host "[DRY-RUN] Would send to $ApiUrl" -ForegroundColor Cyan
            Write-Host $jsonBody -ForegroundColor Gray
            return
        }

        try {
            Invoke-RestMethod -Uri $ApiUrl -Method Post -Body $jsonBody -ContentType "application/json" -TimeoutSec 15 | Out-Null
            $payloadName = if ($Payload -is [string]) { 'payload' } else { $Payload.Name }
            Write-Host "Successfully posted $payloadName to $ProjectName" -ForegroundColor Green
        }
        catch {
            Write-Error "Failed to post to API: $_"
        }
        return
    }

    # Deterministic component Id: same metric always maps to the same Id
    $idSource = if ($Database) {
        "$SystemName|$ProjectName|$Name|$Database|$Metric"
    } else {
        "$SystemName|$ProjectName|$Name|$Metric"
    }
    $md5 = [System.Security.Cryptography.MD5]::Create()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($idSource)
    $hash = $md5.ComputeHash($bytes)
    $componentId = [System.BitConverter]::ToString($hash) -replace '-', ''

    $componentPayload = [ordered]@{
        Id   = $componentId
        Name = $Name
    }
    if ($Database) { $componentPayload.Database = $Database }
    $componentPayload.Metric   = $Metric
    $componentPayload.Severity = $Severity
    $componentPayload.Status   = $Status
    $componentPayload.TTL      = $TTL

    if ($null -ne $ExtraData) {
        if ($ExtraData -is [System.Collections.IDictionary]) {
            foreach ($key in $ExtraData.Keys) {
                if (-not $componentPayload.Contains($key)) {
                    $componentPayload[$key] = $ExtraData[$key]
                }
            }
        }
        else {
            foreach ($prop in $ExtraData.psobject.Properties) {
                if (-not $componentPayload.Contains($prop.Name)) {
                    $componentPayload[$prop.Name] = $prop.Value
                }
            }
        }
    }

    $body = @{
        systemName  = $SystemName
        projectName = $ProjectName
        payload     = ($componentPayload | ConvertTo-Json -Compress -Depth 10)
    } | ConvertTo-Json -Compress

    $color = switch ($Severity) {
        'ok'      { 'Green' }
        'warning' { 'Yellow' }
        'error'   { 'Red' }
        default   { 'Gray' }
    }

    if ($DryRun) {
        Write-Host ("[DRY RUN] {0,-28} {1,-8} {2}" -f $Name, $Severity.ToUpper(), $Status) -ForegroundColor $color
        Write-Host $body -ForegroundColor Gray
        return $true
    }

    try {
        Invoke-RestMethod -Uri $ApiUrl -Method Post -Body $body -ContentType "application/json" -ErrorAction Stop | Out-Null
        Write-Host ("  {0,-28} {1,-8} {2}" -f $Name, $Severity.ToUpper(), $Status) -ForegroundColor $color
        return $true
    }
    catch {
        Write-Warning "Failed to send to API: $_"
        Write-Host ("  {0,-28} {1,-8} {2} (POST FAILED)" -f $Name, $Severity.ToUpper(), $Status) -ForegroundColor Red
        return $false
    }
}


function Get-CyberArkCredential {
    <#
    .SYNOPSIS
        Retrieves a credential from CyberArk Central Credential Provider (CCP).
    #>
    param(
        [string]$CcpUrl,
        [string]$AppId,
        [string]$Safe,
        [string]$ObjectName,
        [bool]$VerifySsl = $true,
        [int]$TimeoutSeconds = 10
    )

    $queryParams = @(
        "AppID=$([uri]::EscapeDataString($AppId))",
        "Safe=$([uri]::EscapeDataString($Safe))",
        "Object=$([uri]::EscapeDataString($ObjectName))"
    )
    $fullUrl = "$CcpUrl`?$($queryParams -join '&')"

    $invokeParams = @{
        Uri         = $fullUrl
        Method      = 'GET'
        ContentType = 'application/json'
        TimeoutSec  = $TimeoutSeconds
        ErrorAction = 'Stop'
    }

    # SkipCertificateCheck only exists on PowerShell 7+
    if (-not $VerifySsl -and $PSVersionTable.PSVersion.Major -ge 7) {
        $invokeParams.SkipCertificateCheck = $true
    }

    try {
        $response = Invoke-RestMethod @invokeParams
        return @{
            Username = $response.UserName
            Password = $response.Content
            Address  = $response.Address
            Success  = $true
        }
    }
    catch {
        Write-Warning "CyberArk CCP lookup failed for '$ObjectName' in safe '$Safe': $_"
        return @{ Username = ""; Password = ""; Address = ""; Success = $false }
    }
}

function Get-EncryptedCredential {
    <#
    .SYNOPSIS
        Reads a password from a DPAPI-encrypted file (created with
        ConvertFrom-SecureString on the same machine/user).
    #>
    param(
        [string]$EncryptedFilePath,
        [string]$Username
    )

    if (-not (Test-Path $EncryptedFilePath)) {
        Write-Warning "Encrypted credential file not found: $EncryptedFilePath"
        return @{ Username = $Username; Password = ""; Success = $false }
    }

    try {
        $secureString = Get-Content $EncryptedFilePath | ConvertTo-SecureString
        $credential = New-Object System.Management.Automation.PSCredential($Username, $secureString)
        return @{
            Username = $Username
            Password = $credential.GetNetworkCredential().Password
            Success  = $true
        }
    }
    catch {
        Write-Warning "Failed to decrypt credential file '$EncryptedFilePath': $_"
        return @{ Username = $Username; Password = ""; Success = $false }
    }
}

function Resolve-Credential {
    <#
    .SYNOPSIS
        Resolves credentials via the configured method: cyberark, encrypted, or plaintext.

    .PARAMETER Target
        Object holding cyberarkSafe / cyberarkObject / encryptedPasswordFile /
        username / password properties (a target entry or the whole config).
        Alias: Config.

    .PARAMETER BasePath
        Directory used to resolve a relative encryptedPasswordFile path.
        Defaults to the calling script's directory.
    #>
    param(
        [string]$Method,
        [Alias('Config')][object]$Target,
        [object]$CyberArkConfig,
        [string]$BasePath
    )

    switch ($Method.ToLower()) {
        'cyberark' {
            return Get-CyberArkCredential `
                -CcpUrl $CyberArkConfig.ccpUrl `
                -AppId $CyberArkConfig.appId `
                -Safe $Target.cyberarkSafe `
                -ObjectName $Target.cyberarkObject `
                -VerifySsl $CyberArkConfig.verifySsl `
                -TimeoutSeconds $CyberArkConfig.timeoutSeconds
        }
        'encrypted' {
            if (-not $BasePath) {
                # Resolve relative to the calling script, not this module
                $BasePath = Split-Path -Parent $MyInvocation.PSCommandPath
            }
            $encPath = Join-Path $BasePath $Target.encryptedPasswordFile
            return Get-EncryptedCredential -EncryptedFilePath $encPath -Username $Target.username
        }
        default {
            return @{
                Username = $Target.username
                Password = $Target.password
                Success  = ($null -ne $Target.password -and $Target.password -ne "")
            }
        }
    }
}

function Get-X509Certificate2Web {
    <#
    .SYNOPSIS
        Retrieves the TLS certificate presented by a remote host.
        Returns $null when the connection or handshake fails.
    #>
    param(
        [string]$ComputerName,
        [Alias('HttpsPort')][int]$Port = 443
    )

    try {
        $tcpClient = [System.Net.Sockets.TcpClient]::new($ComputerName, $Port)
        $sslStream = [System.Net.Security.SslStream]::new($tcpClient.GetStream(), $false, { param($s, $c, $ch, $e) return $true })
        $sslStream.AuthenticateAsClient($ComputerName)
        $cert = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($sslStream.RemoteCertificate)
        $sslStream.Dispose()
        $tcpClient.Dispose()
        return $cert
    }
    catch {
        return $null
    }
}

function Install-ModuleIfNeeded {
    <#
    .SYNOPSIS
        Ensures a PowerShell module is installed and imported.
        Returns $true when the module is available, $false otherwise.
    #>
    param(
        [Parameter(Mandatory)][string]$ModuleName
    )

    if (-not (Get-Module -ListAvailable -Name $ModuleName)) {
        Write-Host "$ModuleName module not found. Attempting to install..." -ForegroundColor Yellow
        try {
            Install-Module -Name $ModuleName -Force -Scope CurrentUser -AllowClobber
            Import-Module $ModuleName -Force
            Write-Host "$ModuleName installed successfully." -ForegroundColor Green
            return $true
        }
        catch {
            Write-Error "Failed to install $ModuleName module: $_"
            Write-Error "Please run: Install-Module -Name $ModuleName -Force -Scope CurrentUser"
            return $false
        }
    }
    Import-Module $ModuleName -Force
    return $true
}

Export-ModuleMember -Function Send-ToApi, Get-CyberArkCredential, Get-EncryptedCredential, Resolve-Credential, Get-X509Certificate2Web, Install-ModuleIfNeeded
