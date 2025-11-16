using Microsoft.AspNetCore.SignalR;

namespace OverviewDashboard.Hubs
{
    public class DashboardHub : Hub
    {
        public async Task NotifyDataChanged()
        {
            await Clients.All.SendAsync("DataChanged");
        }
    }
}
