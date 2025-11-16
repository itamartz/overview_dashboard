using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.SignalR;
using Microsoft.EntityFrameworkCore;
using OverviewDashboard.Data;
using OverviewDashboard.DTOs;
using OverviewDashboard.Hubs;
using OverviewDashboard.Models;

namespace OverviewDashboard.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    public class ComponentsController : ControllerBase
    {
        private readonly DashboardDbContext _context;
        private readonly ILogger<ComponentsController> _logger;
        private readonly IHubContext<DashboardHub> _hubContext;

        public ComponentsController(DashboardDbContext context, ILogger<ComponentsController> logger, IHubContext<DashboardHub> hubContext)
        {
            _context = context;
            _logger = logger;
            _hubContext = hubContext;
        }

        // GET: api/components
        [HttpGet]
        public async Task<ActionResult<IEnumerable<Component>>> GetAll()
        {
            return await _context.Components
                .Include(c => c.Project)
                .ThenInclude(p => p!.System)
                .ToListAsync();
        }

        // GET: api/components/{id}
        [HttpGet("{id}")]
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

        // POST: api/components
        [HttpPost]
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

                    // Notify all connected clients
                    await _hubContext.Clients.All.SendAsync("DataChanged");

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

                    // Notify all connected clients
                    await _hubContext.Clients.All.SendAsync("DataChanged");

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

        // DELETE: api/components/{id}
        [HttpDelete("{id}")]
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

        // GET: api/components/dashboard - Get hierarchical data for dashboard
        [HttpGet("dashboard")]
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
