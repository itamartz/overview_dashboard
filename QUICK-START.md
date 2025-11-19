# Overview Dashboard - Quick Start Guide

## 📦 What Is This?

A real-time IT infrastructure monitoring dashboard built with Blazor Server and .NET 9.0.

**Key Features:**
- Real-time updates via SignalR
- REST API with Swagger documentation
- SQLite database (no server needed)
- Docker deployment ready
- Windows Service support

---

## 🚀 5-Minute Quick Start

### 1. Clone and Run

```powershell
# Clone the repository
git clone https://github.com/itamartz/overview_dashboard.git
cd overview_dashboard

# Run the application (database created automatically)
dotnet run --project OverviewDashboard/OverviewDashboard.csproj
```

### 2. Open Browser

Navigate to the URL shown in console (typically):
- **Dashboard:** `http://localhost:5203`
- **Swagger API:** `http://localhost:5203/swagger`

You should see the dashboard with sample data!

---

## 📊 Understanding the Dashboard

### Data Hierarchy:
```
Systems (e.g., "ActiveDirectory", "vCenter", "WSUS")
  └── Projects (e.g., "UserAudit", "StorageHealth")
       └── Components (individual items with JSON payload)
```

### Sample Data Included:
- **3 Systems:** ActiveDirectory, vCenter, WSUS
- **3 Projects:** UserAudit, StorageHealth, PatchCompliance
- **3 Components:** Sample data for each system

### Status Indicators:
- 🟢 **good** - Everything normal
- 🟡 **warning** - Attention needed
- 🔴 **error** - Critical issue
- 🔵 **info** - Informational only

---

## 🔧 Common Tasks

### Add a New Component via API

```powershell
Invoke-RestMethod -Uri "http://localhost:5203/api/components" `
    -Method POST `
    -ContentType "application/json" `
    -Body '{
        "systemName": "MySystem",
        "projectName": "MyProject",
        "payload": "{\"status\": \"good\", \"value\": 100, \"description\": \"All OK\"}"
    }'
```

### View All Components

```powershell
Invoke-RestMethod -Uri "http://localhost:5203/api/components"
```

### Get Components by System

```powershell
Invoke-RestMethod -Uri "http://localhost:5203/api/components/system/ActiveDirectory"
```

### Delete a Component

```powershell
Invoke-RestMethod -Uri "http://localhost:5203/api/components/1" -Method DELETE
```

### View Database Contents

```powershell
# Install SQLite CLI tool, then:
sqlite3 OverviewDashboard/Database/dashboard.db

# Run queries:
SELECT * FROM Components;
SELECT DISTINCT SystemName FROM Components;
SELECT * FROM Components WHERE SystemName = 'ActiveDirectory';
```

---

## 📁 Project Structure

```
overview_dashboard/
├── OverviewDashboard/              # Main application
│   ├── Components/Pages/           # Blazor pages (Home.razor)
│   ├── Controllers/                # API controllers
│   ├── Data/                       # EF Core DbContext
│   ├── DTOs/                       # Data transfer objects
│   ├── Models/                     # Entity models
│   ├── wwwroot/css/                # Stylesheets
│   ├── Program.cs                  # App entry point
│   └── appsettings.json            # Configuration
│
├── Database/                       # SQLite database location
├── .github/workflows/              # GitHub Actions
├── Dockerfile                      # Docker configuration
└── DOCKER-DEPLOYMENT.md            # Deployment guide
```

---

## 🐛 Troubleshooting

### "Dashboard shows no data"

**Check:**
1. Is the app running? Look for console output
2. Database exists? Check `OverviewDashboard/Database/dashboard.db`
3. Browser console errors? Press F12

**Fix:**
```powershell
# Recreate database
Remove-Item OverviewDashboard/Database/dashboard.db -Force
dotnet run --project OverviewDashboard/OverviewDashboard.csproj
```

### "Port already in use"

**Fix:**
```powershell
# Run on different port
dotnet run --project OverviewDashboard/OverviewDashboard.csproj --urls "http://localhost:5000"
```

### "Database is locked"

**Cause:** Multiple processes accessing SQLite

**Fix:**
```powershell
# Stop all dotnet processes
Get-Process dotnet | Stop-Process -Force

# Restart
dotnet run --project OverviewDashboard/OverviewDashboard.csproj
```

### "SignalR not working - no real-time updates"

**Check:**
1. Browser console shows WebSocket errors?
2. Running on localhost or remote server?

**Fix:**
- Clear browser cache
- Check firewall allows WebSocket connections
- Verify app is running

---

## 📝 Configuration

### Change Database Location

Edit `OverviewDashboard/appsettings.json`:

```json
{
  "ConnectionStrings": {
    "DefaultConnection": "Data Source=C:\\MyData\\dashboard.db"
  }
}
```

### Change Port

```powershell
# Via command line
dotnet run --project OverviewDashboard/OverviewDashboard.csproj --urls "http://localhost:8080"

# Or via appsettings.json
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

### Enable Debug Logging

Edit `appsettings.json`:

```json
{
  "Logging": {
    "LogLevel": {
      "Default": "Debug",
      "Microsoft.AspNetCore": "Information"
    }
  }
}
```

---

## 📚 API Endpoints Reference

### Components

```
GET    /api/components              → Get all components
GET    /api/components/{id}         → Get specific component
POST   /api/components              → Create/update component
DELETE /api/components/{id}         → Delete component
```

### Systems

```
GET    /api/components/systems      → Get all unique systems
GET    /api/components/system/{name} → Get components by system
```

### Swagger UI

Navigate to `/swagger` for interactive API documentation with try-it-out functionality.

### Example POST Request

```json
{
  "systemName": "ActiveDirectory",
  "projectName": "UserAudit",
  "payload": "{\"Username\": \"user01\", \"status\": \"active\", \"Severity\": \"good\"}"
}
```

---

## 🎯 Next Steps

### 1. Customize for Your Environment

- Add your actual systems and projects
- Modify the payload structure for your needs
- Update styling in `wwwroot/css/dashboard.css`

### 2. Deploy to Production

**Option A - Docker (Recommended):**
- See [DOCKER-DEPLOYMENT.md](DOCKER-DEPLOYMENT.md)
- Automated deployment via GitHub Actions

**Option B - Windows Service:**
- See [DEPLOYMENT-GUIDE.md](DEPLOYMENT-GUIDE.md)
- Traditional Windows deployment

### 3. Integrate Data Sources

Create scripts or services to POST data to the API:

```powershell
# Example: Send server metrics
$payload = @{
    systemName = "Monitoring"
    projectName = "ServerHealth"
    payload = @{
        hostname = $env:COMPUTERNAME
        cpu = (Get-Counter '\Processor(_Total)\% Processor Time').CounterSamples.CookedValue
        memory = (Get-Counter '\Memory\Available MBytes').CounterSamples.CookedValue
        status = "good"
    } | ConvertTo-Json
} | ConvertTo-Json

Invoke-RestMethod -Uri "http://your-server:5203/api/components" `
    -Method POST `
    -ContentType "application/json" `
    -Body $payload
```

---

## 💡 Tips

- **Use Swagger UI** for API testing: `http://localhost:5203/swagger`
- **Browser F12 Console** shows SignalR connection status
- **SQLite Database Browser** for viewing database: https://sqlitebrowser.org/
- **Postman** or **Insomnia** for API testing
- **Check logs** in console output for debugging

---

## 📞 Getting Help

**Check in this order:**
1. This Quick Start Guide
2. [README.md](README.md) - Full documentation
3. [DEPLOYMENT-GUIDE.md](DEPLOYMENT-GUIDE.md) - Deployment help
4. [DOCKER-DEPLOYMENT.md](DOCKER-DEPLOYMENT.md) - Docker-specific help
5. Browser console (F12) for errors
6. Swagger documentation at `/swagger`

---

## 🎓 Learning Resources

- [Blazor Documentation](https://docs.microsoft.com/aspnet/core/blazor)
- [Entity Framework Core](https://docs.microsoft.com/ef/core)
- [SignalR Documentation](https://docs.microsoft.com/aspnet/core/signalr)
- [ASP.NET Core Web API](https://docs.microsoft.com/aspnet/core/web-api)

---

**Happy Monitoring!** 🎉

_Built with .NET 9.0 + Blazor Server + EF Core + SQLite_
