using Microsoft.EntityFrameworkCore;
using OverviewDashboard.Models;

namespace OverviewDashboard.Data
{
    public class DashboardDbContext : DbContext
    {
        public DashboardDbContext(DbContextOptions<DashboardDbContext> options) : base(options)
        {
        }

        public DbSet<Component> Components { get; set; }

        protected override void OnModelCreating(ModelBuilder modelBuilder)
        {
            base.OnModelCreating(modelBuilder);

            // Configure Component
            modelBuilder.Entity<Component>()
                .HasKey(c => c.Id);

            modelBuilder.Entity<Component>()
                .Property(c => c.SystemName)
                .IsRequired();

            modelBuilder.Entity<Component>()
                .Property(c => c.ProjectName)
                .IsRequired();

            modelBuilder.Entity<Component>()
                .Property(c => c.Payload)
                .IsRequired();

            // Seed data
            SeedData(modelBuilder);
        }

        private void SeedData(ModelBuilder modelBuilder)
        {
            // Sample data with dynamic payloads
            modelBuilder.Entity<Component>().HasData(
                new Component 
                { 
                    Id = 1, 
                    SystemName = "ActiveDirectory", 
                    ProjectName = "UserAudit", 
                    Payload = "{\"Username\": \"user08\", \"ou\": \"OU=IT,DC=corp,DC=local\", \"inactive_days\": 60, \"status\": \"locked\", \"Severity\": \"error\"}",
                    CreatedAt = DateTime.UtcNow 
                },
                new Component 
                { 
                    Id = 2, 
                    SystemName = "WSUS", 
                    ProjectName = "PatchCompliance", 
                    Payload = "{\"Computername\": \"PC-009\", \"OS\": \"Windows 11\", \"LastReport\": \"2025-06-18\", \"Installed\": 16, \"NotApplicable\": 2, \"Needed\": 2, \"Total\": 20, \"Percent\": 80, \"Severity\": \"good\"}",
                    CreatedAt = DateTime.UtcNow 
                },
                new Component 
                { 
                    Id = 3, 
                    SystemName = "vCenter", 
                    ProjectName = "StorageHealth", 
                    Payload = "{\"Datastore\": \"DS08\", \"Type\": \"vSAN\", \"Used\": 9000, \"Free\": 1000, \"Capacity\": 10000, \"Severity\": \"error\"}",
                    CreatedAt = DateTime.UtcNow 
                }
            );
        }
    }
}
