# Project Roadmap & Improvements

Here is a prioritized list of features and improvements to take the **Overview Dashboard** from a "working prototype" to a robust "production system".

### 1. 🛡️ Security (Critical)
Currently, the dashboard and API are open to everyone.
*   **Web Authentication**: Implement **ASP.NET Core Identity** so only authorized users can view the dashboard or delete components.
*   **API Security**: Add **API Key Authentication** for endpoints.
    *   *Why*: Right now, anyone on the network can POST fake data to the API.
    *   *How*: Middleware that checks for an `X-Api-Key` header against a stored secret.

### 2. 🚀 Performance & Scalability
The current `LoadData()` fetches `dbContext.Components.ToListAsync()` every 2 seconds.
*   **The Problem**: As the database grows to 100k+ records, this **will** crash the server (Out of Memory) or become incredibly slow.
*   **The Fix**:
    *   **Dashboard View**: Query only the *latest* entry for each `SystemName` + `ProjectName`.
    *   **History View**: Only load the full history when a user clicks on a specific component.
    *   **Data Retention**: Implement a background service to delete/archive records older than 30 days.

### 3. 📊 Historical Data & Charts
Currently collecting time-series data but only showing a table.
*   **Charts**: Add a modal or detail page when clicking a row.
    *   *Feature*: Show a line chart for CPU/Memory usage over the last 24 hours.
    *   *Tech*: Use a library like **ApexCharts** or **Blazor.Chartjs**.
*   **Change Log**: Show a diff view of what changed between updates (e.g., "Status changed from OK to Error").

### 4. 🔔 Alerting & Notifications
The dashboard requires someone to be looking at it to see errors.
*   **Proactive Alerting**: Add a background service that checks for incoming "Error" severity.
*   **Integrations**: Send notifications via:
    *   **Email** (SMTP)
    *   **Slack/Teams** (Webhooks)
    *   *Logic*: "If status is Error for > 5 minutes, send alert."

### 5. 💓 Heartbeat Monitoring
If a server crashes completely, the agent stops sending data. The dashboard will just show the last "OK" status forever.
*   **Stale Data Detection**: Add a visual indicator (e.g., a greyed-out row or clock icon) if a component hasn't updated in > 10 minutes.
*   **"Offline" Status**: Automatically treat silent agents as "Error" or "Offline" after a threshold.

### 6. ⚡ Architecture Improvement
*   **Push vs. Polling**: Currently polling the DB every 2 seconds (`System.Threading.Timer`).
*   **Better Approach**: Use **SignalR** to push updates.
    *   When the API Controller receives a POST -> It sends a message to the SignalR Hub -> The Hub updates the UI clients instantly.
    *   This reduces database load significantly.

### 7. 🎨 UI/UX Polish
*   **Dark/Light Mode Toggle**: Essential for operations centers.
*   **Export Data**: Add a "Download CSV" button for reporting purposes.
*   **Search**: Add a global search bar to find specific servers/projects quickly.
