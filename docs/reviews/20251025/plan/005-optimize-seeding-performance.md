# Task: Optimize Vote Seeding Performance with Batch Inserts

## Category
Performance, Database

## Priority
**HIGH** - Current implementation takes 30+ seconds for 10k votes

## Description
The vote seeding process performs 20,000+ individual database operations (10k inserts + 10k updates) when seeding 10,000 votes. This inefficient approach blocks the LiveView process and provides poor user experience. Must be refactored to use batch inserts.

## Current State
```elixir
# Current: O(N) inserts + O(N) updates = 20,000+ DB operations
Enum.each(vote_events, fn event ->
  # First INSERT
  vote_event = Repo.insert!(%VoteEvent{
    option_id: event.option_id,
    language: event.language,
    votes_after: event.votes_after,
    event_type: "seed"
  })
  
  # Then UPDATE to fix timestamp - TERRIBLE!
  Ecto.Adapters.SQL.query!(
    Repo,
    "UPDATE vote_events SET inserted_at = $1 WHERE id = $2",
    [event.timestamp, vote_event.id]
  )
end)
```

### Performance Impact
- 10,000 votes = 30+ seconds
- Blocks LiveView process
- 20,000+ database round trips
- Poor user experience
- Database connection pool exhaustion

## Proposed Solution

### Step 1: Create Efficient Seeder Module
```elixir
# lib/live_poll/polls/seeder.ex
defmodule LivePoll.Polls.Seeder do
  @moduledoc """
  Efficient vote seeding for testing and demonstrations
  """
  
  alias LivePoll.Repo
  alias LivePoll.Polls.{Option, VoteEvent}
  import Ecto.Query
  
  @batch_size 1000
  @default_vote_count 10_000
  
  @doc """
  Seed votes with configurable distribution
  
  ## Options
    * `:vote_count` - Total votes to generate (default: 10,000)
    * `:time_range` - Time range in hours for historical data (default: 24)
    * `:distribution` - :realistic | :random | :weighted (default: :realistic)
  """
  def seed(opts \\ []) do
    vote_count = Keyword.get(opts, :vote_count, @default_vote_count)
    time_range = Keyword.get(opts, :time_range, 24)
    distribution = Keyword.get(opts, :distribution, :realistic)
    
    options = load_options_with_weights()
    
    if length(options) == 0 do
      {:error, "No options available for seeding"}
    else
      perform_seeding(options, vote_count, time_range, distribution)
    end
  end
  
  defp perform_seeding(options, vote_count, time_range, distribution) do
    Repo.transaction(fn ->
      # Generate all events in memory first
      events = generate_vote_events(options, vote_count, time_range, distribution)
      
      # Batch insert with pre-computed timestamps
      {time_microseconds, _} = :timer.tc(fn ->
        insert_events_in_batches(events)
      end)
      
      # Update option vote counts efficiently
      update_option_counts(options)
      
      # Broadcast completion
      broadcast_seeding_complete(vote_count, time_microseconds)
      
      {:ok, %{
        votes_seeded: vote_count,
        time_ms: div(time_microseconds, 1000),
        options_updated: length(options)
      }}
    end)
  end
  
  defp generate_vote_events(options, vote_count, time_range, distribution) do
    now = DateTime.utc_now()
    start_time = DateTime.add(now, -time_range * 3600, :second)
    
    # Pre-calculate vote distribution
    vote_distribution = calculate_distribution(options, vote_count, distribution)
    
    # Generate events with timestamps
    vote_distribution
    |> Enum.flat_map(fn {option, votes} ->
      generate_events_for_option(option, votes, start_time, now)
    end)
    |> Enum.shuffle()  # Randomize order for realistic pattern
    |> Enum.sort_by(& &1.inserted_at)  # Sort by time
  end
  
  defp generate_events_for_option(option, vote_count, start_time, end_time) do
    time_diff = DateTime.diff(end_time, start_time, :second)
    
    # Track cumulative votes
    {events, _} = Enum.map_reduce(1..vote_count, 0, fn i, acc ->
      votes_after = acc + 1
      
      # Distribute votes across time range
      time_offset = :rand.uniform(time_diff)
      timestamp = DateTime.add(start_time, time_offset, :second)
      
      event = %{
        option_id: option.id,
        language: option.text,
        votes_after: votes_after,
        event_type: "seed",
        inserted_at: timestamp,
        updated_at: timestamp
      }
      
      {event, votes_after}
    end)
    
    events
  end
  
  defp calculate_distribution(options, total_votes, :realistic) do
    # Realistic distribution based on language popularity
    weights = %{
      "Python" => 100,
      "JavaScript" => 90,
      "Java" => 80,
      "TypeScript" => 75,
      "Go" => 70,
      "Rust" => 65,
      "C++" => 60,
      "C#" => 55,
      "Ruby" => 50,
      "PHP" => 45,
      "Swift" => 40,
      "Kotlin" => 35,
      "Scala" => 30,
      "Elixir" => 25,
      "Haskell" => 20
    }
    
    total_weight = options
      |> Enum.map(fn opt -> Map.get(weights, opt.text, 10) end)
      |> Enum.sum()
    
    options
    |> Enum.map(fn option ->
      weight = Map.get(weights, option.text, 10)
      votes = round(total_votes * weight / total_weight)
      {option, votes}
    end)
  end
  
  defp calculate_distribution(options, total_votes, :random) do
    # Random distribution
    votes_per_option = div(total_votes, length(options))
    remainder = rem(total_votes, length(options))
    
    options
    |> Enum.with_index()
    |> Enum.map(fn {option, index} ->
      extra = if index < remainder, do: 1, else: 0
      {option, votes_per_option + extra}
    end)
  end
  
  defp calculate_distribution(options, total_votes, :weighted) do
    # Exponential distribution (first options get more votes)
    options
    |> Enum.with_index()
    |> Enum.map(fn {option, index} ->
      weight = :math.pow(0.8, index)
      votes = round(total_votes * weight / length(options))
      {option, votes}
    end)
  end
  
  defp insert_events_in_batches(events) do
    events
    |> Enum.chunk_every(@batch_size)
    |> Enum.each(fn batch ->
      Repo.insert_all(VoteEvent, batch,
        on_conflict: :nothing,
        conflict_target: [],
        returning: false
      )
    end)
  end
  
  defp update_option_counts(options) do
    # Update all option vote counts in a single query
    Enum.each(options, fn option ->
      vote_count = Repo.one(
        from e in VoteEvent,
        where: e.option_id == ^option.id and e.event_type in ["vote", "seed"],
        select: max(e.votes_after)
      ) || 0
      
      from(o in Option, where: o.id == ^option.id)
      |> Repo.update_all(set: [votes: vote_count])
    end)
  end
  
  defp load_options_with_weights do
    Repo.all(from o in Option, order_by: [asc: o.id])
  end
  
  defp broadcast_seeding_complete(vote_count, time_microseconds) do
    Phoenix.PubSub.broadcast(
      LivePoll.PubSub,
      "poll:updates",
      {:seeding_complete, %{
        votes: vote_count,
        time_ms: div(time_microseconds, 1000)
      }}
    )
  end
  
  @doc """
  Clear all seed data (keep manual votes)
  """
  def clear_seed_data do
    Repo.transaction(fn ->
      # Delete only seed events
      deleted = Repo.delete_all(
        from e in VoteEvent,
        where: e.event_type == "seed"
      )
      
      # Recalculate vote counts from remaining events
      update_option_counts(Repo.all(Option))
      
      {:ok, deleted}
    end)
  end
end
```

### Step 2: Create Background Task Handler
```elixir
# lib/live_poll/polls/seeding_task.ex
defmodule LivePoll.Polls.SeedingTask do
  @moduledoc """
  Handles background seeding without blocking LiveView
  """
  
  use Task
  require Logger
  alias LivePoll.Polls.Seeder
  
  def start_seeding(opts \\ []) do
    Task.Supervisor.async_nolink(
      LivePoll.TaskSupervisor,
      fn -> perform_seeding(opts) end
    )
  end
  
  defp perform_seeding(opts) do
    Logger.info("Starting vote seeding...")
    
    case Seeder.seed(opts) do
      {:ok, result} ->
        Logger.info("Seeding completed: #{inspect(result)}")
        broadcast_success(result)
        
      {:error, reason} ->
        Logger.error("Seeding failed: #{inspect(reason)}")
        broadcast_failure(reason)
    end
  end
  
  defp broadcast_success(result) do
    Phoenix.PubSub.broadcast(
      LivePoll.PubSub,
      "poll:updates",
      {:seeding_success, result}
    )
  end
  
  defp broadcast_failure(reason) do
    Phoenix.PubSub.broadcast(
      LivePoll.PubSub,
      "poll:updates",
      {:seeding_failure, reason}
    )
  end
end
```

### Step 3: Update LiveView for Non-blocking Seeding
```elixir
# lib/live_poll_web/live/poll_live.ex
def handle_event("seed_data", params, socket) do
  vote_count = String.to_integer(params["vote_count"] || "10000")
  
  # Start seeding in background
  LivePoll.Polls.SeedingTask.start_seeding(vote_count: vote_count)
  
  {:noreply,
   socket
   |> assign(:seeding, true)
   |> put_flash(:info, "Seeding #{vote_count} votes in background...")}
end

def handle_info({:seeding_complete, %{votes: votes, time_ms: time}}, socket) do
  {:noreply,
   socket
   |> assign(:seeding, false)
   |> load_data()
   |> put_flash(:info, "Successfully seeded #{votes} votes in #{time}ms")}
end

def handle_info({:seeding_failure, reason}, socket) do
  {:noreply,
   socket
   |> assign(:seeding, false)
   |> put_flash(:error, "Seeding failed: #{reason}")}
end
```

## Requirements
1. ✅ Replace individual inserts with batch inserts
2. ✅ Pre-compute timestamps instead of UPDATE after INSERT
3. ✅ Use transactions for atomicity
4. ✅ Run seeding in background task (non-blocking)
5. ✅ Reduce seeding time from 30s to <2s for 10k votes
6. ✅ Provide progress feedback to user
7. ✅ Add configurable vote distribution patterns

## Definition of Done
1. **Performance Goals**
   - [ ] 10,000 votes seed in <2 seconds
   - [ ] LiveView remains responsive during seeding
   - [ ] No database connection pool exhaustion

2. **Code Implementation**
   - [ ] Seeder module with batch inserts
   - [ ] Background task handling
   - [ ] Progress notifications via PubSub
   - [ ] Transaction wrapper for consistency

3. **Tests**
   ```elixir
   test "seeds 10,000 votes in under 2 seconds" do
     {time, {:ok, result}} = :timer.tc(fn ->
       Seeder.seed(vote_count: 10_000)
     end)
     
     assert result.votes_seeded == 10_000
     assert div(time, 1_000_000) < 2  # Less than 2 seconds
   end
   
   test "batch inserts maintain data integrity" do
     {:ok, _} = Seeder.seed(vote_count: 1000)
     
     events = Repo.all(VoteEvent)
     assert length(events) == 1000
     assert Enum.all?(events, & &1.inserted_at != nil)
   end
   ```

4. **Quality Checks**
   - [ ] No individual INSERT/UPDATE patterns
   - [ ] `mix format` passes
   - [ ] Manual testing shows <2s for 10k votes

## Branch Name
`fix/optimize-vote-seeding`

## Dependencies
- Task 004 (Extract Context) - Seeder module should be part of context

## Estimated Complexity
**M (Medium)** - 2-4 hours

## Testing Instructions
1. Implement batch insert seeder
2. Test with 100, 1000, 10000 votes
3. Verify times: 100 votes <100ms, 1000 <500ms, 10000 <2s
4. Check LiveView remains responsive during seeding
5. Verify vote counts are accurate after seeding
6. Test different distribution patterns

## Performance Benchmarks
### Before
- 100 votes: ~300ms
- 1,000 votes: ~3 seconds  
- 10,000 votes: ~30 seconds

### After (Expected)
- 100 votes: <50ms
- 1,000 votes: <200ms
- 10,000 votes: <2 seconds

## Notes
- Consider using `Repo.insert_all` with `chunk_every/2` for batches
- Pre-compute all timestamps to avoid UPDATE queries
- Use Task.Supervisor for proper supervision
- May need to adjust batch size based on database limits
