defmodule LivePoll.Polls do
  @moduledoc """
  The Polls context - manages all voting and poll-related business logic.
  
  This context provides functions for:
  - Managing poll options (languages)
  - Casting and resetting votes
  - Calculating statistics and percentages
  - Analyzing voting trends over time
  - Seeding test data
  - Broadcasting updates via PubSub
  """

  import Ecto.Query
  alias LivePoll.Repo
  alias LivePoll.Poll.{Option, VoteEvent}
  alias LivePoll.Polls.{VoteService, TrendAnalyzer, Seeder}

  @topic "poll:updates"

  # ============================================
  # Options Management
  # ============================================

  @doc """
  List all poll options sorted by ID.
  
  ## Examples
  
      iex> list_options()
      [%Option{id: 1, text: "Elixir", votes: 42}, ...]
  """
  def list_options do
    Repo.all(from o in Option, order_by: [asc: o.id])
  end

  @doc """
  List all poll options sorted by votes (descending).
  
  ## Examples
  
      iex> list_options_by_votes()
      [%Option{text: "Python", votes: 100}, %Option{text: "Elixir", votes: 42}, ...]
  """
  def list_options_by_votes do
    Repo.all(from o in Option, order_by: [desc: o.votes])
  end

  @doc """
  Get a single option by ID, raises if not found.
  
  ## Examples
  
      iex> get_option!(1)
      %Option{id: 1, text: "Elixir"}
      
      iex> get_option!(999)
      ** (Ecto.NoResultsError)
  """
  def get_option!(id), do: Repo.get!(Option, id)

  @doc """
  Get a single option by ID, returns nil if not found.
  """
  def get_option(id), do: Repo.get(Option, id)

  @doc """
  Get an option by text (language name).
  """
  def get_option_by_text(text), do: Repo.get_by(Option, text: text)

  @doc """
  Add a new language option to the poll.
  
  ## Examples
  
      iex> add_language("Rust")
      {:ok, %Option{text: "Rust", votes: 0}}
      
      iex> add_language("")
      {:error, "Language name cannot be empty"}
      
      iex> add_language("Elixir")  # Already exists
      {:error, "Language already exists"}
  """
  def add_language(name) when is_binary(name) and byte_size(name) > 0 do
    # Check if language already exists
    case get_option_by_text(name) do
      nil ->
        %Option{}
        |> Option.changeset(%{text: name, votes: 0})
        |> Repo.insert()
        |> case do
          {:ok, option} = result ->
            broadcast_language_added(option)
            result

          error ->
            error
        end

      _existing ->
        {:error, "Language already exists"}
    end
  end

  def add_language(_), do: {:error, "Language name cannot be empty"}

  @doc """
  Delete a language option.
  
  ## Examples
  
      iex> delete_option(1)
      {:ok, %Option{}}
  """
  def delete_option(id) do
    option = get_option!(id)
    Repo.delete(option)
  end

  # ============================================
  # Voting
  # ============================================

  @doc """
  Cast a vote for an option (atomic operation to prevent race conditions).
  
  This function:
  1. Atomically increments the vote count
  2. Records a vote event for trend analysis
  3. Broadcasts the update to all connected clients
  
  ## Examples
  
      iex> cast_vote(1)
      {:ok, %Option{id: 1, votes: 43}, %VoteEvent{}}
      
      iex> cast_vote(999)
      {:error, :option_not_found}
  """
  def cast_vote(option_id) when is_integer(option_id) do
    Repo.transaction(fn ->
      # Atomic increment to prevent race conditions
      case from(o in Option, where: o.id == ^option_id, select: o)
           |> Repo.update_all([inc: [votes: 1]], returning: true) do
        {1, [updated_option]} ->
          # Record vote event
          vote_event =
            %VoteEvent{
              option_id: updated_option.id,
              language: updated_option.text,
              votes_after: updated_option.votes,
              event_type: "vote"
            }
            |> Repo.insert!()

          broadcast_vote(updated_option)

          {updated_option, vote_event}

        {0, _} ->
          Repo.rollback(:option_not_found)
      end
    end)
    |> case do
      {:ok, {option, event}} -> {:ok, option, event}
      {:error, reason} -> {:error, reason}
    end
  end

  def cast_vote(_), do: {:error, :invalid_option_id}

  @doc """
  Reset all votes to zero.
  
  This function:
  1. Deletes all vote events (clears history)
  2. Resets all vote counts to 0
  3. Broadcasts reset to all clients
  
  ## Examples
  
      iex> reset_all_votes()
      {:ok, :reset_complete}
  """
  def reset_all_votes do
    Repo.transaction(fn ->
      # Delete all vote events
      Repo.delete_all(VoteEvent)

      # Reset all vote counts
      Repo.update_all(Option, set: [votes: 0])

      broadcast_reset()
      :reset_complete
    end)
  end

  # ============================================
  # Statistics & Calculations
  # ============================================

  @doc """
  Calculate vote percentages for all options.
  
  ## Examples
  
      iex> calculate_percentages()
      %{"Elixir" => 42.5, "Python" => 57.5}
  """
  def calculate_percentages(options \\ nil) do
    options = options || list_options()
    VoteService.calculate_percentages(options)
  end

  @doc """
  Get total vote count across all options.
  
  ## Examples
  
      iex> get_total_votes()
      1337
  """
  def get_total_votes do
    Repo.aggregate(Option, :sum, :votes) || 0
  end

  @doc """
  Get comprehensive vote statistics.
  
  Returns a map with:
  - `:options` - All options sorted by ID
  - `:sorted_options` - Options sorted by votes (desc)
  - `:total_votes` - Total vote count
  - `:percentages` - Vote percentages by language
  - `:leader` - Option with most votes
  
  ## Examples
  
      iex> get_stats()
      %{
        options: [...],
        sorted_options: [...],
        total_votes: 1337,
        percentages: %{"Elixir" => 42.5},
        leader: %Option{text: "Python", votes: 100}
      }
  """
  def get_stats do
    options = list_options()
    sorted_options = list_options_by_votes()
    total = get_total_votes()
    percentages = calculate_percentages(options)

    %{
      options: options,
      sorted_options: sorted_options,
      total_votes: total,
      percentages: percentages,
      leader: List.first(sorted_options)
    }
  end

  # ============================================
  # Vote Events & History
  # ============================================

  @doc """
  List vote events with optional filters.
  
  ## Options
  
  - `:option_id` - Filter by specific option
  - `:since` - Filter events after this datetime
  - `:limit` - Limit number of results
  - `:event_type` - Filter by event type ("vote", "seed", "reset")
  
  ## Examples
  
      iex> list_vote_events(limit: 10)
      [%VoteEvent{}, ...]
      
      iex> list_vote_events(option_id: 1, since: ~U[2025-01-01 00:00:00Z])
      [%VoteEvent{}, ...]
  """
  def list_vote_events(opts \\ []) do
    query = from(e in VoteEvent, order_by: [desc: e.inserted_at])

    query =
      case Keyword.get(opts, :option_id) do
        nil -> query
        id -> where(query, [e], e.option_id == ^id)
      end

    query =
      case Keyword.get(opts, :since) do
        nil -> query
        datetime -> where(query, [e], e.inserted_at >= ^datetime)
      end

    query =
      case Keyword.get(opts, :event_type) do
        nil -> query
        type -> where(query, [e], e.event_type == ^type)
      end

    query =
      case Keyword.get(opts, :limit) do
        nil -> query
        limit -> limit(query, ^limit)
      end

    Repo.all(query)
  end

  # ============================================
  # Trends & Time Series
  # ============================================

  @doc """
  Calculate voting trends over time.
  
  ## Examples
  
      iex> calculate_trends(60)
      [%{timestamp: ~U[...], percentages: %{"Elixir" => 42.5}, vote_counts: %{"Elixir" => 42}}, ...]
  """
  def calculate_trends(minutes_back \\ 60) do
    TrendAnalyzer.calculate(minutes_back)
  end

  # ============================================
  # Seeding
  # ============================================

  @doc """
  Seed random votes for testing.
  
  ## Examples
  
      iex> seed_votes()
      {:ok, :seeding_complete}
  """
  def seed_votes(opts \\ []) do
    Seeder.seed(opts)
  end

  # ============================================
  # PubSub Broadcasting
  # ============================================

  defp broadcast_vote(option) do
    Phoenix.PubSub.broadcast(
      LivePoll.PubSub,
      @topic,
      {:poll_update,
       %{
         id: option.id,
         votes: option.votes,
         language: option.text,
         timestamp: DateTime.utc_now()
       }}
    )
  end

  defp broadcast_reset do
    Phoenix.PubSub.broadcast(
      LivePoll.PubSub,
      @topic,
      {:poll_reset, %{timestamp: DateTime.utc_now()}}
    )
  end

  defp broadcast_language_added(option) do
    Phoenix.PubSub.broadcast(
      LivePoll.PubSub,
      @topic,
      {:language_added, %{name: option.text}}
    )
  end

  def broadcast_data_seeded do
    Phoenix.PubSub.broadcast(
      LivePoll.PubSub,
      @topic,
      {:data_seeded, %{timestamp: DateTime.utc_now()}}
    )
  end
end

