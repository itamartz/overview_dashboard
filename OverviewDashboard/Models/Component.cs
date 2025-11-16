namespace OverviewDashboard.Models
{
    public class Component
    {
        public int Id { get; set; }
        public required string Name { get; set; }
        public required string Severity { get; set; } // "ok", "warning", "error", "info"
        public double Value { get; set; }
        public required string Metric { get; set; } // e.g., "Uptime %", "CPU %"
        public required string Description { get; set; }
        public DateTime LastUpdate { get; set; } = DateTime.UtcNow;
        public int ProjectId { get; set; }

        // Navigation property
        public Project? Project { get; set; }
    }
}
