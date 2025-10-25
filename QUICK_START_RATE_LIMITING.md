# Quick Start: Rate Limiting Implementation

## 🚀 Getting Started

### Step 1: Install Dependencies

```bash
mix deps.get
```

This will install the Hammer library (version 6.2) which provides the rate limiting functionality.

### Step 2: Compile the Project

```bash
mix compile
```

This will compile all the new modules:
- `LivePollWeb.RateLimiter`
- `LivePollWeb.RateLimitPlug`
- Updated `LivePollWeb.PollLive`

### Step 3: Run Tests

```bash
# Run all tests
mix test

# Or run specific test files
mix test test/live_poll_web/rate_limiter_test.exs
mix test test/live_poll_web/plugs/rate_limit_plug_test.exs
mix test test/live_poll_web/live/poll_live_test.exs
```

### Step 4: Start the Server

```bash
mix phx.server
```

Visit http://localhost:4000 to test the application.

## 🧪 Manual Testing

### Test 1: Vote Rate Limiting

1. Open the application in your browser
2. Click the "Vote" button for any language **11 times rapidly**
3. **Expected Result**: 
   - First 10 votes succeed
   - 11th vote shows error: "Too many votes! Please wait X seconds."
   - Vote count remains at 10

### Test 2: Add Language Rate Limiting

1. In the "Add New Language" input, add 6 languages quickly:
   - Type "Language1" → Click Add
   - Type "Language2" → Click Add
   - Type "Language3" → Click Add
   - Type "Language4" → Click Add
   - Type "Language5" → Click Add
   - Type "Language6" → Click Add
2. **Expected Result**:
   - First 5 languages are added
   - 6th language shows error: "Too many languages added. Please wait X seconds."

### Test 3: Seed Data Rate Limiting

1. Click the "Seed Data" button
2. Wait for seeding to complete
3. Click "Seed Data" again immediately
4. **Expected Result**:
   - First seed succeeds
   - Second seed shows error: "Seeding can only be done once per hour. Please wait X seconds."

### Test 4: Reset Votes Rate Limiting

1. Click the "Reset All" button
2. Click "Reset All" again immediately
3. **Expected Result**:
   - First reset succeeds
   - Second reset shows error: "Reset can only be done once per hour. Please wait X seconds."

### Test 5: Application-Level Rate Limiting

This is harder to test manually, but you can use a tool like `curl` or a browser extension:

```bash
# Make 101 requests rapidly (exceeds 100/minute limit)
for i in {1..101}; do
  curl http://localhost:4000/ &
done
```

**Expected Result**: Some requests will receive a 429 status code with "Rate limit exceeded" message.

## 📊 Current Rate Limits

| Action | Limit | Time Window |
|--------|-------|-------------|
| Vote | 10 | 1 minute |
| Add Language | 5 | 5 minutes |
| Seed Data | 1 | 1 hour |
| Reset Votes | 1 | 1 hour |
| HTTP Requests | 100 | 1 minute |

## 🔧 Adjusting Rate Limits

To change rate limits, edit `lib/live_poll_web/rate_limiter.ex`:

```elixir
@limits %{
  vote: {10, :timer.minutes(1)},        # Change to {20, :timer.minutes(1)} for 20/min
  add_language: {5, :timer.minutes(5)}, # Change to {10, :timer.minutes(5)} for 10/5min
  seed_data: {1, :timer.hours(1)},      # Keep at 1/hour
  reset_votes: {1, :timer.hours(1)},    # Keep at 1/hour
  default: {60, :timer.minutes(1)}      # Default for unknown actions
}
```

After changing, restart the server:
```bash
# Stop the server (Ctrl+C twice)
# Start again
mix phx.server
```

## 🐛 Troubleshooting

### Issue: "mix: command not found"

**Solution**: Ensure Elixir is installed and in your PATH.

```bash
# Check Elixir installation
elixir --version

# If not installed, install via:
# - macOS: brew install elixir
# - Ubuntu: apt-get install elixir
# - Windows: Download from https://elixir-lang.org/install.html
```

### Issue: Tests failing with "Hammer not started"

**Solution**: Ensure Hammer is configured in `config/config.exs`:

```elixir
config :hammer,
  backend:
    {Hammer.Backend.ETS,
     [expiry_ms: 60_000 * 60 * 24, cleanup_interval_ms: 60_000 * 10]}
```

### Issue: Rate limits not working

**Solution**: 
1. Check that `LivePollWeb.RateLimitPlug` is in the router pipeline
2. Verify Hammer dependency is installed: `mix deps.get`
3. Restart the server

### Issue: All requests being rate limited

**Solution**: 
1. Check if you're testing from the same IP/session
2. Wait for the time window to expire
3. Restart the server to clear ETS tables

## 📝 Files Changed

### New Files Created
- ✅ `lib/live_poll_web/rate_limiter.ex`
- ✅ `lib/live_poll_web/plugs/rate_limit_plug.ex`
- ✅ `test/live_poll_web/rate_limiter_test.exs`
- ✅ `test/live_poll_web/plugs/rate_limit_plug_test.exs`
- ✅ `docs/RATE_LIMITING.md`
- ✅ `RATE_LIMITING_IMPLEMENTATION.md`
- ✅ `QUICK_START_RATE_LIMITING.md` (this file)

### Files Modified
- ✅ `mix.exs` - Added Hammer dependency
- ✅ `config/config.exs` - Added Hammer configuration
- ✅ `lib/live_poll_web/endpoint.ex` - Added peer_data to socket
- ✅ `lib/live_poll_web/router.ex` - Added RateLimitPlug
- ✅ `lib/live_poll_web/live/poll_live.ex` - Added rate limiting to events
- ✅ `test/live_poll_web/live/poll_live_test.exs` - Added rate limiting tests

## ✅ Verification Checklist

Before considering the implementation complete, verify:

- [ ] `mix deps.get` runs successfully
- [ ] `mix compile` completes without errors
- [ ] `mix test` passes all tests
- [ ] Server starts with `mix phx.server`
- [ ] Vote rate limiting works (11th vote blocked)
- [ ] Add language rate limiting works (6th addition blocked)
- [ ] Seed data rate limiting works (2nd seed blocked)
- [ ] Reset votes rate limiting works (2nd reset blocked)
- [ ] Error messages are user-friendly
- [ ] Application remains responsive under load

## 🎯 Next Steps

1. **Run the tests** to ensure everything works
2. **Test manually** using the scenarios above
3. **Monitor in production** to adjust limits based on real usage
4. **Consider enhancements**:
   - Add CAPTCHA for repeated violations
   - Implement Redis backend for distributed systems
   - Add admin dashboard for monitoring
   - Create alerts for suspicious activity

## 📚 Additional Resources

- **Full Documentation**: See `docs/RATE_LIMITING.md`
- **Implementation Summary**: See `RATE_LIMITING_IMPLEMENTATION.md`
- **Hammer Documentation**: https://hexdocs.pm/hammer/
- **Phoenix LiveView Security**: https://hexdocs.pm/phoenix_live_view/security-model.html

## 🆘 Need Help?

If you encounter issues:

1. Check the troubleshooting section above
2. Review the test files for examples
3. Read the full documentation in `docs/RATE_LIMITING.md`
4. Check Hammer documentation for advanced configuration

---

**Implementation Status**: ✅ Complete and ready for testing

**Security Level**: 🔒 High - Two-layer defense against DoS attacks

**Test Coverage**: ✅ Comprehensive - Unit tests, integration tests, and manual test scenarios

