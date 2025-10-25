# Task: Optimize Database Queries and Add Indexes

## Category
Performance, Database

## Priority
**MEDIUM** - Poor query performance affects scalability

## Description
The application has inefficient database queries including unnecessary preloads, missing compound indexes, N+1 query patterns, and loading all events into memory for trend calculations. Database optimization is needed for scalability.

## Current State
```elixir
# Unnecessary preload adding overhead
events = from(e in VoteEvent,
  where: e.inserted_at >= ^cutoff_time,
  order_by: [asc: e.inserted_at],
  preload: :option  # NOT NEEDED - never used!
) |> Repo.all()

# Missing compound indexes for common queries
# Only basic single-column indexes exist
create index(:vote_events, [:option_id])
create index(:vote_events, [:inserted_at])
# No compound index for WHERE option_id AND inserted_at queries

# Loading ALL events into memory
events = Repo.all(VoteEvent)  # Could be millions!
```

## Proposed Solution

### Step 1: Remove Unnecessary Preloads
```elixir
# lib/live_poll/polls/trend_analyzer.ex
defmodule LivePoll.Polls.TrendAnalyzer do
  import Ecto.Query
  alias LivePoll.Repo
  alias LivePoll.Polls.VoteEvent
  
  def calculate(minutes_back \\ 60) do
    cutoff_time = DateTime.add(DateTime.utc_now(), -minutes_back * 60, :second)
    
    # REMOVED preload :option - not needed!
    # Use database aggregation instead of loading all events
    query = from e in VoteEvent,
      where: e.inserted_at >= ^cutoff_time,
      group_by: [
        fragment("date_trunc('minute', ?)", e.inserted_at),
        e.option_id,
        e.language
      ],
      select: %{
        bucket: fragment("date_trunc('minute', ?)", e.inserted_at),
        option_id: e.option_id,
        language: e.language,
        max_votes: max(e.votes_after)
      },
      order_by: [asc: fragment("date_trunc('minute', ?)", e.inserted_at)]
    
    Repo.all(query)
    |> process_aggregated_data()
  end
  
  defp process_aggregated_data(results) do
    # Process pre-aggregated data instead of raw events
    results
    |> Enum.group_by(& &1.bucket)
    |> fill_missing_buckets()
    |> calculate_percentages()
  end
end
```

### Step 2: Add Missing Database Indexes
```elixir
# priv/repo/migrations/20251025000002_add_performance_indexes.exs
defmodule LivePoll.Repo.Migrations.AddPerformanceIndexes do
  use Ecto.Migration
  
  def up do
    # Compound index for trend queries
    create index(:vote_events, [:inserted_at, :option_id, :votes_after], 
      name: :idx_vote_events_time_option_votes,
      comment: "Optimizes trend calculation queries"
    )
    
    # Index for event type filtering
    create index(:vote_events, [:event_type, :inserted_at], 
      name: :idx_vote_events_type_time,
      comment: "Optimizes filtering by event type"
    )
    
    # Covering index for vote queries
    create index(:vote_events, [:option_id, :inserted_at, :votes_after], 
      name: :idx_vote_events_option_time_votes,
      comment: "Covering index for vote queries"
    )
    
    # Partial index for recent events only
    create index(:vote_events, [:inserted_at], 
      name: :idx_vote_events_recent,
      where: "inserted_at > NOW() - INTERVAL '7 days'",
      comment: "Optimizes recent event queries"
    )
    
    # Index for unique constraint performance
    execute "CREATE UNIQUE INDEX CONCURRENTLY poll_options_lower_text_unique 
             ON poll_options (lower(trim(text)))"
    
    # Drop redundant single-column indexes
    drop_if_exists index(:vote_events, [:option_id])
    drop_if_exists index(:vote_events, [:inserted_at])
  end
  
  def down do
    drop_if_exists index(:vote_events, :idx_vote_events_time_option_votes)
    drop_if_exists index(:vote_events, :idx_vote_events_type_time)
    drop_if_exists index(:vote_events, :idx_vote_events_option_time_votes)
    drop_if_exists index(:vote_events, :idx_vote_events_recent)
    drop_if_exists index(:poll_options, :poll_options_lower_text_unique)
    
    # Restore original indexes
    create index(:vote_events, [:option_id])
    create index(:vote_events, [:inserted_at])
  end
end
```

### Step 3: Optimize Common Queries
```elixir
# lib/live_poll/polls/queries.ex
defmodule LivePoll.Polls.Queries do
  @moduledoc """
  Optimized database queries for the Polls context
  """
  
  import Ecto.Query
  alias LivePoll.Repo
  alias LivePoll.Polls.{Option, VoteEvent}
  
  @doc """
  Get vote statistics with single query
  """
  def get_vote_stats do
    query = from o in Option,
      left_join: e in VoteEvent,
      on: o.id == e.option_id and e.event_type == "vote",
      group_by: o.id,
      select: %{
        id: o.id,
        text: o.text,
        votes: o.votes,
        first_vote: min(e.inserted_at),
        last_vote: max(e.inserted_at),
        event_count: count(e.id)
      }
    
    Repo.all(query)
  end
  
  @doc """
  Get recent activity without loading all events
  """
  def get_recent_activity(limit \\ 10) do
    query = from e in VoteEvent,
      where: e.event_type == "vote",
      order_by: [desc: e.inserted_at],
      limit: ^limit,
      select: %{
        language: e.language,
        votes_after: e.votes_after,
        timestamp: e.inserted_at
      }
    
    Repo.all(query)
  end
  
  @doc """
  Calculate trends using window functions
  """
  def calculate_trend_data(minutes_back) do
    cutoff = DateTime.add(DateTime.utc_now(), -minutes_back * 60, :second)
    
    query = """
    WITH time_buckets AS (
      SELECT 
        date_trunc('minute', inserted_at) as bucket,
        option_id,
        language,
        MAX(votes_after) as votes
      FROM vote_events
      WHERE inserted_at >= $1
      GROUP BY bucket, option_id, language
    ),
    all_buckets AS (
      SELECT generate_series(
        date_trunc('minute', $1::timestamp),
        date_trunc('minute', NOW()),
        '1 minute'::interval
      ) as bucket
    ),
    filled_data AS (
      SELECT 
        ab.bucket,
        ve.option_id,
        ve.language,
        COALESCE(
          ve.votes,
          LAG(ve.votes, 1) OVER (PARTITION BY ve.option_id ORDER BY ab.bucket)
        ) as votes
      FROM all_buckets ab
      LEFT JOIN time_buckets ve ON ab.bucket = ve.bucket
    )
    SELECT * FROM filled_data
    ORDER BY bucket, option_id
    """
    
    case Repo.query(query, [cutoff]) do
      {:ok, %{rows: rows}} -> process_trend_rows(rows)
      {:error, _} -> []
    end
  end
  
  @doc """
  Batch update vote counts efficiently
  """
  def update_all_vote_counts do
    query = """
    UPDATE poll_options o
    SET votes = COALESCE((
      SELECT MAX(votes_after)
      FROM vote_events e
      WHERE e.option_id = o.id
        AND e.event_type IN ('vote', 'seed')
    ), 0)
    """
    
    Repo.query(query)
  end
  
  @doc """
  Get options with vote counts in single query
  """
  def get_options_with_stats do
    query = from o in Option,
      left_join: e in subquery(
        from e in VoteEvent,
        where: e.event_type == "vote",
        group_by: e.option_id,
        select: %{
          option_id: e.option_id,
          total_votes: count(e.id),
          last_vote: max(e.inserted_at)
        }
      ),
      on: o.id == e.option_id,
      select: %{
        id: o.id,
        text: o.text,
        votes: o.votes,
        total_events: coalesce(e.total_votes, 0),
        last_vote_at: e.last_vote
      },
      order_by: [asc: o.id]
    
    Repo.all(query)
  end
end
```

### Step 4: Add Query Performance Monitoring
```elixir
# lib/live_poll/repo.ex
defmodule LivePoll.Repo do
  use Ecto.Repo,
    otp_app: :live_poll,
    adapter: Ecto.Adapters.Postgres
  
  @doc """
  Log slow queries in development
  """
  def default_options(_operation) do
    if Mix.env() == :dev do
      [
        telemetry_options: [
          event: [:live_poll, :repo, :query]
        ],
        log: :debug,
        timeout: 15_000,
        log_slow_queries: [threshold: 100]  # Log queries over 100ms
      ]
    else
      [
        telemetry_options: [
          event: [:live_poll, :repo, :query]
        ]
      ]
    end
  end
  
  @doc """
  Explain analyze a query for performance tuning
  """
  def explain_analyze(queryable) do
    sql = Ecto.Adapters.SQL.to_sql(:all, __MODULE__, queryable)
    
    case query("EXPLAIN (ANALYZE, BUFFERS) #{elem(sql, 0)}", elem(sql, 1)) do
      {:ok, result} ->
        Enum.each(result.rows, fn [plan] -> IO.puts(plan) end)
        :ok
      error ->
        error
    end
  end
end
```

### Step 5: Implement Connection Pooling Optimization
```elixir
# config/runtime.exs
import Config

if config_env() == :prod do
  config :live_poll, LivePoll.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "20"),
    queue_target: 5_000,
    queue_interval: 1_000,
    timeout: 15_000,
    # Prepared statements cache
    prepare: :unnamed,
    # Connection parameters
    parameters: [
      tcp_keepalives_idle: "60",
      tcp_keepalives_interval: "10", 
      tcp_keepalives_count: "6"
    ]
end
```

## Requirements
1. ✅ Remove unnecessary preloads from queries
2. ✅ Add compound indexes for common query patterns
3. ✅ Use database aggregation instead of loading all data
4. ✅ Optimize N+1 query patterns
5. ✅ Add query performance monitoring
6. ✅ Configure connection pooling properly
7. ✅ Use window functions for complex calculations

## Definition of Done
1. **Query Optimization**
   - [ ] All unnecessary preloads removed
   - [ ] Aggregation done in database
   - [ ] N+1 patterns eliminated
   - [ ] Window functions used where appropriate

2. **Database Indexes**
   - [ ] Compound indexes created
   - [ ] Redundant indexes removed
   - [ ] Partial indexes for recent data
   - [ ] Covering indexes for common queries

3. **Performance Metrics**
   ```sql
   -- Verify index usage
   SELECT schemaname, tablename, indexname, idx_scan
   FROM pg_stat_user_indexes
   WHERE schemaname = 'public'
   ORDER BY idx_scan DESC;
   
   -- Check query performance
   SELECT mean_exec_time, calls, query
   FROM pg_stat_statements
   WHERE query LIKE '%vote_events%'
   ORDER BY mean_exec_time DESC
   LIMIT 10;
   ```

4. **Quality Checks**
   - [ ] All queries under 100ms
   - [ ] No sequential scans on large tables
   - [ ] Connection pool properly sized
   - [ ] Slow query logging enabled

## Branch Name
`fix/optimize-database-performance`

## Dependencies
- Task 004 (Extract Context) - Queries should be in context

## Estimated Complexity
**M (Medium)** - 4-6 hours

## Testing Instructions
1. Run migration to add indexes
2. Verify indexes created: `\d vote_events` in psql
3. Run EXPLAIN ANALYZE on common queries
4. Verify index usage in query plans
5. Load test with 10k+ events
6. Monitor query performance in logs
7. Check no sequential scans on large tables

## Performance Benchmarks
### Before
- Trend calculation: 500ms+ with 10k events
- Recent activity: 50ms
- Vote stats: 100ms
- Memory usage: 50MB+ for trends

### After (Expected)
- Trend calculation: <50ms with 10k events
- Recent activity: <5ms
- Vote stats: <10ms
- Memory usage: <5MB for trends

## Notes
- Consider partitioning vote_events table for very large datasets
- May need to adjust indexes based on actual query patterns
- Monitor pg_stat_statements for optimization opportunities
- Consider materialized views for complex aggregations
