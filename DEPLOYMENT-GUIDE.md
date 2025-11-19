# Deployment Guide - Overview Dashboard

This guide covers deploying the Overview Dashboard using Docker or as a Windows Service.

## Deployment Options

1. **Docker Deployment (Recommended)** - Automated via GitHub Actions
2. **Windows Service** - Traditional Windows deployment

---

## Option 1: Docker Deployment (Recommended)

For complete Docker deployment instructions, see **[DOCKER-DEPLOYMENT.md](DOCKER-DEPLOYMENT.md)**.

### Quick Summary:

#### Prerequisites:
- GCP instance (or any server) with Docker installed
- GitHub repository with Actions enabled
- SSH access to deployment server

#### Setup Steps:

1. **Configure GitHub Secrets:**
   - `GCP_HOST` - Server IP address
   - `GCP_USERNAME` - SSH username
   - `GCP_SSH_KEY` - Private SSH key

2. **Push to Main Branch:**
   ```bash
   git push origin main
   ```

3. **GitHub Actions Workflow:**
   - Automatically builds Docker image
   - Transfers to your server
   - Deploys container with persistent storage
   - Accessible at `http://[YOUR_SERVER_IP]`

#### Container Details:
- **Ports:** 80:8080 (HTTP), 443:8081 (HTTPS)
- **Data Volume:** `/var/overview-dashboard/data` → `/app/Database`
- **Restart Policy:** `unless-stopped`

---

## Option 2: Windows Service Deployment

### Prerequisites:

- Windows Server 2012 R2 or newer
- .NET 9.0 Runtime
- Administrator access

### Step 1: Publish the Application

```powershell
# Navigate to project root
cd overview_dashboard

# Publish for Windows
dotnet publish OverviewDashboard/OverviewDashboard.csproj `
    -c Release `
    -r win-x64 `
    --self-contained true `
    -o ./Publish
```

### Step 2: Copy to Server

Transfer the `Publish` folder to your server (e.g., `C:\Services\OverviewDashboard`)

### Step 3: Install as Windows Service

**Option A: Using PowerShell Script**

```powershell
# Run the included script as Administrator
.\Deploy-WindowsService.ps1
```

**Option B: Manual Installation**

```powershell
# Create the service
sc create OverviewDashboard `
    binPath="C:\Services\OverviewDashboard\OverviewDashboard.exe" `
    start=auto `
    DisplayName="Overview Dashboard"

# Start the service
sc start OverviewDashboard

# Verify it's running
sc query OverviewDashboard
```

### Step 4: Configure Firewall

```powershell
# Allow HTTP traffic
New-NetFirewallRule `
    -DisplayName "Overview Dashboard" `
    -Direction Inbound `
    -LocalPort 5203 `
    -Protocol TCP `
    -Action Allow
```

### Step 5: Access the Dashboard

Navigate to: `http://[SERVER_IP]:5203`

---

## Configuration

### Database Location

Edit `appsettings.json`:

```json
{
  "ConnectionStrings": {
    "DefaultConnection": "Data Source=C:\\Services\\OverviewDashboard\\Database\\dashboard.db"
  }
}
```

### Change Port

Edit `appsettings.json` or use command line:

```powershell
# Via environment variable
$env:ASPNETCORE_URLS="http://localhost:8080"

# Or in appsettings.json
{
  "Kestrel": {
    "Endpoints": {
      "Http": {
        "Url": "http://localhost:8080"
      }
    }
  }
}
```

### Logging Configuration

```json
{
  "Logging": {
    "LogLevel": {
      "Default": "Information",
      "Microsoft.AspNetCore": "Warning"
    }
  }
}
```

---

## Updating the Application

### Docker Deployment:

Simply push changes to GitHub:

```bash
git add .
git commit -m "Update application"
git push origin main
```

GitHub Actions will automatically rebuild and redeploy.

### Windows Service:

```powershell
# Stop the service
sc stop OverviewDashboard

# Backup database
Copy-Item "C:\Services\OverviewDashboard\Database\dashboard.db" `
    "C:\Backups\dashboard_$(Get-Date -Format 'yyyyMMdd').db"

# Replace files
Copy-Item -Recurse ".\Publish\*" "C:\Services\OverviewDashboard\" -Force

# Start the service
sc start OverviewDashboard
```

---

## Troubleshooting

### Service Won't Start

```powershell
# Check Windows Event Viewer
Get-EventLog -LogName Application -Source "Overview Dashboard" -Newest 10

# Check service status
sc query OverviewDashboard

# Try running manually to see errors
cd C:\Services\OverviewDashboard
.\OverviewDashboard.exe
```

### Database Locked

```powershell
# Stop the service
sc stop OverviewDashboard

# Check for file locks
# Use Process Explorer or similar tool

# Restart
sc start OverviewDashboard
```

### Port Already in Use

```powershell
# Find what's using the port
netstat -ano | findstr :5203

# Kill the process (use PID from above)
taskkill /PID [PID] /F

# Or change the port in appsettings.json
```

### Docker Container Issues

```bash
# SSH into server
ssh user@server

# Check container status
docker ps -a | grep overview-dashboard

# View logs
docker logs overview-dashboard

# Restart container
docker restart overview-dashboard

# Remove and redeploy
docker stop overview-dashboard
docker rm overview-dashboard
# Push to GitHub to trigger redeployment
```

---

## Security Best Practices

### 1. Use HTTPS

**For Docker:**
- Configure reverse proxy (nginx, Caddy) with SSL
- Use Let's Encrypt for certificates

**For Windows Service:**
- Configure Kestrel with SSL certificate
- Or use IIS as reverse proxy

### 2. Authentication

Add authentication middleware in `Program.cs`:

```csharp
builder.Services.AddAuthentication(/* your auth scheme */);
app.UseAuthentication();
app.UseAuthorization();
```

### 3. Firewall Rules

Restrict access to known IP addresses:

```powershell
# Windows Firewall
New-NetFirewallRule `
    -DisplayName "Overview Dashboard - Restricted" `
    -Direction Inbound `
    -LocalPort 5203 `
    -Protocol TCP `
    -Action Allow `
    -RemoteAddress "192.168.1.0/24"
```

### 4. Database Backup

**Docker:**
```bash
# Automated backup script
docker exec overview-dashboard cp /app/Database/dashboard.db /app/Database/backup_$(date +%Y%m%d).db
```

**Windows:**
```powershell
# Scheduled task to backup daily
$date = Get-Date -Format "yyyyMMdd"
Copy-Item "C:\Services\OverviewDashboard\Database\dashboard.db" `
    "C:\Backups\dashboard_$date.db"
```

---

## Monitoring

### Check Application Health

```powershell
# Test API endpoint
Invoke-RestMethod -Uri "http://localhost:5203/api/components"

# Check Swagger
Start-Process "http://localhost:5203/swagger"
```

### View Logs

**Docker:**
```bash
docker logs --tail 100 -f overview-dashboard
```

**Windows Service:**
- Check Windows Event Viewer
- Application logs (if configured in appsettings.json)

---

## Performance Tuning

### Database Optimization

For production with many components, consider:
- Regular VACUUM operations on SQLite
- Or migrate to SQL Server/PostgreSQL

### Kestrel Configuration

```json
{
  "Kestrel": {
    "Limits": {
      "MaxConcurrentConnections": 100,
      "MaxConcurrentUpgradedConnections": 100
    }
  }
}
```

---

## Next Steps

1. ✅ Deploy the application
2. ✅ Configure firewall rules
3. ✅ Set up HTTPS (recommended)
4. ✅ Configure authentication (if needed)
5. ✅ Set up automated backups
6. ✅ Monitor application health

For Docker-specific deployment details, see **[DOCKER-DEPLOYMENT.md](DOCKER-DEPLOYMENT.md)**.

---

**Your dashboard is now ready for production use!** 🎉
