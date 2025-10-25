defmodule LivePoll.Polls.Seeder do
  @moduledoc """
  Seeds vote data for testing and demonstrations.
  
  This module handles:
  - Generating realistic vote distributions
  - Creating weighted language selections
  - Backfilling vote events with timestamps
  - Seeding with realistic popularity patterns
  """

  alias LivePoll.Repo
  alias LivePoll.Poll.{Option, VoteEvent}

  # Programming languages with realistic popularity weights based on 2025 trends
  # Format: {language, popularity_weight}
  # Higher weight = more popular = more votes
  @languages_with_weights [
    # Top tier (most popular) - dominant languages
    {"Python", 100.0},
    # #1 overall, AI/ML/data science
    {"JavaScript", 85.0},
    # Web development king
    {"TypeScript", 70.0},
    # Modern web, growing fast

    # Hot/Growing languages - strong presence
    {"Rust", 45.0},
    # Most admired, systems programming
    {"Go", 40.0},
    # Backend, cloud, gaining popularity

    # Strong established languages - solid middle
    {"C#", 35.0},
    # .NET, enterprise, gaming
    {"C++", 30.0},
    # Systems, performance, gaining
    {"Swift", 25.0},
    # iOS development

    # Mid-tier - noticeable but smaller
    {"Kotlin", 20.0},
    # Android, JVM
    {"Elixir", 12.0},
    # Functional, Phoenix

    # Lower popularity - clearly less popular
    {"Java", 10.0},
    # Declining from peak, still used
    {"Ruby", 8.0},
    # Rails, declining
    {"PHP", 6.0},
    # Web, declining
    {"Scala", 4.0},
    # JVM, niche
    {"Dart", 4.0},
    # Flutter
    {"Haskell", 2.0},
    # Academic, niche
    {"Clojure", 2.0},
    # Lisp, niche
    {"F#", 1.0}
    # .NET, niche
  ]

  @doc """
  Seed the database with realistic vote data.
  
  This function:
  1. Deletes all existing options and vote events
  2. Selects 12-14 random languages with weighted distribution
  3. Creates options with 0 votes initially
  4. Backfills vote events over the last hour with random timestamps
  5. Updates final vote counts
  6. Broadcasts data_seeded event
  
  ## Options
  
  - `:num_languages` - Number of languages to seed (default: random 12-14)
  - `:total_votes` - Target total votes (default: 10000)
  - `:hours_back` - Hours to backfill (default: 1)
  
  ## Examples
  
      iex> Seeder.seed()
      {:ok, :seeding_complete}
      
      iex> Seeder.seed(num_languages: 10, total_votes: 5000)
      {:ok, :seeding_complete}
  """
  def seed(opts \\ []) do
    num_languages = Keyword.get(opts, :num_languages, Enum.random(12..14))
    total_target_votes = Keyword.get(opts, :total_votes, 10_000)
    hours_back = Keyword.get(opts, :hours_back, 1)

    Repo.transaction(fn ->
      # Delete all existing options and vote events
      Repo.delete_all(VoteEvent)
      Repo.delete_all(Option)

      # Pick random languages (weighted selection)
      selected_languages = Enum.take_random(@languages_with_weights, num_languages)

      # Create options with 0 votes initially
      options =
        Enum.map(selected_languages, fn {lang, _weight} ->
          Repo.insert!(%Option{text: lang, votes: 0})
        end)

      # Calculate target votes for each option based on weights
      target_votes = calculate_target_votes(options, selected_languages, total_target_votes)

      # Backfill vote events over the specified time period
      backfill_vote_events(options, target_votes, hours_back)

      # Update final vote counts on options
      update_final_vote_counts(options, target_votes)

      :seeding_complete
    end)
    |> case do
      {:ok, :seeding_complete} ->
        # Broadcast after transaction completes
        LivePoll.Polls.broadcast_data_seeded()
        {:ok, :seeding_complete}

      error ->
        error
    end
  end

  # Calculate target votes for each option based on popularity weights
  defp calculate_target_votes(options, selected_languages, total_target_votes) do
    # Calculate total weight of selected languages
    total_weight =
      selected_languages
      |> Enum.map(fn {_lang, weight} -> weight end)
      |> Enum.sum()

    # Create a map of option -> {language, weight}
    options_with_weights =
      Enum.zip(options, selected_languages)
      |> Enum.map(fn {option, {_lang, weight}} -> {option, weight} end)

    # Distribute votes based on popularity weights
    options_with_weights
    |> Enum.map(fn {option, weight} ->
      # Calculate votes proportional to weight
      base_votes = trunc(total_target_votes * (weight / total_weight))

      # Add some random variation (±20%) to make it more realistic
      variation = trunc(base_votes * 0.2)
      votes = base_votes + :rand.uniform(max(variation * 2, 1)) - variation

      # Ensure at least 5 votes per language
      {option, max(votes, 5)}
    end)
    |> Map.new()
  end

  # Backfill vote events with random timestamps
  defp backfill_vote_events(options, target_votes, hours_back) do
    now = DateTime.utc_now()
    seconds_back = hours_back * 3600

    # Create vote events with completely random timestamps (like real-world data)
    # Each vote happens at a random time within the specified period
    vote_events =
      Enum.flat_map(options, fn option ->
        total_votes = Map.get(target_votes, option)

        # Each vote gets a completely random timestamp within the period
        Enum.map(1..total_votes, fn vote_num ->
          # Random timestamp anywhere in the time period
          seconds_ago = :rand.uniform(seconds_back)
          timestamp = DateTime.add(now, -seconds_ago, :second)

          %{
            option: option,
            vote_number: vote_num,
            timestamp: timestamp
          }
        end)
      end)
      # Sort by timestamp so votes happen in chronological order
      |> Enum.sort_by(& &1.timestamp, DateTime)

    # Insert vote events in chronological order
    # Track cumulative votes for each option
    initial_counts = Map.new(options, fn opt -> {opt.id, 0} end)

    Enum.reduce(vote_events, initial_counts, fn event, vote_counts ->
      option = event.option
      current_count = Map.get(vote_counts, option.id)
      new_count = current_count + 1

      # Insert vote event with the timestamp
      {:ok, vote_event} =
        Repo.insert(%VoteEvent{
          option_id: option.id,
          language: option.text,
          votes_after: new_count,
          event_type: "seed"
        })

      # Update the inserted_at timestamp to match our backfilled time
      Ecto.Adapters.SQL.query!(
        Repo,
        "UPDATE vote_events SET inserted_at = $1 WHERE id = $2",
        [event.timestamp, vote_event.id]
      )

      # Update vote count tracker
      Map.put(vote_counts, option.id, new_count)
    end)
  end

  # Update final vote counts on options
  defp update_final_vote_counts(options, target_votes) do
    Enum.each(options, fn option ->
      final_votes = Map.get(target_votes, option)
      changeset = Ecto.Changeset.change(option, votes: final_votes)
      Repo.update!(changeset)
    end)
  end
end

