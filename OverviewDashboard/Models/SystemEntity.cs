namespace OverviewDashboard.Models
{
    public class SystemEntity
    {
        public int Id { get; set; }
        public required string Name { get; set; }
        public required string Type { get; set; } // e.g., "environment"
        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
        public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;

        // Navigation property
        public ICollection<Project> Projects { get; set; } = new List<Project>();
    }
}
