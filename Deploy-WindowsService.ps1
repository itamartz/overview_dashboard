#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Deploys Overview Dashboard as a Windows Service
.DESCRIPTION
    This script:
    1. Adds Windows Service support to the project
    2. Publishes the application
    3. Installs and starts it as a Windows Service
.PARAMETER TargetPath
    Installation directory (default: C:\Services\OverviewDashboard)
.PARAMETER ServiceName
    Windows Service name (default: OverviewDashboard)
.PARAMETER Port
    HTTP port to listen on (default: 5000)
.EXAMPLE
    .\Deploy-WindowsService.ps1
.EXAMPLE
    .\Deploy-WindowsService.ps1 -TargetPath "D:\Apps\Dashboard" -Port 8080
#>

param(
    [string]$TargetPath = "C:\Services\OverviewDashboard",
    [string]$ServiceName = "OverviewDashboard",
    [int]$Port = 5000
)

$ErrorActionPreference = "Stop"
# Step 1: Stop existing service if running
Write-Host "[1/4] Checking for existing service..." -ForegroundColor Yellow
$existingService = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($existingService) {
    Write-Host "   [WARN] Service exists, stopping..." -ForegroundColor Yellow
    Stop-Service -Name $ServiceName -Force
    Start-Sleep -Seconds 3
    Write-Host "   [OK] Service stopped" -ForegroundColor Green
}
else {
    Write-Host "   [OK] No existing service found" -ForegroundColor Green
}

# Step 2: Install application files
Write-Host "[2/4] Installing application files..." -ForegroundColor Yellow
Write-Host "   Source:      $PSScriptRoot" -ForegroundColor Gray
Write-Host "   Destination: $TargetPath" -ForegroundColor Gray

# Create target directory if it doesn't exist
if (!(Test-Path $TargetPath)) {
    New-Item -ItemType Directory -Path $TargetPath -Force | Out-Null
}

# Copy files
$exclude = @("Deploy-WindowsService.ps1", "*.pdb")
Get-ChildItem -Path $PSScriptRoot -Exclude $exclude | Copy-Item -Destination $TargetPath -Recurse -Force

Write-Host "   [OK] Files copied successfully" -ForegroundColor Green

# Step 3: Configure appsettings for service
Write-Host "[3/4] Configuring application..." -ForegroundColor Yellow
$appsettingsPath = "$TargetPath\appsettings.json"
$appsettings = @{
    Logging      = @{
        LogLevel = @{
            Default                = "Information"
            "Microsoft.AspNetCore" = "Warning"
        }
    }
    AllowedHosts = "*"
    Kestrel      = @{
        Endpoints = @{
            Http = @{
                Url = "http://0.0.0.0:$Port"
            }
        }
    }
} | ConvertTo-Json -Depth 10

Set-Content -Path $appsettingsPath -Value $appsettings
Write-Host "   [OK] Configured to listen on port $Port" -ForegroundColor Green

# Step 4: Install and start service
Write-Host "[4/4] Installing Windows Service..." -ForegroundColor Yellow

if ($existingService) {
    Write-Host "   Updating existing service..." -ForegroundColor Gray
    sc.exe config $ServiceName binPath= "$TargetPath\OverviewDashboard.exe" | Out-Null
}
else {
    Write-Host "   Creating new service..." -ForegroundColor Gray
    New-Service -Name $ServiceName `
        -BinaryPathName "$TargetPath\OverviewDashboard.exe" `
        -DisplayName "Overview Dashboard Service" `
        -Description "IT Infrastructure Overview Dashboard - Monitors system components and displays real-time status" `
        -StartupType Automatic | Out-Null
}

# Configure service recovery
sc.exe failure $ServiceName reset=86400 actions=restart/60000/restart/60000/restart/60000 | Out-Null

# Configure firewall
Write-Host "   Configuring firewall..." -ForegroundColor Gray
$firewallRule = Get-NetFirewallRule -DisplayName "Overview Dashboard" -ErrorAction SilentlyContinue
if (!$firewallRule) {
    New-NetFirewallRule -DisplayName "Overview Dashboard" `
        -Direction Inbound `
        -Protocol TCP `
        -LocalPort $Port `
        -Action Allow | Out-Null
    Write-Host "   [OK] Firewall rule created" -ForegroundColor Green
}
else {
    Write-Host "   [OK] Firewall rule already exists" -ForegroundColor Green
}

# Start service
Write-Host "   Starting service..." -ForegroundColor Gray
Start-Service -Name $ServiceName
Start-Sleep -Seconds 2

# Verify service is running
$service = Get-Service -Name $ServiceName
if ($service.Status -eq 'Running') {
    Write-Host "   [OK] Service started successfully" -ForegroundColor Green
}
else {
    Write-Host "   [ERROR] Service failed to start (Status: $($service.Status))" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "=== Deployment Complete ===" -ForegroundColor Green
Write-Host ""
Write-Host "Service Details:" -ForegroundColor Cyan
Write-Host "  Name:        $ServiceName"
Write-Host "  Status:      $($service.Status)"
Write-Host "  Start Type:  $($service.StartType)"
Write-Host "  Location:    $TargetPath"
Write-Host "  URL:         http://localhost:$Port"
Write-Host ""
Write-Host "Management Commands:" -ForegroundColor Cyan
Write-Host "  Stop:        Stop-Service -Name $ServiceName"
Write-Host "  Start:       Start-Service -Name $ServiceName"
Write-Host "  Restart:     Restart-Service -Name $ServiceName"
Write-Host "  Status:      Get-Service -Name $ServiceName"
Write-Host "  Uninstall:   sc.exe delete $ServiceName"
Write-Host ""
Write-Host "Access the dashboard at: http://localhost:$Port" -ForegroundColor Green
