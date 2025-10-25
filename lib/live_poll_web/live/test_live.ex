defmodule LivePollWeb.TestLive do
  @moduledoc """
  Test LiveView to verify Qodo Merge detects Phoenix patterns.
  """
  use LivePollWeb, :live_view

  alias LivePoll.Repo
  alias LivePoll.Poll.Option

  # This should trigger: "No bang functions in event handlers"
  def handle_event("create_option", %{"text" => text}, socket) do
    option = Repo.insert!(%Option{text: text})
    {:noreply, assign(socket, :option, option)}
  end

  # This should trigger: "Business logic should be in context modules"
  def handle_event("complex_calculation", _params, socket) do
    # Complex business logic that should be in a context
    result = 
      socket.assigns.data
      |> Enum.map(&calculate_score/1)
      |> Enum.filter(&(&1 > 100))
      |> Enum.reduce(0, &+/2)
    
    {:noreply, assign(socket, :result, result)}
  end

  defp calculate_score(item) do
    # More business logic that belongs in context
    item.value * item.weight / item.total
  end
end
