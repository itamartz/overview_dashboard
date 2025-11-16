# IT Dashboard - Quick Reference Guide

## 📦 What's in the Package?

```
IT-Dashboard-Complete.tar.gz
│
├── DashboardAPI/           → REST API (receives metrics from agents)
├── BlazorDashboard/        → Web dashboard (real-time display)
├── PowerShellAgent/        → Scripts to collect server metrics
├── Database/               → SQL reference scripts
├── Deployment/             → IIS setup scripts
└── README.md               → Full documentation
```

---

## 🚀 5-Minute Quick Start (Development)

### 1. Extract & Build

```powershell
# Extract the archive
tar -xzf IT-Dashboard-Complete.tar.gz
cd DashboardSystem

# Build projects
cd DashboardAPI
dotnet build

cd ..\BlazorDashboard
dotnet build
```

### 2. Create Database

```powershell
cd DashboardAPI
dotnet ef database update
# This creates: dashboard.db with sample data
```

### 3. Run Both Applications

**Terminal 1:**
```powershell
cd DashboardAPI
dotnet run --urls "http://localhost:5000"
```

**Terminal 2:**
```powershell
cd BlazorDashboard
dotnet run --urls "http://localhost:5001"
```

### 4. Open Browser

Navigate to: **http://localhost:5001**

You should see the dashboard with sample data!

---

## 📊 Understanding the Dashboard

### Hierarchy:
```
Systems (Top Level)
  └── Projects (Groups)
       └── Components (Individual Items)
            └── Metrics (Status Data)
```

### Sample Data Included:
- **3 Systems:** Production, Development, Database Cluster
- **7 Projects:** Web Servers, App Servers, Load Balancers, etc.
- **28 Components:** Various servers and services
- **Metrics:** CPU, Memory, Disk, Service status

### Severity Levels:
- 🟢 **OK** - Everything normal
- 🟡 **Warning** - Attention needed
- 🔴 **Error** - Critical issue
- 🔵 **Info** - Informational only

---

## 🔧 PowerShell Agent - Send Metrics

### Quick Test:

```powershell
cd PowerShellAgent

# Import module
Import-Module .\DashboardMetrics.psm1

# Send a test metric
Send-ComponentMetric `
    -ApiUrl "http://localhost:5000/api/metrics" `
    -ComponentId "COMP001" `
    -Severity "warning" `
    -Value "85" `
    -Metric "%" `
    -Description "CPU usage elevated"
```

### Check Dashboard:

Refresh browser - you should see COMP001 updated with warning status!

---

## 📁 Project Files Explained

### DashboardAPI/

**Key Files:**
- `Program.cs` - Application entry (old style, not minimal API)
- `Startup.cs` - Service configuration
- `Data/DashboardDbContext.cs` - Entity Framework database context
- `Models/` - Database entities (System, Project, Component, Metric)
- `Controllers/MetricsController.cs` - Receives data from agents
- `Controllers/DashboardController.cs` - Serves data to dashboard
- `appsettings.json` - Configuration (database path, CORS, etc.)

**Database:**
- Type: SQLite (file-based, no server needed)
- File: `dashboard.db`
- Migrations: EF Core migrations included

### BlazorDashboard/

**Key Files:**
- `Program.cs` - Blazor Server entry
- `Startup.cs` - SignalR configuration
- `Pages/Index.razor` - Main dashboard page
- `Services/DashboardService.cs` - API communication
- `Models/DashboardModels.cs` - View models
- `wwwroot/css/app.css` - Styling

### PowerShellAgent/

**Key Files:**
- `DashboardMetrics.psm1` - PowerShell module with functions
- `Install-MetricsAgent.ps1` - Installs as scheduled task
- `Example-SendMetrics.ps1` - Usage examples

---

## 🎯 Common Tasks

### Add a New System

```powershell
# Via API
Invoke-RestMethod -Uri "http://localhost:5000/api/dashboard/systems" `
    -Method POST `
    -ContentType "application/json" `
    -Body '{"systemId":"SYS004","name":"Test System","description":"My test"}'
```

Or directly in database:

```sql
INSERT INTO Systems (SystemId, Name, Description, IsActive, CreatedDate, ModifiedDate)
VALUES ('SYS004', 'Test System', 'My test system', 1, datetime('now'), datetime('now'));
```

### Add a New Component

```csharp
// In code: Update DashboardDbContext.cs SeedData()
// Add to modelBuilder.Entity<Component>().HasData()
```

Or via API:

```powershell
Invoke-RestMethod -Uri "http://localhost:5000/api/dashboard/components" `
    -Method POST `
    -ContentType "application/json" `
    -Body '{"componentId":"COMP999","projectId":1,"name":"New Server","componentType":"WebServer"}'
```

### Send Metrics from Script

```powershell
# Collect CPU usage
$cpu = (Get-Counter '\Processor(_Total)\% Processor Time').CounterSamples.CookedValue

# Determine severity
$severity = if ($cpu -lt 70) { "ok" } elseif ($cpu -lt 90) { "warning" } else { "error" }

# Send to API
Send-ComponentMetric `
    -ApiUrl "http://dashboard-server:5000/api/metrics" `
    -ComponentId "COMP001" `
    -Severity $severity `
    -Value ([math]::Round($cpu, 2)) `
    -Metric "%" `
    -Description "Current CPU utilization"
```

### View Database Contents

```powershell
# Install SQLite CLI tool first
# Then:
sqlite3 dashboard.db

# Run queries:
SELECT * FROM Systems;
SELECT * FROM Projects WHERE SystemId = 1;
SELECT * FROM ComponentMetrics ORDER BY CollectedDate DESC LIMIT 10;
```

---

## 🐛 Troubleshooting

### "Dashboard shows no data"

**Check:**
1. Is API running? Test: `http://localhost:5000/api/dashboard/systems`
2. Database exists? Look for `dashboard.db` file
3. Browser console errors? Press F12 and check console

**Fix:**
```powershell
# Recreate database
cd DashboardAPI
Remove-Item dashboard.db
dotnet ef database update
```

### "Agent can't send metrics - connection refused"

**Check:**
1. API URL correct? Should be `http://server:5000` (no trailing slash)
2. Firewall blocking? Test: `Test-NetConnection server -Port 5000`
3. API running? Check process: `Get-Process dotnet`

**Fix:**
```powershell
# Allow through firewall
New-NetFirewallRule -DisplayName "Dashboard API" -Direction Inbound -LocalPort 5000 -Protocol TCP -Action Allow
```

### "SignalR not working - no real-time updates"

**Check:**
1. Browser console shows WebSocket errors?
2. Is dashboard running on localhost or remote server?

**Fix for remote servers:**
Update `BlazorDashboard/appsettings.json`:
```json
{
  "DetailedErrors": true,
  "CircuitOptions": {
    "DetailedErrors": true
  }
}
```

### "Database is locked"

**Cause:** Multiple processes accessing SQLite file simultaneously

**Fix:**
```powershell
# Stop all dotnet processes
Get-Process dotnet | Stop-Process -Force

# Or use SQL Server instead of SQLite for production
```

---

## 📝 Configuration Files

### DashboardAPI/appsettings.json

```json
{
  "ConnectionStrings": {
    "DefaultConnection": "Data Source=dashboard.db"  ← Database location
  },
  "Logging": {
    "LogLevel": {
      "Default": "Information"  ← Change to "Debug" for verbose logs
    }
  },
  "AllowedHosts": "*",
  "Cors": {
    "AllowedOrigins": [
      "http://localhost:5001",  ← Add your dashboard URLs here
      "http://your-server:5001"
    ]
  }
}
```

### BlazorDashboard/appsettings.json

```json
{
  "ApiSettings": {
    "BaseUrl": "http://localhost:5000"  ← Change to your API server URL
  },
  "RefreshInterval": 30000  ← Milliseconds (30 sec default)
}
```

---

## 🔒 Security Checklist

For Production Deployment:

- [ ] Change default SQLite to SQL Server (for multi-server access)
- [ ] Enable HTTPS with SSL certificates
- [ ] Enable Windows Authentication in IIS
- [ ] Restrict API access to known servers (firewall rules)
- [ ] Use strong passwords/tokens for agent authentication (if implementing)
- [ ] Enable IIS logging and monitor regularly
- [ ] Set appropriate NTFS permissions on database file
- [ ] Implement backup strategy for database

---

## 📚 API Endpoints Reference

### Dashboard Data

```
GET  /api/dashboard                           → Full dashboard data
GET  /api/dashboard/systems                   → All systems
GET  /api/dashboard/systems/{id}              → Single system
GET  /api/dashboard/systems/{id}/projects     → Projects for system
GET  /api/dashboard/projects/{id}/components  → Components for project
```

### Metrics Collection

```
POST /api/metrics                             → Submit new metric
GET  /api/metrics/latest/{componentId}        → Latest metric for component
GET  /api/metrics/history/{componentId}       → Historical metrics
```

### Example POST to /api/metrics

```json
{
  "componentId": "COMP001",
  "severity": "warning",
  "value": "85.5",
  "metric": "%",
  "description": "CPU usage above threshold"
}
```

---

## 🎓 Next Steps

1. **Customize for your environment:**
   - Add your actual servers as Systems/Projects/Components
   - Modify PowerShell agent to collect your specific metrics
   - Adjust severity thresholds

2. **Deploy to production:**
   - Follow DEPLOYMENT-GUIDE.md
   - Setup IIS
   - Install agents on servers

3. **Extend functionality:**
   - Add email alerts for critical errors
   - Implement metric history charts
   - Add user authentication
   - Create custom reports

---

## 💡 Tips

- **Use PowerShell ISE** to write and test agent scripts
- **Check Swagger UI** for API testing: `http://localhost:5000/swagger`
- **Browser F12 Console** shows SignalR connection status
- **SQLite Database Browser** is great for viewing database: https://sqlitebrowser.org/
- **Postman** or **Insomnia** for API testing

---

## 📞 Getting Help

**Check in this order:**
1. This Quick Reference Guide
2. Full README.md
3. DEPLOYMENT-GUIDE.md
4. Code comments (all functions have detailed help)
5. Browser console (F12) for errors
6. API Swagger documentation

---

**Happy Monitoring!** 🎉

_Built with Blazor Server + ASP.NET Core + EF Core + SQLite + PowerShell_
