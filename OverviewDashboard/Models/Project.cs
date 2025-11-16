namespace OverviewDashboard.Models
{
    public class Project
    {
        public int Id { get; set; }
        public required string Name { get; set; }
        public int SystemId { get; set; }
        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
        public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;

        // Navigation properties
        public SystemEntity? System { get; set; }
        public ICollection<Component> Components { get; set; } = new List<Component>();
    }
}
