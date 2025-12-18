using Microsoft.EntityFrameworkCore;
using OverviewDashboard.Data;

namespace OverviewDashboard.Services
{
    public class CleanupHostedService : BackgroundService
    {
        private readonly IServiceProvider _serviceProvider;
        private readonly ILogger<CleanupHostedService> _logger;
        private readonly IConfiguration _configuration;

        public CleanupHostedService(
            IServiceProvider serviceProvider,
            ILogger<CleanupHostedService> logger,
            IConfiguration configuration)
        {
            _serviceProvider = serviceProvider;
            _logger = logger;
            _configuration = configuration;
        }

        protected override async Task ExecuteAsync(CancellationToken stoppingToken)
        {
            _logger.LogInformation("Cleanup Hosted Service running.");

            using var timer = new PeriodicTimer(TimeSpan.FromHours(1));

            while (await timer.WaitForNextTickAsync(stoppingToken))
            {
                await DoWorkAsync();
            }
        }

        private async Task DoWorkAsync()
        {
            try
            {
                var thresholdMinutes = _configuration.GetValue<int>("Dashboard:DeleteThresholdMinutes", 10080); // Default 1 week
                if (thresholdMinutes <= 0)
                {
                    _logger.LogInformation("Cleanup disabled (threshold <= 0).");
                    return;
                }

                var deleteThreshold = DateTime.UtcNow.AddMinutes(-thresholdMinutes);

                using var scope = _serviceProvider.CreateScope();
                var db = scope.ServiceProvider.GetRequiredService<DashboardDbContext>();

                _logger.LogInformation("Cleaning up components older than {Threshold} (ThresholdMinutes: {Minutes})", deleteThreshold, thresholdMinutes);

                var count = await db.Components
                    .Where(c => c.CreatedAt < deleteThreshold)
                    .ExecuteDeleteAsync();

                if (count > 0)
                {
                    _logger.LogInformation("Deleted {Count} old components.", count);
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error occurred during cleanup.");
            }
        }
    }
}
