# Project Roadmap & Improvements

Here is a prioritized list of features and improvements to take the **Overview Dashboard** from a "working prototype" to a robust "production system".

### 1. 🛡️ Security (Critical)
Currently, the dashboard and API are open to everyone.
*   **Web Authentication**: Implement **ASP.NET Core Identity** so only authorized users can view the dashboard or delete components.
*   **API Security**: Add **API Key Authentication** for endpoints.
    *   *Why*: Right now, anyone on the network can POST fake data to the API.
    *   *How*: Middleware that checks for an `X-Api-Key` header against a stored secret.

### 2. 🚀 Performance & Scalability (✅ DONE)
*   **Fix**: Pagination has been implemented for component views, preventing crashes on large datasets.
*   **Optimization**: System Summary uses efficient grouping queries.

### 3. 📊 Historical Data & Charts
Currently collecting time-series data.
*   **Charts**: Add a modal or detail page when clicking a row.
    *   *Feature*: Show a line chart for CPU/Memory usage over the last 24 hours.
*   **Change Log**: Show a diff view of what changed between updates.

### 4. 🔔 Alerting & Notifications
The dashboard requires someone to be looking at it to see errors.
*   **Proactive Alerting**: Add a background service that checks for incoming "Error" severity.
*   **Integrations**: Send notifications via Email or Slack.

### 5. 💓 Heartbeat Monitoring (✅ DONE)
*   **Stale Data Detection**: Implemented globally (1h default).
*   **Dynamic TTL**: Components can now specify their own per-request TTL (in seconds) via the API.
*   **"Offline" Status**: Items automatically turn grey ("offline") when the TTL expires.

### 6. ⚡ Architecture Improvement
*   **Push vs. Polling**: Currently utilizing SignalR for some updates, but polling still exists for fallback.

### 7. 🎨 UI/UX Polish (✅ DONE)
*   **Project Summary**: Implemented Masonry (Pinterest-style) layout for system overviews.
*   **Search**: Global search added to project detail views.
*   **Navigation**: Improved hierarchical navigation (Systems -> Projects).

