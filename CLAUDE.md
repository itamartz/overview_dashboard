# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a **unified Blazor Server + ASP.NET Core Web API** application for real-time IT infrastructure monitoring. The application combines both the dashboard UI and API endpoints in a single deployable project using .NET 9.0.

**Architecture:** Blazor Server with interactive components + Web API controllers + Entity Framework Core with SQLite

## Essential Commands

### Development
```powershell
# Run the application (both dashboard and API)
cd OverviewDashboard
dotnet run

# The app runs on http://localhost:5203
# API endpoints: http://localhost:5203/api/*
# Swagger UI: http://localhost:5203/swagger
# Dashboard: http://localhost:5203/
```

### Database Operations
```powershell
# The database auto-initializes on startup with EnsureCreated()
# No migrations needed - schema is created from models
# Database file: dashboard.db (SQLite)

# To reset database: delete dashboard.db and restart the app
```

### Build & Publish
```powershell
# Build
dotnet build

# Publish for production (self-contained)
dotnet publish -c Release -r win-x64 --self-contained true -o ../Publish

# Publish (framework-dependent)
dotnet publish -c Release -o ../Publish
```

## Architecture

### Unified Application Structure

This is a **single application** that hosts both the Blazor dashboard UI and REST API:

- **Program.cs** - Configures both Blazor Server and Web API controllers
- **Controllers/** - REST API endpoints for external agents
- **Components/Pages/** - Blazor interactive pages (main dashboard)
- **Data/** - EF Core DbContext and database access
- **Models/** - Entity models (SystemEntity, Project, Component)
- **DTOs/** - Data transfer objects for API
- **Hubs/** - SignalR hubs for real-time updates

### Key Architectural Patterns

1. **Hybrid Hosting Model**
   - Single ASP.NET Core app hosts both Blazor Server and API controllers
   - Blazor uses `@rendermode InteractiveServer` for real-time UI
   - API controllers handle external data ingestion from PowerShell agents

2. **Data Flow**
   ```
   PowerShell Agents → POST /api/components → SQLite DB
                                                    ↓
   Blazor Dashboard ← Auto-refresh (5 sec) ← EF Core queries
   ```

3. **Database Schema** (3-level hierarchy)
   ```
   Systems (top level, e.g., "Production Environment")
     └── Projects (groups, e.g., "Infrastructure")
          └── Components (items, e.g., "Web Server Cluster")
   ```

4. **No SignalR Push** - Despite having a `DashboardHub`, the current implementation uses **timer-based auto-refresh** (every 5 seconds) in the Blazor component rather than real-time SignalR push.

### Important Files

**Program.cs** - Application startup
- Configures Blazor Server with interactive components
- Registers API controllers
- Configures Swagger/OpenAPI
- Initializes SQLite database with `EnsureCreated()`

**OverviewDashboard/Components/Pages/Home.razor**
- Main dashboard page with interactive card-based filtering
- Uses `@rendermode InteractiveServer` for client interactivity
- Timer-based auto-refresh (5 second interval)
- Hierarchical navigation: Systems → Projects → Components

**DashboardDbContext.cs**
- EF Core context with SQLite
- Includes seed data for demo/testing
- Configures cascade delete relationships

**ComponentsController.cs**
- Primary API endpoint: `POST /api/components`
- Auto-creates Systems/Projects if they don't exist
- Updates existing components or creates new ones
- Swagger documentation with detailed examples

## Development Workflow

### Adding New Features

**To add a new status severity level:**
1. No code changes needed - severity is stored as string
2. Update CSS in `wwwroot/css/dashboard.css` with new color classes
3. Add corresponding card in `Home.razor` if needed

**To modify dashboard layout:**
- Edit `OverviewDashboard/Components/Pages/Home.razor`
- CSS is in `wwwroot/css/dashboard.css`
- The dashboard uses a left nav panel + right content area layout

**To add new API endpoints:**
- Create controller in `Controllers/` directory
- Add DTOs in `DTOs/` directory
- Controllers are auto-discovered and mapped in Program.cs

### Database Changes

**Current approach:** Code-first with `EnsureCreated()`
- Schema is generated from model classes
- Seed data is in `DashboardDbContext.SeedData()`
- Database recreates on each startup if missing

**To modify schema:**
1. Update model classes in `Models/`
2. Update `SeedData()` in `DashboardDbContext.cs` if needed
3. Delete `dashboard.db` file
4. Restart application

**Note:** This project does NOT use EF migrations - it uses `EnsureCreated()` which is simpler but cannot handle schema updates on existing databases.

## Configuration

### appsettings.json

```json
{
  "ConnectionStrings": {
    "DefaultConnection": "Data Source=dashboard.db"
  }
}
```

SQLite database path can be absolute or relative. For production, use absolute path like `C:\\inetpub\\Dashboard\\dashboard.db`.

## External Integration

### PowerShell Agent Integration

External PowerShell agents can submit metrics via the REST API:

```powershell
# Example POST to create/update a component
Invoke-RestMethod -Uri "http://localhost:5203/api/components" `
    -Method POST `
    -ContentType "application/json" `
    -Body (@{
        name = "Database Server"
        severity = "ok"  # ok, warning, error, info
        value = 98.5
        metric = "Uptime %"
        description = "Database running perfectly"
        projectName = "Infrastructure"
        systemName = "Production Environment"
    } | ConvertTo-Json)
```

**Key behaviors:**
- Systems and Projects are auto-created if they don't exist
- Components with matching name in same project are updated (not duplicated)
- All updates set `LastUpdate = DateTime.UtcNow`

### Swagger/OpenAPI

API documentation available at `/swagger` when running in Development mode. The `ComponentsController.cs` has extensive XML documentation comments that populate Swagger examples.

## Common Issues

**Dashboard shows "Select a System"**
- Click on "Production Environment" in the left panel to load components
- The dashboard requires explicit selection; it doesn't auto-select

**Changes not appearing in database**
- Database is auto-created on startup with seed data
- Delete `dashboard.db` to reset to seed data
- Check that file isn't locked by another process

**CSS changes not reflecting**
- Check browser cache (hard refresh: Ctrl+Shift+R)
- CSS is served from `wwwroot/css/dashboard.css`

**API returns 404**
- Verify the app is running on the correct port (default: 5203)
- API routes are `/api/components`, not `/api/Components` (case-insensitive in practice)
- Check Swagger UI for available endpoints

## Testing

### Manual Testing

1. Run the application
2. Navigate to dashboard: http://localhost:5203
3. Click "Production Environment" to view components
4. Test filtering by clicking summary cards (OK, Warning, Error, Info)
5. Delete a component using trash icon to test cascade

### API Testing with Swagger

1. Navigate to http://localhost:5203/swagger
2. Use "POST /api/components" endpoint
3. Try the example payloads in the Swagger documentation

## Key Dependencies

- **Microsoft.EntityFrameworkCore.Sqlite** (9.x) - SQLite database provider
- **Swashbuckle.AspNetCore** (10.0.1) - Swagger/OpenAPI
- **Microsoft.EntityFrameworkCore.Design** - EF Core design-time tools

## Project History

Based on git commits:
- Started as separate API + Blazor apps
- Refactored into unified application with real-time SignalR
- Uses .NET 9.0 (not .NET 8.0 as mentioned in older documentation)
- Auto-refresh changed from 30s to 5s
- Recent UI updates: removed control buttons, made cards clickable filters with colored backgrounds
