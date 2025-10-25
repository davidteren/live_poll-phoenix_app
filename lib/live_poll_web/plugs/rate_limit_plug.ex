defmodule LivePollWeb.RateLimitPlug do
  @moduledoc """
  Application-level rate limiting plug to prevent DoS attacks.
  
  This provides a first line of defense by limiting the total number of
  requests from a single IP address, regardless of the specific action.
  """

  import Plug.Conn

  @doc """
  Initialize the plug with options.
  
  Options:
  - `:limit` - Maximum number of requests (default: 100)
  - `:window` - Time window in milliseconds (default: 1 minute)
  """
  def init(opts) do
    %{
      limit: Keyword.get(opts, :limit, 100),
      window: Keyword.get(opts, :window, :timer.minutes(1))
    }
  end

  @doc """
  Apply rate limiting to the connection.
  
  If the rate limit is exceeded, returns a 429 Too Many Requests response
  with a Retry-After header.
  """
  def call(conn, opts) do
    client_ip = get_client_ip(conn)
    bucket = "global:#{client_ip}"

    case Hammer.check_rate(bucket, opts.window, opts.limit) do
      {:allow, _count} ->
        conn

      {:deny, _limit} ->
        retry_after = calculate_retry_after(bucket, opts.window)

        conn
        |> put_status(:too_many_requests)
        |> put_resp_header("retry-after", to_string(retry_after))
        |> Phoenix.Controller.text("Rate limit exceeded. Please try again later.")
        |> halt()
    end
  end

  # Private functions

  defp get_client_ip(conn) do
    # Try to get the real IP from X-Forwarded-For header (for proxies)
    case get_req_header(conn, "x-forwarded-for") do
      [ip | _] ->
        # Take the first IP in the chain
        ip
        |> String.split(",")
        |> List.first()
        |> String.trim()

      [] ->
        # Fall back to remote_ip
        conn.remote_ip
        |> Tuple.to_list()
        |> Enum.join(".")
    end
  end

  defp calculate_retry_after(bucket, window) do
    case Hammer.inspect_bucket(bucket, window, 1) do
      {:ok, {_count, _limit, ms_to_reset, _created}} ->
        # Convert milliseconds to seconds, round up
        div(ms_to_reset + 999, 1000)

      _ ->
        60
    end
  end
end

