using System.ComponentModel.DataAnnotations;

namespace DashboardAPI.DTOs
{
    /// <summary>
    /// DTO for submitting metric data from agents
    /// </summary>
    public class MetricSubmissionDto
    {
        [Required]
        [MaxLength(50)]
        public string ComponentId { get; set; } = string.Empty;

        [Required]
        [MaxLength(20)]
        public string Severity { get; set; } = "info";

        [Required]
        [MaxLength(100)]
        public string Value { get; set; } = string.Empty;

        [Required]
        [MaxLength(50)]
        public string Metric { get; set; } = string.Empty;

        public decimal? RawValue { get; set; }

        [MaxLength(1000)]
        public string? Description { get; set; }
    }

    /// <summary>
    /// DTO for batch metric submission
    /// </summary>
    public class BatchMetricSubmissionDto
    {
        [Required]
        public List<MetricSubmissionDto> Metrics { get; set; } = new();
    }

    /// <summary>
    /// DTO for dashboard data response
    /// </summary>
    public class DashboardDataDto
    {
        public List<SystemDto> Systems { get; set; } = new();
        public DateTime LastUpdated { get; set; } = DateTime.UtcNow;
    }

    /// <summary>
    /// System DTO with nested projects and components
    /// </summary>
    public class SystemDto
    {
        public int Id { get; set; }
        public string SystemId { get; set; } = string.Empty;
        public string Name { get; set; } = string.Empty;
        public string? Description { get; set; }
        public List<ProjectDto> Projects { get; set; } = new();
    }

    /// <summary>
    /// Project DTO with components
    /// </summary>
    public class ProjectDto
    {
        public int Id { get; set; }
        public string ProjectId { get; set; } = string.Empty;
        public string Name { get; set; } = string.Empty;
        public string? Description { get; set; }
        public List<ComponentDto> Components { get; set; } = new();
    }

    /// <summary>
    /// Component DTO with latest metric
    /// </summary>
    public class ComponentDto
    {
        public int Id { get; set; }
        public string ComponentId { get; set; } = string.Empty;
        public string Name { get; set; } = string.Empty;
        public string? Description { get; set; }
        public string ComponentType { get; set; } = string.Empty;
        public string Severity { get; set; } = "info";
        public string Value { get; set; } = string.Empty;
        public string Metric { get; set; } = string.Empty;
        public string? MetricDescription { get; set; }
        public DateTime LastUpdate { get; set; }
    }

    /// <summary>
    /// Response wrapper for API calls
    /// </summary>
    /// <typeparam name="T"></typeparam>
    public class ApiResponse<T>
    {
        public bool Success { get; set; }
        public string? Message { get; set; }
        public T? Data { get; set; }
        public DateTime Timestamp { get; set; } = DateTime.UtcNow;
    }
}
