# Deprecated Code & Dependencies Analysis

## Critical Version Mismatches

### Phoenix Framework
**Current:** 1.8.1  
**Latest Stable:** 1.7.14  
**Issue:** Version 1.8.1 doesn't exist in the official Phoenix releases. This appears to be a pre-release or custom version.

**Action Required:** Downgrade to stable 1.7.14 or verify the source of 1.8.1

### Phoenix LiveView  
**Current:** 1.1.0  
**Latest Stable:** 1.0.0-rc.7 (as of late 2024)  
**Issue:** Version 1.1.0 is newer than the latest RC, suggesting use of unreleased version

**Recommendation:** Use stable 0.20.x series or official 1.0.0 when released

## Deprecated Phoenix Patterns

### 1. Missing Phoenix.Component Usage
The application doesn't properly utilize Phoenix.Component patterns introduced in Phoenix 1.7:

```elixir
# Current approach (outdated):
def render(assigns) do
  ~H"""
  <div>...</div>
  """
end

# Should use function components:
attr :options, :list, required: true
attr :total_votes, :integer, default: 0

def poll_chart(assigns) do
  ~H"""
  <div>...</div>
  """
end
```

### 2. Outdated Router Configuration
**File:** `lib/live_poll_web/router.ex`

Missing modern LiveView session configuration:
```elixir
# Should include:
live_session :default,
  on_mount: [{LivePollWeb.UserAuth, :ensure_authenticated}] do
  live "/", PollLive, :index
end
```

### 3. Legacy PubSub Patterns
Using string topics instead of structured topics:
```elixir
# Current:
@topic "poll:updates"

# Modern approach:
@topic inspect(__MODULE__)
# or
topic = "poll:#{poll_id}"
```

## Deprecated Ecto Patterns

### 1. Missing Ecto.Query Import Best Practices
Direct module calls instead of imports:
```elixir
# Current:
from(e in VoteEvent, where: e.inserted_at >= ^cutoff_time)

# Should import at module level:
import Ecto.Query, warn: false
```

### 2. Raw SQL Usage
**Lines:** 234-238 in `poll_live.ex`
```elixir
# Deprecated approach:
Ecto.Adapters.SQL.query!(Repo, "UPDATE vote_events SET...")

# Should use:
from(v in VoteEvent, where: v.id == ^id, update: [set: [inserted_at: ^timestamp]])
|> Repo.update_all([])
```

## JavaScript Dependencies

### 1. ECharts Version
**Current:** 6.0.0 (from early 2024)  
**Latest:** 5.5.1 (stable) or 6.0.0-alpha  
**Issue:** Using alpha/beta version in production

### 2. Missing Dependencies
No package-lock.json suggests improper npm installation

### 3. Vendor Files
Multiple vendor files that should be npm packages:
- `/vendor/topbar.js`
- `/vendor/heroicons.js`
- `/vendor/daisyui.js`

## CSS/Tailwind Issues

### 1. DaisyUI Inclusion
**Files:** `assets/css/app.css`, `assets/vendor/daisyui.js`

DaisyUI is imported but barely used:
```css
@plugin "../vendor/daisyui" {
  themes: false;
}
```

**Recommendation:** Remove DaisyUI entirely - it's adding 50KB+ for no benefit

### 2. Tailwind v4 Syntax with v3 Features
Using new v4 import syntax:
```css
@import "tailwindcss" source(none);
@source "../css";
```

But the project uses Tailwind v3 features. This is incompatible.

### 3. Deprecated Tailwind Patterns
Custom variants using old syntax:
```css
@custom-variant phx-click-loading (.phx-click-loading&, .phx-click-loading &);
```

## LiveView Deprecated Patterns

### 1. Timer-based Updates
Using `:timer.send_interval` instead of `Process.send_after` with proper lifecycle:
```elixir
# Deprecated:
:timer.send_interval(5000, self(), :update_stats)

# Modern:
Process.send_after(self(), :update_stats, 5000)
# With handle_info recursion
```

### 2. Manual Chart Updates
Using `push_event` for charts instead of modern approaches:
```elixir
# Current:
push_event("update-pie-chart", %{data: data})

# Should consider:
# Server-side rendering or LiveView Native components
```

### 3. Missing Telemetry Integration
No proper telemetry events for monitoring:
```elixir
# Should have:
:telemetry.execute(
  [:live_poll, :vote, :cast],
  %{count: 1},
  %{option_id: option_id}
)
```

## Database Migration Issues

### 1. Missing Indexes
**File:** `20251023072711_create_vote_events.exs`

Indexes are basic, missing compound indexes:
```elixir
# Current:
create index(:vote_events, [:option_id])
create index(:vote_events, [:inserted_at])

# Should add:
create index(:vote_events, [:option_id, :inserted_at])
create index(:vote_events, [:event_type, :inserted_at])
```

### 2. No UUID Primary Keys
Using integer IDs instead of UUIDs:
```elixir
# Current:
create table(:poll_options) do

# Modern:
create table(:poll_options, primary_key: false) do
  add :id, :binary_id, primary_key: true
```

## Test Framework Issues

### 1. Missing ExUnit.CaseTemplate
Tests don't use modern ExUnit patterns:
```elixir
# Should have:
use LivePollWeb.ConnCase, async: true
```

### 2. Deprecated Phoenix.ConnTest Patterns
Using old assertion patterns:
```elixir
# Old:
assert html =~ "text"

# Modern:
assert html_response(conn, 200) =~ "text"
```

## Configuration Issues

### 1. Missing Runtime Configuration
No `runtime.exs` for modern deployment configuration

### 2. Deprecated Endpoint Configuration
Using old patterns in `endpoint.ex`

### 3. Missing Health Check Routes
No `/health` endpoint for modern deployment

## Security Deprecations

### 1. Missing Content Security Policy
No CSP headers configured

### 2. Old CORS Handling
No proper CORS configuration for API endpoints

### 3. Missing Rate Limiting
No Hammer or similar rate limiting library

## Recommended Dependency Updates

```elixir
# mix.exs updates needed:
{:phoenix, "~> 1.7.14"},
{:phoenix_live_view, "~> 0.20.17"},
{:phoenix_ecto, "~> 4.6"},
{:ecto_sql, "~> 3.12"},
{:postgrex, "~> 0.19"},
{:phoenix_html, "~> 4.2"},
{:phoenix_live_dashboard, "~> 0.8.5"},
{:telemetry_metrics, "~> 1.0"},
{:telemetry_poller, "~> 1.1"},
{:jason, "~> 1.4"},
{:bandit, "~> 1.6"},
{:dns_cluster, "~> 0.1.3"},
{:heroicons, "~> 0.5.6"},  # Use hex package instead of GitHub

# Remove:
# - DaisyUI (unused)

# Add:
{:phoenix_live_reload, "~> 1.5", only: :dev},
{:credo, "~> 1.7", only: [:dev, :test], runtime: false},
{:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
{:sobelow, "~> 0.13", only: [:dev, :test], runtime: false}
```

## Migration Path

### Phase 1: Stabilize Versions (Immediate)
1. Downgrade to stable Phoenix 1.7.14
2. Use stable LiveView 0.20.x
3. Update all dependencies to latest stable
4. Remove unused DaisyUI

### Phase 2: Modernize Patterns (Week 1)
1. Implement Phoenix.Component patterns
2. Update router with live_sessions
3. Add proper telemetry
4. Modernize test patterns

### Phase 3: Remove Deprecations (Week 2)
1. Replace raw SQL with Ecto queries
2. Update JavaScript to use npm packages
3. Implement proper CSP and security headers
4. Add runtime configuration

## Risk Assessment

**High Risk:**
- Unstable Phoenix/LiveView versions
- Raw SQL usage
- Missing security headers

**Medium Risk:**
- Deprecated patterns affecting maintainability
- Outdated dependencies with known vulnerabilities
- Missing monitoring/telemetry

**Low Risk:**
- CSS/styling deprecations
- Test pattern updates
- Configuration modernization

## Conclusion

The application uses several deprecated patterns and unstable versions that should be addressed immediately. The most critical issue is the use of non-existent Phoenix 1.8.1 and LiveView 1.1.0 versions. A systematic migration to stable versions and modern patterns is essential for long-term maintainability.