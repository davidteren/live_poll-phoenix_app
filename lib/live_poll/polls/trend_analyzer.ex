defmodule LivePoll.Polls.TrendAnalyzer do
  @moduledoc """
  Analyzes voting trends over time.
  
  This module handles:
  - Time-series bucketing of vote events
  - Trend calculation with configurable time ranges
  - Percentage distribution over time
  - State carry-forward for missing buckets
  """

  import Ecto.Query
  alias LivePoll.Repo
  alias LivePoll.Poll.{Option, VoteEvent}

  @doc """
  Calculate voting trends over a specified time period.
  
  This function:
  1. Retrieves vote events from the last N minutes
  2. Groups events into time buckets
  3. Calculates vote percentages for each bucket
  4. Carries forward state for buckets with no events
  
  ## Parameters
  
  - `minutes_back` - Number of minutes to look back (default: 60)
  
  ## Returns
  
  A list of snapshots, each containing:
  - `:timestamp` - The bucket timestamp
  - `:percentages` - Map of language to percentage
  - `:vote_counts` - Map of language to vote count
  
  ## Examples
  
      iex> TrendAnalyzer.calculate(60)
      [
        %{
          timestamp: ~U[2025-01-01 12:00:00Z],
          percentages: %{"Elixir" => 42.5, "Python" => 57.5},
          vote_counts: %{"Elixir" => 42, "Python" => 58}
        },
        ...
      ]
  """
  def calculate(minutes_back \\ 60) do
    cutoff_time = DateTime.add(DateTime.utc_now(), -minutes_back * 60, :second)
    now = DateTime.utc_now()

    events =
      from(e in VoteEvent,
        where: e.inserted_at >= ^cutoff_time,
        order_by: [asc: e.inserted_at]
      )
      |> Repo.all()

    # If no events, return current state
    if events == [] do
      build_empty_snapshot(now)
    else
      build_trend_snapshots(events, cutoff_time, now, minutes_back)
    end
  end

  # Build a single snapshot with current state when no events exist
  defp build_empty_snapshot(now) do
    options = Repo.all(Option)
    total_votes = Enum.sum(Enum.map(options, & &1.votes))
    vote_counts = options |> Enum.map(fn opt -> {opt.text, opt.votes} end) |> Map.new()

    percentages =
      if total_votes > 0 do
        options
        |> Enum.map(fn opt ->
          {opt.text, Float.round(opt.votes * 100 / total_votes, 1)}
        end)
        |> Map.new()
      else
        options |> Enum.map(fn opt -> {opt.text, 0.0} end) |> Map.new()
      end

    [
      %{
        timestamp: now,
        percentages: percentages,
        vote_counts: vote_counts
      }
    ]
  end

  # Build trend snapshots from events
  defp build_trend_snapshots(events, cutoff_time, now, minutes_back) do
    # Dynamic bucket size and snapshot limit based on time range
    {bucket_seconds, max_snapshots} = get_bucket_config(minutes_back)

    # Get all languages from events
    all_languages = events |> Enum.map(& &1.language) |> Enum.uniq()

    # Group events by bucket
    events_by_bucket = group_events_by_bucket(events, bucket_seconds)

    # Generate ALL time buckets from cutoff to now
    all_buckets = generate_all_buckets(cutoff_time, now, bucket_seconds)

    # Build snapshots by iterating through all buckets and carrying forward state
    {snapshots, _final_state} =
      Enum.map_reduce(all_buckets, %{}, fn bucket_time, current_state ->
        build_snapshot_for_bucket(
          bucket_time,
          events_by_bucket,
          current_state,
          all_languages
        )
      end)

    snapshots
    # Keep last N snapshots based on time range
    |> Enum.take(-max_snapshots)
  end

  # Get bucket configuration based on time range
  defp get_bucket_config(minutes_back) do
    case minutes_back do
      # 5 minutes: 5-second buckets, 60 snapshots
      5 -> {5, 60}
      # 1 hour: 30-second buckets, 120 snapshots
      60 -> {30, 120}
      # 12 hours: 5-minute buckets, 144 snapshots
      720 -> {300, 144}
      # 24 hours: 10-minute buckets, 144 snapshots
      1440 -> {600, 144}
      # Default: 30-second buckets, 120 snapshots
      _ -> {30, 120}
    end
  end

  # Group events by time bucket
  defp group_events_by_bucket(events, bucket_seconds) do
    events
    |> Enum.group_by(fn event ->
      timestamp = event.inserted_at
      seconds = DateTime.to_unix(timestamp)
      rounded_seconds = div(seconds, bucket_seconds) * bucket_seconds
      DateTime.from_unix!(rounded_seconds)
    end)
  end

  # Generate all time buckets from start to end
  defp generate_all_buckets(cutoff_time, now, bucket_seconds) do
    cutoff_unix = DateTime.to_unix(cutoff_time)
    now_unix = DateTime.to_unix(now)

    # Round cutoff down to bucket boundary
    start_bucket = div(cutoff_unix, bucket_seconds) * bucket_seconds
    end_bucket = div(now_unix, bucket_seconds) * bucket_seconds

    # Create list of all bucket timestamps
    Stream.iterate(start_bucket, &(&1 + bucket_seconds))
    |> Enum.take_while(&(&1 <= end_bucket))
    |> Enum.map(&DateTime.from_unix!/1)
  end

  # Build a snapshot for a single bucket
  defp build_snapshot_for_bucket(bucket_time, events_by_bucket, current_state, all_languages) do
    # Get events in this bucket (if any)
    bucket_events = Map.get(events_by_bucket, bucket_time, [])

    # Update state with events from this bucket
    new_state =
      if bucket_events == [] do
        # No events in this bucket, carry forward previous state
        current_state
      else
        # Update state with new vote counts from events in this bucket
        Enum.reduce(bucket_events, current_state, fn event, state ->
          Map.put(state, event.language, event.votes_after)
        end)
      end

    # Calculate percentages from current state
    total_votes = new_state |> Map.values() |> Enum.sum()

    percentages =
      if total_votes > 0 do
        new_state
        |> Enum.map(fn {lang, votes} ->
          {lang, Float.round(votes * 100 / total_votes, 1)}
        end)
        |> Map.new()
      else
        # No votes yet, all languages at 0%
        all_languages |> Enum.map(fn lang -> {lang, 0.0} end) |> Map.new()
      end

    snapshot = %{
      timestamp: bucket_time,
      percentages: percentages,
      vote_counts: new_state
    }

    {snapshot, new_state}
  end
end

