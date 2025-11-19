namespace OverviewDashboard.Models
{
    public class Component
    {
        public int Id { get; set; }
        public required string SystemName { get; set; }
        public required string ProjectName { get; set; }
        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
        public required string Payload { get; set; } // JSON string
    }
}
