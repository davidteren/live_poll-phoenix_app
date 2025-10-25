defmodule LivePollWeb.PollLive do
  use LivePollWeb, :live_view

  alias LivePoll.Poll.Option
  alias LivePoll.Poll.VoteEvent
  alias LivePoll.Repo
  import Ecto.Query

  @topic "poll:updates"

  def mount(_params, _session, socket) do
    Phoenix.PubSub.subscribe(LivePoll.PubSub, @topic)

    options = Repo.all(Option) |> Enum.sort_by(& &1.id)
    total_votes = Enum.sum(Enum.map(options, & &1.votes))

    # Sort options by votes for pie chart (descending)
    sorted_options = Enum.sort_by(options, & &1.votes, :desc)

    # Initialize trend data from vote events in database (default: 1 hour)
    trend_data = build_trend_data_from_events(60)

    socket =
      assign(socket,
        options: options,
        sorted_options: sorted_options,
        total_votes: total_votes,
        recent_activity: [],
        votes_per_minute: 0,
        last_minute_votes: 0,
        trend_data: trend_data,
        # Default time range in minutes
        time_range: 60,
        # Seeding progress modal state
        seeding_progress: %{show: false}
      )

    # Schedule periodic stats update and trend tracking
    if connected?(socket) do
      :timer.send_interval(5000, self(), :update_stats)
      :timer.send_interval(5000, self(), :capture_trend)
    end

    {:ok, socket}
  end

  def handle_event("vote", %{"id" => id}, socket) do
    option = Repo.get!(Option, id)
    new_votes = option.votes + 1
    changeset = Ecto.Changeset.change(option, votes: new_votes)
    updated_option = Repo.update!(changeset)

    # Capture vote event in time series
    Repo.insert!(%VoteEvent{
      option_id: updated_option.id,
      language: updated_option.text,
      votes_after: new_votes,
      event_type: "vote"
    })

    Phoenix.PubSub.broadcast(
      LivePoll.PubSub,
      @topic,
      {:poll_update,
       %{
         id: String.to_integer(id),
         votes: new_votes,
         language: option.text,
         timestamp: DateTime.utc_now()
       }}
    )

    {:noreply, socket}
  end

  def handle_event("toggle_theme", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("reset_votes", _params, socket) do
    # Delete all vote events (clears time series data)
    Repo.delete_all(VoteEvent)

    # Reset all votes to 0
    Repo.all(Option)
    |> Enum.each(fn option ->
      changeset = Ecto.Changeset.change(option, votes: 0)
      Repo.update!(changeset)
    end)

    # Broadcast reset to all connected clients
    Phoenix.PubSub.broadcast(
      LivePoll.PubSub,
      @topic,
      {:poll_reset, %{timestamp: DateTime.utc_now()}}
    )

    {:noreply, socket}
  end

  def handle_event("add_language", %{"name" => name}, socket) when byte_size(name) > 0 do
    case LivePoll.Polls.add_language(name) do
      {:ok, option} ->
        # Reload options to include the new one
        options = Repo.all(Option) |> Enum.sort_by(& &1.id)
        total_votes = Enum.sum(Enum.map(options, & &1.votes))
        sorted_options = Enum.sort_by(options, & &1.votes, :desc)

        {:noreply,
         socket
         |> assign(:options, options)
         |> assign(:sorted_options, sorted_options)
         |> assign(:total_votes, total_votes)
         |> put_flash(:info, "Added #{option.text} to the poll!")}

      {:error, message} when is_binary(message) ->
        # Check if it's a duplicate error and provide helpful suggestions
        if String.contains?(message, "already exists") do
          similar = LivePoll.Polls.find_similar_languages(name)

          suggestion =
            if length(similar) > 0 do
              similar_names = Enum.map(similar, & &1.text) |> Enum.join(", ")
              " Did you mean: #{similar_names}?"
            else
              ""
            end

          {:noreply,
           socket
           |> put_flash(:error, "#{message}.#{suggestion}")}
        else
          {:noreply, put_flash(socket, :error, "Invalid input: #{message}")}
        end
    end
  end

  def handle_event("add_language", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("change_time_range", %{"range" => range_str}, socket) do
    range_minutes = String.to_integer(range_str)
    trend_data = build_trend_data_from_events(range_minutes)
    languages = socket.assigns.sorted_options |> Enum.map(& &1.text)

    socket =
      socket
      |> assign(:time_range, range_minutes)
      |> assign(:trend_data, trend_data)
      |> push_event("update-trend-chart", %{
        trendData: trend_data,
        languages: languages
      })

    {:noreply, socket}
  end

  def handle_event("seed_data", _params, socket) do
    # Show seeding modal
    socket = assign(socket, :seeding_progress, %{show: true})

    # Start seeding process asynchronously
    Process.send_after(self(), :perform_seeding, 100)

    {:noreply, socket}
  end

  def handle_info(:perform_seeding, socket) do
    # Programming languages with realistic popularity weights based on 2025 trends
    # Format: {language, popularity_weight}
    # Higher weight = more popular = more votes
    # Using much larger weight differences to create dramatic visual separation
    languages_with_weights = [
      # Top tier (most popular) - dominant languages
      # #1 overall, AI/ML/data science
      {"Python", 100.0},
      # Web development king
      {"JavaScript", 85.0},
      # Modern web, growing fast
      {"TypeScript", 70.0},

      # Hot/Growing languages - strong presence
      # Most admired, systems programming
      {"Rust", 45.0},
      # Backend, cloud, gaining popularity
      {"Go", 40.0},

      # Strong established languages - solid middle
      # .NET, enterprise, gaming
      {"C#", 35.0},
      # Systems, performance, gaining
      {"C++", 30.0},
      # iOS development
      {"Swift", 25.0},

      # Mid-tier - noticeable but smaller
      # Android, JVM
      {"Kotlin", 20.0},
      # Functional, Phoenix
      {"Elixir", 12.0},

      # Lower popularity - clearly less popular
      # Declining from peak, still used
      {"Java", 10.0},
      # Rails, declining
      {"Ruby", 8.0},
      # Web, declining
      {"PHP", 6.0},
      # JVM, niche
      {"Scala", 4.0},
      # Flutter
      {"Dart", 4.0},
      # Academic, niche
      {"Haskell", 2.0},
      # Lisp, niche
      {"Clojure", 2.0},
      # .NET, niche
      {"F#", 1.0}
    ]

    # Delete all existing options and vote events
    Repo.delete_all(VoteEvent)
    Repo.delete_all(Option)

    # Pick 12-14 random languages (weighted selection)
    num_languages = Enum.random(12..14)
    selected_languages = Enum.take_random(languages_with_weights, num_languages)

    # Create options with 0 votes initially
    options =
      Enum.map(selected_languages, fn {lang, _weight} ->
        Repo.insert!(%Option{text: lang, votes: 0})
      end)

    # Backfill vote events over the last hour
    now = DateTime.utc_now()
    one_hour_ago = DateTime.add(now, -3600, :second)

    # Target around 10,000 total votes for more dramatic differences
    # This creates clear visual separation between popular and niche languages
    total_target_votes = 10000

    # Calculate total weight of selected languages
    total_weight = selected_languages |> Enum.map(fn {_lang, weight} -> weight end) |> Enum.sum()

    # Create a map of option -> {language, weight}
    options_with_weights =
      Enum.zip(options, selected_languages)
      |> Enum.map(fn {option, {lang, weight}} -> {option, weight} end)

    # Distribute votes based on popularity weights
    target_votes =
      options_with_weights
      |> Enum.map(fn {option, weight} ->
        # Calculate votes proportional to weight
        base_votes = trunc(total_target_votes * (weight / total_weight))

        # Add some random variation (±20%) to make it more realistic
        variation = trunc(base_votes * 0.2)
        votes = base_votes + :rand.uniform(variation * 2) - variation

        # Ensure at least 5 votes per language
        {option, max(votes, 5)}
      end)
      |> Map.new()

    # Create vote events with completely random timestamps (like real-world data)
    # Each vote happens at a random time within the last hour
    vote_events =
      Enum.flat_map(options, fn option ->
        total_votes = Map.get(target_votes, option)

        # Each vote gets a completely random timestamp within the hour
        Enum.map(1..total_votes, fn vote_num ->
          # Random timestamp anywhere in the last hour
          seconds_ago = :rand.uniform(3600)
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

    # Update final vote counts on options
    Enum.each(options, fn option ->
      final_votes = Map.get(target_votes, option)
      changeset = Ecto.Changeset.change(option, votes: final_votes)
      Repo.update!(changeset)
    end)

    # Hide progress modal after a short delay
    Process.send_after(self(), :hide_seeding_progress, 800)

    # Broadcast the update to all clients
    Phoenix.PubSub.broadcast(
      LivePoll.PubSub,
      @topic,
      {:data_seeded, %{timestamp: DateTime.utc_now()}}
    )

    {:noreply, socket}
  end

  def handle_info(:hide_seeding_progress, socket) do
    {:noreply, assign(socket, :seeding_progress, %{show: false})}
  end

  def handle_info({:poll_update, update_data}, socket) do
    %{id: id, votes: votes, language: language, timestamp: timestamp} = update_data

    options =
      Enum.map(socket.assigns.options, fn
        %{id: ^id} = option -> %{option | votes: votes}
        option -> option
      end)

    total_votes = Enum.sum(Enum.map(options, & &1.votes))
    sorted_options = Enum.sort_by(options, & &1.votes, :desc)

    # Add to recent activity (keep last 10)
    activity_item = %{
      language: language,
      timestamp: timestamp,
      id: System.unique_integer([:positive])
    }

    recent_activity =
      [activity_item | socket.assigns.recent_activity]
      |> Enum.take(10)

    socket =
      socket
      |> assign(
        options: options,
        sorted_options: sorted_options,
        total_votes: total_votes,
        recent_activity: recent_activity,
        last_minute_votes: socket.assigns.last_minute_votes + 1
      )
      |> push_event("update-pie-chart", %{
        data: Enum.map(sorted_options, fn opt -> %{name: opt.text, votes: opt.votes} end)
      })

    {:noreply, socket}
  end

  def handle_info(:update_stats, socket) do
    # Calculate votes per minute based on recent activity
    # 5 second intervals
    votes_per_minute = socket.assigns.last_minute_votes * 12

    socket =
      assign(socket,
        votes_per_minute: votes_per_minute,
        last_minute_votes: 0
      )

    {:noreply, socket}
  end

  def handle_info(:capture_trend, socket) do
    # Build trend data from vote events in the database using current time range
    time_range = socket.assigns.time_range
    trend_data = build_trend_data_from_events(time_range)
    languages = Enum.map(socket.assigns.sorted_options, & &1.text)

    socket =
      socket
      |> assign(trend_data: trend_data)
      |> push_event("update-trend-chart", %{
        trendData: trend_data,
        languages: languages
      })

    {:noreply, socket}
  end

  def handle_info({:poll_reset, _data}, socket) do
    # Reload all options from database
    options = Repo.all(Option) |> Enum.sort_by(& &1.id)
    total_votes = 0
    sorted_options = Enum.sort_by(options, & &1.votes, :desc)

    # Build trend data from vote events using current time range
    time_range = socket.assigns.time_range
    trend_data = build_trend_data_from_events(time_range)

    socket =
      socket
      |> assign(
        options: options,
        sorted_options: sorted_options,
        total_votes: total_votes,
        recent_activity: [],
        votes_per_minute: 0,
        last_minute_votes: 0,
        trend_data: trend_data
      )
      |> push_event("update-pie-chart", %{
        data: Enum.map(sorted_options, fn opt -> %{name: opt.text, votes: opt.votes} end)
      })
      |> push_event("update-trend-chart", %{
        trendData: trend_data,
        languages: Enum.map(sorted_options, & &1.text)
      })

    {:noreply, socket}
  end

  def handle_info({:data_seeded, _data}, socket) do
    # Reload all options from database
    options = Repo.all(Option) |> Enum.sort_by(& &1.id)
    total_votes = Enum.sum(Enum.map(options, & &1.votes))
    sorted_options = Enum.sort_by(options, & &1.votes, :desc)

    # Build trend data from vote events using current time range
    time_range = socket.assigns.time_range
    trend_data = build_trend_data_from_events(time_range)

    socket =
      socket
      |> assign(
        options: options,
        sorted_options: sorted_options,
        total_votes: total_votes,
        recent_activity: [],
        votes_per_minute: 0,
        last_minute_votes: 0,
        trend_data: trend_data
      )
      |> push_event("update-pie-chart", %{
        data: Enum.map(sorted_options, fn opt -> %{name: opt.text, votes: opt.votes} end)
      })
      |> push_event("update-trend-chart", %{
        trendData: trend_data,
        languages: Enum.map(sorted_options, & &1.text)
      })

    {:noreply, socket}
  end

  def handle_info({:language_added, _data}, socket) do
    # Reload all options from database
    options = Repo.all(Option) |> Enum.sort_by(& &1.id)
    total_votes = Enum.sum(Enum.map(options, & &1.votes))
    sorted_options = Enum.sort_by(options, & &1.votes, :desc)

    socket =
      assign(socket, options: options, sorted_options: sorted_options, total_votes: total_votes)

    {:noreply, socket}
  end

  defp percentage(votes, total) when total > 0 do
    (votes / total * 100) |> round()
  end

  defp percentage(_votes, _total), do: 0

  # Helper function to convert language names to CSS-safe class names
  def language_to_class(language) do
    language
    |> String.downcase()
    |> String.replace("#", "sharp")
    |> String.replace("+", "plus")
    |> String.replace(" ", "")
  end

  # Helper function to calculate percentages for all languages
  def calculate_percentages(options, total_votes) when total_votes > 0 do
    options
    |> Enum.map(fn option ->
      {option.text, (option.votes / total_votes * 100) |> Float.round(1)}
    end)
    |> Map.new()
  end

  def calculate_percentages(options, _total_votes) do
    options
    |> Enum.map(fn option -> {option.text, 0.0} end)
    |> Map.new()
  end

  # Helper function to generate SVG polyline points for trend chart
  def trend_line_points(language, trend_data) do
    # Reverse to get chronological order (oldest to newest)
    data_points = Enum.reverse(trend_data)
    num_points = length(data_points)

    if num_points < 2 do
      ""
    else
      # Calculate x spacing (600px width / number of points)
      x_spacing = 600 / max(num_points - 1, 1)

      # Generate points: x,y pairs
      points =
        data_points
        |> Enum.with_index()
        |> Enum.map(fn {snapshot, index} ->
          percentage = Map.get(snapshot.percentages, language, 0.0)
          # Y axis: 0% at bottom (200), 100% at top (0)
          # Invert: 200 - (percentage * 2)
          x = index * x_spacing
          y = 200 - percentage * 2
          "#{x},#{y}"
        end)
        |> Enum.join(" ")

      points
    end
  end

  # Helper function to build trend data from vote events
  defp build_trend_data_from_events(minutes_back \\ 60) do
    # Get events from the last N minutes (default: 60 minutes = 1 hour)
    cutoff_time = DateTime.add(DateTime.utc_now(), -minutes_back * 60, :second)
    now = DateTime.utc_now()

    events =
      from(e in VoteEvent,
        where: e.inserted_at >= ^cutoff_time,
        order_by: [asc: e.inserted_at],
        preload: :option
      )
      |> Repo.all()

    # If no events, return current state
    if events == [] do
      options = Repo.all(Option)
      total_votes = Enum.sum(Enum.map(options, & &1.votes))
      vote_counts = options |> Enum.map(fn opt -> {opt.text, opt.votes} end) |> Map.new()

      [
        %{
          timestamp: now,
          percentages: calculate_percentages(options, total_votes),
          vote_counts: vote_counts
        }
      ]
    else
      # Dynamic bucket size and snapshot limit based on time range
      {bucket_seconds, max_snapshots} =
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

      # Get all languages from events
      all_languages = events |> Enum.map(& &1.language) |> Enum.uniq()

      # Group events by bucket
      events_by_bucket =
        events
        |> Enum.group_by(fn event ->
          timestamp = event.inserted_at
          seconds = DateTime.to_unix(timestamp)
          rounded_seconds = div(seconds, bucket_seconds) * bucket_seconds
          DateTime.from_unix!(rounded_seconds)
        end)

      # Generate ALL time buckets from cutoff to now
      cutoff_unix = DateTime.to_unix(cutoff_time)
      now_unix = DateTime.to_unix(now)

      # Round cutoff down to bucket boundary
      start_bucket = div(cutoff_unix, bucket_seconds) * bucket_seconds
      end_bucket = div(now_unix, bucket_seconds) * bucket_seconds

      # Create list of all bucket timestamps
      all_buckets =
        Stream.iterate(start_bucket, &(&1 + bucket_seconds))
        |> Enum.take_while(&(&1 <= end_bucket))
        |> Enum.map(&DateTime.from_unix!/1)

      # Build snapshots by iterating through all buckets and carrying forward state
      {snapshots, _final_state} =
        Enum.map_reduce(all_buckets, %{}, fn bucket_time, current_state ->
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
                {lang, (votes / total_votes * 100) |> Float.round(1)}
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
        end)

      snapshots
      # Keep last N snapshots based on time range
      |> Enum.take(-max_snapshots)
    end
  end

  # Helper function to generate pie chart path for a slice
  defp pie_slice_path(_option, _options, 0), do: ""

  defp pie_slice_path(option, options, total_votes) when total_votes > 0 do
    # Skip if this option has no votes
    if option.votes == 0 do
      ""
    else
      # Calculate angles
      previous_votes =
        Enum.take_while(options, fn o -> o.id != option.id end)
        |> Enum.map(& &1.votes)
        |> Enum.sum()

      start_angle = previous_votes / total_votes * 360
      slice_angle = option.votes / total_votes * 360
      end_angle = start_angle + slice_angle

      # If this option has 100% of votes, draw a full circle
      if slice_angle >= 359.9 do
        # Draw a full donut using two semicircles
        outer_radius = 90
        inner_radius = 50

        # First semicircle (top half)
        path1 =
          "M 100 #{100 - outer_radius} A #{outer_radius} #{outer_radius} 0 0 1 100 #{100 + outer_radius}"

        # Second semicircle (bottom half)
        path2 = "A #{outer_radius} #{outer_radius} 0 0 1 100 #{100 - outer_radius}"
        # Inner circle (reverse direction)
        path3 =
          "M 100 #{100 - inner_radius} A #{inner_radius} #{inner_radius} 0 0 0 100 #{100 + inner_radius}"

        path4 = "A #{inner_radius} #{inner_radius} 0 0 0 100 #{100 - inner_radius}"

        "#{path1} #{path2} #{path3} #{path4} Z"
      else
        # Convert to radians (subtract 90 to start from top)
        start_rad = (start_angle - 90) * :math.pi() / 180
        end_rad = (end_angle - 90) * :math.pi() / 180

        # Define radii
        outer_radius = 90
        inner_radius = 50

        # Calculate points
        x1 = 100 + outer_radius * :math.cos(start_rad)
        y1 = 100 + outer_radius * :math.sin(start_rad)
        x2 = 100 + outer_radius * :math.cos(end_rad)
        y2 = 100 + outer_radius * :math.sin(end_rad)
        x3 = 100 + inner_radius * :math.cos(end_rad)
        y3 = 100 + inner_radius * :math.sin(end_rad)
        x4 = 100 + inner_radius * :math.cos(start_rad)
        y4 = 100 + inner_radius * :math.sin(start_rad)

        # Large arc flag
        large_arc = if slice_angle > 180, do: 1, else: 0

        # Build path
        "M #{x1} #{y1} A #{outer_radius} #{outer_radius} 0 #{large_arc} 1 #{x2} #{y2} L #{x3} #{y3} A #{inner_radius} #{inner_radius} 0 #{large_arc} 0 #{x4} #{y4} Z"
      end
    end
  end
end
