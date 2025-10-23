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
        time_range: 60  # Default time range in minutes
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
      {:poll_update, %{
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
    # Reset all votes to 0 and capture reset events
    Repo.all(Option)
    |> Enum.each(fn option ->
      changeset = Ecto.Changeset.change(option, votes: 0)
      updated_option = Repo.update!(changeset)

      # Capture reset event
      Repo.insert!(%VoteEvent{
        option_id: updated_option.id,
        language: updated_option.text,
        votes_after: 0,
        event_type: "reset"
      })
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
    # Check if language already exists
    existing = Repo.get_by(Option, text: name)

    if existing do
      {:noreply, socket}
    else
      # Create new language option
      %Option{}
      |> Ecto.Changeset.change(text: name, votes: 0)
      |> Repo.insert!()

      # Broadcast update to all clients
      Phoenix.PubSub.broadcast(
        LivePoll.PubSub,
        @topic,
        {:language_added, %{name: name}}
      )

      {:noreply, socket}
    end
  end

  def handle_event("add_language", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("change_time_range", %{"range" => range_str}, socket) do
    range_minutes = String.to_integer(range_str)
    trend_data = build_trend_data_from_events(range_minutes)

    socket =
      socket
      |> assign(:time_range, range_minutes)
      |> assign(:trend_data, trend_data)

    # Push updated trend data to chart
    languages = socket.assigns.sorted_options |> Enum.map(& &1.text)

    {:noreply,
      push_event(socket, "update-trend-chart", %{
        trendData: trend_data,
        languages: languages
      })
    }
  end

  def handle_event("seed_data", _params, socket) do
    # List of popular programming languages
    languages = [
      "Elixir", "Python", "JavaScript", "Ruby", "Go", "Rust",
      "TypeScript", "Swift", "Kotlin", "PHP", "Java", "C#",
      "C++", "Dart", "Scala", "Haskell", "Clojure", "F#"
    ]

    # Delete all existing options and vote events
    Repo.delete_all(VoteEvent)
    Repo.delete_all(Option)

    # Pick 12-14 random languages
    num_languages = Enum.random(12..14)
    selected_languages = Enum.take_random(languages, num_languages)

    # Create options with 0 votes initially
    options = Enum.map(selected_languages, fn lang ->
      Repo.insert!(%Option{text: lang, votes: 0})
    end)

    # Backfill vote events over the last hour
    now = DateTime.utc_now()
    one_hour_ago = DateTime.add(now, -3600, :second)

    # Target around 1000 total votes spread across all languages
    total_target_votes = 1000
    num_options = length(options)

    # Distribute votes across languages with some variation
    # Base votes per language, then add random variation
    base_votes_per_lang = div(total_target_votes, num_options)

    target_votes =
      options
      |> Enum.map(fn option ->
        # Add variation: ±30% of base votes
        variation = div(base_votes_per_lang * 30, 100)
        votes = base_votes_per_lang + :rand.uniform(variation * 2) - variation
        {option, max(votes, 10)} # Ensure at least 10 votes per language
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
      {:ok, vote_event} = Repo.insert(%VoteEvent{
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

    # Broadcast the update to all clients with seeded flag
    Phoenix.PubSub.broadcast(
      LivePoll.PubSub,
      @topic,
      {:data_seeded, %{timestamp: DateTime.utc_now()}}
    )

    {:noreply, socket}
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
    votes_per_minute = socket.assigns.last_minute_votes * 12 # 5 second intervals

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

    socket =
      socket
      |> assign(trend_data: trend_data)
      |> push_event("update-trend-chart", %{
        trendData: trend_data,
        languages: Enum.map(socket.assigns.sorted_options, & &1.text)
      })

    {:noreply, socket}
  end

  def handle_info({:poll_reset, _data}, socket) do
    # Reload all options from database
    options = Repo.all(Option) |> Enum.sort_by(& &1.id)
    total_votes = 0
    sorted_options = Enum.sort_by(options, & &1.votes, :desc)

    # Build trend data from vote events
    trend_data = build_trend_data_from_events(5)

    socket =
      assign(socket,
        options: options,
        sorted_options: sorted_options,
        total_votes: total_votes,
        recent_activity: [],
        votes_per_minute: 0,
        last_minute_votes: 0,
        trend_data: trend_data
      )

    {:noreply, socket}
  end

  def handle_info({:data_seeded, _data}, socket) do
    # Reload all options from database
    options = Repo.all(Option) |> Enum.sort_by(& &1.id)
    total_votes = Enum.sum(Enum.map(options, & &1.votes))
    sorted_options = Enum.sort_by(options, & &1.votes, :desc)

    # Build trend data from vote events
    trend_data = build_trend_data_from_events(5)

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

    socket = assign(socket, options: options, sorted_options: sorted_options, total_votes: total_votes)

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
          y = 200 - (percentage * 2)
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

      [%{
        timestamp: DateTime.utc_now(),
        percentages: calculate_percentages(options, total_votes)
      }]
    else
      # Dynamic bucket size and snapshot limit based on time range
      {bucket_seconds, max_snapshots} = case minutes_back do
        5 -> {5, 60}           # 5 minutes: 5-second buckets, 60 snapshots
        60 -> {30, 120}        # 1 hour: 30-second buckets, 120 snapshots
        720 -> {300, 144}      # 12 hours: 5-minute buckets, 144 snapshots
        1440 -> {600, 144}     # 24 hours: 10-minute buckets, 144 snapshots
        _ -> {30, 120}         # Default: 30-second buckets, 120 snapshots
      end

      # Group events into time buckets
      events
      |> Enum.group_by(fn event ->
        # Round timestamp down to nearest bucket
        timestamp = event.inserted_at
        seconds = DateTime.to_unix(timestamp)
        rounded_seconds = div(seconds, bucket_seconds) * bucket_seconds
        DateTime.from_unix!(rounded_seconds)
      end)
      |> Enum.map(fn {bucket_time, bucket_events} ->
        # Get the state at the end of this bucket
        # Calculate vote totals for each language at this point in time
        language_votes =
          bucket_events
          |> Enum.group_by(& &1.language)
          |> Enum.map(fn {language, lang_events} ->
            # Get the last event for this language in this bucket
            last_event = Enum.max_by(lang_events, & &1.inserted_at)
            {language, last_event.votes_after}
          end)
          |> Map.new()

        total_votes = language_votes |> Map.values() |> Enum.sum()

        percentages =
          if total_votes > 0 do
            language_votes
            |> Enum.map(fn {lang, votes} ->
              {lang, (votes / total_votes * 100) |> Float.round(1)}
            end)
            |> Map.new()
          else
            %{}
          end

        %{
          timestamp: bucket_time,
          percentages: percentages
        }
      end)
      |> Enum.sort_by(& &1.timestamp, DateTime)
      |> Enum.take(-max_snapshots) # Keep last N snapshots based on time range
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

      start_angle = (previous_votes / total_votes) * 360
      slice_angle = (option.votes / total_votes) * 360
      end_angle = start_angle + slice_angle

      # If this option has 100% of votes, draw a full circle
      if slice_angle >= 359.9 do
        # Draw a full donut using two semicircles
        outer_radius = 90
        inner_radius = 50

        # First semicircle (top half)
        path1 = "M 100 #{100 - outer_radius} A #{outer_radius} #{outer_radius} 0 0 1 100 #{100 + outer_radius}"
        # Second semicircle (bottom half)
        path2 = "A #{outer_radius} #{outer_radius} 0 0 1 100 #{100 - outer_radius}"
        # Inner circle (reverse direction)
        path3 = "M 100 #{100 - inner_radius} A #{inner_radius} #{inner_radius} 0 0 0 100 #{100 + inner_radius}"
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
