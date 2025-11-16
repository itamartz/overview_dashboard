using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using OverviewDashboard.Data;
using OverviewDashboard.DTOs;
using OverviewDashboard.Models;

namespace OverviewDashboard.Controllers
{
    /// <summary>
    /// API Controller for managing monitoring components in the IT infrastructure dashboard
    /// </summary>
    [ApiController]
    [Route("api/[controller]")]
    [Produces("application/json")]
    public class ComponentsController : ControllerBase
    {
        private readonly DashboardDbContext _context;
        private readonly ILogger<ComponentsController> _logger;

        public ComponentsController(DashboardDbContext context, ILogger<ComponentsController> logger)
        {
            _context = context;
            _logger = logger;
        }

        /// <summary>
        /// Get all components with their related project and system information
        /// </summary>
        /// <returns>A list of all components</returns>
        /// <response code="200">Returns the list of components</response>
        [HttpGet]
        [ProducesResponseType(StatusCodes.Status200OK)]
        public async Task<ActionResult<IEnumerable<Component>>> GetAll()
        {
            return await _context.Components
                .Include(c => c.Project)
                .ThenInclude(p => p!.System)
                .ToListAsync();
        }

        /// <summary>
        /// Get a specific component by ID
        /// </summary>
        /// <param name="id">The component ID</param>
        /// <returns>The requested component</returns>
        /// <response code="200">Returns the component</response>
        /// <response code="404">If the component is not found</response>
        [HttpGet("{id}")]
        [ProducesResponseType(StatusCodes.Status200OK)]
        [ProducesResponseType(StatusCodes.Status404NotFound)]
        public async Task<ActionResult<Component>> GetById(int id)
        {
            var component = await _context.Components
                .Include(c => c.Project)
                .ThenInclude(p => p!.System)
                .FirstOrDefaultAsync(c => c.Id == id);

            if (component == null)
            {
                return NotFound();
            }

            return component;
        }

        /// <summary>
        /// Create or update a component
        /// </summary>
        /// <param name="dto">Component data including system and project names</param>
        /// <returns>The created or updated component</returns>
        /// <remarks>
        /// Sample requests for each severity level:
        ///
        /// Example 1 - "ok" severity (green status):
        ///
        ///     POST /api/components
        ///     {
        ///        "name": "Database Server",
        ///        "severity": "ok",
        ///        "value": 98.5,
        ///        "metric": "Uptime %",
        ///        "description": "Primary database server running smoothly",
        ///        "projectName": "Backend Services",
        ///        "systemName": "Production Environment"
        ///     }
        ///
        /// Example 2 - "warning" severity (yellow/orange status):
        ///
        ///     POST /api/components
        ///     {
        ///        "name": "API Gateway",
        ///        "severity": "warning",
        ///        "value": 85.2,
        ///        "metric": "CPU Usage %",
        ///        "description": "CPU usage is approaching threshold",
        ///        "projectName": "Backend Services",
        ///        "systemName": "Production Environment"
        ///     }
        ///
        /// Example 3 - "error" severity (red status):
        ///
        ///     POST /api/components
        ///     {
        ///        "name": "Payment Service",
        ///        "severity": "error",
        ///        "value": 0,
        ///        "metric": "Status",
        ///        "description": "Service is down and not responding",
        ///        "projectName": "Backend Services",
        ///        "systemName": "Production Environment"
        ///     }
        ///
        /// Example 4 - "info" severity (blue status):
        ///
        ///     POST /api/components
        ///     {
        ///        "name": "Deployment Pipeline",
        ///        "severity": "info",
        ///        "value": 1,
        ///        "metric": "Active Deployments",
        ///        "description": "Deployment in progress to staging environment",
        ///        "projectName": "DevOps",
        ///        "systemName": "CI/CD"
        ///     }
        ///
        /// If a component with the same name exists in the specified project, it will be updated.
        /// If the system or project doesn't exist, they will be automatically created.
        ///
        /// Valid severity values: ok, warning, error, info
        /// </remarks>
        /// <response code="200">Component updated successfully</response>
        /// <response code="201">Component created successfully</response>
        /// <response code="500">Internal server error</response>
        [HttpPost]
        [ProducesResponseType(StatusCodes.Status200OK)]
        [ProducesResponseType(StatusCodes.Status201Created)]
        [ProducesResponseType(StatusCodes.Status500InternalServerError)]
        public async Task<ActionResult<Component>> Create([FromBody] ComponentDto dto)
        {
            try
            {
                // Find or create System
                var system = await _context.Systems
                    .FirstOrDefaultAsync(s => s.Name == dto.SystemName);

                if (system == null)
                {
                    system = new SystemEntity
                    {
                        Name = dto.SystemName,
                        Type = "environment"
                    };
                    _context.Systems.Add(system);
                    await _context.SaveChangesAsync();
                }

                // Find or create Project
                var project = await _context.Projects
                    .FirstOrDefaultAsync(p => p.Name == dto.ProjectName && p.SystemId == system.Id);

                if (project == null)
                {
                    project = new Project
                    {
                        Name = dto.ProjectName,
                        SystemId = system.Id
                    };
                    _context.Projects.Add(project);
                    await _context.SaveChangesAsync();
                }

                // Create or update Component
                var existingComponent = await _context.Components
                    .FirstOrDefaultAsync(c => c.Name == dto.Name && c.ProjectId == project.Id);

                if (existingComponent != null)
                {
                    // Update existing component
                    existingComponent.Severity = dto.Severity;
                    existingComponent.Value = dto.Value;
                    existingComponent.Metric = dto.Metric;
                    existingComponent.Description = dto.Description;
                    existingComponent.LastUpdate = DateTime.UtcNow;
                    await _context.SaveChangesAsync();

                    _logger.LogInformation("Updated component: {Name}", dto.Name);

                    return Ok(new
                    {
                        message = "Component updated successfully",
                        id = existingComponent.Id,
                        name = existingComponent.Name,
                        severity = existingComponent.Severity
                    });
                }
                else
                {
                    // Create new component
                    var component = new Component
                    {
                        Name = dto.Name,
                        Severity = dto.Severity,
                        Value = dto.Value,
                        Metric = dto.Metric,
                        Description = dto.Description,
                        ProjectId = project.Id,
                        LastUpdate = DateTime.UtcNow
                    };

                    _context.Components.Add(component);
                    await _context.SaveChangesAsync();

                    _logger.LogInformation("Created component: {Name}", dto.Name);

                    return CreatedAtAction(nameof(GetById), new { id = component.Id }, new
                    {
                        message = "Component created successfully",
                        id = component.Id,
                        name = component.Name,
                        severity = component.Severity,
                        projectName = dto.ProjectName,
                        systemName = dto.SystemName
                    });
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error creating component");
                return StatusCode(500, "An error occurred while creating the component");
            }
        }

        /// <summary>
        /// Delete a component by ID
        /// </summary>
        /// <param name="id">The component ID to delete</param>
        /// <returns>No content</returns>
        /// <response code="204">Component successfully deleted</response>
        /// <response code="404">Component not found</response>
        [HttpDelete("{id}")]
        [ProducesResponseType(StatusCodes.Status204NoContent)]
        [ProducesResponseType(StatusCodes.Status404NotFound)]
        public async Task<IActionResult> Delete(int id)
        {
            var component = await _context.Components.FindAsync(id);
            if (component == null)
            {
                return NotFound();
            }

            _context.Components.Remove(component);
            await _context.SaveChangesAsync();

            _logger.LogInformation("Deleted component: {Name} (ID: {Id})", component.Name, id);
            return NoContent();
        }

        /// <summary>
        /// Get complete hierarchical dashboard data (Systems > Projects > Components)
        /// </summary>
        /// <returns>All systems with their nested projects and components</returns>
        /// <remarks>
        /// Returns the entire hierarchical structure of the dashboard data:
        /// - Systems (top level)
        ///   - Projects (nested under systems)
        ///     - Components (nested under projects)
        ///
        /// This endpoint is useful for loading the complete dashboard structure in one request.
        /// </remarks>
        /// <response code="200">Returns the complete hierarchical data</response>
        [HttpGet("dashboard")]
        [ProducesResponseType(StatusCodes.Status200OK)]
        public async Task<ActionResult<object>> GetDashboardData()
        {
            var systems = await _context.Systems
                .Include(s => s.Projects)
                .ThenInclude(p => p.Components)
                .ToListAsync();

            return Ok(systems);
        }
    }
}
