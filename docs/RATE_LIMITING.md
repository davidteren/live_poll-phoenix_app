# Rate Limiting Implementation

This document describes the rate limiting implementation added to prevent DoS (Denial of Service) attacks on the LivePoll application.

## Overview

The application now implements a comprehensive rate limiting system with two layers of protection:

1. **Application-level rate limiting** - Limits total requests per IP address
2. **Action-level rate limiting** - Limits specific actions (voting, adding languages, etc.)

## Architecture

### Components

#### 1. RateLimiter Module (`lib/live_poll_web/rate_limiter.ex`)

The core rate limiting logic that provides:
- Configurable rate limits for different actions
- Client identification (session, IP, or socket ID)
- Rate limit checking and enforcement
- Retry-after calculation

#### 2. RateLimitPlug (`lib/live_poll_web/plugs/rate_limit_plug.ex`)

A Plug that provides application-level rate limiting:
- Limits total requests per IP address
- Returns 429 (Too Many Requests) when limit exceeded
- Includes Retry-After header for proper client behavior
- Handles X-Forwarded-For for proxied requests

#### 3. PollLive Integration

Rate limiting is integrated into all LiveView event handlers:
- `handle_event("vote", ...)` - Voting actions
- `handle_event("add_language", ...)` - Adding new languages
- `handle_event("seed_data", ...)` - Data seeding
- `handle_event("reset_votes", ...)` - Resetting votes

## Rate Limits

### Action-Specific Limits

| Action | Limit | Time Window | Rationale |
|--------|-------|-------------|-----------|
| `vote` | 10 requests | 1 minute | Allows normal voting but prevents spam |
| `add_language` | 5 requests | 5 minutes | Prevents language spam |
| `seed_data` | 1 request | 1 hour | Expensive operation, rarely needed |
| `reset_votes` | 1 request | 1 hour | Destructive operation, rarely needed |
| `default` | 60 requests | 1 minute | Fallback for any other action |

### Application-Level Limit

- **100 requests per minute** per IP address
- Applies to all HTTP requests, not just LiveView events
- First line of defense against DoS attacks

## Client Identification

Clients are identified using the following priority:

1. **Session ID** - Most reliable for authenticated sessions
2. **IP Address** - From peer_data or X-Forwarded-For header
3. **Socket ID** - Fallback when neither session nor IP available

This ensures rate limits are applied per-client, not globally.

## Configuration

### Hammer Backend

The rate limiter uses Hammer with an ETS backend:

```elixir
# config/config.exs
config :hammer,
  backend:
    {Hammer.Backend.ETS,
     [expiry_ms: 60_000 * 60 * 24, cleanup_interval_ms: 60_000 * 10]}
```

- **expiry_ms**: 24 hours - How long to keep rate limit data
- **cleanup_interval_ms**: 10 minutes - How often to clean up expired data

### Adjusting Limits

To adjust rate limits, modify the `@limits` map in `lib/live_poll_web/rate_limiter.ex`:

```elixir
@limits %{
  vote: {10, :timer.minutes(1)},        # {max_requests, time_window}
  add_language: {5, :timer.minutes(5)},
  # ... etc
}
```

### Environment-Specific Configuration

You can override limits per environment:

```elixir
# config/dev.exs
config :live_poll, :rate_limits,
  vote: {100, :timer.minutes(1)}  # More lenient in development

# config/prod.exs
config :live_poll, :rate_limits,
  vote: {5, :timer.minutes(1)}    # Stricter in production
```

## User Experience

### Error Messages

When rate limited, users see clear error messages:

- **Voting**: "Too many votes! Please wait X seconds."
- **Adding Languages**: "Too many languages added. Please wait X seconds."
- **Seeding**: "Seeding can only be done once per hour. Please wait X seconds."
- **Resetting**: "Reset can only be done once per hour. Please wait X seconds."

### Client-Side Events

Rate limit events are pushed to the client:

```javascript
// JavaScript can listen for rate_limited events
window.addEventListener("phx:rate_limited", (e) => {
  const { action, retry_after } = e.detail;
  console.log(`Rate limited on ${action}. Retry after ${retry_after} seconds.`);
});
```

This allows for:
- Disabling buttons temporarily
- Showing countdown timers
- Providing better user feedback

## Testing

### Running Tests

```bash
# Run all tests
mix test

# Run only rate limiting tests
mix test test/live_poll_web/rate_limiter_test.exs
mix test test/live_poll_web/plugs/rate_limit_plug_test.exs
mix test test/live_poll_web/live/poll_live_test.exs --only rate_limiting
```

### Test Coverage

Tests cover:
- ✅ Rate limits are enforced correctly
- ✅ Different actions have different limits
- ✅ Different clients have independent limits
- ✅ Rate limits reset after time window
- ✅ Error messages are displayed correctly
- ✅ Retry-after headers are set
- ✅ X-Forwarded-For handling for proxies

## Monitoring

### Metrics to Track

Consider adding metrics for:
- Number of rate-limited requests per action
- Most frequently rate-limited IPs
- Average retry-after times
- Legitimate users being rate-limited (false positives)

### Telemetry Integration

You can add telemetry events:

```elixir
# In RateLimiter.check_rate/2
:telemetry.execute(
  [:live_poll, :rate_limiter, :check],
  %{count: 1},
  %{action: action, result: :allowed}
)
```

## Security Considerations

### Defense in Depth

The two-layer approach provides:
1. **Application-level** - Stops attacks before they reach LiveView
2. **Action-level** - Protects specific expensive operations

### Distributed Systems

The current implementation uses ETS (in-memory storage):
- ✅ Fast and efficient
- ✅ No external dependencies
- ❌ Not shared across multiple nodes

For distributed deployments, consider:
- **Hammer.Backend.Redis** - Shared rate limits across nodes
- **Hammer.Backend.Mnesia** - Distributed Erlang database

### IP Spoofing

The implementation handles X-Forwarded-For headers but:
- Only use in production behind a trusted proxy
- Configure your proxy to set X-Forwarded-For correctly
- Consider additional validation of forwarded IPs

## Future Enhancements

### Potential Improvements

1. **CAPTCHA Integration**
   - Show CAPTCHA after repeated rate limit violations
   - Helps distinguish bots from legitimate users

2. **Adaptive Rate Limiting**
   - Adjust limits based on system load
   - Tighter limits during high traffic

3. **User-Based Limits**
   - Different limits for authenticated vs anonymous users
   - Premium users get higher limits

4. **Graceful Degradation**
   - Queue requests instead of rejecting them
   - Implement backoff strategies

5. **Admin Dashboard**
   - View current rate limit status
   - Manually reset limits for specific IPs
   - Whitelist/blacklist IPs

## Troubleshooting

### Common Issues

**Issue**: Legitimate users being rate limited
- **Solution**: Increase limits or time windows
- **Check**: Are multiple users sharing the same IP (NAT)?

**Issue**: Rate limits not working
- **Solution**: Ensure Hammer is started in application supervision tree
- **Check**: Is the Hammer backend configured correctly?

**Issue**: Tests failing intermittently
- **Solution**: Use unique client IDs in tests
- **Check**: Are tests running in parallel (async: true)?

## References

- [Hammer Documentation](https://hexdocs.pm/hammer/)
- [Phoenix LiveView Security](https://hexdocs.pm/phoenix_live_view/security-model.html)
- [OWASP Rate Limiting](https://owasp.org/www-community/controls/Blocking_Brute_Force_Attacks)

