using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace DashboardAPI.Models
{
    /// <summary>
    /// Represents a project within a system (e.g., Web Servers, Database Cluster)
    /// </summary>
    public class Project
    {
        [Key]
        [DatabaseGenerated(DatabaseGeneratedOption.Identity)]
        public int Id { get; set; }

        [Required]
        [MaxLength(50)]
        public string ProjectId { get; set; } = string.Empty;

        [Required]
        public int SystemId { get; set; }

        [Required]
        [MaxLength(200)]
        public string Name { get; set; } = string.Empty;

        [MaxLength(500)]
        public string? Description { get; set; }

        public bool IsActive { get; set; } = true;

        public DateTime CreatedDate { get; set; } = DateTime.UtcNow;

        public DateTime ModifiedDate { get; set; } = DateTime.UtcNow;

        // Navigation properties
        [ForeignKey(nameof(SystemId))]
        public virtual SystemEntity? System { get; set; }

        public virtual ICollection<Component> Components { get; set; } = new List<Component>();
    }
}
