defmodule LivePollWeb.PollLive do
  use LivePollWeb, :live_view

  alias LivePoll.Poll.Option
  alias LivePoll.Repo

  @topic "poll:updates"

  def mount(_params, _session, socket) do
    Phoenix.PubSub.subscribe(LivePoll.PubSub, @topic)

    options = Repo.all(Option) |> Enum.sort_by(& &1.id)
    total_votes = Enum.sum(Enum.map(options, & &1.votes))

    socket =
      assign(socket,
        options: options,
        total_votes: total_votes,
        recent_activity: [],
        votes_per_minute: 0,
        last_minute_votes: 0
      )

    # Schedule periodic stats update
    if connected?(socket) do
      :timer.send_interval(5000, self(), :update_stats)
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

  def handle_info({:poll_update, update_data}, socket) do
    %{id: id, votes: votes, language: language, timestamp: timestamp} = update_data

    options =
      Enum.map(socket.assigns.options, fn
        %{id: ^id} = option -> %{option | votes: votes}
        option -> option
      end)

    total_votes = Enum.sum(Enum.map(options, & &1.votes))

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

  def handle_info({:poll_reset, _data}, socket) do
    # Reload all options from database
    options = Repo.all(Option) |> Enum.sort_by(& &1.id)
    total_votes = 0

    socket =
      assign(socket,
        options: options,
        total_votes: total_votes,
        recent_activity: [],
        votes_per_minute: 0,
        last_minute_votes: 0
      )

    {:noreply, socket}
  end

  defp percentage(votes, total) when total > 0 do
    (votes / total * 100) |> round()
  end

  defp percentage(_votes, _total), do: 0

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
