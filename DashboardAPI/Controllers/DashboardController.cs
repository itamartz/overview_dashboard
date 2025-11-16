using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using DashboardAPI.Data;
using DashboardAPI.DTOs;

namespace DashboardAPI.Controllers
{
    /// <summary>
    /// API Controller for dashboard data retrieval
    /// </summary>
    [ApiController]
    [Route("api/[controller]")]
    [Produces("application/json")]
    public class DashboardController : ControllerBase
    {
        private readonly DashboardDbContext _context;
        private readonly ILogger<DashboardController> _logger;

        public DashboardController(DashboardDbContext context, ILogger<DashboardController> logger)
        {
            _context = context;
            _logger = logger;
        }

        /// <summary>
        /// Get complete dashboard data (all systems, projects, components with latest metrics)
        /// </summary>
        /// <returns>Hierarchical dashboard data</returns>
        [HttpGet]
        [ProducesResponseType(StatusCodes.Status200OK)]
        public async Task<ActionResult<ApiResponse<DashboardDataDto>>> GetDashboardData()
        {
            try
            {
                _logger.LogInformation("Fetching complete dashboard data");

                var systems = await _context.Systems
                    .Where(s => s.IsActive)
                    .Include(s => s.Projects.Where(p => p.IsActive))
                    .ThenInclude(p => p.Components.Where(c => c.IsActive))
                    .ToListAsync();

                var dashboardData = new DashboardDataDto
                {
                    LastUpdated = DateTime.UtcNow,
                    Systems = new List<SystemDto>()
                };

                foreach (var system in systems)
                {
                    var systemDto = new SystemDto
                    {
                        Id = system.Id,
                        SystemId = system.SystemId,
                        Name = system.Name,
                        Description = system.Description,
                        Projects = new List<ProjectDto>()
                    };

                    foreach (var project in system.Projects)
                    {
                        var projectDto = new ProjectDto
                        {
                            Id = project.Id,
                            ProjectId = project.ProjectId,
                            Name = project.Name,
                            Description = project.Description,
                            Components = new List<ComponentDto>()
                        };

                        foreach (var component in project.Components)
                        {
                            // Get latest metric for this component
                            var latestMetric = await _context.ComponentMetrics
                                .Where(m => m.ComponentId == component.Id)
                                .OrderByDescending(m => m.CollectedDate)
                                .FirstOrDefaultAsync();

                            var componentDto = new ComponentDto
                            {
                                Id = component.Id,
                                ComponentId = component.ComponentId,
                                Name = component.Name,
                                Description = component.Description,
                                ComponentType = component.ComponentType,
                                Severity = latestMetric?.Severity ?? "info",
                                Value = latestMetric?.Value ?? "N/A",
                                Metric = latestMetric?.Metric ?? "",
                                MetricDescription = latestMetric?.Description,
                                LastUpdate = latestMetric?.CollectedDate ?? component.ModifiedDate
                            };

                            projectDto.Components.Add(componentDto);
                        }

                        systemDto.Projects.Add(projectDto);
                    }

                    dashboardData.Systems.Add(systemDto);
                }

                _logger.LogInformation("Dashboard data retrieved successfully: {SystemCount} systems, {ComponentCount} total components",
                    dashboardData.Systems.Count,
                    dashboardData.Systems.Sum(s => s.Projects.Sum(p => p.Components.Count)));

                return Ok(new ApiResponse<DashboardDataDto>
                {
                    Success = true,
                    Message = "Dashboard data retrieved successfully",
                    Data = dashboardData
                });
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error retrieving dashboard data");
                return StatusCode(500, new ApiResponse<DashboardDataDto>
                {
                    Success = false,
                    Message = "An error occurred while retrieving dashboard data"
                });
            }
        }

        /// <summary>
        /// Get data for a specific system
        /// </summary>
        /// <param name="systemId">System ID</param>
        /// <returns>System data with projects and components</returns>
        [HttpGet("system/{systemId}")]
        [ProducesResponseType(StatusCodes.Status200OK)]
        [ProducesResponseType(StatusCodes.Status404NotFound)]
        public async Task<ActionResult<ApiResponse<SystemDto>>> GetSystemData(string systemId)
        {
            try
            {
                var system = await _context.Systems
                    .Where(s => s.SystemId == systemId && s.IsActive)
                    .Include(s => s.Projects.Where(p => p.IsActive))
                    .ThenInclude(p => p.Components.Where(c => c.IsActive))
                    .FirstOrDefaultAsync();

                if (system == null)
                {
                    return NotFound(new ApiResponse<SystemDto>
                    {
                        Success = false,
                        Message = $"System not found: {systemId}"
                    });
                }

                var systemDto = new SystemDto
                {
                    Id = system.Id,
                    SystemId = system.SystemId,
                    Name = system.Name,
                    Description = system.Description,
                    Projects = new List<ProjectDto>()
                };

                foreach (var project in system.Projects)
                {
                    var projectDto = new ProjectDto
                    {
                        Id = project.Id,
                        ProjectId = project.ProjectId,
                        Name = project.Name,
                        Description = project.Description,
                        Components = new List<ComponentDto>()
                    };

                    foreach (var component in project.Components)
                    {
                        var latestMetric = await _context.ComponentMetrics
                            .Where(m => m.ComponentId == component.Id)
                            .OrderByDescending(m => m.CollectedDate)
                            .FirstOrDefaultAsync();

                        projectDto.Components.Add(new ComponentDto
                        {
                            Id = component.Id,
                            ComponentId = component.ComponentId,
                            Name = component.Name,
                            Description = component.Description,
                            ComponentType = component.ComponentType,
                            Severity = latestMetric?.Severity ?? "info",
                            Value = latestMetric?.Value ?? "N/A",
                            Metric = latestMetric?.Metric ?? "",
                            MetricDescription = latestMetric?.Description,
                            LastUpdate = latestMetric?.CollectedDate ?? component.ModifiedDate
                        });
                    }

                    systemDto.Projects.Add(projectDto);
                }

                return Ok(new ApiResponse<SystemDto>
                {
                    Success = true,
                    Message = "System data retrieved successfully",
                    Data = systemDto
                });
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error retrieving system data: {SystemId}", systemId);
                return StatusCode(500, new ApiResponse<SystemDto>
                {
                    Success = false,
                    Message = "An error occurred while retrieving system data"
                });
            }
        }

        /// <summary>
        /// Get summary statistics for the dashboard
        /// </summary>
        /// <returns>Dashboard statistics</returns>
        [HttpGet("stats")]
        [ProducesResponseType(StatusCodes.Status200OK)]
        public async Task<ActionResult<ApiResponse<object>>> GetDashboardStats()
        {
            try
            {
                var totalSystems = await _context.Systems.CountAsync(s => s.IsActive);
                var totalProjects = await _context.Projects.CountAsync(p => p.IsActive);
                var totalComponents = await _context.Components.CountAsync(c => c.IsActive);

                // Get latest metrics per component and count by severity
                var componentIds = await _context.Components
                    .Where(c => c.IsActive)
                    .Select(c => c.Id)
                    .ToListAsync();

                var latestMetrics = new List<string>();
                foreach (var componentId in componentIds)
                {
                    var latestMetric = await _context.ComponentMetrics
                        .Where(m => m.ComponentId == componentId)
                        .OrderByDescending(m => m.CollectedDate)
                        .Select(m => m.Severity)
                        .FirstOrDefaultAsync();
                    
                    if (latestMetric != null)
                    {
                        latestMetrics.Add(latestMetric);
                    }
                }

                var stats = new
                {
                    TotalSystems = totalSystems,
                    TotalProjects = totalProjects,
                    TotalComponents = totalComponents,
                    SeverityCounts = new
                    {
                        Ok = latestMetrics.Count(m => m == "ok"),
                        Warning = latestMetrics.Count(m => m == "warning"),
                        Error = latestMetrics.Count(m => m == "error"),
                        Info = latestMetrics.Count(m => m == "info")
                    },
                    LastUpdated = DateTime.UtcNow
                };

                return Ok(new ApiResponse<object>
                {
                    Success = true,
                    Message = "Statistics retrieved successfully",
                    Data = stats
                });
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error retrieving dashboard statistics");
                return StatusCode(500, new ApiResponse<object>
                {
                    Success = false,
                    Message = "An error occurred while retrieving statistics"
                });
            }
        }
    }
}
