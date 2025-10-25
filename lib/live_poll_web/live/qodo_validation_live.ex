defmodule LivePollWeb.QodoValidationLive do
  @moduledoc """
  This LiveView intentionally contains ALL 10 anti-patterns from Qodo configuration.
  Purpose: Validate that Qodo Merge detects every configured issue.
  
  Expected Qodo Findings:
  1. Race condition in vote counting
  2. Business logic in LiveView (should be in context)
  3. Memory issue - loading all records
  4. Unnecessary preload
  5. Individual inserts instead of batch
  6. Bang functions in event handlers
  7. No error handling
  8. Missing input validation
  9. Hardcoded values
  10. Functions >50 lines
  """
  
  use LivePollWeb, :live_view
  
  alias LivePoll.Repo
  alias LivePoll.Poll.{Option, VoteEvent}
  import Ecto.Query

  # ANTI-PATTERN #9: Hardcoded values (magic numbers)
  @update_interval 5000
  @max_votes 10000
  
  def mount(_params, _session, socket) do
    if connected?(socket) do
      :timer.send_interval(@update_interval, self(), :update_stats)
    end
    
    {:ok, 
     socket
     |> assign(:options, [])
     |> assign(:total_votes, 0)
     |> assign(:recent_events, [])
     |> load_data()}
  end

  # ANTI-PATTERN #2: Business logic in LiveView (should be in Polls context)
  # ANTI-PATTERN #3: Loading all records without limit - MEMORY ISSUE
  # ANTI-PATTERN #4: Unnecessary preload (option data not used)
  defp load_data(socket) do
    # BAD: Direct database access from LiveView
    options = Repo.all(from o in Option, order_by: [asc: o.id])
    
    # BAD: Loading ALL events into memory - causes 400MB RAM @ 1000 users
    events = Repo.all(
      from e in VoteEvent,
      where: e.inserted_at >= ^DateTime.add(DateTime.utc_now(), -3600),
      preload: :option,  # BAD: Preload not used, wastes memory
      order_by: [desc: e.inserted_at]
    )
    
    total_votes = Enum.sum(Enum.map(options, & &1.votes))
    
    socket
    |> assign(:options, options)
    |> assign(:recent_events, events)
    |> assign(:total_votes, total_votes)
  end

  # ANTI-PATTERN #1: RACE CONDITION - Read-modify-write pattern
  # ANTI-PATTERN #6: Bang function in event handler (crashes LiveView)
  # ANTI-PATTERN #7: No error handling
  def handle_event("vote", %{"id" => id}, socket) do
    # BAD: Read-modify-write causes lost votes under concurrency
    option = Repo.get!(Option, id)  # BAD: Will crash on invalid ID
    
    # BAD: Non-atomic update - race condition!
    updated_option = 
      option
      |> Ecto.Changeset.change(votes: option.votes + 1)
      |> Repo.update!()  # BAD: Bang function crashes on error
    
    # BAD: Direct insert from LiveView
    Repo.insert!(%VoteEvent{
      option_id: updated_option.id,
      language: updated_option.text,
      votes_after: updated_option.votes,
      event_type: "vote"
    })
    
    Phoenix.PubSub.broadcast(LivePoll.PubSub, "poll:updates", {:vote_cast, updated_option})
    
    {:noreply, load_data(socket)}
  end

  # ANTI-PATTERN #6: Bang function crashes on invalid input
  # ANTI-PATTERN #7: No error handling or validation
  # ANTI-PATTERN #8: Missing input validation
  def handle_event("add_language", %{"name" => name}, socket) do
    # BAD: No validation for XSS, SQL injection, length, format
    # BAD: No unique constraint check
    # BAD: Direct database insert from LiveView
    Repo.insert!(%Option{
      text: name,  # BAD: No sanitization - XSS risk
      votes: 0
    })
    
    {:noreply, load_data(socket)}
  end

  # ANTI-PATTERN #5: Individual inserts instead of batch operation
  # ANTI-PATTERN #10: Function >50 lines
  def handle_event("seed_votes", %{"count" => count_str}, socket) do
    count = String.to_integer(count_str)
    options = socket.assigns.options
    
    # BAD: Looping with individual inserts - 20,000+ DB ops for 10k votes
    # Should use Repo.insert_all instead
    for _i <- 1..count do
      option = Enum.random(options)
      
      # BAD: Individual insert in loop - very slow!
      vote_event = Repo.insert!(%VoteEvent{
        option_id: option.id,
        language: option.text,
        votes_after: option.votes + 1,
        event_type: "seed"
      })
      
      # BAD: Another database operation in loop
      Ecto.Adapters.SQL.query!(
        Repo,
        "UPDATE vote_events SET inserted_at = $1 WHERE id = $2",
        [DateTime.add(DateTime.utc_now(), -Enum.random(1..3600)), vote_event.id]
      )
      
      # BAD: Yet another update in loop
      from(o in Option, where: o.id == ^option.id)
      |> Repo.update_all(inc: [votes: 1])
    end
    
    {:noreply, put_flash(socket, :info, "Seeded #{count} votes") |> load_data()}
  end

  # ANTI-PATTERN #2: Complex business logic in LiveView
  # ANTI-PATTERN #10: Function >50 lines with complex logic
  def handle_event("reset_all", _params, socket) do
    # BAD: Business logic should be in context module
    options = socket.assigns.options
    
    # Delete all events
    Repo.delete_all(VoteEvent)
    
    # Reset all vote counts
    Enum.each(options, fn option ->
      option
      |> Ecto.Changeset.change(votes: 0)
      |> Repo.update!()
    end)
    
    # Create reset events
    Enum.each(options, fn option ->
      Repo.insert!(%VoteEvent{
        option_id: option.id,
        language: option.text,
        votes_after: 0,
        event_type: "reset"
      })
    end)
    
    Phoenix.PubSub.broadcast(LivePoll.PubSub, "poll:updates", :reset)
    
    {:noreply, 
     socket
     |> put_flash(:info, "All votes reset")
     |> load_data()}
  end

  def handle_info(:update_stats, socket) do
    {:noreply, load_data(socket)}
  end

  def handle_info({:vote_cast, _option}, socket) do
    {:noreply, load_data(socket)}
  end

  def render(assigns) do
    ~H"""
    <div class="p-8">
      <h1 class="text-3xl font-bold mb-4">Qodo Validation Test</h1>
      <p class="mb-4 text-gray-600">This page contains 10 anti-patterns for Qodo to detect</p>
      
      <div class="space-y-4">
        <%= for option <- @options do %>
          <div class="flex items-center justify-between p-4 border rounded">
            <span class="font-semibold"><%= option.text %></span>
            <div class="flex gap-2 items-center">
              <span class="text-gray-600"><%= option.votes %> votes</span>
              <button 
                phx-click="vote" 
                phx-value-id={option.id}
                class="px-4 py-2 bg-blue-500 text-white rounded hover:bg-blue-600">
                Vote
              </button>
            </div>
          </div>
        <% end %>
      </div>
      
      <div class="mt-8 space-x-4">
        <button 
          phx-click="seed_votes" 
          phx-value-count="100"
          class="px-4 py-2 bg-green-500 text-white rounded">
          Seed 100 Votes
        </button>
        
        <button 
          phx-click="reset_all"
          class="px-4 py-2 bg-red-500 text-white rounded">
          Reset All
        </button>
      </div>
      
      <div class="mt-8">
        <h2 class="text-xl font-bold mb-2">Add Language</h2>
        <form phx-submit="add_language">
          <input 
            type="text" 
            name="name" 
            placeholder="Language name"
            class="border px-4 py-2 rounded" />
          <button type="submit" class="ml-2 px-4 py-2 bg-purple-500 text-white rounded">
            Add
          </button>
        </form>
      </div>
      
      <div class="mt-8">
        <h2 class="text-xl font-bold mb-2">Recent Events (Memory Issue)</h2>
        <p class="text-sm text-gray-600 mb-2">
          Loading <%= length(@recent_events) %> events - causes memory issues
        </p>
      </div>
    </div>
    """
  end
end
