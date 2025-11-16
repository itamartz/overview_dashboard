using Microsoft.EntityFrameworkCore;
using OverviewDashboard.Models;

namespace OverviewDashboard.Data
{
    public class DashboardDbContext : DbContext
    {
        public DashboardDbContext(DbContextOptions<DashboardDbContext> options) : base(options)
        {
        }

        public DbSet<SystemEntity> Systems { get; set; }
        public DbSet<Project> Projects { get; set; }
        public DbSet<Component> Components { get; set; }

        protected override void OnModelCreating(ModelBuilder modelBuilder)
        {
            base.OnModelCreating(modelBuilder);

            // Configure relationships
            modelBuilder.Entity<SystemEntity>()
                .HasMany(s => s.Projects)
                .WithOne(p => p.System)
                .HasForeignKey(p => p.SystemId)
                .OnDelete(DeleteBehavior.Cascade);

            modelBuilder.Entity<Project>()
                .HasMany(p => p.Components)
                .WithOne(c => c.Project)
                .HasForeignKey(c => c.ProjectId)
                .OnDelete(DeleteBehavior.Cascade);

            // Seed data based on the mockup
            SeedData(modelBuilder);
        }

        private void SeedData(ModelBuilder modelBuilder)
        {
            // Production Environment
            modelBuilder.Entity<SystemEntity>().HasData(
                new SystemEntity { Id = 1, Name = "Production Environment", Type = "environment" }
            );

            modelBuilder.Entity<Project>().HasData(
                new Project { Id = 1, Name = "Infrastructure", SystemId = 1 },
                new Project { Id = 2, Name = "Applications", SystemId = 1 },
                new Project { Id = 3, Name = "Security", SystemId = 1 }
            );

            // Infrastructure Components
            modelBuilder.Entity<Component>().HasData(
                new Component { Id = 1, Name = "Web Server Cluster", Severity = "ok", Value = 99.9, Metric = "Uptime %", Description = "All 5 servers operational", ProjectId = 1 },
                new Component { Id = 2, Name = "Database Primary", Severity = "ok", Value = 100, Metric = "Availability %", Description = "Healthy replication", ProjectId = 1 },
                new Component { Id = 3, Name = "Database Replica", Severity = "warning", Value = 2.5, Metric = "Replication Lag (s)", Description = "Slight delay detected", ProjectId = 1 },
                new Component { Id = 4, Name = "Load Balancer", Severity = "ok", Value = 98.5, Metric = "Health Score", Description = "Distributing evenly", ProjectId = 1 },
                new Component { Id = 5, Name = "Cache Layer", Severity = "info", Value = 85, Metric = "Hit Rate %", Description = "Normal operation", ProjectId = 1 }
            );

            // Application Components
            modelBuilder.Entity<Component>().HasData(
                new Component { Id = 6, Name = "API Gateway", Severity = "ok", Value = 250, Metric = "Req/sec", Description = "Normal traffic load", ProjectId = 2 },
                new Component { Id = 7, Name = "Auth Service", Severity = "error", Value = 85, Metric = "Success Rate %", Description = "Authentication failures", ProjectId = 2 },
                new Component { Id = 8, Name = "Payment Service", Severity = "ok", Value = 99.9, Metric = "Success Rate %", Description = "Processing normally", ProjectId = 2 },
                new Component { Id = 9, Name = "Email Service", Severity = "warning", Value = 350, Metric = "Queue Size", Description = "Backlog building", ProjectId = 2 },
                new Component { Id = 10, Name = "Search Service", Severity = "ok", Value = 45, Metric = "Avg Response (ms)", Description = "Fast queries", ProjectId = 2 }
            );

            // Security Components
            modelBuilder.Entity<Component>().HasData(
                new Component { Id = 11, Name = "Firewall", Severity = "ok", Value = 0, Metric = "Violations", Description = "No threats detected", ProjectId = 3 },
                new Component { Id = 12, Name = "SSL Certificates", Severity = "warning", Value = 15, Metric = "Days to Expiry", Description = "Renewal needed soon", ProjectId = 3 },
                new Component { Id = 13, Name = "Intrusion Detection", Severity = "error", Value = 3, Metric = "Active Threats", Description = "Suspicious activity", ProjectId = 3 },
                new Component { Id = 14, Name = "DDoS Protection", Severity = "ok", Value = 100, Metric = "Protection %", Description = "Fully active", ProjectId = 3 }
            );
        }
    }
}
