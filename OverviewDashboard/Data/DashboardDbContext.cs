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
        }
    }
}
