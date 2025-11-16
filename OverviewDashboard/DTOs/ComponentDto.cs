namespace OverviewDashboard.DTOs
{
    public class ComponentDto
    {
        public required string Name { get; set; }
        public required string Severity { get; set; } // "ok", "warning", "error", "info"
        public double Value { get; set; }
        public required string Metric { get; set; }
        public required string Description { get; set; }
        public required string ProjectName { get; set; }
        public required string SystemName { get; set; }
    }
}
