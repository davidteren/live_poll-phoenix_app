# Performance & Optimization

## Database Query Analysis

### Frequent Queries
**Issue**: `Repo.all(Option)` called multiple times across handlers

**Locations**:
- `mount/3` (line 14)
- `handle_info({:poll_reset, _}, socket)` (line 376)
- `handle_info({:data_seeded, _}, socket)` (line 408)
- `handle_info({:language_added, _}, socket)` (line 439)

**Impact**: N database queries per client action
**Solution**: Cache options in socket assigns and update incrementally

### Missing Indexes
**Critical Indexes Needed**:
```sql
-- For trend queries
CREATE INDEX idx_vote_events_inserted_at ON vote_events(inserted_at);
CREATE INDEX idx_vote_events_option_inserted_at ON vote_events(option_id, inserted_at);

-- For option queries (if sorting by votes becomes common)
CREATE INDEX idx_options_votes ON poll_options(votes DESC);
```

**Impact**: Slow trend chart loading for large datasets
**Evidence**: `build_trend_data_from_events/1` queries without indexes

### No Association Preloading
**Issue**: VoteEvent queries don't preload options
```elixir
# Current (line 517-520)
events =
  from(e in VoteEvent,
    where: e.inserted_at >= ^cutoff_time,
    order_by: [asc: e.inserted_at],
    preload: :option  # This is good
  )
  |> Repo.all()
```

**Status**: Actually properly preloaded - this is good

## Seeding Process Performance

### Current Implementation Analysis
**10,000 Vote Seeding Process** (`perform_seeding/1`, lines 152-299):

1. **Deletes existing data**: `Repo.delete_all(VoteEvent)` + `Repo.delete_all(Option)`
2. **Creates 12-14 options** with 0 votes
3. **Distributes ~10,000 votes** across options based on weights
4. **Creates VoteEvent records** with randomized timestamps
5. **Updates option vote counts**

### Performance Issues

#### Memory Usage
- **Issue**: All 10,000 vote events created in memory before insertion
- **Code**: `Enum.flat_map/2` creates full event list in memory (lines 233-249)
- **Impact**: High memory usage during seeding
- **Solution**: Use `Stream` or batch insertions

#### Database Load
- **Issue**: Individual `Repo.insert!/1` calls for each event
- **Impact**: 10,000+ database round trips
- **Solution**: Use `Repo.insert_all/2` for bulk insertion

#### Random Timestamp Generation
- **Current**: `:rand.uniform(3600)` for each vote
- **Issue**: Not truly random distribution, may cluster votes
- **Better**: Use proper statistical distribution

### Optimization Recommendations

```elixir
# Bulk insert vote events
vote_events_data = Enum.map(events, fn event ->
  %{
    option_id: event.option.id,
    language: event.option.text,
    votes_after: event.vote_count,
    event_type: "seed",
    inserted_at: event.timestamp
  }
end)

Repo.insert_all(VoteEvent, vote_events_data)
```

## Trend Data Calculation

### Current Performance Issues

#### Complex Bucketing Logic
- **Function**: `build_trend_data_from_events/1` (106 lines)
- **Issue**: Processes all events in memory for bucketing
- **Time Complexity**: O(n) where n = number of events in time range

#### Memory Usage by Time Range
- **5 minutes**: Loads events from last 5 minutes
- **1 hour**: Loads events from last hour
- **12 hours**: Loads events from last 12 hours
- **24 hours**: Loads events from last 24 hours

#### Database Query Efficiency
- **Current**: Single query with time filter (good)
- **Issue**: No LIMIT clause - loads all events in range
- **Impact**: For 24h with heavy voting, could be 100k+ events

### Optimization Strategies

#### Database-Level Aggregation
```elixir
# Instead of loading all events, aggregate in database
from(e in VoteEvent,
  where: e.inserted_at >= ^cutoff_time,
  group_by: [fragment("date_trunc('minute', inserted_at)")],
  select: %{
    bucket: fragment("date_trunc('minute', inserted_at)"),
    option_id: e.option_id,
    language: e.language,
    votes: max(e.votes_after)
  }
)
```

#### Implement Caching
```elixir
# Cache trend data in ETS or similar
defmodule TrendCache do
  use GenServer

  def get_trend_data(time_range) do
    # Check cache first
  end
end
```

## LiveView Performance

### State Management Issues

#### Large Socket Assigns
- **Issue**: Full options list, trend data, recent activity stored in socket
- **Impact**: Large state serialized on each update
- **Solution**: Use `Phoenix.LiveView.stream/3` for options list

#### Frequent Updates
- **Current**: Stats update every 5 seconds via `:timer.send_interval/3`
- **Issue**: Unnecessary updates when no activity
- **Solution**: Event-driven updates only

### Memory Usage Patterns

#### Recent Activity Storage
- **Current**: Keeps last 10 activities in memory
- **Issue**: Grows indefinitely in long-running processes
- **Solution**: Limit and rotate properly

#### Trend Data Storage
- **Current**: Full trend snapshots stored in socket
- **Impact**: Large data structures kept in memory
- **Solution**: Store only necessary data for rendering

## JavaScript Performance

### Bundle Size Analysis

#### Current Bundle Composition
- **ECharts**: ~500KB (main contributor)
- **Phoenix LiveView**: ~100KB
- **DaisyUI**: ~300KB (unused)
- **Custom JS**: ~20KB
- **Total**: ~920KB (before gzip)

#### Optimization Opportunities
1. **Remove DaisyUI**: -300KB immediate savings
2. **Lazy Load ECharts**: Load only when charts visible
3. **Tree Shaking**: Ensure unused ECharts features removed

### Chart Rendering Performance

#### Current Issues
- **Full Re-renders**: Charts fully reinitialize on updates
- **No Incremental Updates**: Entire datasets replaced
- **Theme Changes**: MutationObserver triggers full rebuilds

#### Optimization Strategies
```javascript
// Incremental updates instead of full replacement
updateChart(newData) {
  const series = this.chart.getOption().series;
  series[0].data = newData;
  this.chart.setOption({ series });
}
```

## N+1 Query Problems

### Identified N+1 Issues

#### Vote Event Preloading
- **Status**: Properly preloaded with `preload: :option`
- **Good**: No N+1 here

#### Option Queries
- **Issue**: Multiple `Repo.all(Option)` calls without caching
- **Impact**: Database hit on every broadcast
- **Solution**: Cache options in application state

### Database Connection Pooling
- **Issue**: No explicit pool configuration
- **Default**: Uses Ecto's default pool size
- **Recommendation**: Configure based on expected load

## Memory Leak Potential

### Accumulating Data Structures
1. **VoteEvents**: Grow indefinitely without cleanup
2. **LiveView State**: Trend data accumulates over time
3. **Recent Activity**: Limited but could grow in edge cases

### Process Memory
- **Long-running LiveViews**: May accumulate state over days
- **No Cleanup**: Old trend data never garbage collected

## Recommended Performance Improvements

### High Priority (Critical)
1. **Add Database Indexes** for time-based queries
2. **Implement Data Retention Policy** for VoteEvents
3. **Fix Seeding Performance** - use bulk inserts
4. **Remove DaisyUI** to reduce bundle size

### Medium Priority (Important)
1. **Cache Options Data** to avoid repeated queries
2. **Optimize Trend Calculation** with database aggregation
3. **Implement Streaming** for large option lists
4. **Lazy Load Charts** to reduce initial bundle size

### Low Priority (Nice to Have)
1. **Add Connection Pool Monitoring**
2. **Implement Query Result Caching**
3. **Add Performance Metrics** and monitoring

## Performance Benchmarks

### Expected Improvements
- **Database Queries**: 60-80% reduction with proper indexing
- **Bundle Size**: 300KB reduction by removing DaisyUI
- **Memory Usage**: 50% reduction with streaming and cleanup
- **Seeding Time**: 90% faster with bulk inserts

### Monitoring Recommendations
```elixir
# Add telemetry for performance tracking
:telemetry.execute([:live_poll, :vote, :processed], %{duration: duration})
:telemetry.execute([:live_poll, :trend, :calculated], %{event_count: count})
```

The application shows good real-time performance for small to medium datasets but needs optimization for production scale with high vote volumes.
