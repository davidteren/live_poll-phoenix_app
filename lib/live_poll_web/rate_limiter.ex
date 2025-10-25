defmodule LivePollWeb.RateLimiter do
  @moduledoc """
  Rate limiting for LiveView events to prevent DoS attacks.
  
  Provides configurable rate limits for different actions based on their
  computational expense and potential for abuse.
  """

  # Default limits for different actions
  # Format: {max_requests, time_window_in_milliseconds}
  # These can be overridden in config files (e.g., config/dev.exs, config/prod.exs)
  @default_limits %{
    # 10 votes per minute - allows normal voting but prevents spam
    vote: {10, :timer.minutes(1)},
    # 5 languages per 5 minutes - prevents language spam
    add_language: {5, :timer.minutes(5)},
    # 1 seed per hour - expensive operation
    seed_data: {1, :timer.hours(1)},
    # 1 reset per hour - destructive operation
    reset_votes: {1, :timer.hours(1)},
    # 60 requests per minute default for any other action
    default: {60, :timer.minutes(1)}
  }

  # Get rate limits from application config or use defaults
  defp get_limits do
    Application.get_env(:live_poll, :rate_limits, @default_limits)
  end

  @doc """
  Check if an action is rate limited for a client.
  
  Returns:
  - `{:ok, %{count: count, limit: limit}}` if the action is allowed
  - `{:error, :rate_limited, %{limit: limit, retry_after: seconds}}` if rate limited
  
  ## Examples
  
      iex> check_rate("client123", :vote)
      {:ok, %{count: 1, limit: 10}}
      
      iex> check_rate("client123", :vote)  # After 11 votes
      {:error, :rate_limited, %{limit: 10, retry_after: 45}}
  """
  def check_rate(client_id, action) do
    limits = get_limits()
    {limit, window} = Map.get(limits, action, limits.default)
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
  
  Tries to identify the client using (in order of preference):
  1. Session ID (most reliable for authenticated sessions)
  2. IP address from peer data
  3. Socket ID as fallback
  
  ## Examples
  
      iex> get_client_id(socket)
      "session:abc123"
  """
  def get_client_id(socket) do
    cond do
      session_id = get_in(socket.assigns, [:session_id]) ->
        "session:#{session_id}"

      ip = get_connect_info(socket, :peer_data) ->
        "ip:#{format_ip(ip)}"

      true ->
        # Fallback to socket ID
        "socket:#{socket.id}"
    end
  end

  @doc """
  Get the configured rate limit for a specific action.
  
  Returns a tuple of {max_requests, window_ms}.
  
  ## Examples
  
      iex> get_limit(:vote)
      {10, 60000}
  """
  def get_limit(action) do
    limits = get_limits()
    Map.get(limits, action, limits.default)
  end

  # Private functions

  defp calculate_retry_after(bucket, window) do
    # Calculate seconds until rate limit resets
    case Hammer.inspect_bucket(bucket, window, 1) do
      {:ok, {_count, _limit, ms_to_reset, _created}} ->
        # Convert milliseconds to seconds, round up
        div(ms_to_reset + 999, 1000)

      _ ->
        # Default to 60 seconds if we can't determine
        60
    end
  end

  defp get_connect_info(socket, key) do
    get_in(socket, [:private, :connect_info, key])
  end

  defp format_ip({:peer_data, %{address: address}}) do
    format_ip_tuple(address)
  end

  defp format_ip(%{address: address}) do
    format_ip_tuple(address)
  end

  defp format_ip(_), do: "unknown"

  defp format_ip_tuple(address) when is_tuple(address) do
    address
    |> Tuple.to_list()
    |> Enum.join(".")
  end

  defp format_ip_tuple(_), do: "unknown"
end

