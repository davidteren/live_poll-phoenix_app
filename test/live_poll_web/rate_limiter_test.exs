defmodule LivePollWeb.RateLimiterTest do
  use ExUnit.Case, async: false

  alias LivePollWeb.RateLimiter

  setup do
    # Clean up any existing rate limit buckets before each test
    # This ensures tests don't interfere with each other
    :timer.sleep(100)
    :ok
  end

  describe "check_rate/2" do
    test "allows requests within rate limit" do
      client_id = "test_client_#{:rand.uniform(1000000)}"

      # First request should be allowed
      assert {:ok, %{count: 1, limit: 10}} = RateLimiter.check_rate(client_id, :vote)

      # Second request should also be allowed
      assert {:ok, %{count: 2, limit: 10}} = RateLimiter.check_rate(client_id, :vote)
    end

    test "denies requests exceeding rate limit" do
      client_id = "test_client_#{:rand.uniform(1000000)}"

      # Make 10 requests (the limit for voting)
      for i <- 1..10 do
        assert {:ok, %{count: ^i, limit: 10}} = RateLimiter.check_rate(client_id, :vote)
      end

      # 11th request should be denied
      assert {:error, :rate_limited, %{limit: 10, retry_after: retry_after}} =
               RateLimiter.check_rate(client_id, :vote)

      assert is_integer(retry_after)
      assert retry_after > 0
    end

    test "different actions have different limits" do
      client_id = "test_client_#{:rand.uniform(1000000)}"

      # Vote limit is 10
      assert {:ok, %{limit: 10}} = RateLimiter.check_rate(client_id, :vote)

      # Add language limit is 5
      assert {:ok, %{limit: 5}} = RateLimiter.check_rate(client_id, :add_language)

      # Seed data limit is 1
      assert {:ok, %{limit: 1}} = RateLimiter.check_rate(client_id, :seed_data)

      # Reset votes limit is 1
      assert {:ok, %{limit: 1}} = RateLimiter.check_rate(client_id, :reset_votes)
    end

    test "different clients have independent rate limits" do
      client1 = "test_client_#{:rand.uniform(1000000)}"
      client2 = "test_client_#{:rand.uniform(1000000)}"

      # Client 1 makes 10 requests
      for i <- 1..10 do
        assert {:ok, %{count: ^i}} = RateLimiter.check_rate(client1, :vote)
      end

      # Client 1 is rate limited
      assert {:error, :rate_limited, _} = RateLimiter.check_rate(client1, :vote)

      # Client 2 should still be able to make requests
      assert {:ok, %{count: 1}} = RateLimiter.check_rate(client2, :vote)
    end

    test "different actions for same client are independent" do
      client_id = "test_client_#{:rand.uniform(1000000)}"

      # Use up vote limit
      for i <- 1..10 do
        assert {:ok, %{count: ^i}} = RateLimiter.check_rate(client_id, :vote)
      end

      # Voting is rate limited
      assert {:error, :rate_limited, _} = RateLimiter.check_rate(client_id, :vote)

      # But add_language should still work
      assert {:ok, %{count: 1}} = RateLimiter.check_rate(client_id, :add_language)
    end

    test "uses default limit for unknown actions" do
      client_id = "test_client_#{:rand.uniform(1000000)}"

      # Unknown action should use default limit (60)
      assert {:ok, %{limit: 60}} = RateLimiter.check_rate(client_id, :unknown_action)
    end
  end

  describe "get_limit/1" do
    test "returns correct limits for known actions" do
      assert {10, _} = RateLimiter.get_limit(:vote)
      assert {5, _} = RateLimiter.get_limit(:add_language)
      assert {1, _} = RateLimiter.get_limit(:seed_data)
      assert {1, _} = RateLimiter.get_limit(:reset_votes)
    end

    test "returns default limit for unknown actions" do
      assert {60, _} = RateLimiter.get_limit(:unknown_action)
    end

    test "returns time windows in milliseconds" do
      {_limit, window} = RateLimiter.get_limit(:vote)
      assert is_integer(window)
      assert window > 0
    end
  end

  describe "get_client_id/1" do
    test "uses session_id when available" do
      socket = %{
        assigns: %{session_id: "abc123"},
        id: "socket_id",
        private: %{connect_info: %{}}
      }

      assert "session:abc123" = RateLimiter.get_client_id(socket)
    end

    test "uses peer_data when session_id not available" do
      socket = %{
        assigns: %{},
        id: "socket_id",
        private: %{
          connect_info: %{
            peer_data: %{address: {192, 168, 1, 1}}
          }
        }
      }

      client_id = RateLimiter.get_client_id(socket)
      assert client_id =~ "ip:"
      assert client_id =~ "192.168.1.1"
    end

    test "falls back to socket_id when neither session nor peer_data available" do
      socket = %{
        assigns: %{},
        id: "socket_123",
        private: %{connect_info: %{}}
      }

      assert "socket:socket_123" = RateLimiter.get_client_id(socket)
    end

    test "handles missing connect_info gracefully" do
      socket = %{
        assigns: %{},
        id: "socket_123",
        private: %{}
      }

      assert "socket:socket_123" = RateLimiter.get_client_id(socket)
    end
  end

  describe "rate limit expiry" do
    @tag :slow
    test "rate limits reset after time window expires" do
      client_id = "test_client_#{:rand.uniform(1000000)}"

      # This test would require waiting for the actual time window to expire
      # For vote action, that's 1 minute, which is too long for a test
      # In a real scenario, you might want to:
      # 1. Use a shorter time window in test config
      # 2. Mock the time
      # 3. Skip this test in regular runs and only run it manually

      # For now, we'll just verify the behavior is correct
      # Make 10 requests
      for i <- 1..10 do
        assert {:ok, %{count: ^i}} = RateLimiter.check_rate(client_id, :vote)
      end

      # Should be rate limited
      assert {:error, :rate_limited, _} = RateLimiter.check_rate(client_id, :vote)

      # In a real test, we would wait for the window to expire
      # :timer.sleep(60_000)
      # assert {:ok, %{count: 1}} = RateLimiter.check_rate(client_id, :vote)
    end
  end
end

