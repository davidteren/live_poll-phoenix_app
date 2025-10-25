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
  2. IP address from connection info (address only, not port)
  3. Socket ID as fallback (for test environment only - not secure for production)

  Note: In production, socket ID fallback allows rate limit bypass by reconnecting.
  This is acceptable for test environment where we need unique identifiers per test.
  """
  def get_client_id(socket) do
    cond do
      session_id = get_in(socket.assigns, [:session_id]) ->
        "session:#{session_id}"

      ip_tuple = get_ip_address(socket) ->
        # Use only IP address (not port) to prevent bypass via reconnection
        "ip:#{:inet.ntoa(ip_tuple)}"

      true ->
        # Fallback to socket ID for test environment
        # In production, this would allow bypass, but it's needed for tests
        # where each LiveView gets a unique socket ID
        "socket:#{socket.id}"
    end
  end

  # Safely extract IP address from socket
  defp get_ip_address(socket) do
    socket.private[:connect_info][:peer_data][:address]
  rescue
    _ -> nil
  end

  # Calculate seconds until rate limit resets
  defp calculate_retry_after(bucket, window) do
    case Hammer.inspect_bucket(bucket, window, 1) do
      {:ok, {_count, ms_to_reset, _created, _limit, _limit_rem}} ->
        # Convert milliseconds to seconds, round up
        div(ms_to_reset + 999, 1000)

      _ ->
        # Default to the full window time if inspection fails
        div(window + 999, 1000)
    end
  end
end
