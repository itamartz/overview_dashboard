using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace DashboardAPI.Models
{
    /// <summary>
    /// Represents a metric reading for a component (CPU, Memory, Disk, etc.)
    /// </summary>
    public class ComponentMetric
    {
        [Key]
        [DatabaseGenerated(DatabaseGeneratedOption.Identity)]
        public long Id { get; set; }

        [Required]
        public int ComponentId { get; set; }

        [Required]
        [MaxLength(20)]
        public string Severity { get; set; } = "info"; // ok, warning, error, info

        [Required]
        [MaxLength(100)]
        public string Value { get; set; } = string.Empty;

        [Required]
        [MaxLength(50)]
        public string Metric { get; set; } = string.Empty;

        [Column(TypeName = "decimal(18,4)")]
        public decimal? RawValue { get; set; }

        [MaxLength(1000)]
        public string? Description { get; set; }

        public DateTime CollectedDate { get; set; } = DateTime.UtcNow;

        // Navigation properties
        [ForeignKey(nameof(ComponentId))]
        public virtual Component? Component { get; set; }
    }

    /// <summary>
    /// Valid severity levels
    /// </summary>
    public static class SeverityLevels
    {
        public const string Ok = "ok";
        public const string Warning = "warning";
        public const string Error = "error";
        public const string Info = "info";

        public static bool IsValid(string severity)
        {
            return severity switch
            {
                Ok or Warning or Error or Info => true,
                _ => false
            };
        }
    }
}
