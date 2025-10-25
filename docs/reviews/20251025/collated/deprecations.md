# Deprecated Code & Dependencies Analysis

## Critical Version Status (As of October 2025)

### Phoenix Framework
**Current in Project:** 1.8.1  
**Latest Stable:** 1.8.1 (Released August 29, 2025)  
**Status:** ✅ Up-to-date with latest stable version

### Phoenix LiveView  
**Current in Project:** 1.1.0  
**Latest Stable:** 1.1.16 (Released October 22, 2025)  
**Status:** ⚠️ Outdated - should update to 1.1.16

**Recommendation:** Update to latest stable:
```elixir
{:phoenix_live_view, "~> 1.1.16"}
```

### Ecto
**Current in Project:** Not specified precisely  
**Latest Stable:** 3.13.3 (Released September 19, 2025)  
**Status:** Should pin to latest stable versions

**Recommendation:**
```elixir
{:ecto, "~> 3.13.3"},
{:ecto_sql, "~> 3.13.2"}
```

## Deprecated Phoenix Patterns

### 1. Missing Phoenix.Component Usage
The application doesn't properly utilize Phoenix.Component patterns introduced in Phoenix 1.7+:

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

### 2. Outdated Form Handling
Not using modern Phoenix form components:

```elixir
# Current: Raw HTML forms
<form phx-submit="add_language">
  <input type="text" name="name" />
</form>

# Should use:
<.form for={@form} id="language-form" phx-submit="add_language">
  <.input field={@form[:name]} type="text" placeholder="Language name" />
  <.button type="submit">Add</.button>
</.form>
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

### 4. Project Guideline Violations
- **Inline Scripts:** Theme toggle script in root.html.heex violates guidelines
- **Flash Group Misuse:** `<Layouts.flash_group>` used outside layouts module
- **Missing Layout Wrapper:** LiveView template not wrapped with `<Layouts.app>`

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

### 3. Non-Atomic Updates
Read-modify-write pattern causes race conditions:
```elixir
# Current (DEPRECATED):
option = Repo.get!(Option, id)
Ecto.Changeset.change(option, votes: option.votes + 1)
|> Repo.update()

# Modern (ATOMIC):
from(o in Option, where: o.id == ^id)
|> Repo.update_all([inc: [votes: 1]], returning: true)
```

## JavaScript Dependencies

### 1. ECharts Version
**Current:** Appears to be using v5.x or v6.x  
**Latest Stable:** 5.5.1  
**Recommendation:** Pin to stable version in package.json

### 2. Missing Dependencies
No package-lock.json suggests improper npm installation

### 3. Vendor Files
Multiple vendor files that should be npm packages:
- `/vendor/topbar.js`
- `/vendor/heroicons.js`
- `/vendor/daisyui.js`

**Recommendation:** Install via npm:
```json
{
  "dependencies": {
    "topbar": "^2.0.0",
    "@heroicons/react": "^2.0.0"
  }
}
```

## CSS/Tailwind Issues

### 1. DaisyUI Inclusion
**Files:** `assets/css/app.css`, `assets/vendor/daisyui.js`

DaisyUI is imported but barely used:
```css
@plugin "../vendor/daisyui" {
  themes: false;
}
```

**Recommendation:** Remove DaisyUI entirely - it's adding 50KB+ for no benefit and violates project guidelines preferring Tailwind-only custom components

### 2. Tailwind v4 Syntax
Project uses new Tailwind v4 import syntax which is correct for Phoenix 1.8:
```css
@import "tailwindcss" source(none);
@source "../css";
@source "../js";
@source "../../lib/live_poll_web";
```

### 3. Deprecated Tailwind Patterns
Custom variants using old syntax should be updated:
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
def mount(_params, _session, socket) do
  if connected?(socket), do: schedule_update()
  {:ok, socket}
end

defp schedule_update do
  Process.send_after(self(), :update_stats, 5000)
end

def handle_info(:update_stats, socket) do
  schedule_update()
  {:noreply, update_stats(socket)}
end
```

### 2. Manual Chart Updates
Using `push_event` for charts instead of modern approaches:
```elixir
# Current:
push_event("update-pie-chart", %{data: data})

# Consider:
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

### 4. Not Using LiveView Streams
For collections that could benefit from streaming:
```elixir
# Current:
assign(socket, :options, options)

# Should use for large collections:
stream(socket, :options, options)
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

### 2. Missing Unique Constraint
No unique index on poll_options(text):
```elixir
# Add in migration:
create unique_index(:poll_options, [:text])
```

### 3. No UUID Primary Keys
Using integer IDs instead of UUIDs (acceptable but not modern):
```elixir
# Current:
create table(:poll_options) do

# Modern alternative:
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

### 2. Deprecated Async Test Patterns
Using sleep for async operations:
```elixir
# Old:
:timer.sleep(100)

# Modern:
assert_receive {:message, _}, 1000
```

## Configuration Issues

### 1. Missing Runtime Configuration
No `runtime.exs` for modern deployment configuration

### 2. Missing Health Check Routes
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
defp deps do
  [
    {:phoenix, "~> 1.8.1"},
    {:phoenix_live_view, "~> 1.1.16"},
    {:phoenix_ecto, "~> 4.6"},
    {:ecto, "~> 3.13.3"},
    {:ecto_sql, "~> 3.13.2"},
    {:postgrex, "~> 0.19"},
    {:phoenix_html, "~> 4.2"},
    {:phoenix_live_dashboard, "~> 0.8.5"},
    {:telemetry_metrics, "~> 1.0"},
    {:telemetry_poller, "~> 1.1"},
    {:jason, "~> 1.4"},
    {:bandit, "~> 1.6"},
    {:dns_cluster, "~> 0.1.3"},
    {:heroicons, "~> 0.5.6"},  # Use hex package instead of GitHub
    
    # Development & Testing
    {:phoenix_live_reload, "~> 1.5", only: :dev},
    {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
    {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
    {:sobelow, "~> 0.13", only: [:dev, :test], runtime: false},
    {:ex_doc, "~> 0.34", only: :dev, runtime: false},
    
    # Security & Performance
    {:hammer, "~> 6.2"},  # Rate limiting
    {:cachex, "~> 3.6"},  # Caching
    
    # Remove:
    # - DaisyUI (unused and against guidelines)
  ]
end
```

## Migration Path

### Phase 1: Stabilize Versions (Immediate)
1. Update LiveView to 1.1.16
2. Pin all dependencies to specific versions
3. Remove unused DaisyUI
4. Fix deprecated patterns

### Phase 2: Modernize Patterns (Week 1)
1. Implement Phoenix.Component patterns
2. Update form handling to use modern components
3. Add proper telemetry
4. Modernize test patterns
5. Fix project guideline violations

### Phase 3: Remove Deprecations (Week 2)
1. Replace raw SQL with Ecto queries
2. Implement atomic updates
3. Update JavaScript to use npm packages
4. Implement proper CSP and security headers
5. Add runtime configuration

## Risk Assessment

**High Risk:**
- Non-atomic vote updates (data corruption)
- Raw SQL usage (maintenance burden)
- Missing security headers

**Medium Risk:**
- Outdated LiveView version
- Deprecated patterns affecting maintainability
- Missing monitoring/telemetry

**Low Risk:**
- CSS/styling deprecations
- Test pattern updates
- Configuration modernization

## Conclusion

The application is mostly up-to-date with Phoenix 1.8.1 but needs updates to LiveView and several pattern modernizations. The most critical issues are the non-atomic vote updates and project guideline violations. A systematic migration to modern patterns is essential for long-term maintainability. Priority should be given to fixing concurrency issues, updating LiveView, and complying with Phoenix 1.8 best practices.