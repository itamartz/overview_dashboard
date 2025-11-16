namespace BlazorDashboard.Models
{
    public class DashboardData
    {
        public List<SystemModel> Systems { get; set; } = new();
        public DateTime LastUpdated { get; set; }
    }

    public class SystemModel
    {
        public int Id { get; set; }
        public string SystemId { get; set; } = string.Empty;
        public string Name { get; set; } = string.Empty;
        public string? Description { get; set; }
        public List<ProjectModel> Projects { get; set; } = new();
    }

    public class ProjectModel
    {
        public int Id { get; set; }
        public string ProjectId { get; set; } = string.Empty;
        public string Name { get; set; } = string.Empty;
        public string? Description { get; set; }
        public List<ComponentModel> Components { get; set; } = new();
    }

    public class ComponentModel
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

    public class ApiResponse<T>
    {
        public bool Success { get; set; }
        public string? Message { get; set; }
        public T? Data { get; set; }
        public DateTime Timestamp { get; set; }
    }

    public class SeverityCounts
    {
        public int Ok { get; set; }
        public int Warning { get; set; }
        public int Error { get; set; }
        public int Info { get; set; }

        public string GetWorstSeverity()
        {
            if (Error > 0) return "error";
            if (Warning > 0) return "warning";
            if (Info > 0) return "info";
            return "ok";
        }

        public int GetCount(string severity)
        {
            return severity.ToLower() switch
            {
                "ok" => Ok,
                "warning" => Warning,
                "error" => Error,
                "info" => Info,
                _ => 0
            };
        }
    }
}
