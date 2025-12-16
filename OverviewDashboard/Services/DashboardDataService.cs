using Microsoft.EntityFrameworkCore;
using OverviewDashboard.Data;
using OverviewDashboard.Models;
using System.Text.Json;

namespace OverviewDashboard.Services
{
    public class DashboardDataService
    {
        private readonly IServiceScopeFactory _scopeFactory;
        private static readonly TimeSpan StaleThreshold = TimeSpan.FromHours(1);

        public DashboardDataService(IServiceScopeFactory scopeFactory)
        {
            _scopeFactory = scopeFactory;
        }

        /// <summary>
        /// Get summary counts for navigation panel - efficient database query
        /// </summary>
        public async Task<List<SystemProjectSummary>> GetSystemProjectSummariesAsync()
        {
            using var scope = _scopeFactory.CreateScope();
            var db = scope.ServiceProvider.GetRequiredService<DashboardDbContext>();

            var staleTime = DateTime.UtcNow - StaleThreshold;

            // Get all components with minimal data for counting
            var components = await db.Components
                .Select(c => new { c.SystemName, c.ProjectName, c.Payload, c.CreatedAt })
                .ToListAsync();

            // Group and count in memory (SQLite doesn't support complex JSON queries)
            var summaries = components
                .GroupBy(c => new { c.SystemName, c.ProjectName })
                .Select(g => new SystemProjectSummary
                {
                    SystemName = g.Key.SystemName,
                    ProjectName = g.Key.ProjectName,
                    ErrorCount = g.Count(c => GetSeverityFromPayload(c.Payload, c.CreatedAt, staleTime) == "error"),
                    WarningCount = g.Count(c => GetSeverityFromPayload(c.Payload, c.CreatedAt, staleTime) == "warning"),
                    OfflineCount = g.Count(c => GetSeverityFromPayload(c.Payload, c.CreatedAt, staleTime) == "offline"),
                    OkCount = g.Count(c => GetSeverityFromPayload(c.Payload, c.CreatedAt, staleTime) == "ok"),
                    InfoCount = g.Count(c => GetSeverityFromPayload(c.Payload, c.CreatedAt, staleTime) == "info"),
                    TotalCount = g.Count()
                })
                .OrderBy(s => s.SystemName)
                .ThenBy(s => s.ProjectName)
                .ToList();

            return summaries;
        }

        /// <summary>
        /// Get paginated components for a specific project
        /// </summary>
        public async Task<PagedResult<ComponentViewModel>> GetComponentsPagedAsync(
            string systemName,
            string projectName,
            string? severityFilter = null,
            string? searchText = null,
            int page = 1,
            int pageSize = 50,
            string? sortColumn = null,
            bool sortAscending = true)
        {
            using var scope = _scopeFactory.CreateScope();
            var db = scope.ServiceProvider.GetRequiredService<DashboardDbContext>();
            var staleTime = DateTime.UtcNow - StaleThreshold;

            // Base query with index-optimized filter
            var query = db.Components
                .Where(c => c.SystemName == systemName && c.ProjectName == projectName);

            // Get all matching components (we need to parse JSON in memory for SQLite)
            var allComponents = await query.ToListAsync();

            // Convert to view models with parsed data
            var viewModels = allComponents.Select(c => new ComponentViewModel
            {
                Id = c.Id,
                SystemName = c.SystemName,
                ProjectName = c.ProjectName,
                CreatedAt = c.CreatedAt,
                Payload = c.Payload,
                ParsedPayload = ParsePayloadCached(c.Payload),
                Severity = GetSeverityFromPayload(c.Payload, c.CreatedAt, staleTime)
            }).ToList();

            // Apply severity filter
            if (!string.IsNullOrEmpty(severityFilter))
            {
                viewModels = viewModels.Where(v => v.Severity == severityFilter).ToList();
            }

            // Apply search filter
            if (!string.IsNullOrWhiteSpace(searchText))
            {
                var term = searchText.Trim().ToLower();
                viewModels = viewModels.Where(v =>
                    v.Payload.ToLower().Contains(term)).ToList();
            }

            // Get total before pagination
            var totalCount = viewModels.Count;

            // Apply sorting
            if (!string.IsNullOrEmpty(sortColumn))
            {
                viewModels = SortViewModels(viewModels, sortColumn, sortAscending);
            }
            else
            {
                // Default sort by CreatedAt descending
                viewModels = viewModels.OrderByDescending(v => v.CreatedAt).ToList();
            }

            // Apply pagination
            var pagedItems = viewModels
                .Skip((page - 1) * pageSize)
                .Take(pageSize)
                .ToList();

            return new PagedResult<ComponentViewModel>
            {
                Items = pagedItems,
                TotalCount = totalCount,
                Page = page,
                PageSize = pageSize,
                TotalPages = (int)Math.Ceiling(totalCount / (double)pageSize)
            };
        }

        /// <summary>
        /// Get severity counts for current context
        /// </summary>
        public async Task<SeverityCounts> GetSeverityCountsAsync(string systemName, string projectName)
        {
            using var scope = _scopeFactory.CreateScope();
            var db = scope.ServiceProvider.GetRequiredService<DashboardDbContext>();
            var staleTime = DateTime.UtcNow - StaleThreshold;

            var components = await db.Components
                .Where(c => c.SystemName == systemName && c.ProjectName == projectName)
                .Select(c => new { c.Payload, c.CreatedAt })
                .ToListAsync();

            return new SeverityCounts
            {
                Ok = components.Count(c => GetSeverityFromPayload(c.Payload, c.CreatedAt, staleTime) == "ok"),
                Warning = components.Count(c => GetSeverityFromPayload(c.Payload, c.CreatedAt, staleTime) == "warning"),
                Error = components.Count(c => GetSeverityFromPayload(c.Payload, c.CreatedAt, staleTime) == "error"),
                Info = components.Count(c => GetSeverityFromPayload(c.Payload, c.CreatedAt, staleTime) == "info"),
                Offline = components.Count(c => GetSeverityFromPayload(c.Payload, c.CreatedAt, staleTime) == "offline")
            };
        }

        /// <summary>
        /// Get dynamic headers from a sample of components
        /// </summary>
        public async Task<List<string>> GetDynamicHeadersAsync(string systemName, string projectName)
        {
            using var scope = _scopeFactory.CreateScope();
            var db = scope.ServiceProvider.GetRequiredService<DashboardDbContext>();

            // Get a sample of components to determine headers
            var samplePayloads = await db.Components
                .Where(c => c.SystemName == systemName && c.ProjectName == projectName)
                .Take(100)
                .Select(c => c.Payload)
                .ToListAsync();

            var headers = new HashSet<string>();
            foreach (var payload in samplePayloads)
            {
                var parsed = ParsePayloadCached(payload);
                foreach (var key in parsed.Keys)
                {
                    headers.Add(key);
                }
            }

            var headerList = headers.OrderBy(h => h).ToList();
            headerList.Remove("Id");

            // Prioritize Severity and Name
            var nameHeader = headerList.FirstOrDefault(h => h.Equals("name", StringComparison.OrdinalIgnoreCase));
            var severityHeader = headerList.FirstOrDefault(h => h.Equals("Severity", StringComparison.OrdinalIgnoreCase));

            if (nameHeader != null) headerList.Remove(nameHeader);
            if (severityHeader != null) headerList.Remove(severityHeader);

            if (nameHeader != null) headerList.Insert(0, nameHeader);
            if (severityHeader != null) headerList.Insert(0, severityHeader);

            return headerList;
        }

        /// <summary>
        /// Get components for virtualization (on-demand loading)
        /// </summary>
        public async Task<VirtualizeResult<ComponentViewModel>> GetComponentsVirtualizedAsync(
            string systemName,
            string projectName,
            string? severityFilter,
            string? searchText,
            string? sortColumn,
            bool sortAscending,
            int startIndex,
            int count)
        {
            using var scope = _scopeFactory.CreateScope();
            var db = scope.ServiceProvider.GetRequiredService<DashboardDbContext>();
            var staleTime = DateTime.UtcNow - StaleThreshold;

            var query = db.Components
                .Where(c => c.SystemName == systemName && c.ProjectName == projectName);

            var allComponents = await query.ToListAsync();

            var viewModels = allComponents.Select(c => new ComponentViewModel
            {
                Id = c.Id,
                SystemName = c.SystemName,
                ProjectName = c.ProjectName,
                CreatedAt = c.CreatedAt,
                Payload = c.Payload,
                ParsedPayload = ParsePayloadCached(c.Payload),
                Severity = GetSeverityFromPayload(c.Payload, c.CreatedAt, staleTime)
            }).ToList();

            if (!string.IsNullOrEmpty(severityFilter))
            {
                viewModels = viewModels.Where(v => v.Severity == severityFilter).ToList();
            }

            if (!string.IsNullOrWhiteSpace(searchText))
            {
                var term = searchText.Trim().ToLower();
                viewModels = viewModels.Where(v => v.Payload.ToLower().Contains(term)).ToList();
            }

            var totalCount = viewModels.Count;

            if (!string.IsNullOrEmpty(sortColumn))
            {
                viewModels = SortViewModels(viewModels, sortColumn, sortAscending);
            }
            else
            {
                viewModels = viewModels.OrderByDescending(v => v.CreatedAt).ToList();
            }

            var items = viewModels.Skip(startIndex).Take(count).ToList();

            return new VirtualizeResult<ComponentViewModel>
            {
                Items = items,
                TotalCount = totalCount
            };
        }

        public async Task DeleteComponentAsync(int id)
        {
            using var scope = _scopeFactory.CreateScope();
            var db = scope.ServiceProvider.GetRequiredService<DashboardDbContext>();
            var component = await db.Components.FindAsync(id);
            if (component != null)
            {
                db.Components.Remove(component);
                await db.SaveChangesAsync();
            }
        }

        private static string GetSeverityFromPayload(string payload, DateTime createdAt, DateTime staleTime)
        {
            if (createdAt < staleTime) return "offline";

            try
            {
                using var doc = JsonDocument.Parse(payload);
                if (doc.RootElement.TryGetProperty("Severity", out var severityProp))
                {
                    return severityProp.GetString()?.ToLower() ?? "info";
                }
            }
            catch { }
            return "info";
        }

        private static Dictionary<string, object> ParsePayloadCached(string json)
        {
            try
            {
                return JsonSerializer.Deserialize<Dictionary<string, object>>(json) ?? new();
            }
            catch
            {
                return new();
            }
        }

        private static List<ComponentViewModel> SortViewModels(List<ComponentViewModel> items, string column, bool ascending)
        {
            if (column == "CreatedAt")
            {
                return ascending
                    ? items.OrderBy(c => c.CreatedAt).ToList()
                    : items.OrderByDescending(c => c.CreatedAt).ToList();
            }

            var sorted = items.Select(item =>
            {
                string? strVal = item.ParsedPayload.TryGetValue(column, out var val) ? val?.ToString() : null;
                bool isNum = double.TryParse(strVal, out double numVal);
                return new { Item = item, StrValue = strVal, NumValue = isNum ? (double?)numVal : null };
            }).ToList();

            var nonNull = sorted.Where(x => x.StrValue != null).ToList();
            bool isNumeric = nonNull.Any() && nonNull.All(x => x.NumValue.HasValue);

            if (isNumeric)
            {
                return ascending
                    ? sorted.OrderBy(x => x.NumValue).Select(x => x.Item).ToList()
                    : sorted.OrderByDescending(x => x.NumValue).Select(x => x.Item).ToList();
            }

            return ascending
                ? sorted.OrderBy(x => x.StrValue).Select(x => x.Item).ToList()
                : sorted.OrderByDescending(x => x.StrValue).Select(x => x.Item).ToList();
        }
    }

    public class SystemProjectSummary
    {
        public string SystemName { get; set; } = "";
        public string ProjectName { get; set; } = "";
        public int ErrorCount { get; set; }
        public int WarningCount { get; set; }
        public int OfflineCount { get; set; }
        public int OkCount { get; set; }
        public int InfoCount { get; set; }
        public int TotalCount { get; set; }
    }

    public class SeverityCounts
    {
        public int Ok { get; set; }
        public int Warning { get; set; }
        public int Error { get; set; }
        public int Info { get; set; }
        public int Offline { get; set; }
    }

    public class ComponentViewModel
    {
        public int Id { get; set; }
        public string SystemName { get; set; } = "";
        public string ProjectName { get; set; } = "";
        public DateTime CreatedAt { get; set; }
        public string Payload { get; set; } = "";
        public Dictionary<string, object> ParsedPayload { get; set; } = new();
        public string Severity { get; set; } = "info";
    }

    public class PagedResult<T>
    {
        public List<T> Items { get; set; } = new();
        public int TotalCount { get; set; }
        public int Page { get; set; }
        public int PageSize { get; set; }
        public int TotalPages { get; set; }
    }

    public class VirtualizeResult<T>
    {
        public List<T> Items { get; set; } = new();
        public int TotalCount { get; set; }
    }
}
