using System.Net.Http.Json;
using BlazorDashboard.Models;

namespace BlazorDashboard.Services
{
    public interface IDashboardService
    {
        Task<DashboardData?> GetDashboardDataAsync();
        Task<SystemModel?> GetSystemDataAsync(string systemId);
    }

    public class DashboardService : IDashboardService
    {
        private readonly IHttpClientFactory _httpClientFactory;
        private readonly ILogger<DashboardService> _logger;

        public DashboardService(IHttpClientFactory httpClientFactory, ILogger<DashboardService> logger)
        {
            _httpClientFactory = httpClientFactory;
            _logger = logger;
        }

        public async Task<DashboardData?> GetDashboardDataAsync()
        {
            try
            {
                var client = _httpClientFactory.CreateClient("DashboardAPI");
                var response = await client.GetFromJsonAsync<ApiResponse<DashboardData>>("api/dashboard");

                if (response?.Success == true && response.Data != null)
                {
                    _logger.LogInformation("Successfully retrieved dashboard data");
                    return response.Data;
                }

                _logger.LogWarning("Failed to retrieve dashboard data: {Message}", response?.Message);
                return null;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error retrieving dashboard data");
                return null;
            }
        }

        public async Task<SystemModel?> GetSystemDataAsync(string systemId)
        {
            try
            {
                var client = _httpClientFactory.CreateClient("DashboardAPI");
                var response = await client.GetFromJsonAsync<ApiResponse<SystemModel>>($"api/dashboard/system/{systemId}");

                if (response?.Success == true && response.Data != null)
                {
                    _logger.LogInformation("Successfully retrieved system data for {SystemId}", systemId);
                    return response.Data;
                }

                _logger.LogWarning("Failed to retrieve system data for {SystemId}: {Message}", systemId, response?.Message);
                return null;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error retrieving system data for {SystemId}", systemId);
                return null;
            }
        }
    }
}
