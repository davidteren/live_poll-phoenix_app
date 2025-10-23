defmodule LivePollWeb.PollLive do
  use LivePollWeb, :live_view

  alias LivePoll.Poll.Option
  alias LivePoll.Repo

  @topic "poll:updates"

  def mount(_params, _session, socket) do
    Phoenix.PubSub.subscribe(LivePoll.PubSub, @topic)

    options = Repo.all(Option)
    total_votes = Enum.sum(Enum.map(options, & &1.votes))

    socket = assign(socket, options: options, total_votes: total_votes)

    {:ok, socket}
  end

  def handle_event("vote", %{"id" => id}, socket) do
    option = Repo.get!(Option, id)
    changeset = Ecto.Changeset.change(option, votes: option.votes + 1)
    Repo.update!(changeset)

    Phoenix.PubSub.broadcast(
      LivePoll.PubSub,
      @topic,
      {:poll_update, %{id: String.to_integer(id), votes: option.votes + 1}}
    )

    {:noreply, socket}
  end

  def handle_info({:poll_update, %{id: id, votes: votes}}, socket) do
    options =
      Enum.map(socket.assigns.options, fn
        %{id: ^id} = option -> %{option | votes: votes}
        option -> option
      end)

    total_votes = Enum.sum(Enum.map(options, & &1.votes))

    socket = assign(socket, options: options, total_votes: total_votes)

    {:noreply, socket}
  end

  defp percentage(votes, total) when total > 0 do
    (votes / total * 100) |> round()
  end

  defp percentage(_votes, _total), do: 0
end
