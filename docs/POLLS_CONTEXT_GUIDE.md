# Polls Context Developer Guide

## Overview

The Polls context is the central business logic layer for all poll-related operations in the LivePoll application. It follows Phoenix's context pattern to provide a clean, testable API.

## Architecture

```
LivePoll.Polls (Context)
├── LivePoll.Polls.VoteService (Calculations)
├── LivePoll.Polls.TrendAnalyzer (Time Series)
└── LivePoll.Polls.Seeder (Test Data)
```

## Quick Start

### Basic Usage

```elixir
# In your LiveView or controller
alias LivePoll.Polls

# Get all poll options
options = Polls.list_options()

# Cast a vote
{:ok, option, event} = Polls.cast_vote(option_id)

# Get comprehensive statistics
stats = Polls.get_stats()
# => %{
#   options: [...],
#   sorted_options: [...],
#   total_votes: 1337,
#   percentages: %{"Elixir" => 42.5},
#   leader: %Option{text: "Python"}
# }

# Calculate trends
trend_data = Polls.calculate_trends(60) # last 60 minutes
```

## API Reference

### Options Management

#### `list_options/0`
Returns all poll options sorted by ID.

```elixir
options = Polls.list_options()
# => [%Option{id: 1, text: "Elixir", votes: 42}, ...]
```

#### `list_options_by_votes/0`
Returns options sorted by vote count (descending).

```elixir
options = Polls.list_options_by_votes()
# => [%Option{text: "Python", votes: 100}, %Option{text: "Elixir", votes: 42}]
```

#### `get_option!/1`
Gets a single option by ID. Raises `Ecto.NoResultsError` if not found.

```elixir
option = Polls.get_option!(1)
# => %Option{id: 1, text: "Elixir"}
```

#### `add_language/1`
Adds a new language option with validation.

```elixir
{:ok, option} = Polls.add_language("Rust")
# => {:ok, %Option{text: "Rust", votes: 0}}

{:error, reason} = Polls.add_language("")
# => {:error, "Language name cannot be empty"}

{:error, reason} = Polls.add_language("Elixir") # already exists
# => {:error, "Language already exists"}
```

### Voting Operations

#### `cast_vote/1`
Atomically increments vote count and records event.

```elixir
{:ok, option, event} = Polls.cast_vote(option_id)
# => {:ok, %Option{votes: 43}, %VoteEvent{votes_after: 43}}

{:error, :option_not_found} = Polls.cast_vote(999)
{:error, :invalid_option_id} = Polls.cast_vote("invalid")
```

**Features:**
- Atomic increment (prevents race conditions)
- Creates vote event for trend analysis
- Broadcasts update via PubSub

#### `reset_all_votes/0`
Resets all votes to zero and clears history.

```elixir
{:ok, :reset_complete} = Polls.reset_all_votes()
```

**Actions:**
- Deletes all vote events
- Resets all vote counts to 0
- Broadcasts reset to all clients

### Statistics & Calculations

#### `calculate_percentages/1`
Calculates vote percentages for options.

```elixir
percentages = Polls.calculate_percentages()
# => %{"Elixir" => 42.5, "Python" => 57.5}

# Or pass specific options
percentages = Polls.calculate_percentages(options)
```

#### `get_total_votes/0`
Returns sum of all votes.

```elixir
total = Polls.get_total_votes()
# => 1337
```

#### `get_stats/0`
Returns comprehensive statistics.

```elixir
stats = Polls.get_stats()
# => %{
#   options: [%Option{}, ...],           # All options by ID
#   sorted_options: [%Option{}, ...],    # Options by votes (desc)
#   total_votes: 1337,                   # Total vote count
#   percentages: %{"Elixir" => 42.5},   # Vote percentages
#   leader: %Option{text: "Python"}      # Option with most votes
# }
```

### Vote Events & History

#### `list_vote_events/1`
Query vote events with filters.

```elixir
# All events (most recent first)
events = Polls.list_vote_events()

# Filter by option
events = Polls.list_vote_events(option_id: 1)

# Filter by time
since = DateTime.add(DateTime.utc_now(), -3600, :second)
events = Polls.list_vote_events(since: since)

# Filter by event type
events = Polls.list_vote_events(event_type: "vote")

# Limit results
events = Polls.list_vote_events(limit: 10)

# Combine filters
events = Polls.list_vote_events(
  option_id: 1,
  since: since,
  event_type: "vote",
  limit: 100
)
```

### Trends & Time Series

#### `calculate_trends/1`
Calculates voting trends over time with dynamic bucketing.

```elixir
# Last hour (default)
trend_data = Polls.calculate_trends(60)

# Last 5 minutes
trend_data = Polls.calculate_trends(5)

# Last 12 hours
trend_data = Polls.calculate_trends(720)

# Returns list of snapshots
# [
#   %{
#     timestamp: ~U[2025-01-01 12:00:00Z],
#     percentages: %{"Elixir" => 42.5, "Python" => 57.5},
#     vote_counts: %{"Elixir" => 42, "Python" => 58}
#   },
#   ...
# ]
```

**Bucket Sizes:**
- 5 minutes: 5-second buckets, 60 snapshots
- 1 hour: 30-second buckets, 120 snapshots
- 12 hours: 5-minute buckets, 144 snapshots
- 24 hours: 10-minute buckets, 144 snapshots

### Seeding

#### `seed_votes/1`
Generates realistic test data.

```elixir
# Default: 12-14 languages, 10k votes, 1 hour history
{:ok, :seeding_complete} = Polls.seed_votes()

# Custom configuration
{:ok, :seeding_complete} = Polls.seed_votes(
  num_languages: 10,
  total_votes: 5000,
  hours_back: 2
)
```

**Features:**
- Weighted language selection (Python, JavaScript, TypeScript most popular)
- Random timestamp backfilling
- Realistic vote distribution
- Broadcasts completion event

## PubSub Events

The context broadcasts the following events on the `"poll:updates"` topic:

### `:poll_update`
Broadcast when a vote is cast.

```elixir
{:poll_update, %{
  id: 1,
  votes: 43,
  language: "Elixir",
  timestamp: ~U[2025-01-01 12:00:00Z]
}}
```

### `:poll_reset`
Broadcast when votes are reset.

```elixir
{:poll_reset, %{
  timestamp: ~U[2025-01-01 12:00:00Z]
}}
```

### `:language_added`
Broadcast when a new language is added.

```elixir
{:language_added, %{
  name: "Rust"
}}
```

### `:data_seeded`
Broadcast when seeding completes.

```elixir
{:data_seeded, %{
  timestamp: ~U[2025-01-01 12:00:00Z]
}}
```

## Testing

### Unit Tests

```elixir
# Test voting
test "cast_vote increments vote count" do
  option = insert_option("Elixir", 10)
  {:ok, updated, _event} = Polls.cast_vote(option.id)
  assert updated.votes == 11
end

# Test concurrent votes
test "handles concurrent votes correctly" do
  option = insert_option("Elixir", 0)
  
  tasks = for _ <- 1..10 do
    Task.async(fn -> Polls.cast_vote(option.id) end)
  end
  
  Enum.each(tasks, &Task.await/1)
  
  final = Polls.get_option!(option.id)
  assert final.votes == 10
end
```

### Integration Tests

```elixir
test "seeding creates realistic data" do
  {:ok, :seeding_complete} = Polls.seed_votes()
  
  stats = Polls.get_stats()
  assert stats.total_votes > 0
  assert length(stats.options) >= 12
  
  # Verify trend data exists
  trends = Polls.calculate_trends(60)
  assert length(trends) > 0
end
```

## Best Practices

### 1. Always Use the Context
❌ **Don't** query the database directly in LiveViews:
```elixir
# BAD
options = Repo.all(Option)
```

✅ **Do** use the context:
```elixir
# GOOD
options = Polls.list_options()
```

### 2. Handle Errors Gracefully
```elixir
case Polls.cast_vote(option_id) do
  {:ok, option, _event} ->
    # Success
    {:noreply, socket}
    
  {:error, :option_not_found} ->
    {:noreply, put_flash(socket, :error, "Option not found")}
    
  {:error, _reason} ->
    {:noreply, put_flash(socket, :error, "Failed to cast vote")}
end
```

### 3. Use Pattern Matching
```elixir
# Get specific stats
%{total_votes: total, leader: leader} = Polls.get_stats()
```

### 4. Subscribe to PubSub Events
```elixir
def mount(_params, _session, socket) do
  Phoenix.PubSub.subscribe(LivePoll.PubSub, "poll:updates")
  # ...
end

def handle_info({:poll_update, data}, socket) do
  # Handle update
end
```

## Performance Considerations

### Trend Calculation
- Uses database aggregation for efficiency
- Dynamic bucket sizing reduces data points
- Caches state carry-forward for missing buckets

### Concurrent Votes
- Uses atomic database operations
- No race conditions
- Scales horizontally

### Seeding
- Batch inserts for performance
- Runs in transaction
- Can be moved to background job if needed

## Migration from Old Code

### Before (Direct Repo Access)
```elixir
option = Repo.get!(Option, id)
changeset = Ecto.Changeset.change(option, votes: option.votes + 1)
Repo.update!(changeset)
```

### After (Using Context)
```elixir
{:ok, option, _event} = Polls.cast_vote(id)
```

## Further Reading

- [Phoenix Contexts Guide](https://hexdocs.pm/phoenix/contexts.html)
- [Ecto Query Guide](https://hexdocs.pm/ecto/Ecto.Query.html)
- [Phoenix PubSub](https://hexdocs.pm/phoenix_pubsub/Phoenix.PubSub.html)

