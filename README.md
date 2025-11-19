# IT Infrastructure Overview Dashboard

A real-time monitoring dashboard for IT infrastructure built with **Blazor Server**, **ASP.NET Core Web API**, and **Entity Framework Core with SQLite**. Designed for air-gapped environments with no developer required for maintenance.

<img width="1890" height="905" alt="image" src="https://github.com/user-attachments/assets/e8a9191c-a037-4272-9b7b-c6ec8831227d" />



## 🎯 Features

- ✅ **Real-time Updates** - SignalR-based live dashboard without page refresh
- ✅ **Hierarchical Navigation** - Systems → Projects → Components
- ✅ **Status Monitoring** - OK, Warning, Error, Info severity levels
- ✅ **SQLite Database** - No external database server required
- ✅ **Air-Gap Ready** - Self-contained deployment, no internet needed
- ✅ **PowerShell Agents** - Automated data collection from Windows servers
- ✅ **IIS Compatible** - Easy deployment on Windows Server
- ✅ **Zero JavaScript** - Pure C# Blazor application

## 📋 Prerequisites

### On Your Development Machine:
- .NET 8.0 SDK
- Visual Studio 2022 or VS Code (optional)
- Git (for cloning)

### On Production Server (IIS):
- Windows Server 2012 R2 or newer
- IIS with ASP.NET Core Hosting Bundle
- .NET 8.0 Runtime (or use self-contained deployment)

## 🏗️ Project Structure

```
DashboardSystem/
├── DashboardAPI/              # ASP.NET Core Web API (old Program.cs style)
│   ├── Controllers/           # API controllers for metrics and dashboard data
│   ├── Data/                  # EF Core DbContext with SQLite
│   ├── Models/                # Entity models (System, Project, Component, Metric)
│   ├── DTOs/                  # Data Transfer Objects
│   └── Services/              # Background services for data updates
│
├── BlazorDashboard/           # Blazor Server Application
│   ├── Pages/                 # Razor pages/components
│   ├── Services/              # Dashboard services and SignalR hubs
│   └── Models/                # View models
│
├── PowerShellAgent/           # Data collection agents
│   ├── Install-MetricsAgent.ps1     # Agent installer script
│   └── Example-SendMetrics.ps1      # Example usage
│
├── Database/                  # SQL scripts (reference only - using EF migrations)
├── Deployment/                # IIS deployment scripts
└── Documentation/             # Additional documentation

```

## 🚀 Quick Start

### 1. Clone the Repository

```powershell
git clone https://github.com/itamartz/overview_dashboard.git
cd overview_dashboard
```

### 2. Build the Projects

```powershell
# Build API
cd DashboardAPI
dotnet build

# Build Blazor Dashboard
cd ../BlazorDashboard
dotnet build
```

### 3. Initialize the Database

```powershell
cd DashboardAPI
dotnet ef database update
```

This creates `dashboard.db` SQLite file with sample data.

### 4. Run Locally (Development)

**Terminal 1 - API:**
```powershell
cd DashboardAPI
dotnet run
# API runs on: https://localhost:7001
```

**Terminal 2 - Blazor Dashboard:**
```powershell
cd BlazorDashboard
dotnet run
# Dashboard runs on: https://localhost:7002
```

Navigate to `https://localhost:7002` to see the dashboard.

## 📦 Deployment to IIS (Air-Gapped Environment)

### Step 1: Publish the Applications

```powershell
# Publish API (self-contained for air-gap)
cd DashboardAPI
dotnet publish -c Release -r win-x64 --self-contained true -o ../Publish/API

# Publish Blazor Dashboard (self-contained)
cd ../BlazorDashboard
dotnet publish -c Release -r win-x64 --self-contained true -o ../Publish/Dashboard
```

### Step 2: Copy to Production Server

Copy the `Publish` folder to your production server via USB or approved transfer method.

### Step 3: Setup IIS

Run the PowerShell deployment script on the server:

```powershell
# Run as Administrator
cd Deployment
.\Deploy-ToIIS.ps1
```

Or manually configure:

1. **Install ASP.NET Core Hosting Bundle** (if not using self-contained)
2. **Create Application Pools:**
   - `DashboardAPI_Pool` (.NET CLR: No Managed Code)
   - `BlazorDashboard_Pool` (.NET CLR: No Managed Code)

3. **Create IIS Sites:**
   - API: Port 5000, Path: `C:\inetpub\DashboardAPI`
   - Dashboard: Port 5001, Path: `C:\inetpub\BlazorDashboard`

4. **Enable WebSockets** (required for SignalR)

### Step 4: Configure Database Path

Edit `appsettings.json` in both applications:

```json
{
  "ConnectionStrings": {
    "DefaultConnection": "Data Source=C:\\inetpub\\Dashboard\\dashboard.db"
  }
}
```

### Step 5: Copy Database

```powershell
# Copy the database file to shared location
copy dashboard.db C:\inetpub\Dashboard\
```

## 🔧 PowerShell Agent Setup

The PowerShell agent collects metrics from Windows servers and sends them to the API.

### Install on Monitored Servers:

```powershell
# Copy agent to server
copy PowerShellAgent C:\Tools\DashboardAgent

# Install as scheduled task (runs every 5 minutes)
cd C:\Tools\DashboardAgent
.\Install-MetricsAgent.ps1 -ApiUrl "http://dashboard-server:5000" -InstallPath "C:\Tools\DashboardAgent"
```

### Manual Test:

```powershell
.\Example-SendMetrics.ps1 -ApiUrl "http://dashboard-server:5000/api/metrics" -ComponentId "COMP001"
```

## ⚙️ Configuration

### API Configuration (`DashboardAPI/appsettings.json`)

```json
{
  "ConnectionStrings": {
    "DefaultConnection": "Data Source=dashboard.db"
  },
  "Logging": {
    "LogLevel": {
      "Default": "Information",
      "Microsoft.AspNetCore": "Warning"
    }
  },
  "AllowedHosts": "*",
  "Cors": {
    "AllowedOrigins": [
      "https://localhost:7002",
      "http://your-dashboard-server"
    ]
  }
}
```

### Blazor Configuration (`BlazorDashboard/appsettings.json`)

```json
{
  "ApiSettings": {
    "BaseUrl": "https://localhost:7001"  // Change to your API URL
  },
  "RefreshInterval": 30000  // Milliseconds (30 seconds)
}
```

## 📊 Database Schema

The system uses a hierarchical structure:

```
Systems (e.g., "Production Environment")
  └── Projects (e.g., "Web Servers")
       └── Components (e.g., "WEB-SRV-01")
            └── ComponentMetrics (CPU, Memory, Disk status)
```

### Entity Models:

- **SystemEntity** - Top-level systems
- **Project** - Groups of related components
- **Component** - Individual monitored items
- **ComponentMetric** - Time-series metrics with severity levels

## 🔄 How It Works

1. **PowerShell agents** on each server collect metrics every 1-5 minutes
2. Agents POST data to **DashboardAPI** `/api/metrics` endpoint
3. API saves metrics to **SQLite database** via Entity Framework
4. **Background service** in Blazor app polls database for changes
5. **SignalR** pushes updates to all connected browser clients
6. Dashboard updates in **real-time** without page refresh

## 🛠️ Customization

### Add New Component Types:

1. Update `Component.ComponentType` enum (if using enums)
2. Create PowerShell collection script
3. Add UI display logic in Blazor pages

### Add New Metrics:

1. Modify `ComponentMetric` model if needed
2. Update PowerShell agent to collect new data
3. Add display in dashboard

### Change Refresh Intervals:

- **PowerShell Agent:** Edit scheduled task interval
- **Dashboard Updates:** Modify `RefreshInterval` in appsettings.json
- **Background Service:** Edit `BackgroundMetricsService.cs`

## 📝 API Endpoints

### Dashboard Data:
- `GET /api/dashboard` - Get complete dashboard hierarchy
- `GET /api/dashboard/systems` - Get all systems
- `GET /api/dashboard/systems/{id}/projects` - Get projects for system
- `GET /api/dashboard/projects/{id}/components` - Get components for project

### Metrics Collection:
- `POST /api/metrics` - Submit new metrics from agents
- `GET /api/metrics/latest/{componentId}` - Get latest metric for component

### Swagger UI:
- Navigate to `https://your-api-server:5000/swagger` for interactive API documentation

## 🐛 Troubleshooting

### Dashboard Not Updating:
1. Check SignalR WebSocket connection in browser console
2. Verify IIS WebSocket is enabled
3. Check firewall allows WebSocket connections

### Agent Can't Send Data:
1. Test API endpoint: `curl http://api-server:5000/api/metrics -v`
2. Check network connectivity from agent server
3. Verify API is running in IIS

### Database Locked:
1. Ensure only one application instance accesses SQLite
2. Check file permissions on `dashboard.db`
3. Consider switching to SQL Server for multi-instance

## 📚 Additional Resources

- [Blazor Server Documentation](https://docs.microsoft.com/en-us/aspnet/core/blazor/)
- [Entity Framework Core](https://docs.microsoft.com/en-us/ef/core/)
- [SignalR Documentation](https://docs.microsoft.com/en-us/aspnet/core/signalr/)
- [IIS Deployment](https://docs.microsoft.com/en-us/aspnet/core/host-and-deploy/iis/)

## 📄 License

This project is provided as-is for internal use.

## 🤝 Support

For issues or questions:
1. Check this README
2. Review code comments (comprehensive help included)
3. Check browser console for errors
4. Review IIS logs: `C:\inetpub\logs\LogFiles`

## 🔐 Security Notes

- **Air-Gapped Environment:** No external dependencies after deployment
- **Authentication:** Add Windows Authentication in IIS for production
- **HTTPS:** Configure SSL certificates in IIS
- **Database:** Protect `dashboard.db` with NTFS permissions

---

**Built with ❤️ using C# and Blazor - No JavaScript Required!**
