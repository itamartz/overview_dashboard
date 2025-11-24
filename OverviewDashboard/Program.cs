using Microsoft.AspNetCore.HttpOverrides;
using Microsoft.EntityFrameworkCore;
using OverviewDashboard.Components;
using OverviewDashboard.Data;
using OverviewDashboard.Models;
using OverviewDashboard.Services;

// Set current directory to the application base directory to ensure relative paths work correctly in Windows Service
Directory.SetCurrentDirectory(AppContext.BaseDirectory);

var builder = WebApplication.CreateBuilder(args);

builder.Host.UseWindowsService();

// Configure forwarded headers for proxy support
builder.Services.Configure<ForwardedHeadersOptions>(options =>
{
    options.ForwardedHeaders = ForwardedHeaders.XForwardedFor | ForwardedHeaders.XForwardedProto;
    options.KnownNetworks.Clear();
    options.KnownProxies.Clear();
});

// Add services to the container.
builder.Services.AddRazorComponents()
    .AddInteractiveServerComponents();

// Add State Management Service
builder.Services.AddSingleton<DashboardStateService>();

// Add API Controllers
builder.Services.AddControllers();

// Add SignalR
builder.Services.AddSignalR();

// Add Swagger/OpenAPI
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen(c =>
{
    // Include XML comments
    var xmlFile = $"{System.Reflection.Assembly.GetExecutingAssembly().GetName().Name}.xml";
    var xmlPath = Path.Combine(AppContext.BaseDirectory, xmlFile);
    if (File.Exists(xmlPath))
    {
        c.IncludeXmlComments(xmlPath);
    }
});

// Add DbContext with SQLite
builder.Services.AddDbContext<DashboardDbContext>(options =>
    options.UseSqlite(builder.Configuration.GetConnectionString("DefaultConnection") ?? "Data Source=dashboard.db"));

var app = builder.Build();

// Initialize database
using (var scope = app.Services.CreateScope())
{
    var db = scope.ServiceProvider.GetRequiredService<DashboardDbContext>();
    
    // Ensure database directory exists
    var connectionString = builder.Configuration.GetConnectionString("DefaultConnection") ?? "Data Source=dashboard.db";
    var match = System.Text.RegularExpressions.Regex.Match(connectionString, "Data Source=([^;]+)");
    if (match.Success)
    {
        var dbPath = match.Groups[1].Value;
        var dbDir = Path.GetDirectoryName(dbPath);
        if (!string.IsNullOrEmpty(dbDir) && !Directory.Exists(dbDir))
        {
            Directory.CreateDirectory(dbDir);
        }
    }

    db.Database.EnsureCreated();
    
    // Create default Welcome event if database is empty
    if (!db.Components.Any())
    {
        var welcomeComponent = new Component
        {
            SystemName = "Welcome",
            ProjectName = "demo",
            Payload = "{\"Severity\": \"info\", \"Description\": \"you can add data with the API\"}",
            CreatedAt = DateTime.UtcNow
        };
        
        db.Components.Add(welcomeComponent);
        db.SaveChanges();
    }
}

// Configure the HTTP request pipeline.
app.UseForwardedHeaders();

// Serve static files
app.UseStaticFiles();

// Enable Swagger in all environments
app.UseSwagger();
app.UseSwaggerUI();

if (!app.Environment.IsDevelopment())
{
    app.UseExceptionHandler("/Error", createScopeForErrors: true);
    // Don't use HSTS when behind a reverse proxy
}

// Don't use HTTPS redirection - Traefik handles SSL termination
app.UseAntiforgery();

// Map API Controllers
app.MapControllers();

// Map SignalR Hub
app.MapHub<OverviewDashboard.Hubs.DashboardHub>("/dashboardHub");

// Map Blazor Components
app.MapRazorComponents<App>()
    .AddInteractiveServerRenderMode();

app.Run();
