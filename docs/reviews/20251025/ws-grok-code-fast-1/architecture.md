# Architecture & Design Patterns

## Overall Application Structure

### Phoenix LiveView Architecture
The application follows a traditional Phoenix LiveView pattern:

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   LiveView      │    │   PubSub         │    │   Database      │
│   (poll_live.ex)│◄──►│   Broadcasting   │◄──►│   PostgreSQL    │
└─────────────────┘    └──────────────────┘    └─────────────────┘
         │                       │                       │
         ▼                       ▼                       ▼
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Templates     │    │   WebSocket      │    │   Ecto Models   │
│   (HEEx)        │    │   Connections     │    │   (Schemas)     │
└─────────────────┘    └──────────────────┘    └─────────────────┘
```

### Data Flow Architecture

1. **Client Request**: User clicks vote button
2. **LiveView Event**: `handle_event("vote", ...)` processes the vote
3. **Database Update**: Direct Ecto update + VoteEvent creation
4. **PubSub Broadcast**: `Phoenix.PubSub.broadcast/3` notifies all clients
5. **Real-time Updates**: Connected LiveViews receive updates via `handle_info/2`

## PubSub Implementation

### Current Implementation
- **Topic**: `"poll:updates"` (single global topic)
- **Broadcast Events**:
  - `{:poll_update, %{id: id, votes: votes, language: language, timestamp: timestamp}}`
  - `{:poll_reset, %{timestamp: timestamp}}`
  - `{:language_added, %{name: name}}`
  - `{:data_seeded, %{timestamp: timestamp}}`

### Strengths
- Simple and effective for real-time updates
- Proper subscription in `mount/3`
- All connected clients receive updates immediately

### Issues
- **Single Topic**: All poll updates go to one topic - scales poorly with multiple polls
- **No Filtering**: All clients receive all updates, even if not relevant
- **Broadcast Overhead**: Large numbers of clients all process every update

### Recommendations
```elixir
# Better topic structure
@topic "poll:#{poll_id}:updates"

# Or per-option topics for more granular control
@option_topic "poll:option:#{option_id}"
```

## Time-Series Event System

### Design Overview
The application implements a time-series database for vote events:

```
VoteEvent Schema:
- option_id (foreign key)
- language (denormalized for performance)
- votes_after (snapshot of vote count)
- event_type ("vote" | "seed" | "reset")
- inserted_at (timestamp)
```

### Data Bucketing Strategy
The `build_trend_data_from_events/1` function implements dynamic bucketing:

```elixir
{bucket_seconds, max_snapshots} = case minutes_back do
  5 -> {5, 60}           # 5-second buckets, 60 snapshots
  60 -> {30, 120}        # 30-second buckets, 120 snapshots
  720 -> {300, 144}      # 5-minute buckets, 144 snapshots
  1440 -> {600, 144}     # 10-minute buckets, 144 snapshots
end
```

### Strengths
- **Flexible Time Ranges**: Supports 5min to 24hr views with appropriate granularity
- **Event Sourcing**: Complete audit trail of all votes
- **Denormalization**: Language stored in events for fast queries
- **Snapshot Approach**: Buckets reduce data points for visualization

### Issues
- **Memory Intensive**: Large time ranges load many events into memory
- **Complex Logic**: 106-line function doing too much
- **No Indexing**: Potential slow queries on `inserted_at` for large datasets
- **No Data Retention**: Events accumulate indefinitely

### Recommendations
1. **Add Database Indexes**:
```elixir
create index(:vote_events, [:inserted_at])
create index(:vote_events, [:option_id, :inserted_at])
```

2. **Implement Data Retention Policy**:
```elixir
# Delete events older than 30 days
Repo.delete_all(from e in VoteEvent, where: e.inserted_at < ago(30, "day"))
```

3. **Extract Service Module**:
```elixir
defmodule LivePoll.Poll.TrendCalculator do
  def build_trend_data(events, time_range) do
    # Extracted logic
  end
end
```

## Separation of Concerns

### Current Structure
```
lib/live_poll/
├── poll/           # Domain models
│   ├── option.ex
│   └── vote_event.ex
├── application.ex  # OTP application
├── repo.ex         # Database configuration
└── mailer.ex       # Email (unused)

lib/live_poll_web/
├── live/           # LiveViews (business logic mixed)
├── components/     # UI components
├── controllers/    # HTTP endpoints (minimal)
└── views/          # Templates (minimal)
```

### Issues
- **Business Logic in LiveView**: Voting, seeding, trend calculation all in `PollLive`
- **No Service Layer**: Domain logic scattered across LiveView handlers
- **Thin Models**: Ecto schemas have no business logic methods

### Recommended Architecture
```
lib/live_poll/
├── poll/
│   ├── option.ex
│   ├── vote_event.ex
│   └── services/          # NEW
│       ├── voting_service.ex
│       ├── seeding_service.ex
│       └── trend_service.ex
└── pubsub.ex              # NEW - PubSub wrapper

lib/live_poll_web/
├── live/
│   └── poll_live.ex       # Thin LiveView, delegates to services
└── components/
    └── poll_components.ex # Extracted UI components
```

## Chart Integration Strategy

### ECharts Integration
- **Hooks**: `PieChart` and `TrendChart` hooks manage chart instances
- **Data Flow**: Server pushes data via `push_event/3`
- **Theme Support**: Charts adapt to light/dark themes

### Strengths
- **Modern Library**: ECharts is powerful and well-maintained
- **Real-time Updates**: Charts update instantly via LiveView events
- **Responsive**: Charts resize properly with container

### Issues
- **Large Bundle**: ECharts adds ~500KB to JavaScript bundle
- **Complex Setup**: Multiple hooks for different chart types
- **Theme Handling**: MutationObserver approach works but is overkill

### Recommendations
1. **Lazy Loading**: Load ECharts only when charts are visible
2. **Single Hook**: Merge PieChart and TrendChart into one configurable hook
3. **CSS Variables**: Use CSS custom properties for theming instead of JavaScript

## Real-time Update Patterns

### Current Implementation
- **Periodic Updates**: Stats update every 5 seconds
- **Event-Driven**: Chart updates triggered by vote events
- **Broadcast Model**: All clients receive all updates

### Scalability Concerns
- **Memory Usage**: Each LiveView holds full poll state
- **Database Load**: Frequent `Repo.all(Option)` calls
- **Network Overhead**: All clients process all broadcasts

### Optimization Strategies
1. **Stream LiveView**: Use `Phoenix.LiveView.stream/3` for large option lists
2. **Presence Tracking**: Only broadcast to active clients
3. **Debounced Updates**: Batch rapid vote updates
4. **Selective Updates**: Only send diffs instead of full state

## Database Design

### Schema Relationships
```
Option (1) ──── (many) VoteEvent
   │                    │
   └── id               └── option_id
   └── text             └── language (denormalized)
   └── votes            └── votes_after
   └── timestamps       └── event_type
                        └── timestamps
```

### Strengths
- **Event Sourcing**: Complete audit trail
- **Denormalization**: Fast reads for trends
- **Proper Constraints**: Foreign keys and validations

### Issues
- **No Preloading**: N+1 queries possible
- **No Indexes**: Missing performance indexes
- **Accumulating Data**: VoteEvents grow indefinitely

## Summary

The architecture is solid for a real-time polling application but has several areas for improvement:

1. **Extract Business Logic**: Move domain logic out of LiveView into service modules
2. **Improve PubSub**: Use more specific topics and consider presence tracking
3. **Optimize Database**: Add indexes, implement data retention, use preloading
4. **Enhance Real-time**: Implement streaming and selective updates
5. **Refactor Large Functions**: Break down complex functions into smaller modules

The time-series approach is innovative and well-suited for trend analysis, but needs performance optimizations for production scale.
