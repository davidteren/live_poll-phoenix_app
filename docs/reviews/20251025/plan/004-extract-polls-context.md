# Task: Extract Business Logic to Polls Context Module

## Category
Architecture, Code Quality

## Priority
**HIGH** - Monolithic LiveView violates Phoenix conventions and maintainability

## Description
The PollLive module is 700+ lines and contains all business logic, database queries, calculations, and UI rendering in one place. This violates Phoenix's context pattern, makes testing impossible, and creates maintenance nightmares. All business logic must be extracted into a proper Polls context module.

## Current State
```elixir
# lib/live_poll_web/live/poll_live.ex - MONOLITHIC MESS
defmodule LivePollWeb.PollLive do
  # 700+ lines mixing everything:
  # - Direct database queries (Repo.all, Repo.insert)
  # - Business logic (vote counting, trend calculation)
  # - Complex algorithms (bucketing, percentages)
  # - Event sourcing logic
  # - Seeding logic
  # - UI rendering
  # - WebSocket handling
end
```

### Problems
- Cannot test business logic in isolation
- Cannot reuse logic in other parts of the app
- LiveView process blocked by heavy computations
- No separation of concerns
- Violates Phoenix conventions

## Proposed Solution

### Step 1: Create Polls Context Module
```elixir
# lib/live_poll/polls.ex
defmodule LivePoll.Polls do
  @moduledoc """
  The Polls context - manages all voting and poll-related business logic
  """
  
  import Ecto.Query
  alias LivePoll.Repo
  alias LivePoll.Polls.{Option, VoteEvent, VoteService, TrendAnalyzer, Seeder}
  
  # ============================================
  # Options Management
  # ============================================
  
  @doc "List all poll options sorted by ID"
  def list_options do
    Repo.all(from o in Option, order_by: [asc: o.id])
  end
  
  @doc "Get a single option by ID"
  def get_option!(id), do: Repo.get!(Option, id)
  
  def get_option(id), do: Repo.get(Option, id)
  
  @doc "Add a new language option to the poll"
  def add_language(name) when is_binary(name) do
    %Option{}
    |> Option.changeset(%{text: name, votes: 0})
    |> Repo.insert()
  end
  
  @doc "Delete a language option"
  def delete_option(id) do
    option = get_option!(id)
    Repo.delete(option)
  end
  
  # ============================================
  # Voting
  # ============================================
  
  @doc "Cast a vote for an option (atomic)"
  def cast_vote(option_id) when is_integer(option_id) do
    Repo.transaction(fn ->
      # Atomic increment to prevent race conditions
      {1, [updated_option]} = 
        from(o in Option, where: o.id == ^option_id, select: o)
        |> Repo.update_all([inc: [votes: 1]], returning: true)
      
      # Record vote event
      vote_event = %VoteEvent{
        option_id: updated_option.id,
        language: updated_option.text,
        votes_after: updated_option.votes,
        event_type: "vote"
      } |> Repo.insert!()
      
      broadcast_vote(updated_option)
      
      {:ok, updated_option, vote_event}
    end)
  end
  
  def cast_vote(_), do: {:error, :invalid_option_id}
  
  @doc "Reset all votes to zero"
  def reset_all_votes do
    Repo.transaction(fn ->
      # Delete all vote events
      Repo.delete_all(VoteEvent)
      
      # Reset all vote counts
      Repo.update_all(Option, set: [votes: 0])
      
      # Create reset event
      for option <- list_options() do
        %VoteEvent{
          option_id: option.id,
          language: option.text,
          votes_after: 0,
          event_type: "reset"
        } |> Repo.insert!()
      end
      
      broadcast_reset()
      :ok
    end)
  end
  
  # ============================================
  # Statistics & Calculations
  # ============================================
  
  @doc "Calculate vote percentages for all options"
  def calculate_percentages(options \\ nil) do
    options = options || list_options()
    VoteService.calculate_percentages(options)
  end
  
  @doc "Get total vote count"
  def get_total_votes do
    Repo.aggregate(Option, :sum, :votes) || 0
  end
  
  @doc "Get vote statistics"
  def get_stats do
    options = list_options()
    total = get_total_votes()
    percentages = calculate_percentages(options)
    
    %{
      options: options,
      total_votes: total,
      percentages: percentages,
      leader: Enum.max_by(options, & &1.votes, fn -> nil end)
    }
  end
  
  # ============================================
  # Vote Events & History
  # ============================================
  
  @doc "List vote events with optional filters"
  def list_vote_events(opts \\ []) do
    query = from(e in VoteEvent, order_by: [desc: e.inserted_at])
    
    query = case Keyword.get(opts, :option_id) do
      nil -> query
      id -> where(query, [e], e.option_id == ^id)
    end
    
    query = case Keyword.get(opts, :since) do
      nil -> query
      datetime -> where(query, [e], e.inserted_at >= ^datetime)
    end
    
    query = case Keyword.get(opts, :limit) do
      nil -> query
      limit -> limit(query, ^limit)
    end
    
    Repo.all(query)
  end
  
  @doc "Get recent voting activity"
  def get_recent_activity(limit \\ 10) do
    list_vote_events(limit: limit, event_type: "vote")
    |> Enum.map(&format_activity/1)
  end
  
  defp format_activity(event) do
    %{
      language: event.language,
      votes: event.votes_after,
      timestamp: event.inserted_at,
      type: event.event_type
    }
  end
  
  # ============================================
  # Trends & Time Series
  # ============================================
  
  @doc "Calculate voting trends over time"
  def calculate_trends(minutes_back \\ 60) do
    TrendAnalyzer.calculate(minutes_back)
  end
  
  @doc "Get chart data for visualizations"
  def get_chart_data(type \\ :pie) do
    options = list_options()
    
    case type do
      :pie -> build_pie_chart_data(options)
      :bar -> build_bar_chart_data(options)
      :trend -> calculate_trends(60)
    end
  end
  
  defp build_pie_chart_data(options) do
    total = Enum.sum(Enum.map(options, & &1.votes))
    
    Enum.map(options, fn option ->
      %{
        name: option.text,
        value: option.votes,
        percentage: if(total > 0, do: option.votes * 100 / total, else: 0)
      }
    end)
  end
  
  defp build_bar_chart_data(options) do
    Enum.map(options, fn option ->
      %{
        name: option.text,
        value: option.votes
      }
    end)
  end
  
  # ============================================
  # Seeding
  # ============================================
  
  @doc "Seed random votes for testing"
  def seed_votes(count, opts \\ []) do
    Seeder.seed(count, opts)
  end
  
  # ============================================
  # PubSub Broadcasting
  # ============================================
  
  defp broadcast_vote(option) do
    Phoenix.PubSub.broadcast(
      LivePoll.PubSub,
      "poll:updates",
      {:vote_cast, %{
        option_id: option.id,
        text: option.text,
        votes: option.votes,
        timestamp: DateTime.utc_now()
      }}
    )
  end
  
  defp broadcast_reset do
    Phoenix.PubSub.broadcast(
      LivePoll.PubSub,
      "poll:updates",
      {:votes_reset, %{timestamp: DateTime.utc_now()}}
    )
  end
end
```

### Step 2: Create Supporting Service Modules

```elixir
# lib/live_poll/polls/vote_service.ex
defmodule LivePoll.Polls.VoteService do
  @moduledoc "Voting calculations and business logic"
  
  def calculate_percentages(options) when is_list(options) do
    total = Enum.sum(Enum.map(options, & &1.votes))
    
    if total > 0 do
      options
      |> Enum.map(fn option ->
        {option.text, Float.round(option.votes * 100 / total, 1)}
      end)
      |> Map.new()
    else
      options
      |> Enum.map(fn option -> {option.text, 0.0} end)
      |> Map.new()
    end
  end
  
  def calculate_percentages(_), do: %{}
end

# lib/live_poll/polls/trend_analyzer.ex  
defmodule LivePoll.Polls.TrendAnalyzer do
  @moduledoc "Analyzes voting trends over time"
  
  import Ecto.Query
  alias LivePoll.Repo
  alias LivePoll.Polls.{Option, VoteEvent}
  
  def calculate(minutes_back \\ 60) do
    cutoff_time = DateTime.add(DateTime.utc_now(), -minutes_back * 60, :second)
    
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
    |> group_by_bucket()
    |> fill_missing_buckets(minutes_back)
    |> calculate_percentages_per_bucket()
  end
  
  defp group_by_bucket(results) do
    Enum.group_by(results, & &1.bucket)
  end
  
  defp fill_missing_buckets(grouped, minutes_back) do
    # Implementation to ensure all time buckets are present
    # with carried-forward values
  end
  
  defp calculate_percentages_per_bucket(buckets) do
    # Calculate percentage distribution for each time bucket
  end
end

# lib/live_poll/polls/seeder.ex
defmodule LivePoll.Polls.Seeder do
  @moduledoc "Seeds vote data for testing"
  
  alias LivePoll.Repo
  alias LivePoll.Polls.{Option, VoteEvent}
  import Ecto.Query
  
  def seed(count, opts \\ []) do
    options = Repo.all(Option)
    
    if length(options) == 0 do
      {:error, "No options available to seed"}
    else
      seed_with_batch_insert(options, count, opts)
    end
  end
  
  defp seed_with_batch_insert(options, count, opts) do
    # Generate events with proper distribution
    events = generate_events(options, count, opts)
    
    # Batch insert for performance
    Repo.transaction(fn ->
      events
      |> Enum.chunk_every(1000)
      |> Enum.each(fn batch ->
        Repo.insert_all(VoteEvent, batch)
      end)
      
      # Update vote counts
      update_vote_counts(options)
    end)
  end
  
  defp generate_events(options, count, opts) do
    # Generate realistic vote distribution
  end
  
  defp update_vote_counts(options) do
    # Update the vote counts based on events
  end
end
```

### Step 3: Refactor LiveView to Use Context
```elixir
# lib/live_poll_web/live/poll_live.ex - REFACTORED
defmodule LivePollWeb.PollLive do
  use LivePollWeb, :live_view
  alias LivePoll.Polls
  
  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(LivePoll.PubSub, "poll:updates")
    end
    
    {:ok, load_data(socket)}
  end
  
  @impl true
  def handle_event("vote", %{"id" => id}, socket) do
    with {int_id, ""} <- Integer.parse(id),
         {:ok, option, _event} <- Polls.cast_vote(int_id) do
      {:noreply, update_option_in_socket(socket, option)}
    else
      _ -> {:noreply, put_flash(socket, :error, "Failed to record vote")}
    end
  end
  
  @impl true
  def handle_event("add_language", %{"name" => name}, socket) do
    case Polls.add_language(name) do
      {:ok, option} ->
        {:noreply, socket |> load_data() |> put_flash(:info, "Added #{option.text}!")}
      {:error, message} ->
        {:noreply, put_flash(socket, :error, message)}
    end
  end
  
  @impl true
  def handle_event("reset_votes", _params, socket) do
    case Polls.reset_all_votes() do
      {:ok, _} -> {:noreply, load_data(socket)}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Failed to reset")}
    end
  end
  
  @impl true
  def handle_event("seed_data", %{"count" => count}, socket) do
    Task.start(fn -> Polls.seed_votes(String.to_integer(count)) end)
    {:noreply, put_flash(socket, :info, "Seeding #{count} votes...")}
  end
  
  @impl true
  def handle_info({:vote_cast, payload}, socket) do
    {:noreply, handle_vote_update(socket, payload)}
  end
  
  @impl true
  def handle_info({:votes_reset, _}, socket) do
    {:noreply, load_data(socket)}
  end
  
  defp load_data(socket) do
    stats = Polls.get_stats()
    
    socket
    |> assign(:options, stats.options)
    |> assign(:total_votes, stats.total_votes)
    |> assign(:percentages, stats.percentages)
    |> assign(:chart_data, Polls.get_chart_data(:pie))
    |> assign(:trend_data, Polls.calculate_trends(60))
    |> assign(:recent_activity, Polls.get_recent_activity())
  end
  
  defp update_option_in_socket(socket, updated_option) do
    options = socket.assigns.options
      |> Enum.map(fn opt ->
        if opt.id == updated_option.id, do: updated_option, else: opt
      end)
    
    assign(socket, :options, options)
  end
  
  defp handle_vote_update(socket, %{option_id: id} = payload) do
    # Efficient targeted update instead of full reload
    socket
    |> update(:options, fn options ->
      Enum.map(options, fn opt ->
        if opt.id == id, do: %{opt | votes: payload.votes}, else: opt
      end)
    end)
    |> update(:total_votes, &(&1 + 1))
    |> push_event("vote_update", payload)
  end
end
```

## Requirements
1. ✅ Create Polls context module with all business logic
2. ✅ Extract database queries from LiveView
3. ✅ Create service modules for complex calculations
4. ✅ Implement proper error handling in context
5. ✅ Add documentation for all public functions
6. ✅ Reduce LiveView to <200 lines focused on UI
7. ✅ Make business logic testable in isolation

## Definition of Done
1. **Code Structure**
   - [ ] Polls context module created
   - [ ] VoteService module for calculations
   - [ ] TrendAnalyzer module for time-series
   - [ ] Seeder module for test data
   - [ ] LiveView refactored to use context

2. **Functionality Preserved**
   - [ ] All existing features still work
   - [ ] Performance improved or maintained
   - [ ] Real-time updates still functional

3. **Tests**
   - [ ] Context functions have unit tests
   - [ ] Service modules have tests
   - [ ] Integration tests pass
   - [ ] Test coverage >60%

4. **Quality Checks**
   - [ ] LiveView under 200 lines
   - [ ] No direct Repo calls in LiveView
   - [ ] `mix format` passes
   - [ ] `mix credo` shows improvements

## Branch Name
`refactor/extract-polls-context`

## Dependencies
- Task 001 (Fix Race Condition) - Should be integrated
- Task 003 (Unique Constraint) - Should be integrated

## Estimated Complexity
**L (Large)** - 1-2 days

## Testing Instructions
1. Create context module structure
2. Move functions one category at a time
3. Test each category works before moving next
4. Verify LiveView still functions correctly
5. Run existing tests and fix any breaks
6. Add new tests for context functions
7. Verify real-time updates still work

## Notes
- This is a major refactoring that touches most of the codebase
- Should be done incrementally to avoid breaking everything
- Each extracted function should be tested immediately
- Consider using `mix phx.gen.context` as a starting point
- Will make future changes much easier
