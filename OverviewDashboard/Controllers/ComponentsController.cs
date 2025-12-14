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

                // Helper to safely get string property case-insensitive
                string? GetStringPropertyCaseInsensitive(JsonElement element, string propName)
                {
                    if (element.ValueKind != JsonValueKind.Object) return null;
                    foreach (var prop in element.EnumerateObject())
                    {
                        if (string.Equals(prop.Name, propName, StringComparison.OrdinalIgnoreCase))
                        {
                            return prop.Value.ToString();
                        }
                    }
                    return null;
                }

                // Prepare payload element for inspection
                JsonElement payloadElement = payloadProp;
                if (payloadProp.ValueKind == JsonValueKind.String)
                {
                    try
                    {
                        // If payload is a string, try to parse it as JSON object to check fields
                        var doc = JsonDocument.Parse(payloadProp.GetString()!);
                        payloadElement = doc.RootElement;
                    }
                    catch
                    {
                        // Not valid JSON string, treat as opaque string
                    }
                }

                string? payloadId = GetStringPropertyCaseInsensitive(payloadElement, "Id");
                string? payloadName = GetStringPropertyCaseInsensitive(payloadElement, "Name");
                string? payloadNamespace = GetStringPropertyCaseInsensitive(payloadElement, "Namespace");

                Component? existingComponent = null;

                if (!string.IsNullOrEmpty(payloadId) || !string.IsNullOrEmpty(payloadName))
                {
                    // Find existing component with same System, Project, and Payload details
                    var candidates = await _context.Components
                        .Where(c => c.SystemName == systemName && c.ProjectName == projectName)
                        .ToListAsync();

                    foreach (var c in candidates)
                    {
                        try
                        {
                            using var doc = JsonDocument.Parse(c.Payload);
                            var root = doc.RootElement;
                            bool isMatch = false;

                            // 1. Try matching by ID
                            if (!string.IsNullOrEmpty(payloadId))
                            {
                                var existingId = GetStringPropertyCaseInsensitive(root, "Id");
                                if (existingId == payloadId)
                                {
                                    isMatch = true;
                                }
                            }
                            // 2. Try matching by Name (and Namespace)
                            else if (!string.IsNullOrEmpty(payloadName))
                            {
                                var existingName = GetStringPropertyCaseInsensitive(root, "Name");
                                if (existingName == payloadName)
                                {
                                    // Check Namespace
                                    if (!string.IsNullOrEmpty(payloadNamespace))
                                    {
                                        var existingNamespace = GetStringPropertyCaseInsensitive(root, "Namespace");
                                        if (existingNamespace == payloadNamespace)
                                        {
                                            isMatch = true;
                                        }
                                    }
                                    else
                                    {
                                        // Match by Name only if Namespace not provided in request
                                        isMatch = true;
                                    }
                                }
                            }

                            if (isMatch)
                            {
                                existingComponent = c;
                                break;
                            }
                        }
                        catch
                        {
                            // Ignore parsing errors
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

        /// <summary>
        /// Delete all components for a specific system and project
        /// </summary>
        /// <param name="systemName">The name of the system</param>
        /// <param name="projectName">The name of the project to clear</param>
        /// <returns>The number of components deleted</returns>
        [HttpDelete("system/{systemName}/project/{projectName}")]
        public async Task<IActionResult> DeleteBySystemAndProject(string systemName, string projectName)
        {
            if (string.IsNullOrEmpty(systemName))
            {
                return BadRequest("System name cannot be empty");
            }

            if (string.IsNullOrEmpty(projectName))
            {
                return BadRequest("Project name cannot be empty");
            }

            var components = await _context.Components
                .Where(c => c.SystemName == systemName && c.ProjectName == projectName)
                .ToListAsync();

            if (!components.Any())
            {
                return NotFound($"No components found for system '{systemName}' and project '{projectName}'");
            }

            var count = components.Count;
            _context.Components.RemoveRange(components);
            await _context.SaveChangesAsync();

            _logger.LogInformation("Deleted {Count} components from system '{SystemName}', project '{ProjectName}'", count, systemName, projectName);

            // Notify clients (SignalR)
            await _hubContext.Clients.All.SendAsync("DataChanged");

            // Notify internal state (Blazor Server)
            _stateService.NotifyStateChanged();

            return Ok(new { message = $"Deleted {count} components from system '{systemName}', project '{projectName}'", count });
        }
    }
}
