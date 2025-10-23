defmodule LivePollWeb.PollLive do
  use LivePollWeb, :live_view

  alias LivePoll.Poll.Option
  alias LivePoll.Repo

  @topic "poll:updates"

  def mount(_params, _session, socket) do
    Phoenix.PubSub.subscribe(LivePoll.PubSub, @topic)

    options = Repo.all(Option) |> Enum.sort_by(& &1.id)
    total_votes = Enum.sum(Enum.map(options, & &1.votes))

    # Sort options by votes for pie chart (descending)
    sorted_options = Enum.sort_by(options, & &1.votes, :desc)

    # Initialize trend data - store last 60 data points (5 minutes at 5-second intervals)
    now = DateTime.utc_now()
    initial_snapshot = %{
      timestamp: now,
      percentages: calculate_percentages(options, total_votes)
    }

    socket =
      assign(socket,
        options: options,
        sorted_options: sorted_options,
        total_votes: total_votes,
        recent_activity: [],
        votes_per_minute: 0,
        last_minute_votes: 0,
        trend_data: [initial_snapshot]
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
    changeset = Ecto.Changeset.change(option, votes: option.votes + 1)
    Repo.update!(changeset)

    Phoenix.PubSub.broadcast(
      LivePoll.PubSub,
      @topic,
      {:poll_update, %{
        id: String.to_integer(id),
        votes: option.votes + 1,
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

  def handle_event("seed_data", _params, socket) do
    # List of popular programming languages
    languages = [
      "Elixir", "Python", "JavaScript", "Ruby", "Go", "Rust",
      "TypeScript", "Swift", "Kotlin", "PHP", "Java", "C#",
      "C++", "Dart", "Scala", "Haskell", "Clojure", "F#"
    ]

    # Delete all existing options
    Repo.delete_all(Option)

    # Pick 12-14 random languages
    num_languages = Enum.random(12..14)
    selected_languages = Enum.take_random(languages, num_languages)

    # Insert languages with random votes between 10 and 39
    Enum.each(selected_languages, fn lang ->
      votes = Enum.random(10..39)
      Repo.insert!(%Option{text: lang, votes: votes})
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
      assign(socket,
        options: options,
        sorted_options: sorted_options,
        total_votes: total_votes,
        recent_activity: recent_activity,
        last_minute_votes: socket.assigns.last_minute_votes + 1
      )

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
    # Capture current state for trend chart
    now = DateTime.utc_now()
    percentages = calculate_percentages(socket.assigns.options, socket.assigns.total_votes)

    snapshot = %{
      timestamp: now,
      percentages: percentages
    }

    # Keep last 60 snapshots (5 minutes)
    trend_data = [snapshot | socket.assigns.trend_data] |> Enum.take(60)

    {:noreply, assign(socket, trend_data: trend_data)}
  end

  def handle_info({:poll_reset, _data}, socket) do
    # Reload all options from database
    options = Repo.all(Option) |> Enum.sort_by(& &1.id)
    total_votes = 0
    sorted_options = Enum.sort_by(options, & &1.votes, :desc)

    # Reset trend data
    now = DateTime.utc_now()
    initial_snapshot = %{
      timestamp: now,
      percentages: calculate_percentages(options, total_votes)
    }

    socket =
      assign(socket,
        options: options,
        sorted_options: sorted_options,
        total_votes: total_votes,
        recent_activity: [],
        votes_per_minute: 0,
        last_minute_votes: 0,
        trend_data: [initial_snapshot]
      )

    {:noreply, socket}
  end

  def handle_info({:data_seeded, _data}, socket) do
    # Reload all options from database
    options = Repo.all(Option) |> Enum.sort_by(& &1.id)
    total_votes = Enum.sum(Enum.map(options, & &1.votes))
    sorted_options = Enum.sort_by(options, & &1.votes, :desc)

    # Initialize trend data with seeded values
    now = DateTime.utc_now()
    initial_snapshot = %{
      timestamp: now,
      percentages: calculate_percentages(options, total_votes)
    }

    socket =
      assign(socket,
        options: options,
        sorted_options: sorted_options,
        total_votes: total_votes,
        recent_activity: [],
        votes_per_minute: 0,
        last_minute_votes: 0,
        trend_data: [initial_snapshot]
      )

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
