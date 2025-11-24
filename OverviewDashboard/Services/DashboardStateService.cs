namespace OverviewDashboard.Services
{
    public class DashboardStateService
    {
        public event Action? OnChange;

        public void NotifyStateChanged() => OnChange?.Invoke();
    }
}
