defmodule LivePollWeb.RateLimiter do
  @moduledoc """
  Rate limiting for LiveView events to prevent DoS attacks.

  Provides configurable rate limits for different actions to protect
  against abuse while allowing normal usage patterns.
  """

  # Different limits for different actions
  # Format: {max_requests, time_window_in_ms}
  @limits %{
    # 10 votes per minute
    vote: {10, :timer.minutes(1)},
    # 5 languages per 5 minutes
    add_language: {5, :timer.minutes(5)},
    # 1 seed per hour
    seed_data: {1, :timer.hours(1)},
    # 1 reset per hour
    reset_votes: {1, :timer.hours(1)},
    # 60 requests per minute default
    default: {60, :timer.minutes(1)}
  }

  @doc """
  Check if an action is rate limited for a client.

  Returns `{:ok, %{count: count, limit: limit}}` if allowed,
  or `{:error, :rate_limited, %{limit: limit, retry_after: seconds}}` if denied.

  ## Examples

      iex> check_rate("client123", :vote)
      {:ok, %{count: 1, limit: 10}}
      
      iex> check_rate("client123", :vote) # after 11 votes
      {:error, :rate_limited, %{limit: 10, retry_after: 45}}
  """
  def check_rate(client_id, action) do
    {limit, window} = Map.get(@limits, action, @limits.default)
    bucket = "#{client_id}:#{action}"

    case Hammer.check_rate(bucket, window, limit) do
      {:allow, count} ->
        {:ok, %{count: count, limit: limit}}

      {:deny, _limit} ->
        {:error, :rate_limited,
         %{limit: limit, retry_after: calculate_retry_after(bucket, window)}}
    end
  end

  @doc """
  Get client identifier from socket.

  Tries to identify the client using (in order):
  1. Session ID from assigns
  2. IP address from connection info
  3. Socket ID as fallback
  """
  def get_client_id(socket) do
    cond do
      session_id = get_in(socket.assigns, [:session_id]) ->
        "session:#{session_id}"

      ip = get_connect_info(socket, :peer_data) ->
        "ip:#{inspect(ip)}"

      true ->
        # Fallback to socket ID
        "socket:#{socket.id}"
    end
  end

  # Calculate seconds until rate limit resets
  defp calculate_retry_after(bucket, window) do
    case Hammer.inspect_bucket(bucket, window, 1) do
      {:ok, {_count, ms_to_reset, _created, _limit, _limit_rem}} ->
        # Convert milliseconds to seconds, round up
        div(ms_to_reset + 999, 1000)

      _ ->
        # Default to 60 seconds if inspection fails
        60
    end
  end

  # Safely get connection info from socket
  defp get_connect_info(socket, key) do
    socket.private[:connect_info][key]
  rescue
    _ -> nil
  end
end
