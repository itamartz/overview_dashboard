using Microsoft.EntityFrameworkCore;
using DashboardAPI.Models;

namespace DashboardAPI.Data
{
    /// <summary>
    /// Database context for IT Infrastructure Dashboard
    /// Uses SQLite for lightweight, file-based storage
    /// </summary>
    public class DashboardDbContext : DbContext
    {
        public DashboardDbContext(DbContextOptions<DashboardDbContext> options)
            : base(options)
        {
        }

        public DbSet<SystemEntity> Systems { get; set; }
        public DbSet<Project> Projects { get; set; }
        public DbSet<Component> Components { get; set; }
        public DbSet<ComponentMetric> ComponentMetrics { get; set; }

        protected override void OnModelCreating(ModelBuilder modelBuilder)
        {
            base.OnModelCreating(modelBuilder);

            // System Entity Configuration
            modelBuilder.Entity<SystemEntity>(entity =>
            {
                entity.ToTable("Systems");
                entity.HasKey(e => e.Id);
                entity.Property(e => e.SystemId).IsRequired().HasMaxLength(50);
                entity.HasIndex(e => e.SystemId).IsUnique();
                entity.Property(e => e.Name).IsRequired().HasMaxLength(200);
                entity.Property(e => e.Description).HasMaxLength(500);
                entity.Property(e => e.IsActive).IsRequired().HasDefaultValue(true);
                entity.Property(e => e.CreatedDate).IsRequired();
                entity.Property(e => e.ModifiedDate).IsRequired();

                // Relationships
                entity.HasMany(e => e.Projects)
                      .WithOne(p => p.System)
                      .HasForeignKey(p => p.SystemId)
                      .OnDelete(DeleteBehavior.Cascade);
            });

            // Project Configuration
            modelBuilder.Entity<Project>(entity =>
            {
                entity.ToTable("Projects");
                entity.HasKey(e => e.Id);
                entity.Property(e => e.ProjectId).IsRequired().HasMaxLength(50);
                entity.HasIndex(e => e.ProjectId).IsUnique();
                entity.Property(e => e.Name).IsRequired().HasMaxLength(200);
                entity.Property(e => e.Description).HasMaxLength(500);
                entity.Property(e => e.IsActive).IsRequired().HasDefaultValue(true);
                entity.Property(e => e.CreatedDate).IsRequired();
                entity.Property(e => e.ModifiedDate).IsRequired();

                // Relationships
                entity.HasMany(e => e.Components)
                      .WithOne(c => c.Project)
                      .HasForeignKey(c => c.ProjectId)
                      .OnDelete(DeleteBehavior.Cascade);
            });

            // Component Configuration
            modelBuilder.Entity<Component>(entity =>
            {
                entity.ToTable("Components");
                entity.HasKey(e => e.Id);
                entity.Property(e => e.ComponentId).IsRequired().HasMaxLength(50);
                entity.HasIndex(e => e.ComponentId).IsUnique();
                entity.Property(e => e.Name).IsRequired().HasMaxLength(200);
                entity.Property(e => e.Description).HasMaxLength(500);
                entity.Property(e => e.ComponentType).IsRequired().HasMaxLength(50);
                entity.Property(e => e.IsActive).IsRequired().HasDefaultValue(true);
                entity.Property(e => e.CreatedDate).IsRequired();
                entity.Property(e => e.ModifiedDate).IsRequired();

                // Relationships
                entity.HasMany(e => e.Metrics)
                      .WithOne(m => m.Component)
                      .HasForeignKey(m => m.ComponentId)
                      .OnDelete(DeleteBehavior.Cascade);
            });

            // ComponentMetric Configuration
            modelBuilder.Entity<ComponentMetric>(entity =>
            {
                entity.ToTable("ComponentMetrics");
                entity.HasKey(e => e.Id);
                entity.Property(e => e.Severity).IsRequired().HasMaxLength(20);
                entity.Property(e => e.Value).IsRequired().HasMaxLength(100);
                entity.Property(e => e.Metric).IsRequired().HasMaxLength(50);
                entity.Property(e => e.RawValue).HasColumnType("decimal(18,4)");
                entity.Property(e => e.Description).HasMaxLength(1000);
                entity.Property(e => e.CollectedDate).IsRequired();

                // Indexes for performance
                entity.HasIndex(e => e.ComponentId);
                entity.HasIndex(e => e.CollectedDate);
                entity.HasIndex(e => e.Severity);
            });

            // Seed initial data
            SeedData(modelBuilder);
        }

        private void SeedData(ModelBuilder modelBuilder)
        {
            var now = DateTime.UtcNow;

            // Seed Systems
            modelBuilder.Entity<SystemEntity>().HasData(
                new SystemEntity
                {
                    Id = 1,
                    SystemId = "SYS001",
                    Name = "Production Environment",
                    Description = "Main production infrastructure",
                    IsActive = true,
                    CreatedDate = now,
                    ModifiedDate = now
                },
                new SystemEntity
                {
                    Id = 2,
                    SystemId = "SYS002",
                    Name = "Development Environment",
                    Description = "Development and testing systems",
                    IsActive = true,
                    CreatedDate = now,
                    ModifiedDate = now
                },
                new SystemEntity
                {
                    Id = 3,
                    SystemId = "SYS003",
                    Name = "Database Cluster",
                    Description = "Database infrastructure",
                    IsActive = true,
                    CreatedDate = now,
                    ModifiedDate = now
                }
            );

            // Seed Projects
            modelBuilder.Entity<Project>().HasData(
                new Project { Id = 1, ProjectId = "PROJ001", SystemId = 1, Name = "Web Servers", Description = "IIS web server farm", IsActive = true, CreatedDate = now, ModifiedDate = now },
                new Project { Id = 2, ProjectId = "PROJ002", SystemId = 1, Name = "Application Servers", Description = "Business logic tier", IsActive = true, CreatedDate = now, ModifiedDate = now },
                new Project { Id = 3, ProjectId = "PROJ003", SystemId = 2, Name = "Dev Web Servers", Description = "Development web servers", IsActive = true, CreatedDate = now, ModifiedDate = now },
                new Project { Id = 4, ProjectId = "PROJ004", SystemId = 3, Name = "SQL Primary", Description = "Primary database servers", IsActive = true, CreatedDate = now, ModifiedDate = now }
            );

            // Seed Components
            modelBuilder.Entity<Component>().HasData(
                // Web Server Components
                new Component { Id = 1, ComponentId = "COMP001", ProjectId = 1, Name = "WEB-SRV-01", Description = "Primary web server", ComponentType = "WebServer", IsActive = true, CreatedDate = now, ModifiedDate = now },
                new Component { Id = 2, ComponentId = "COMP002", ProjectId = 1, Name = "WEB-SRV-02", Description = "Secondary web server", ComponentType = "WebServer", IsActive = true, CreatedDate = now, ModifiedDate = now },
                
                // App Server Components
                new Component { Id = 3, ComponentId = "COMP003", ProjectId = 2, Name = "APP-SRV-01", Description = "Application server 1", ComponentType = "AppServer", IsActive = true, CreatedDate = now, ModifiedDate = now },
                new Component { Id = 4, ComponentId = "COMP004", ProjectId = 2, Name = "APP-SRV-02", Description = "Application server 2", ComponentType = "AppServer", IsActive = true, CreatedDate = now, ModifiedDate = now },
                
                // Dev Components
                new Component { Id = 5, ComponentId = "COMP005", ProjectId = 3, Name = "DEV-WEB-01", Description = "Dev web server", ComponentType = "WebServer", IsActive = true, CreatedDate = now, ModifiedDate = now },
                
                // Database Components
                new Component { Id = 6, ComponentId = "COMP006", ProjectId = 4, Name = "SQL-01", Description = "Primary SQL Server", ComponentType = "Database", IsActive = true, CreatedDate = now, ModifiedDate = now },
                new Component { Id = 7, ComponentId = "COMP007", ProjectId = 4, Name = "SQL-02", Description = "Secondary SQL Server", ComponentType = "Database", IsActive = true, CreatedDate = now, ModifiedDate = now }
            );
        }
    }
}
