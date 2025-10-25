defmodule LivePollWeb.RateLimitPlugTest do
  use LivePollWeb.ConnCase, async: false

  alias LivePollWeb.RateLimitPlug

  describe "init/1" do
    test "uses default options when none provided" do
      opts = RateLimitPlug.init([])
      assert opts.limit == 100
      assert opts.window == :timer.minutes(1)
    end

    test "accepts custom limit" do
      opts = RateLimitPlug.init(limit: 50)
      assert opts.limit == 50
    end

    test "accepts custom window" do
      opts = RateLimitPlug.init(window: :timer.minutes(5))
      assert opts.window == :timer.minutes(5)
    end

    test "accepts both custom limit and window" do
      opts = RateLimitPlug.init(limit: 200, window: :timer.minutes(2))
      assert opts.limit == 200
      assert opts.window == :timer.minutes(2)
    end
  end

  describe "call/2" do
    setup do
      # Use a unique IP for each test to avoid interference
      unique_ip = {192, 168, 1, :rand.uniform(255)}
      %{unique_ip: unique_ip}
    end

    test "allows requests within rate limit", %{conn: conn, unique_ip: ip} do
      opts = RateLimitPlug.init(limit: 10, window: :timer.minutes(1))

      # Set the remote IP
      conn = %{conn | remote_ip: ip}

      # First request should pass through
      result_conn = RateLimitPlug.call(conn, opts)
      refute result_conn.halted
    end

    test "blocks requests exceeding rate limit", %{conn: conn, unique_ip: ip} do
      opts = RateLimitPlug.init(limit: 5, window: :timer.minutes(1))

      # Set the remote IP
      conn = %{conn | remote_ip: ip}

      # Make 5 requests (the limit)
      Enum.each(1..5, fn _ ->
        result_conn = RateLimitPlug.call(conn, opts)
        refute result_conn.halted
      end)

      # 6th request should be blocked
      result_conn = RateLimitPlug.call(conn, opts)
      assert result_conn.halted
      assert result_conn.status == 429
    end

    test "sets retry-after header when rate limited", %{conn: conn, unique_ip: ip} do
      opts = RateLimitPlug.init(limit: 1, window: :timer.minutes(1))

      # Set the remote IP
      conn = %{conn | remote_ip: ip}

      # First request passes
      RateLimitPlug.call(conn, opts)

      # Second request is blocked
      result_conn = RateLimitPlug.call(conn, opts)

      assert result_conn.halted
      retry_after = get_resp_header(result_conn, "retry-after")
      assert length(retry_after) == 1
      assert String.to_integer(List.first(retry_after)) > 0
    end

    test "returns appropriate error message when rate limited", %{conn: conn, unique_ip: ip} do
      opts = RateLimitPlug.init(limit: 1, window: :timer.minutes(1))

      # Set the remote IP
      conn = %{conn | remote_ip: ip}

      # First request passes
      RateLimitPlug.call(conn, opts)

      # Second request is blocked
      result_conn = RateLimitPlug.call(conn, opts)

      assert result_conn.halted
      assert result_conn.resp_body == "Rate limit exceeded. Please try again later."
    end

    test "different IPs have independent rate limits", %{conn: conn} do
      opts = RateLimitPlug.init(limit: 2, window: :timer.minutes(1))

      ip1 = {192, 168, 1, 100}
      ip2 = {192, 168, 1, 101}

      # IP1 makes 2 requests (hits limit)
      conn1 = %{conn | remote_ip: ip1}

      Enum.each(1..2, fn _ ->
        result_conn = RateLimitPlug.call(conn1, opts)
        refute result_conn.halted
      end)

      # IP1's 3rd request is blocked
      result_conn = RateLimitPlug.call(conn1, opts)
      assert result_conn.halted

      # IP2 should still be able to make requests
      conn2 = %{conn | remote_ip: ip2}
      result_conn = RateLimitPlug.call(conn2, opts)
      refute result_conn.halted
    end

    test "handles X-Forwarded-For header for proxied requests", %{conn: conn} do
      opts = RateLimitPlug.init(limit: 2, window: :timer.minutes(1))

      # Set X-Forwarded-For header (simulating a proxy)
      forwarded_ip = "203.0.113.1"
      conn = put_req_header(conn, "x-forwarded-for", forwarded_ip)

      # Make 2 requests (hits limit)
      Enum.each(1..2, fn _ ->
        result_conn = RateLimitPlug.call(conn, opts)
        refute result_conn.halted
      end)

      # 3rd request should be blocked
      result_conn = RateLimitPlug.call(conn, opts)
      assert result_conn.halted
    end

    test "handles multiple IPs in X-Forwarded-For header", %{conn: conn} do
      opts = RateLimitPlug.init(limit: 2, window: :timer.minutes(1))

      # X-Forwarded-For can contain multiple IPs (client, proxy1, proxy2, ...)
      # We should use the first one (the original client)
      conn = put_req_header(conn, "x-forwarded-for", "203.0.113.1, 198.51.100.1, 192.0.2.1")

      # Make 2 requests (hits limit)
      Enum.each(1..2, fn _ ->
        result_conn = RateLimitPlug.call(conn, opts)
        refute result_conn.halted
      end)

      # 3rd request should be blocked
      result_conn = RateLimitPlug.call(conn, opts)
      assert result_conn.halted

      # A request from a different IP in the chain should not be blocked
      conn2 = put_req_header(conn, "x-forwarded-for", "198.51.100.1, 203.0.113.1")
      result_conn = RateLimitPlug.call(conn2, opts)
      refute result_conn.halted
    end
  end
end

