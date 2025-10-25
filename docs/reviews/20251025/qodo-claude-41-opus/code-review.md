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
Direct SQL should be avoided when possible.

### 5. Inefficient Queries
**Lines:** 461-468
```elixir
events = from(e in VoteEvent,
  where: e.inserted_at >= ^cutoff_time,
  order_by: [asc: e.inserted_at],
  preload: :option
) |> Repo.all()
```
Loading all events into memory for processing. Should use aggregation queries.

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
}
```
Missing null assignment after disposal.

### 3. Hardcoded Colors
Language colors are hardcoded in both JavaScript and CSS, violating DRY principle.

## Testing Issues

### 1. Limited Test Coverage
Only basic LiveView tests exist. Missing:
- Context/business logic tests
- VoteEvent aggregation tests
- Trend calculation tests
- PubSub broadcast tests
- Error handling tests

### 2. Test Quality
Tests use `timer.sleep(100)` for async operations instead of proper synchronization:
```elixir
:timer.sleep(100)  # Wait for broadcast
```

### 3. Missing Edge Cases
No tests for:
- Concurrent voting
- Large data sets
- Time range changes
- Database failures

## Performance Concerns

### 1. N+1 Query Potential
Options and vote events are loaded separately without proper preloading strategy.

### 2. Memory Usage
All vote events are loaded into memory for trend calculation. With 10,000+ events, this becomes problematic.

### 3. Blocking Operations
Seeding 10,000 votes happens synchronously in the LiveView process.

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

## Recommendations

### Immediate Actions
1. Create `LivePoll.Polls` context module
2. Extract business logic from LiveView
3. Implement proper error handling
4. Add comprehensive tests
5. Update dependencies

### Short-term Improvements
1. Implement vote rate limiting
2. Use LiveView streams for collections
3. Add database indexes for performance
4. Consolidate duplicate JavaScript code
5. Extract chart components

### Long-term Refactoring
1. Implement proper CQRS pattern for events
2. Use GenServer for vote aggregation
3. Add caching layer for trend data
4. Implement WebSocket connection pooling
5. Consider using Oban for background jobs

## Code Metrics

- **LiveView Complexity:** 700+ lines (should be <200)
- **Cyclomatic Complexity:** High (multiple nested conditions)
- **Test Coverage:** ~30% (should be >80%)
- **Code Duplication:** High (charts, colors, logic)
- **Technical Debt:** Significant

## Conclusion

While the application works, it requires significant refactoring to meet production standards. The monolithic LiveView is the primary concern, followed by missing abstractions and poor separation of concerns. Immediate action should focus on extracting business logic into a proper context module and improving test coverage.