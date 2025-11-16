# Deployment Guide - IT Infrastructure Dashboard

## Part 1: Upload to GitHub

Since I cannot directly push to GitHub from this environment, follow these steps:

### Step 1: Download the Project Archive

1. Download the file: `IT-Dashboard-Complete.tar.gz`
2. Extract it on your Windows machine using 7-Zip or similar tool

### Step 2: Upload to GitHub

**Option A: Using Git Command Line**

```powershell
# Navigate to extracted folder
cd DashboardSystem

# Initialize (already done, but verify)
git remote -v

# If no remote, add it:
git remote add origin https://github.com/itamartz/overview_dashboard.git

# Push to GitHub
git push -u origin main
```

**Option B: Using GitHub Desktop**

1. Open GitHub Desktop
2. File → Add Local Repository
3. Select the `DashboardSystem` folder
4. Click "Publish repository"
5. Choose your account and repository name

**Option C: Manual Upload via GitHub Web**

1. Go to https://github.com/itamartz/overview_dashboard
2. Click "uploading an existing file"
3. Drag and drop all folders/files
4. Commit changes

---

## Part 2: Deploy to IIS (Air-Gapped Environment)

### Prerequisites on Target Server

1. **Windows Server 2012 R2+** with IIS installed
2. **.NET 8.0 Hosting Bundle** (download offline installer before going to air-gap)
   - Download from: https://dotnet.microsoft.com/download/dotnet/8.0
   - Install file: `dotnet-hosting-8.0.x-win.exe`

### Step-by-Step Deployment

#### 1. Build the Projects (On Development Machine with Internet)

```powershell
# Clone from GitHub
git clone https://github.com/itamartz/overview_dashboard.git
cd overview_dashboard

# Publish API (self-contained for air-gap)
cd DashboardAPI
dotnet publish -c Release -r win-x64 --self-contained true /p:PublishSingleFile=false -o ..\Publish\API

# Publish Blazor Dashboard (self-contained)
cd ..\BlazorDashboard
dotnet publish -c Release -r win-x64 --self-contained true /p:PublishSingleFile=false -o ..\Publish\Dashboard

# Create database with migrations
cd ..\DashboardAPI
dotnet ef database update
```

#### 2. Copy Files to Production Server

Transfer these folders to your air-gapped server:

```
Publish/
├── API/              # Copy to: C:\inetpub\DashboardAPI
├── Dashboard/        # Copy to: C:\inetpub\BlazorDashboard
└── database.db       # From DashboardAPI folder
```

#### 3. Setup IIS (Run PowerShell as Administrator)

```powershell
# Import IIS module
Import-Module WebAdministration

# Create Application Pools
New-WebAppPool -Name "DashboardAPI_Pool"
Set-ItemProperty IIS:\AppPools\DashboardAPI_Pool -Name "managedRuntimeVersion" -Value ""
Set-ItemProperty IIS:\AppPools\DashboardAPI_Pool -Name "startMode" -Value "AlwaysRunning"

New-WebAppPool -Name "BlazorDashboard_Pool"
Set-ItemProperty IIS:\AppPools\BlazorDashboard_Pool -Name "managedRuntimeVersion" -Value ""
Set-ItemProperty IIS:\AppPools\BlazorDashboard_Pool -Name "startMode" -Value "AlwaysRunning"

# Create Websites
New-WebSite -Name "DashboardAPI" `
    -Port 5000 `
    -PhysicalPath "C:\inetpub\DashboardAPI" `
    -ApplicationPool "DashboardAPI_Pool"

New-WebSite -Name "BlazorDashboard" `
    -Port 5001 `
    -PhysicalPath "C:\inetpub\BlazorDashboard" `
    -ApplicationPool "BlazorDashboard_Pool"

# Enable WebSockets (required for SignalR)
Set-WebConfigurationProperty `
    -PSPath "IIS:\Sites\BlazorDashboard" `
    -Filter "system.webServer/webSocket" `
    -Name "enabled" `
    -Value "True"
```

#### 4. Configure Firewall

```powershell
# Allow inbound traffic
New-NetFirewallRule -DisplayName "Dashboard API" -Direction Inbound -LocalPort 5000 -Protocol TCP -Action Allow
New-NetFirewallRule -DisplayName "Blazor Dashboard" -Direction Inbound -LocalPort 5001 -Protocol TCP -Action Allow
```

#### 5. Update Configuration Files

**C:\inetpub\BlazorDashboard\appsettings.json**

```json
{
  "ApiSettings": {
    "BaseUrl": "http://localhost:5000"
  },
  "RefreshInterval": 30000
}
```

**C:\inetpub\DashboardAPI\appsettings.json**

```json
{
  "ConnectionStrings": {
    "DefaultConnection": "Data Source=C:\\inetpub\\Shared\\dashboard.db"
  },
  "AllowedHosts": "*",
  "Cors": {
    "AllowedOrigins": [
      "http://localhost:5001",
      "http://your-dashboard-server:5001"
    ]
  }
}
```

#### 6. Setup Database Location

```powershell
# Create shared folder
New-Item -ItemType Directory -Path "C:\inetpub\Shared" -Force

# Copy database
Copy-Item ".\database.db" -Destination "C:\inetpub\Shared\dashboard.db"

# Set permissions
icacls "C:\inetpub\Shared" /grant "IIS AppPool\DashboardAPI_Pool:(OI)(CI)M"
icacls "C:\inetpub\Shared" /grant "IIS AppPool\BlazorDashboard_Pool:(OI)(CI)R"
```

#### 7. Start Services

```powershell
# Start websites
Start-WebSite -Name "DashboardAPI"
Start-WebSite -Name "BlazorDashboard"

# Verify they're running
Get-WebSite | Select Name, State, Bindings
```

#### 8. Test the Deployment

1. **Test API:**
   ```powershell
   Invoke-WebRequest -Uri "http://localhost:5000/api/dashboard/systems"
   ```

2. **Open Dashboard:**
   - Navigate to: `http://localhost:5001`
   - Or: `http://server-name:5001`

---

## Part 3: Install PowerShell Agents on Monitored Servers

### On Each Server You Want to Monitor:

```powershell
# Copy PowerShellAgent folder to server
Copy-Item -Recurse PowerShellAgent C:\Tools\DashboardAgent

# Install as scheduled task
cd C:\Tools\DashboardAgent
.\Install-MetricsAgent.ps1 `
    -ApiUrl "http://dashboard-server:5000" `
    -InstallPath "C:\Tools\DashboardAgent" `
    -IntervalMinutes 5
```

### Test Agent Manually:

```powershell
# Import the module
Import-Module .\DashboardMetrics.psm1

# Send test metric
Send-ComponentMetric `
    -ApiUrl "http://dashboard-server:5000/api/metrics" `
    -ComponentId "COMP001" `
    -Severity "ok" `
    -Value "45" `
    -Metric "%" `
    -Description "CPU usage is normal"
```

---

## Part 4: Verify Everything Works

### Checklist:

- [ ] API responds at `http://server:5000/api/dashboard/systems`
- [ ] Dashboard loads at `http://server:5001`
- [ ] SignalR connection established (check browser console - no errors)
- [ ] PowerShell agent can send metrics
- [ ] Dashboard updates when agent sends new data
- [ ] Database file is accessible and not locked

### Common Issues:

**1. "HTTP Error 500.19" - Configuration Error**
```powershell
# Install URL Rewrite Module (if needed)
# Download from: https://www.iis.net/downloads/microsoft/url-rewrite
```

**2. "Database is Locked"**
```powershell
# Check which process has the file open
handle.exe dashboard.db

# Stop IIS
iisreset /stop

# Restart
iisreset /start
```

**3. "SignalR Not Connecting"**
```powershell
# Verify WebSockets enabled
Get-WindowsFeature -Name Web-WebSockets
Install-WindowsFeature -Name Web-WebSockets
```

**4. "CORS Error in Browser Console"**
```
Update Cors.AllowedOrigins in API appsettings.json
to include your dashboard server URL
```

---

## Part 5: Maintenance

### Update Application:

```powershell
# Stop IIS
iisreset /stop

# Backup database
Copy-Item "C:\inetpub\Shared\dashboard.db" "C:\Backups\dashboard_$(Get-Date -Format 'yyyyMMdd').db"

# Replace files
Copy-Item -Recurse ".\NewPublish\API\*" "C:\inetpub\DashboardAPI\" -Force
Copy-Item -Recurse ".\NewPublish\Dashboard\*" "C:\inetpub\BlazorDashboard\" -Force

# Start IIS
iisreset /start
```

### Backup Database Regularly:

```powershell
# Schedule this script to run daily
$date = Get-Date -Format "yyyyMMdd"
Copy-Item "C:\inetpub\Shared\dashboard.db" "C:\Backups\dashboard_$date.db"
```

### Monitor Logs:

```powershell
# IIS Logs
Get-Content "C:\inetpub\logs\LogFiles\W3SVC1\u_ex*.log" -Tail 50

# Application Logs (if configured)
Get-Content "C:\inetpub\DashboardAPI\logs\*.log" -Tail 50
```

---

## Security Recommendations

1. **Enable Windows Authentication in IIS:**
   ```powershell
   Set-WebConfigurationProperty `
       -Filter "/system.webServer/security/authentication/windowsAuthentication" `
       -Name "enabled" `
       -Value "True" `
       -PSPath "IIS:\Sites\BlazorDashboard"
   ```

2. **Use HTTPS with SSL Certificate:**
   ```powershell
   # Bind SSL certificate to site
   New-WebBinding -Name "BlazorDashboard" -Protocol https -Port 443
   ```

3. **Restrict API Access:**
   - Use firewall rules to limit which servers can call the API
   - Consider IP whitelisting

4. **Database Encryption:**
   - Use BitLocker on the volume containing the database
   - Or use SQLCipher for SQLite encryption

---

## Support

For issues:
1. Check browser console (F12) for JavaScript errors
2. Review IIS logs
3. Check Windows Event Viewer → Application logs
4. Verify database permissions

**Your dashboard is now ready for production use!** 🎉
