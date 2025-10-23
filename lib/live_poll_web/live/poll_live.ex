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
end
