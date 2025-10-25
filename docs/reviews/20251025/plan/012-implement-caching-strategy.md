# Task: Implement Caching Strategy with ETS/Cachex

## Category
Performance, Scalability

## Priority
**MEDIUM** - Reduces database load and improves response times

## Description
The application has no caching, causing every request to hit the database. This creates unnecessary load and poor performance under concurrent usage. A caching layer using ETS or Cachex must be implemented for frequently accessed data.

## Current State
```elixir
# Every request hits the database
def get_stats do
  options = Repo.all(Option)  # Database hit
  events = Repo.all(VoteEvent)  # Database hit
  # Calculate everything from scratch every time
end

# Multiple clients = multiple identical database queries
# 100 clients viewing = 100x database queries for same data
```

## Proposed Solution

### Step 1: Add Cachex Dependency
```elixir
# mix.exs
defp deps do
  [
    # ... existing deps
    {:cachex, "~> 3.6"}
  ]
end
```

### Step 2: Configure Cache Application
```elixir
# lib/live_poll/application.ex
defmodule LivePoll.Application do
  use Application
  
  def start(_type, _args) do
    children = [
      # ... existing children
      
      # Cache for poll statistics
      {Cachex, name: :poll_cache, 
       limit: 1000,
       stats: true,
       warmers: [
         warmer(module: LivePoll.Cache.Warmer, state: %{})
       ]},
      
      # Cache for trend data
      {Cachex, name: :trend_cache,
       limit: 100,
       ttl: :timer.minutes(1),
       stats: true},
      
      # Cache for chart data
      {Cachex, name: :chart_cache,
       limit: 50,
       ttl: :timer.seconds(30),
       stats: true}
    ]
    
    opts = [strategy: :one_for_one, name: LivePoll.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

### Step 3: Create Cache Module
```elixir
# lib/live_poll/cache.ex
defmodule LivePoll.Cache do
  @moduledoc """
  Centralized caching for poll data
  """
  
  require Logger
  
  @poll_cache :poll_cache
  @trend_cache :trend_cache
  @chart_cache :chart_cache
  
  # TTL configurations
  @stats_ttl :timer.seconds(5)
  @trend_ttl :timer.minutes(1)
  @chart_ttl :timer.seconds(30)
  @options_ttl :timer.minutes(5)
  
  # ============================================
  # Poll Statistics Cache
  # ============================================
  
  @doc """
  Get cached poll statistics or compute and cache
  """
  def get_stats do
    Cachex.fetch(@poll_cache, "stats", fn ->
      {:commit, compute_stats(), ttl: @stats_ttl}
    end)
    |> handle_cache_result()
  end
  
  @doc """
  Get cached options list
  """
  def get_options do
    Cachex.fetch(@poll_cache, "options", fn ->
      {:commit, LivePoll.Polls.list_options_from_db(), ttl: @options_ttl}
    end)
    |> handle_cache_result()
  end
  
  @doc """
  Invalidate stats cache after vote
  """
  def invalidate_stats do
    Cachex.del(@poll_cache, "stats")
    Cachex.del(@chart_cache, "pie_chart")
    :ok
  end
  
  @doc """
  Update specific option in cache
  """
  def update_option_cache(option) do
    Cachex.get_and_update(@poll_cache, "options", fn
      nil -> {:commit, [option]}
      options ->
        updated = Enum.map(options, fn opt ->
          if opt.id == option.id, do: option, else: opt
        end)
        {:commit, updated}
    end)
  end
  
  # ============================================
  # Trend Data Cache
  # ============================================
  
  @doc """
  Get cached trend data for time range
  """
  def get_trends(minutes_back \\ 60) do
    cache_key = "trends_#{minutes_back}"
    
    Cachex.fetch(@trend_cache, cache_key, fn ->
      {:commit, compute_trends(minutes_back), ttl: @trend_ttl}
    end)
    |> handle_cache_result()
  end
  
  @doc """
  Invalidate trend cache
  """
  def invalidate_trends do
    Cachex.clear(@trend_cache)
    :ok
  end
  
  # ============================================
  # Chart Data Cache
  # ============================================
  
  @doc """
  Get cached chart data
  """
  def get_chart_data(type \\ :pie) do
    cache_key = "#{type}_chart"
    
    Cachex.fetch(@chart_cache, cache_key, fn ->
      {:commit, compute_chart_data(type), ttl: @chart_ttl}
    end)
    |> handle_cache_result()
  end
  
  # ============================================
  # Recent Activity Cache (LRU)
  # ============================================
  
  @doc """
  Get recent activity with caching
  """
  def get_recent_activity(limit \\ 10) do
    Cachex.fetch(@poll_cache, "recent_activity_#{limit}", fn ->
      {:commit, LivePoll.Polls.get_recent_activity_from_db(limit), ttl: @stats_ttl}
    end)
    |> handle_cache_result()
  end
  
  @doc """
  Add new activity to cache
  """
  def add_activity(activity) do
    Cachex.get_and_update(@poll_cache, "recent_activity_10", fn
      nil -> {:commit, [activity]}
      activities ->
        updated = [activity | activities] |> Enum.take(10)
        {:commit, updated}
    end)
  end
  
  # ============================================
  # Cache Management
  # ============================================
  
  @doc """
  Clear all caches
  """
  def clear_all do
    Cachex.clear(@poll_cache)
    Cachex.clear(@trend_cache)
    Cachex.clear(@chart_cache)
    Logger.info("All caches cleared")
    :ok
  end
  
  @doc """
  Get cache statistics
  """
  def get_cache_stats do
    %{
      poll_cache: get_cache_info(@poll_cache),
      trend_cache: get_cache_info(@trend_cache),
      chart_cache: get_cache_info(@chart_cache)
    }
  end
  
  defp get_cache_info(cache) do
    {:ok, stats} = Cachex.stats(cache)
    
    %{
      hits: stats.hits,
      misses: stats.misses,
      hit_rate: calculate_hit_rate(stats),
      size: Cachex.size!(cache),
      memory: :erlang.memory(:ets)
    }
  end
  
  defp calculate_hit_rate(%{hits: hits, misses: misses}) do
    total = hits + misses
    if total > 0, do: Float.round(hits * 100 / total, 2), else: 0.0
  end
  
  # ============================================
  # Private Functions
  # ============================================
  
  defp handle_cache_result({:ok, value}), do: value
  defp handle_cache_result({:commit, value}), do: value
  defp handle_cache_result({:error, _reason}), do: nil
  
  defp compute_stats do
    options = LivePoll.Polls.list_options_from_db()
    total = Enum.sum(Enum.map(options, & &1.votes))
    percentages = LivePoll.Polls.calculate_percentages(options)
    
    %{
      options: options,
      total_votes: total,
      percentages: percentages,
      timestamp: DateTime.utc_now()
    }
  end
  
  defp compute_trends(minutes_back) do
    LivePoll.Polls.TrendAnalyzer.calculate(minutes_back)
  end
  
  defp compute_chart_data(type) do
    LivePoll.Polls.get_chart_data_from_db(type)
  end
end
```

### Step 4: Create Cache Warmer
```elixir
# lib/live_poll/cache/warmer.ex
defmodule LivePoll.Cache.Warmer do
  @moduledoc """
  Warms cache on startup and periodically
  """
  
  use Cachex.Warmer
  
  @impl true
  def interval(_state), do: :timer.minutes(5)
  
  @impl true
  def execute(_state) do
    # Pre-load frequently accessed data
    options = LivePoll.Polls.list_options_from_db()
    stats = compute_stats(options)
    trends = LivePoll.Polls.TrendAnalyzer.calculate(60)
    
    {:ok, [
      {"options", options, ttl: :timer.minutes(5)},
      {"stats", stats, ttl: :timer.seconds(30)},
      {"trends_60", trends, ttl: :timer.minutes(1)}
    ]}
  end
  
  defp compute_stats(options) do
    %{
      options: options,
      total_votes: Enum.sum(Enum.map(options, & &1.votes)),
      percentages: LivePoll.Polls.calculate_percentages(options)
    }
  end
end
```

### Step 5: Update Polls Context to Use Cache
```elixir
# lib/live_poll/polls.ex
defmodule LivePoll.Polls do
  alias LivePoll.Cache
  
  @doc """
  Get options with caching
  """
  def list_options do
    Cache.get_options()
  end
  
  @doc """
  Get options directly from database (cache bypass)
  """
  def list_options_from_db do
    Repo.all(from o in Option, order_by: [asc: o.id])
  end
  
  @doc """
  Get stats with caching
  """
  def get_stats do
    Cache.get_stats()
  end
  
  @doc """
  Cast vote and update cache
  """
  def cast_vote(option_id) do
    result = Repo.transaction(fn ->
      # Atomic vote increment
      {1, [updated]} = from(o in Option, where: o.id == ^option_id)
        |> Repo.update_all([inc: [votes: 1]], returning: true)
      
      # Record event
      event = create_vote_event(updated)
      
      # Update cache with new data
      Cache.update_option_cache(updated)
      Cache.invalidate_stats()
      Cache.add_activity(format_activity(event))
      
      {:ok, updated, event}
    end)
    
    case result do
      {:ok, data} -> data
      error -> error
    end
  end
  
  @doc """
  Get trend data with caching
  """
  def calculate_trends(minutes_back \\ 60) do
    Cache.get_trends(minutes_back)
  end
  
  @doc """
  Get chart data with caching
  """
  def get_chart_data(type \\ :pie) do
    Cache.get_chart_data(type)
  end
  
  @doc """
  Reset votes and clear cache
  """
  def reset_all_votes do
    result = Repo.transaction(fn ->
      Repo.delete_all(VoteEvent)
      Repo.update_all(Option, set: [votes: 0])
    end)
    
    # Clear all caches after reset
    Cache.clear_all()
    
    result
  end
end
```

### Step 6: Add Cache Monitoring
```elixir
# lib/live_poll_web/live/admin/cache_live.ex
defmodule LivePollWeb.Admin.CacheLive do
  use LivePollWeb, :live_view
  
  def mount(_params, _session, socket) do
    if connected?(socket) do
      :timer.send_interval(5000, self(), :update_stats)
    end
    
    {:ok, load_stats(socket)}
  end
  
  def render(assigns) do
    ~H"""
    <div class="cache-stats">
      <h2>Cache Statistics</h2>
      
      <%= for {name, stats} <- @cache_stats do %>
        <div class="cache-info">
          <h3><%= name %></h3>
          <dl>
            <dt>Hit Rate:</dt>
            <dd><%= stats.hit_rate %>%</dd>
            
            <dt>Hits:</dt>
            <dd><%= stats.hits %></dd>
            
            <dt>Misses:</dt>
            <dd><%= stats.misses %></dd>
            
            <dt>Size:</dt>
            <dd><%= stats.size %> items</dd>
          </dl>
        </div>
      <% end %>
      
      <div class="actions">
        <.button phx-click="clear_cache" data-confirm="Clear all caches?">
          Clear All Caches
        </.button>
      </div>
    </div>
    """
  end
  
  def handle_info(:update_stats, socket) do
    {:noreply, load_stats(socket)}
  end
  
  def handle_event("clear_cache", _params, socket) do
    LivePoll.Cache.clear_all()
    {:noreply, 
     socket
     |> load_stats()
     |> put_flash(:info, "All caches cleared")}
  end
  
  defp load_stats(socket) do
    assign(socket, :cache_stats, LivePoll.Cache.get_cache_stats())
  end
end
```

## Requirements
1. ✅ Implement multi-level caching with TTLs
2. ✅ Cache frequently accessed data (options, stats, trends)
3. ✅ Invalidate cache on updates
4. ✅ Warm cache on startup
5. ✅ Add cache statistics monitoring
6. ✅ Reduce database load by 80%+
7. ✅ Support cache bypass when needed

## Definition of Done
1. **Cache Implementation**
   - [ ] Cachex dependency added
   - [ ] Cache modules created
   - [ ] TTLs configured appropriately
   - [ ] Cache warming implemented

2. **Integration**
   - [ ] Polls context uses cache
   - [ ] Cache invalidation on updates
   - [ ] Cache statistics available
   - [ ] Admin UI for cache management

3. **Performance Metrics**
   - [ ] Database queries reduced by 80%+
   - [ ] Response time improved by 50%+
   - [ ] Cache hit rate >90%
   - [ ] Memory usage reasonable

4. **Quality Checks**
   - [ ] Cache doesn't serve stale data
   - [ ] Invalidation works correctly
   - [ ] No memory leaks
   - [ ] Tests pass with cache

## Branch Name
`feature/add-caching-layer`

## Dependencies
- Task 004 (Extract Context) - Cache integrated with context

## Estimated Complexity
**M (Medium)** - 4-6 hours

## Testing Instructions
1. Add Cachex dependency and compile
2. Configure cache in application
3. Implement cache module
4. Update Polls context to use cache
5. Test voting updates cache properly
6. Monitor cache hit rates
7. Verify database query reduction
8. Test cache invalidation works

## Performance Impact
### Before
- Every request hits database
- 100 clients = 100 DB queries/second
- Response time: 50-100ms

### After (Expected)
- 90%+ requests served from cache
- 100 clients = 10 DB queries/second
- Response time: 5-10ms
- Database load reduced by 90%

## Notes
- Consider Redis for distributed deployments
- Monitor cache memory usage
- Adjust TTLs based on usage patterns
- May need different cache strategies for different data types
