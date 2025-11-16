using Microsoft.EntityFrameworkCore;
using Microsoft.OpenApi.Models;
using DashboardAPI.Data;

namespace DashboardAPI
{
    public class Startup
    {
        public Startup(IConfiguration configuration)
        {
            Configuration = configuration;
        }

        public IConfiguration Configuration { get; }

        // This method gets called by the runtime. Use this method to add services to the container.
        public void ConfigureServices(IServiceCollection services)
        {
            // Add DbContext with SQLite
            var dbPath = Configuration.GetConnectionString("DefaultConnection") 
                ?? Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "dashboard.db");
            
            services.AddDbContext<DashboardDbContext>(options =>
                options.UseSqlite($"Data Source={dbPath}"));

            // Add Controllers
            services.AddControllers()
                .AddJsonOptions(options =>
                {
                    options.JsonSerializerOptions.ReferenceHandler = 
                        System.Text.Json.Serialization.ReferenceHandler.IgnoreCycles;
                    options.JsonSerializerOptions.WriteIndented = true;
                });

            // Add CORS
            services.AddCors(options =>
            {
                options.AddPolicy("AllowAll",
                    builder =>
                    {
                        builder.AllowAnyOrigin()
                               .AllowAnyMethod()
                               .AllowAnyHeader();
                    });
            });

            // Add Swagger/OpenAPI
            services.AddEndpointsApiExplorer();
            services.AddSwaggerGen(c =>
            {
                c.SwaggerDoc("v1", new OpenApiInfo
                {
                    Title = "IT Infrastructure Dashboard API",
                    Version = "v1",
                    Description = "API for monitoring IT infrastructure components and metrics",
                    Contact = new OpenApiContact
                    {
                        Name = "IT Operations Team"
                    }
                });

                // Include XML comments if available
                var xmlFile = $"{System.Reflection.Assembly.GetExecutingAssembly().GetName().Name}.xml";
                var xmlPath = Path.Combine(AppContext.BaseDirectory, xmlFile);
                if (File.Exists(xmlPath))
                {
                    c.IncludeXmlComments(xmlPath);
                }
            });

            // Add logging
            services.AddLogging(logging =>
            {
                logging.AddConsole();
                logging.AddDebug();
            });
        }

        // This method gets called by the runtime. Use this method to configure the HTTP request pipeline.
        public void Configure(IApplicationBuilder app, IWebHostEnvironment env, DashboardDbContext dbContext)
        {
            if (env.IsDevelopment())
            {
                app.UseDeveloperExceptionPage();
            }

            // Enable Swagger in all environments (useful for air-gapped environments)
            app.UseSwagger();
            app.UseSwaggerUI(c =>
            {
                c.SwaggerEndpoint("/swagger/v1/swagger.json", "Dashboard API v1");
                c.RoutePrefix = "swagger"; // Access at /swagger
            });

            // Ensure database is created and migrations are applied
            try
            {
                dbContext.Database.EnsureCreated();
                Console.WriteLine("Database initialized successfully");
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Error initializing database: {ex.Message}");
            }

            app.UseRouting();

            app.UseCors("AllowAll");

            app.UseAuthorization();

            app.UseEndpoints(endpoints =>
            {
                endpoints.MapControllers();
                
                // Health check endpoint
                endpoints.MapGet("/", async context =>
                {
                    await context.Response.WriteAsJsonAsync(new
                    {
                        status = "healthy",
                        service = "IT Infrastructure Dashboard API",
                        version = "1.0.0",
                        timestamp = DateTime.UtcNow,
                        endpoints = new
                        {
                            swagger = "/swagger",
                            dashboard = "/api/dashboard",
                            metrics = "/api/metrics",
                            stats = "/api/dashboard/stats"
                        }
                    });
                });
            });
        }
    }
}
