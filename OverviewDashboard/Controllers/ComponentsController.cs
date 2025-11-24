using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.SignalR;
using Microsoft.EntityFrameworkCore;
using OverviewDashboard.Data;
using OverviewDashboard.Hubs;
using OverviewDashboard.Models;
using OverviewDashboard.Services;
using System.Text.Json;

namespace OverviewDashboard.Controllers
{
    /// <summary>
    /// API Controller for managing monitoring components with dynamic payloads
    /// </summary>
    [ApiController]
    [Route("api/[controller]")]
    [Produces("application/json")]
    public class ComponentsController : ControllerBase
    {
        private readonly DashboardDbContext _context;
        private readonly ILogger<ComponentsController> _logger;
        private readonly IHubContext<DashboardHub> _hubContext;
        private readonly DashboardStateService _stateService;

        public ComponentsController(DashboardDbContext context, ILogger<ComponentsController> logger, IHubContext<DashboardHub> hubContext, DashboardStateService stateService)
        {
            _context = context;
            _logger = logger;
            _hubContext = hubContext;
            _stateService = stateService;
        }

        /// <summary>
        /// Get all components
        /// </summary>
        /// <returns>A list of all components</returns>
        [HttpGet]
        public async Task<ActionResult<IEnumerable<Component>>> GetAll()
        {
            return await _context.Components.ToListAsync();
        }

        /// <summary>
        /// Get a specific component by ID
        /// </summary>
        [HttpGet("{id}")]
        public async Task<ActionResult<Component>> GetById(int id)
        {
            var component = await _context.Components.FindAsync(id);

            if (component == null)
            {
                return NotFound();
            }

            return component;
        }

        /// <summary>
        /// Create a new component entry
        /// </summary>
        /// <param name="request">The component data</param>
        /// <returns>The created component</returns>
        [HttpPost]
        public async Task<ActionResult<Component>> Create([FromBody] JsonElement request)
        {
            try
            {
                // Extract required fields
                if (!request.TryGetProperty("systemName", out var systemNameProp) ||
                    !request.TryGetProperty("projectName", out var projectNameProp) ||
                    !request.TryGetProperty("payload", out var payloadProp))
                {
                    return BadRequest("Missing required fields: systemName, projectName, payload");
                }

                var systemName = systemNameProp.GetString();
                var projectName = projectNameProp.GetString();
                
                if (string.IsNullOrEmpty(systemName) || string.IsNullOrEmpty(projectName))
                {
                    return BadRequest("systemName and projectName cannot be empty");
                }

                // Check for "Id" in the payload for Upsert logic
                string? payloadId = null;
                if (payloadProp.ValueKind == JsonValueKind.Object && payloadProp.TryGetProperty("Id", out var idProp))
                {
                    payloadId = idProp.ToString();
                }

                Component? existingComponent = null;

                if (!string.IsNullOrEmpty(payloadId))
                {
                    // Find existing component with same System, Project, and Payload.Id
                    // Since Payload is a string, we have to fetch candidates and parse
                    var candidates = await _context.Components
                        .Where(c => c.SystemName == systemName && c.ProjectName == projectName)
                        .ToListAsync();

                    foreach (var c in candidates)
                    {
                        try
                        {
                            using var doc = JsonDocument.Parse(c.Payload);
                            if (doc.RootElement.TryGetProperty("Id", out var existingIdProp) && 
                                existingIdProp.ToString() == payloadId)
                            {
                                existingComponent = c;
                                break;
                            }
                        }
                        catch
                        {
                            // Ignore parsing errors for existing data
                        }
                    }
                }

                if (existingComponent != null)
                {
                    // Update existing
                    existingComponent.Payload = payloadProp.ToString();
                    existingComponent.CreatedAt = DateTime.UtcNow; // Update timestamp
                    
                    _context.Components.Update(existingComponent);
                    await _context.SaveChangesAsync();
                    
                    _logger.LogInformation("Updated component {Id} for System: {System}, Project: {Project}", payloadId, systemName, projectName);
                    
                    // Notify clients (SignalR)
                    await _hubContext.Clients.All.SendAsync("DataChanged");
                    
                    // Notify internal state (Blazor Server)
                    _stateService.NotifyStateChanged();
                    
                    return Ok(existingComponent);
                }
                else
                {
                    // Create new component
                    var component = new Component
                    {
                        SystemName = systemName,
                        ProjectName = projectName,
                        Payload = payloadProp.ToString(), // Store payload as JSON string
                        CreatedAt = DateTime.UtcNow
                    };

                    _context.Components.Add(component);
                    await _context.SaveChangesAsync();

                    _logger.LogInformation("Created component for System: {System}, Project: {Project}", systemName, projectName);

                    // Notify clients (SignalR)
                    await _hubContext.Clients.All.SendAsync("DataChanged");

                    // Notify internal state (Blazor Server)
                    _stateService.NotifyStateChanged();

                    return CreatedAtAction(nameof(GetById), new { id = component.Id }, component);
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

            // Notify clients (SignalR)
            await _hubContext.Clients.All.SendAsync("DataChanged");

            // Notify internal state (Blazor Server)
            _stateService.NotifyStateChanged();

            return NoContent();
        }
    }
}
