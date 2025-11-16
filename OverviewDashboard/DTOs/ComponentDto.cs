namespace OverviewDashboard.DTOs
{
    /// <summary>
    /// Data Transfer Object for creating or updating a monitoring component
    /// </summary>
    public class ComponentDto
    {
        /// <summary>
        /// The name of the component (e.g., "Database Server", "API Gateway")
        /// </summary>
        /// <example>Database Server</example>
        public required string Name { get; set; }

        /// <summary>
        /// The severity level of the component status
        /// </summary>
        /// <remarks>
        /// Valid values:
        /// - "ok": Component is functioning normally (green status)
        /// - "warning": Component needs attention (yellow/orange status)
        /// - "error": Component has critical issues (red status)
        /// - "info": Informational status (blue status)
        /// </remarks>
        /// <example>ok</example>
        public required string Severity { get; set; }

        /// <summary>
        /// Numeric value associated with the component metric
        /// </summary>
        /// <example>98.5</example>
        public double Value { get; set; }

        /// <summary>
        /// The metric being measured (e.g., "Uptime %", "CPU Usage", "Memory MB")
        /// </summary>
        /// <example>Uptime %</example>
        public required string Metric { get; set; }

        /// <summary>
        /// Detailed description of the component
        /// </summary>
        /// <example>Primary database server running PostgreSQL</example>
        public required string Description { get; set; }

        /// <summary>
        /// The name of the project this component belongs to. Will be created if it doesn't exist.
        /// </summary>
        /// <example>Backend Services</example>
        public required string ProjectName { get; set; }

        /// <summary>
        /// The name of the system this component belongs to. Will be created if it doesn't exist.
        /// </summary>
        /// <example>Production Environment</example>
        public required string SystemName { get; set; }
    }
}
