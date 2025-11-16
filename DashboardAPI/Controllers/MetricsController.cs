using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using DashboardAPI.Data;
using DashboardAPI.DTOs;
using DashboardAPI.Models;

namespace DashboardAPI.Controllers
{
    /// <summary>
    /// API Controller for receiving metrics from monitoring agents
    /// </summary>
    [ApiController]
    [Route("api/[controller]")]
    [Produces("application/json")]
    public class MetricsController : ControllerBase
    {
        private readonly DashboardDbContext _context;
        private readonly ILogger<MetricsController> _logger;

        public MetricsController(DashboardDbContext context, ILogger<MetricsController> logger)
        {
            _context = context;
            _logger = logger;
        }

        /// <summary>
        /// Submit a single metric reading
        /// </summary>
        /// <param name="metricDto">Metric data</param>
        /// <returns>API response with status</returns>
        [HttpPost]
        [ProducesResponseType(StatusCodes.Status200OK)]
        [ProducesResponseType(StatusCodes.Status400BadRequest)]
        [ProducesResponseType(StatusCodes.Status404NotFound)]
        public async Task<ActionResult<ApiResponse<string>>> SubmitMetric([FromBody] MetricSubmissionDto metricDto)
        {
            try
            {
                _logger.LogInformation("Receiving metric for component: {ComponentId}", metricDto.ComponentId);

                // Validate severity
                if (!SeverityLevels.IsValid(metricDto.Severity))
                {
                    return BadRequest(new ApiResponse<string>
                    {
                        Success = false,
                        Message = $"Invalid severity level: {metricDto.Severity}. Valid values are: ok, warning, error, info"
                    });
                }

                // Find component
                var component = await _context.Components
                    .FirstOrDefaultAsync(c => c.ComponentId == metricDto.ComponentId && c.IsActive);

                if (component == null)
                {
                    _logger.LogWarning("Component not found: {ComponentId}", metricDto.ComponentId);
                    return NotFound(new ApiResponse<string>
                    {
                        Success = false,
                        Message = $"Component not found: {metricDto.ComponentId}"
                    });
                }

                // Create metric
                var metric = new ComponentMetric
                {
                    ComponentId = component.Id,
                    Severity = metricDto.Severity,
                    Value = metricDto.Value,
                    Metric = metricDto.Metric,
                    RawValue = metricDto.RawValue,
                    Description = metricDto.Description,
                    CollectedDate = DateTime.UtcNow
                };

                _context.ComponentMetrics.Add(metric);
                await _context.SaveChangesAsync();

                _logger.LogInformation("Metric saved successfully for component: {ComponentId}", metricDto.ComponentId);

                return Ok(new ApiResponse<string>
                {
                    Success = true,
                    Message = "Metric submitted successfully",
                    Data = metric.Id.ToString()
                });
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error submitting metric for component: {ComponentId}", metricDto.ComponentId);
                return StatusCode(500, new ApiResponse<string>
                {
                    Success = false,
                    Message = "An error occurred while submitting the metric"
                });
            }
        }

        /// <summary>
        /// Submit multiple metrics in a single request (batch)
        /// </summary>
        /// <param name="batchDto">Batch of metrics</param>
        /// <returns>API response with batch status</returns>
        [HttpPost("batch")]
        [ProducesResponseType(StatusCodes.Status200OK)]
        [ProducesResponseType(StatusCodes.Status400BadRequest)]
        public async Task<ActionResult<ApiResponse<Dictionary<string, string>>>> SubmitBatchMetrics(
            [FromBody] BatchMetricSubmissionDto batchDto)
        {
            try
            {
                _logger.LogInformation("Receiving batch of {Count} metrics", batchDto.Metrics.Count);

                var results = new Dictionary<string, string>();
                var metricsToAdd = new List<ComponentMetric>();

                // Get all unique component IDs
                var componentIds = batchDto.Metrics.Select(m => m.ComponentId).Distinct().ToList();
                
                // Fetch all components at once
                var components = await _context.Components
                    .Where(c => componentIds.Contains(c.ComponentId) && c.IsActive)
                    .ToDictionaryAsync(c => c.ComponentId, c => c);

                foreach (var metricDto in batchDto.Metrics)
                {
                    // Validate severity
                    if (!SeverityLevels.IsValid(metricDto.Severity))
                    {
                        results[metricDto.ComponentId] = $"Invalid severity: {metricDto.Severity}";
                        continue;
                    }

                    // Check if component exists
                    if (!components.TryGetValue(metricDto.ComponentId, out var component))
                    {
                        results[metricDto.ComponentId] = "Component not found";
                        continue;
                    }

                    // Create metric
                    metricsToAdd.Add(new ComponentMetric
                    {
                        ComponentId = component.Id,
                        Severity = metricDto.Severity,
                        Value = metricDto.Value,
                        Metric = metricDto.Metric,
                        RawValue = metricDto.RawValue,
                        Description = metricDto.Description,
                        CollectedDate = DateTime.UtcNow
                    });

                    results[metricDto.ComponentId] = "Success";
                }

                // Save all metrics at once
                if (metricsToAdd.Any())
                {
                    _context.ComponentMetrics.AddRange(metricsToAdd);
                    await _context.SaveChangesAsync();
                }

                _logger.LogInformation("Batch processed: {Success} successful, {Failed} failed",
                    results.Count(r => r.Value == "Success"),
                    results.Count(r => r.Value != "Success"));

                return Ok(new ApiResponse<Dictionary<string, string>>
                {
                    Success = true,
                    Message = $"Batch processed: {metricsToAdd.Count} metrics saved",
                    Data = results
                });
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error processing batch metrics");
                return StatusCode(500, new ApiResponse<Dictionary<string, string>>
                {
                    Success = false,
                    Message = "An error occurred while processing the batch"
                });
            }
        }

        /// <summary>
        /// Get latest metrics for a specific component
        /// </summary>
        /// <param name="componentId">Component ID</param>
        /// <param name="count">Number of recent metrics to retrieve (default: 10)</param>
        /// <returns>List of recent metrics</returns>
        [HttpGet("component/{componentId}")]
        [ProducesResponseType(StatusCodes.Status200OK)]
        [ProducesResponseType(StatusCodes.Status404NotFound)]
        public async Task<ActionResult<ApiResponse<List<ComponentMetric>>>> GetComponentMetrics(
            string componentId, 
            [FromQuery] int count = 10)
        {
            try
            {
                var component = await _context.Components
                    .FirstOrDefaultAsync(c => c.ComponentId == componentId);

                if (component == null)
                {
                    return NotFound(new ApiResponse<List<ComponentMetric>>
                    {
                        Success = false,
                        Message = $"Component not found: {componentId}"
                    });
                }

                var metrics = await _context.ComponentMetrics
                    .Where(m => m.ComponentId == component.Id)
                    .OrderByDescending(m => m.CollectedDate)
                    .Take(count)
                    .ToListAsync();

                return Ok(new ApiResponse<List<ComponentMetric>>
                {
                    Success = true,
                    Message = $"Retrieved {metrics.Count} metrics",
                    Data = metrics
                });
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error retrieving metrics for component: {ComponentId}", componentId);
                return StatusCode(500, new ApiResponse<List<ComponentMetric>>
                {
                    Success = false,
                    Message = "An error occurred while retrieving metrics"
                });
            }
        }

        /// <summary>
        /// Clean up old metrics (retention policy)
        /// </summary>
        /// <param name="daysToKeep">Number of days to keep (default: 30)</param>
        /// <returns>Number of deleted metrics</returns>
        [HttpDelete("cleanup")]
        [ProducesResponseType(StatusCodes.Status200OK)]
        public async Task<ActionResult<ApiResponse<int>>> CleanupOldMetrics([FromQuery] int daysToKeep = 30)
        {
            try
            {
                var cutoffDate = DateTime.UtcNow.AddDays(-daysToKeep);
                
                var oldMetrics = await _context.ComponentMetrics
                    .Where(m => m.CollectedDate < cutoffDate)
                    .ToListAsync();

                var count = oldMetrics.Count;
                _context.ComponentMetrics.RemoveRange(oldMetrics);
                await _context.SaveChangesAsync();

                _logger.LogInformation("Cleaned up {Count} old metrics (older than {Days} days)", count, daysToKeep);

                return Ok(new ApiResponse<int>
                {
                    Success = true,
                    Message = $"Deleted {count} old metrics",
                    Data = count
                });
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error cleaning up old metrics");
                return StatusCode(500, new ApiResponse<int>
                {
                    Success = false,
                    Message = "An error occurred during cleanup"
                });
            }
        }
    }
}
