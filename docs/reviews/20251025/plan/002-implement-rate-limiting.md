# Task: Implement Rate Limiting to Prevent DoS Attacks

## Category
Security

## Priority
**CRITICAL** - System vulnerable to complete DoS with simple script

## Description
The application has no rate limiting on any operations, allowing malicious users to overwhelm the system with rapid requests. A simple script can crash the application by spamming votes, creating languages, or triggering expensive operations like seeding. This is a critical security vulnerability.

## Current State
```elixir
# No rate limiting exists - anyone can do this:
def handle_event("vote", %{"id" => id}, socket) do
  # Processes every vote immediately with no limits
  # Can be called thousands of times per second
end

def handle_event("seed_data", _params, socket) do
  # Expensive operation can be triggered repeatedly
  # No protection against abuse
end
```

### Attack Example
```javascript
// Simple DoS attack
for(let i = 0; i < 10000; i++) {
  fetch('/live/websocket', {
    method: 'POST',
    body: JSON.stringify({event: 'vote', id: 1})
  });
}
```

## Proposed Solution

### Step 1: Add Hammer Dependency
```elixir
# mix.exs
defp deps do
  [
    # ... existing deps
    {:hammer, "~> 6.2"}
  ]
end
```

### Step 2: Configure Rate Limiter
```elixir
# config/config.exs
config :hammer,
  backend: {Hammer.Backend.ETS, [expiry_ms: 60_000 * 60 * 24, cleanup_interval_ms: 60_000 * 10]}
```

### Step 3: Create Rate Limiter Module
```elixir
# lib/live_poll_web/rate_limiter.ex
defmodule LivePollWeb.RateLimiter do
  @moduledoc """
  Rate limiting for LiveView events to prevent DoS attacks
  """
  
  # Different limits for different actions
  @limits %{
    vote: {10, :timer.minutes(1)},        # 10 votes per minute
    add_language: {5, :timer.minutes(5)}, # 5 languages per 5 minutes
    seed_data: {1, :timer.hours(1)},      # 1 seed per hour
    reset_votes: {1, :timer.hours(1)},    # 1 reset per hour
    default: {60, :timer.minutes(1)}      # 60 requests per minute default
  }
  
  @doc """
  Check if an action is rate limited for a client
  """
  def check_rate(client_id, action) do
    {limit, window} = Map.get(@limits, action, @limits.default)
    bucket = "#{client_id}:#{action}"
    
    case Hammer.check_rate(bucket, window, limit) do
      {:allow, count} -> 
        {:ok, %{count: count, limit: limit}}
      {:deny, limit} -> 
        {:error, :rate_limited, %{limit: limit, retry_after: calculate_retry_after(bucket, window)}}
    end
  end
  
  @doc """
  Get client identifier from socket
  """
  def get_client_id(socket) do
    # Try to get from session, IP, or generate one
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
  
  defp calculate_retry_after(bucket, window) do
    # Calculate seconds until rate limit resets
    case Hammer.inspect_bucket(bucket, window, 1) do
      {:ok, {_count, _limit, ms_to_reset, _created}} ->
        div(ms_to_reset, 1000)
      _ ->
        60 # Default to 60 seconds
    end
  end
  
  defp get_connect_info(socket, key) do
    socket.private[:connect_info][key]
  rescue
    _ -> nil
  end
end
```

### Step 4: Apply Rate Limiting to LiveView
```elixir
# lib/live_poll_web/live/poll_live.ex
defmodule LivePollWeb.PollLive do
  alias LivePollWeb.RateLimiter
  
  def handle_event("vote", %{"id" => id}, socket) do
    client_id = RateLimiter.get_client_id(socket)
    
    case RateLimiter.check_rate(client_id, :vote) do
      {:ok, _} ->
        # Process vote normally
        cast_vote(id, socket)
      
      {:error, :rate_limited, %{retry_after: retry_after}} ->
        {:noreply, 
         socket
         |> put_flash(:error, "Too many votes! Please wait #{retry_after} seconds.")
         |> push_event("rate_limited", %{retry_after: retry_after})}
    end
  end
  
  def handle_event("add_language", %{"name" => name}, socket) do
    client_id = RateLimiter.get_client_id(socket)
    
    case RateLimiter.check_rate(client_id, :add_language) do
      {:ok, _} ->
        # Process language addition
        add_language(name, socket)
      
      {:error, :rate_limited, _} ->
        {:noreply, put_flash(socket, :error, "Too many languages added. Please wait.")}
    end
  end
  
  def handle_event("seed_data", params, socket) do
    client_id = RateLimiter.get_client_id(socket)
    
    case RateLimiter.check_rate(client_id, :seed_data) do
      {:ok, _} ->
        # Process expensive seeding operation
        seed_votes(params, socket)
      
      {:error, :rate_limited, _} ->
        {:noreply, put_flash(socket, :error, "Seeding can only be done once per hour.")}
    end
  end
  
  def handle_event("reset_votes", _params, socket) do
    client_id = RateLimiter.get_client_id(socket)
    
    case RateLimiter.check_rate(client_id, :reset_votes) do
      {:ok, _} ->
        # Process reset
        reset_all_votes(socket)
      
      {:error, :rate_limited, _} ->
        {:noreply, put_flash(socket, :error, "Reset can only be done once per hour.")}
    end
  end
end
```

### Step 5: Add Application-Level Rate Limiting
```elixir
# lib/live_poll_web/plugs/rate_limit_plug.ex
defmodule LivePollWeb.RateLimitPlug do
  import Plug.Conn
  
  def init(opts), do: opts
  
  def call(conn, _opts) do
    client_ip = get_client_ip(conn)
    
    case Hammer.check_rate("global:#{client_ip}", :timer.minutes(1), 100) do
      {:allow, _} ->
        conn
      
      {:deny, _} ->
        conn
        |> put_status(:too_many_requests)
        |> put_resp_header("retry-after", "60")
        |> Phoenix.Controller.text("Rate limit exceeded. Please try again later.")
        |> halt()
    end
  end
  
  defp get_client_ip(conn) do
    conn.remote_ip 
    |> Tuple.to_list() 
    |> Enum.join(".")
  end
end

# Add to router.ex
pipeline :browser do
  # ... existing plugs
  plug LivePollWeb.RateLimitPlug
end
```

## Requirements
1. ✅ Implement rate limiting for all user actions (vote, add_language, seed, reset)
2. ✅ Different limits for different action types based on expense
3. ✅ Clear error messages when rate limited
4. ✅ Track rate limits per client (session/IP)
5. ✅ Add retry-after headers for proper client behavior
6. ✅ Configure reasonable limits that prevent abuse but allow normal use
7. ✅ Add application-level rate limiting as defense in depth

## Definition of Done
1. **Code Implementation**
   - [ ] Hammer dependency added to mix.exs
   - [ ] RateLimiter module created with configurable limits
   - [ ] Rate limiting applied to all LiveView events
   - [ ] Application-level rate limiting plug added
   - [ ] Clear error messages for rate limited users

2. **Configuration**
   - [ ] Rate limits configured in config files
   - [ ] Different limits for dev/test/prod environments
   - [ ] Ability to adjust limits without code changes

3. **Tests**
   ```elixir
   test "prevents rapid voting" do
     {:ok, view, _} = live(conn, "/")
     
     # First 10 votes succeed
     for _ <- 1..10 do
       view |> element("[data-testid='vote-elixir']") |> render_click()
     end
     
     # 11th vote is rate limited
     result = view |> element("[data-testid='vote-elixir']") |> render_click()
     assert result =~ "Too many votes"
   end
   
   test "different actions have different limits" do
     # Test that expensive operations have stricter limits
   end
   ```

4. **Quality Checks**
   - [ ] `mix deps.get` successfully installs Hammer
   - [ ] `mix test` passes all tests
   - [ ] Manual testing confirms rate limiting works
   - [ ] Load testing shows system remains responsive under attack

## Branch Name
`fix/add-rate-limiting`

## Dependencies
- Task 001 (Fix Race Condition) - Should be completed first for clean testing

## Estimated Complexity
**M (Medium)** - 2-4 hours

## Testing Instructions
1. Install Hammer dependency
2. Configure rate limits
3. Test normal voting (should allow 10 votes/minute)
4. Test rapid voting (11th vote should be blocked)
5. Test different actions have different limits
6. Use a script to attempt DoS - verify system remains responsive
7. Verify rate limits reset after time window

## Monitoring
- Add metrics for rate limited requests
- Monitor for legitimate users being rate limited
- Adjust limits based on actual usage patterns

## Notes
- Start with conservative limits and adjust based on real usage
- Consider implementing CAPTCHA for repeated rate limit violations
- May need Redis backend for distributed deployments
- Consider IP-based and session-based tracking for better accuracy
