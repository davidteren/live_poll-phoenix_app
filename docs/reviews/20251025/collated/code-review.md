# Code Review - LivePoll Phoenix Application

## Executive Summary
The LivePoll application demonstrates functional real-time voting capabilities but suffers from significant architectural and code quality issues. The primary concern is a monolithic LiveView module that violates separation of concerns, combined with outdated dependencies and missing business logic abstractions.

## Critical Issues

### 1. Monolithic LiveView Module (700+ lines)
**File:** `lib/live_poll_web/live/poll_live.ex`

The `PollLive` module is severely overloaded with responsibilities:
- Direct database queries (should be in context)
- Complex business logic (vote counting, trend calculation)
- Data transformation (bucketing, percentage calculations)
- Manual SVG generation
- Event handling
- PubSub broadcasting

**Recommendation:** Extract into separate modules:
```elixir
# Proposed structure:
LivePoll.Polls (context module)
├── LivePoll.Polls.Option
├── LivePoll.Polls.VoteEvent
├── LivePoll.Polls.TrendCalculator
├── LivePoll.Polls.VoteAggregator
└── LivePoll.Polls.Seeder

LivePollWeb.PollLive (LiveView - UI only)
LivePollWeb.Components.Charts (chart components)
```

### 2. Direct Database Access in LiveView
**Lines:** 13-14, 41-48, 61-72, 85-93, etc.

```elixir
# Current (BAD):
options = Repo.all(Option) |> Enum.sort_by(& &1.id)
Repo.insert!(%VoteEvent{...})

# Should be:
options = Polls.list_options()
Polls.record_vote(option_id)
```

### 3. Missing Context Module
No `LivePoll.Polls` context exists. All business logic is embedded in the LiveView, making it:
- Impossible to test business logic in isolation
- Difficult to reuse logic
- Hard to maintain
- Violates Phoenix conventions

### 4. Complex Time-Series Logic in UI Layer
**Lines:** 445-594

The `build_trend_data_from_events/1` function is 150+ lines of complex bucketing logic that belongs in a dedicated module with proper testing.

### 5. Concurrency Issues with Vote Counting
**Critical:** Non-atomic vote increments lead to lost updates under concurrent voting:

```elixir
# Current (RACE CONDITION):
option = Repo.get!(Option, id)
{:ok, updated_option} = option
  |> Ecto.Changeset.change(votes: option.votes + 1)
  |> Repo.update()

# Fixed (ATOMIC):
{1, [updated_option]} = 
  from(o in Option, where: o.id == ^id, select: o)
  |> Repo.update_all([inc: [votes: 1]], returning: true)
```

## Code Quality Issues

### 1. Hardcoded Values
**Lines:** 108-143
```elixir
languages_with_weights = [
  {"Python", 100.0},
  {"JavaScript", 85.0},
  # ... hardcoded language weights
]
```
Should be configuration or database-driven.

### 2. Magic Numbers
```elixir
:timer.send_interval(5000, self(), :update_stats)  # What is 5000?
total_target_votes = 10000  # Why 10000?
variation = trunc(base_votes * 0.2)  # Why 0.2?
```

### 3. Inconsistent Error Handling
No error handling for:
- Database operations
- PubSub broadcasts
- Timer operations

### 4. SQL Injection Risk
**Lines:** 234-238
```elixir
Ecto.Adapters.SQL.query!(
  Repo,
  "UPDATE vote_events SET inserted_at = $1 WHERE id = $2",
  [event.timestamp, vote_event.id]
)
```
Direct SQL should be avoided when possible. Use Ecto queries instead.

### 5. Inefficient Queries
**Lines:** 461-468
```elixir
events = from(e in VoteEvent,
  where: e.inserted_at >= ^cutoff_time,
  order_by: [asc: e.inserted_at],
  preload: :option  # Unnecessary preload
) |> Repo.all()
```
Loading all events into memory for processing. Should use aggregation queries.

### 6. Missing Unique Constraint
**Database Issue:** No unique index on `poll_options(text)`, allowing duplicate language names:

```elixir
# Migration needed:
create unique_index(:poll_options, [:text])

# Changeset update:
def changeset(option, attrs) do
  option
  |> cast(attrs, [:text, :votes])
  |> validate_required([:text, :votes])
  |> unique_constraint(:text)
end
```

## LiveView Best Practices Violations

### 1. Heavy Computation in LiveView
Trend calculation happens in the LiveView process, blocking UI updates.

### 2. Missing Stream Usage for Large Collections
Recent activity list uses regular assigns instead of streams:
```elixir
# Current:
recent_activity: []

# Should be:
stream(:recent_activity, [])
```

### 3. Inefficient Re-rendering
Entire option lists are re-assigned on every update instead of using targeted updates.

### 4. Project Guideline Violations
- **Inline Scripts:** Theme toggle in root.html.heex (should be in assets/js)
- **Flash Group Misuse:** `<Layouts.flash_group>` used outside layouts module
- **Missing Layout Wrapper:** Template not wrapped with `<Layouts.app flash={@flash}>`
- **Form Patterns:** Not using `to_form` + `<.form>` + `<.input>` for Add Language form

## JavaScript/Hook Issues

### 1. Duplicated Chart Logic
**File:** `assets/js/charts.js`

`TrendChart` and `PercentageTrendChart` are nearly identical (400+ lines duplicated).

### 2. Memory Leaks
Chart instances may not be properly disposed:
```javascript
destroyed() {
  if (this.chart && !this.chart.isDisposed()) {
    this.chart.dispose();
  }
  // Missing: this.chart = null;
}
```

### 3. Hardcoded Colors
Language colors are hardcoded in both JavaScript and CSS, violating DRY principle.

## Testing Issues

### 1. Limited Test Coverage (~25%)
Only basic LiveView tests exist. Missing:
- Context/business logic tests
- VoteEvent aggregation tests
- Trend calculation tests
- PubSub broadcast tests
- Error handling tests
- Concurrency tests

### 2. Test Quality
Tests use `timer.sleep(100)` for async operations instead of proper synchronization:
```elixir
:timer.sleep(100)  # Wait for broadcast - BAD

# Should use:
assert_receive {:vote_cast, _}, 1000
```

### 3. Missing Edge Cases
No tests for:
- Concurrent voting
- Large data sets
- Time range changes
- Database failures
- Duplicate language names

## Performance Concerns

### 1. N+1 Query Potential
Options and vote events are loaded separately without proper preloading strategy.

### 2. Memory Usage
All vote events are loaded into memory for trend calculation. With 10,000+ events, this becomes problematic.

### 3. Blocking Operations
Seeding 10,000 votes happens synchronously in the LiveView process:

```elixir
# Current: Individual inserts with follow-up UPDATE
Enum.each(vote_events, fn event ->
  vote_event = Repo.insert!(%VoteEvent{...})
  Ecto.Adapters.SQL.query!(Repo, "UPDATE vote_events SET inserted_at = $1 WHERE id = $2", [event.timestamp, vote_event.id])
end)

# Optimized: Batch insert with precomputed timestamps
vote_events = Enum.map(events, fn event ->
  %{
    option_id: event.option_id,
    language: event.language,
    votes_after: event.votes_after,
    event_type: event.event_type,
    inserted_at: event.timestamp,
    updated_at: event.timestamp
  }
end)

Repo.insert_all(VoteEvent, vote_events, on_conflict: :nothing)
```

## Security Issues

### 1. No Rate Limiting
Users can vote unlimited times rapidly.

### 2. No CSRF Protection for Mutations
While Phoenix provides CSRF tokens, there's no additional validation for critical operations.

### 3. Direct ID Exposure
```elixir
handle_event("vote", %{"id" => id}, socket)
```
IDs are directly exposed and used without validation.

### 4. Missing Input Validation
Language names not validated for length/content:

```elixir
# Current: No validation
def handle_event("add_language", %{"name" => name}, socket) when byte_size(name) > 0 do
  # No length or content validation
end

# Should validate:
def add_language_changeset(attrs) do
  %Option{}
  |> cast(attrs, [:text])
  |> validate_required([:text])
  |> validate_length(:text, min: 1, max: 50)
  |> validate_format(:text, ~r/^[a-zA-Z0-9\s\#\+\-\.]+$/)
  |> unique_constraint(:text)
end
```

### 5. XSS Risk in Chart Tooltips
Language names displayed in ECharts tooltips without escaping.

## Recommendations

### Immediate Actions
1. **Fix Concurrency:** Implement atomic vote increments
2. **Add Unique Constraint:** Prevent duplicate language names
3. **Create Context Module:** Extract business logic from LiveView
4. **Fix Project Violations:** Comply with Phoenix 1.8 guidelines
5. **Implement Error Handling:** Add proper error boundaries
6. **Update Dependencies:** Use stable versions

### Short-term Improvements
1. **Optimize Seeding:** Use batch inserts with transactions
2. **Remove Preloads:** Eliminate unnecessary database loads
3. **Use LiveView Streams:** For collections and recent activity
4. **Add Database Indexes:** Improve query performance
5. **Consolidate JavaScript:** Remove duplicate chart code
6. **Extract Components:** Create reusable UI components

### Long-term Refactoring
1. **Implement CQRS:** Separate read/write models for events
2. **Add GenServer:** For vote aggregation and caching
3. **Database Partitioning:** For time-series data
4. **WebSocket Pooling:** Optimize connection handling
5. **Background Jobs:** Use Oban for async operations

## Code Metrics

- **LiveView Complexity:** 700+ lines (should be <200)
- **Cyclomatic Complexity:** High (multiple nested conditions)
- **Test Coverage:** ~25% (should be >80%)
- **Code Duplication:** High (charts, colors, logic)
- **Technical Debt:** Significant

## Implementation Roadmap

### Week 1: Critical Fixes
1. Implement atomic vote increments
2. Add unique constraint on language names
3. Fix project guideline violations
4. Optimize seeding with batch inserts
5. Remove unnecessary preloads

### Week 2: Architecture
1. Create Polls context module
2. Extract business logic from LiveView
3. Implement proper error handling
4. Add comprehensive tests
5. Set up CI/CD pipeline

### Week 3: Optimization
1. Implement caching strategy
2. Add database indexes
3. Use LiveView streams
4. Consolidate chart code
5. Performance testing

## Conclusion

While the application works, it requires significant refactoring to meet production standards. The monolithic LiveView is the primary concern, followed by missing abstractions and poor separation of concerns. Immediate action should focus on fixing concurrency issues, extracting business logic into a proper context module, and improving test coverage. The estimated effort for full remediation is approximately 3 weeks of focused development.