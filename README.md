# IT Infrastructure Overview Dashboard

A real-time monitoring dashboard for IT infrastructure built with **Blazor Server**, **ASP.NET Core Web API**, and **Entity Framework Core with SQLite**. Features Docker deployment via GitHub Actions and Windows Service support.

![Dashboard Screenshot](https://github.com/user-attachments/assets/e8a9191c-a037-4272-9b7b-c6ec8831227d)

## 🎯 Features

- ✅ **Real-time Updates** - SignalR-based live dashboard without page refresh
- ✅ **Dynamic Layouts** - Pinterest-style Masonry view for project overviews
- ✅ **Responsive UI** - Collapsible sidebar and scrollable data tables (horizontal & vertical)
- ✅ **Deep Linking** - Shareable URLs via hash fragments (e.g., `/#System/Project`)
- ✅ **Hierarchical Navigation** - Systems → Projects → Components  
- ✅ **Keyboard Shortcuts** - Navigate systems using Up/Down arrow keys, and pages/projects using Left/Right arrow keys
- ✅ **Status Monitoring** - OK, Warning, Error, Info, and **Offline** severity levels
- ✅ **Heartbeat Monitoring** - Dynamic per-component TTL (Time-To-Live) support
- ✅ **SQLite Database** - No external database server required
- ✅ **Docker Deployment** - GitHub Actions workflow for GCP deployment
- ✅ **Windows Service** - Can run as a Windows Service
- ✅ **REST API** - Built-in API with Swagger documentation
- ✅ **Admin Controls** - Dedicated `/admin` interface for managing data
- ✅ **Zero JavaScript** - Pure C# Blazor application

## 📋 Prerequisites

### Development:
- .NET 9.0 SDK
- Visual Studio 2022 or VS Code (optional)
- Git (for cloning)

### Deployment Options:

**Option A - Docker (Recommended):**
- Docker installed on target server
- GitHub repository with Actions enabled
- GCP instance (or any server with Docker)

**Option B - Windows Service:**
- Windows Server 2012 R2 or newer
- .NET 9.0 Runtime

## 🏗️ Project Structure

```
overview_dashboard/
├── OverviewDashboard/              # Main Blazor Server Application
│   ├── Components/                 # Blazor components and pages
│   │   └── Pages/                  # Razor pages
│   ├── Controllers/                # API controllers
│   ├── Data/                       # EF Core DbContext
│   ├── DTOs/                       # Data Transfer Objects
│   ├── Models/                     # Entity models
│   ├── wwwroot/                    # Static files (CSS, JS)
│   ├── Program.cs                  # Application entry point
│   └── appsettings.json            # Configuration
│
├── Database/                       # SQLite database location
├── PowerShellAgent/                # Data collection agents (optional)
├── .github/workflows/              # GitHub Actions for deployment
├── Dockerfile                      # Docker container configuration
├── .dockerignore                   # Docker build exclusions
└── DOCKER-DEPLOYMENT.md            # Docker deployment guide
```

## 🚀 Quick Start

### 1. Clone the Repository

```powershell
git clone https://github.com/itamartz/overview_dashboard.git
cd overview_dashboard
```

### 2. Run Locally (Development)

```powershell
# The database will be created automatically
dotnet run --project OverviewDashboard/OverviewDashboard.csproj
```

Navigate to the URL shown in the console (typically `http://localhost:5203`)

### 3. Access the Dashboard

- **Dashboard:** `http://localhost:5203`
- **Admin Panel:** `http://localhost:5203/admin`
- **API Endpoints:** `http://localhost:5203/api/*`
- **Swagger UI:** `http://localhost:5203/swagger`

## 📦 Deployment Options

### Option A: Docker Deployment (Recommended)

See [DOCKER-DEPLOYMENT.md](DOCKER-DEPLOYMENT.md) for complete instructions.

**Quick Summary:**
1. Configure GitHub Secrets (GCP_HOST, GCP_USERNAME, GCP_SSH_KEY)
2. Push to main branch
3. GitHub Actions automatically builds and deploys to your server

### Option B: Windows Service

```powershell
# Publish the application
dotnet publish OverviewDashboard/OverviewDashboard.csproj -c Release -o ./publish

# Install as Windows Service (requires admin)
sc create OverviewDashboard binPath="C:\path\to\publish\OverviewDashboard.exe"
sc start OverviewDashboard
```

See `Deploy-WindowsService.ps1` for automated installation.

## ⚙️ Configuration

### Application & Database Configuration

Edit `OverviewDashboard/appsettings.json`:

```json
{
  "ConnectionStrings": {
    "DefaultConnection": "Data Source=Database/dashboard.db"
  },
  "Dashboard": {
    "PageSize": 100,
    "OfflineThresholdMinutes": 60,
    "DeleteThresholdMinutes": 129600
  }
}
```

#### Settings Description:

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `ConnectionStrings:DefaultConnection` | string | `Data Source=Database/dashboard.db` | SQLite database connection string |
| `Dashboard:PageSize` | integer | `100` | Number of items per page in paginated dashboard component views |
| `Dashboard:OfflineThresholdMinutes` | integer | `60` | Fallback threshold (in minutes) after which a component is marked **Offline** if no payload `TTL` is specified |
| `Dashboard:DeleteThresholdMinutes` | integer | `129600` (90 days) | Data cleanup retention window (in minutes). A background cleanup service runs hourly and deletes components older than this threshold. Set to `<= 0` to disable auto-cleanup. |

### Environment Variables

You can override any `appsettings.json` setting using environment variables (ideal for Docker / Linux deployments):

```bash
# Database path
ConnectionStrings__DefaultConnection="Data Source=/custom/path/dashboard.db"

# Offline detection threshold (e.g., 30 minutes)
Dashboard__OfflineThresholdMinutes=30

# Data retention & automatic cleanup threshold (e.g., 43200 minutes = 30 days)
Dashboard__DeleteThresholdMinutes=43200

# Logging level
Logging__LogLevel__Default="Debug"
```

## 📊 Database Schema

The system uses a hierarchical structure:

```
Systems (e.g., "ActiveDirectory", "vCenter", "WSUS")
  └── Projects (e.g., "UserAudit", "StorageHealth")
       └── Components (individual monitored items)
            └── Payload (JSON data with metrics)
```

### Entity Models:

- **Component** - Monitored items with JSON payload
- **SystemName** - Top-level system identifier
- **ProjectName** - Project/category identifier
- **Payload** - Flexible JSON data structure

## 🔄 How It Works

1. **Data Collection** - Components send data via API POST to `/api/components`
2. **Storage** - Data saved to SQLite database via Entity Framework
3. **Real-time Updates** - SignalR pushes changes to connected clients
4. **Dashboard Display** - Blazor components render data with color-coded status

## 📝 API Endpoints

### Components:
- `GET /api/components` - Get all components
- `GET /api/components/{id}` - Get specific component
- `POST /api/components` - Create/update component
- `DELETE /api/components/{id}` - Delete component

### Systems:
- `GET /api/components/systems` - Get all unique systems
- `GET /api/components/system/{systemName}` - Get components by system

### Swagger UI:
- Navigate to `/swagger` for interactive API documentation

## 🛠️ Customization

### Add New Component:

```powershell
# Via API (with optional TTL)
Invoke-RestMethod -Uri "http://localhost:5203/api/components" `
    -Method POST `
    -ContentType "application/json" `
    -Body '{
        "systemName": "MySystem",
        "projectName": "MyProject",
        "payload": "{\"Name\": \"HeartbeatService\", \"Severity\": \"ok\", \"TTL\": 30}"
    }'
```

### Modify Dashboard Styling:

Edit `OverviewDashboard/wwwroot/css/dashboard.css`

### Change Refresh Intervals:

Update SignalR configuration in `Program.cs`

## 🐛 Troubleshooting

### Database Issues:
```powershell
# Delete and recreate database
Remove-Item Database/dashboard.db
dotnet run --project OverviewDashboard/OverviewDashboard.csproj
```

### Port Already in Use:
```powershell
# Run on different port
dotnet run --project OverviewDashboard/OverviewDashboard.csproj --urls "http://localhost:5000"
```

### Docker Build Fails:
- Check Dockerfile publish settings
- Ensure .dockerignore is present
- Review GitHub Actions logs

## 📚 Additional Resources

- [Docker Deployment Guide](DOCKER-DEPLOYMENT.md)
- [Blazor Server Documentation](https://docs.microsoft.com/en-us/aspnet/core/blazor/)
- [Entity Framework Core](https://docs.microsoft.com/en-us/ef/core/)
- [SignalR Documentation](https://docs.microsoft.com/en-us/aspnet/core/signalr/)

## 📄 License

This project is provided as-is for internal use.

## 🤝 Support

For issues or questions:
1. Check this README
2. Review [DOCKER-DEPLOYMENT.md](DOCKER-DEPLOYMENT.md)
3. Check browser console for errors (F12)
4. Review application logs

## 🔐 Security Notes

- **Docker Deployment:** Use SSH keys for secure deployment
- **Authentication:** Add authentication middleware for production
- **HTTPS:** Configure SSL certificates
- **Database:** Protect database file with appropriate permissions
- **Secrets:** Use GitHub Secrets for sensitive configuration

## 🛡️ Administration
- Access the admin panel at `/admin`
- **Delete Systems:** Remove entire systems and all their data
- **Delete Projects:** Remove specific projects
- **Bulk Delete:** Select and remove multiple components at once

---

**Built with ❤️ using .NET 9.0, Blazor Server, and C# - No JavaScript Required!**
