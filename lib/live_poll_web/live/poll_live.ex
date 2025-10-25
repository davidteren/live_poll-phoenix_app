defmodule LivePollWeb.PollLive do
  use LivePollWeb, :live_view

  alias LivePoll.Polls

  @topic "poll:updates"

  def mount(_params, _session, socket) do
    Phoenix.PubSub.subscribe(LivePoll.PubSub, @topic)

    socket =
      socket
      |> load_poll_data()
      |> assign(
        recent_activity: [],
        votes_per_minute: 0,
        last_minute_votes: 0,
        time_range: 60,
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
    with {int_id, ""} <- Integer.parse(id),
         {:ok, _option, _event} <- Polls.cast_vote(int_id) do
      {:noreply, socket}
    else
      _ -> {:noreply, put_flash(socket, :error, "Failed to record vote")}
    end
  end

  def handle_event("toggle_theme", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("reset_votes", _params, socket) do
    case Polls.reset_all_votes() do
      {:ok, _} -> {:noreply, socket}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Failed to reset votes")}
    end
  end

  def handle_event("add_language", %{"name" => name}, socket) when byte_size(name) > 0 do
    case Polls.add_language(name) do
      {:ok, _option} -> {:noreply, socket}
      {:error, _} -> {:noreply, socket}
    end
  end

  def handle_event("add_language", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("change_time_range", %{"range" => range_str}, socket) do
    range_minutes = String.to_integer(range_str)
    trend_data = Polls.calculate_trends(range_minutes)
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
    # Seed data using the Polls context
    case Polls.seed_votes() do
      {:ok, _} ->
        # Hide progress modal after a short delay
        Process.send_after(self(), :hide_seeding_progress, 800)
        {:noreply, socket}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to seed data")}
    end
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
    trend_data = Polls.calculate_trends(time_range)
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
    socket =
      socket
      |> load_poll_data()
      |> assign(
        recent_activity: [],
        votes_per_minute: 0,
        last_minute_votes: 0
      )
      |> push_event("update-pie-chart", %{
        data: Enum.map(socket.assigns.sorted_options, fn opt -> %{name: opt.text, votes: opt.votes} end)
      })
      |> push_event("update-trend-chart", %{
        trendData: socket.assigns.trend_data,
        languages: Enum.map(socket.assigns.sorted_options, & &1.text)
      })

    {:noreply, socket}
  end

  def handle_info({:data_seeded, _data}, socket) do
    socket =
      socket
      |> load_poll_data()
      |> assign(
        recent_activity: [],
        votes_per_minute: 0,
        last_minute_votes: 0
      )
      |> push_event("update-pie-chart", %{
        data: Enum.map(socket.assigns.sorted_options, fn opt -> %{name: opt.text, votes: opt.votes} end)
      })
      |> push_event("update-trend-chart", %{
        trendData: socket.assigns.trend_data,
        languages: Enum.map(socket.assigns.sorted_options, & &1.text)
      })

    {:noreply, socket}
  end

  def handle_info({:language_added, _data}, socket) do
    socket = load_poll_data(socket)
    {:noreply, socket}
  end

  # Helper function to load all poll data from context
  defp load_poll_data(socket) do
    stats = Polls.get_stats()
    time_range = socket.assigns[:time_range] || 60
    trend_data = Polls.calculate_trends(time_range)

    socket
    |> assign(:options, stats.options)
    |> assign(:sorted_options, stats.sorted_options)
    |> assign(:total_votes, stats.total_votes)
    |> assign(:trend_data, trend_data)
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
  def calculate_percentages(options, total_votes) do
    Polls.calculate_percentages(options)
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
