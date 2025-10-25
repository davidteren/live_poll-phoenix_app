# Qodo Merge Configuration Validation Checklist

## Purpose
This PR validates that Qodo Merge detects all 10 anti-patterns configured in the Wiki.

## Test Files

### `lib/live_poll_web/live/qodo_validation_live.ex`
Intentionally contains ALL 10 configured anti-patterns

### `test/live_poll_web/live/qodo_validation_live_test.exs`
Contains testing anti-patterns

## Expected Qodo Merge Findings

### ✅ Anti-Pattern #1: Race Condition (CRITICAL)
**Location**: `qodo_validation_live.ex:72-85`
```elixir
option = Repo.get!(Option, id)
updated_option = 
  option
  |> Ecto.Changeset.change(votes: option.votes + 1)
  |> Repo.update!()
```
**Expected Detection**: Qodo should flag non-atomic read-modify-write pattern
**Recommended Fix**: Use `Repo.update_all([inc: [votes: 1]])`

---

### ✅ Anti-Pattern #2: Business Logic in LiveView (HIGH)
**Location**: Multiple places - `load_data/1`, `handle_event/3` functions
```elixir
options = Repo.all(from o in Option, order_by: [asc: o.id])
Repo.insert!(%VoteEvent{...})
```
**Expected Detection**: Direct database access from LiveView
**Recommended Fix**: Extract to `LivePoll.Polls` context module

---

### ✅ Anti-Pattern #3: Memory Issue - Loading All Records (HIGH)
**Location**: `qodo_validation_live.ex:48-54`
```elixir
events = Repo.all(
  from e in VoteEvent,
  where: e.inserted_at >= ^DateTime.add(DateTime.utc_now(), -3600),
  preload: :option,
  order_by: [desc: e.inserted_at]
)
```
**Expected Detection**: Loading all events causes 400MB RAM @ 1000 users
**Recommended Fix**: Add pagination or aggregate in database

---

### ✅ Anti-Pattern #4: Unnecessary Preload (MEDIUM)
**Location**: `qodo_validation_live.ex:51`
```elixir
preload: :option  # Option data never used
```
**Expected Detection**: Wasteful preload when association not accessed
**Recommended Fix**: Remove preload

---

### ✅ Anti-Pattern #5: Individual Inserts vs Batch (HIGH)
**Location**: `qodo_validation_live.ex:119-146`
```elixir
for _i <- 1..count do
  vote_event = Repo.insert!(%VoteEvent{...})
  Ecto.Adapters.SQL.query!(Repo, "UPDATE...", [...])
  Repo.update_all(inc: [votes: 1])
end
```
**Expected Detection**: Loop with 3 DB operations per iteration (20,000+ ops for 10k votes)
**Recommended Fix**: Use `Repo.insert_all` with precomputed values

---

### ✅ Anti-Pattern #6: Bang Functions in Handlers (HIGH)
**Location**: Multiple - lines 72, 75, 82, 100, 122, 137, 158
```elixir
def handle_event("vote", %{"id" => id}, socket) do
  option = Repo.get!(Option, id)  # Crashes on invalid ID
  Repo.update!()                  # Crashes on error
end
```
**Expected Detection**: Bang functions crash entire LiveView
**Recommended Fix**: Use non-bang versions with proper error handling

---

### ✅ Anti-Pattern #7: No Error Handling (HIGH)
**Location**: All event handlers
```elixir
def handle_event("vote", %{"id" => id}, socket) do
  option = Repo.get!(Option, id)
  # No case statement, no error handling
end
```
**Expected Detection**: Missing error handling and user feedback
**Recommended Fix**: Add case statements with flash messages

---

### ✅ Anti-Pattern #8: Missing Input Validation (MEDIUM)
**Location**: `qodo_validation_live.ex:98-105`
```elixir
def handle_event("add_language", %{"name" => name}, socket) do
  Repo.insert!(%Option{
    text: name,  # No validation - XSS risk
    votes: 0
  })
end
```
**Expected Detection**: No length limits, format validation, or XSS protection
**Recommended Fix**: Use changeset with validations and sanitization

---

### ✅ Anti-Pattern #9: Hardcoded Values (LOW)
**Location**: `qodo_validation_live.ex:19-20`
```elixir
@update_interval 5000
@max_votes 10000
```
**Expected Detection**: Magic numbers without explanation
**Recommended Fix**: Move to configuration or add clear documentation

---

### ✅ Anti-Pattern #10: Functions >50 Lines (MEDIUM)
**Location**: `handle_event("seed_votes", ...)` and `handle_event("reset_all", ...)`
**Expected Detection**: Functions exceed 50 line limit
**Recommended Fix**: Extract to smaller functions or context module

---

## Testing Anti-Patterns

### ✅ timer.sleep Usage (MEDIUM)
**Location**: `qodo_validation_live_test.exs:24, 60`
```elixir
:timer.sleep(100)
```
**Expected Detection**: Flaky test pattern
**Recommended Fix**: Use `assert_receive` with timeout

### ✅ No Concurrent Operation Tests (CRITICAL)
**Location**: `qodo_validation_live_test.exs:31-43`
**Expected Detection**: Missing race condition test
**Recommended Fix**: Add test with 100 concurrent votes

### ✅ No Error Path Tests (HIGH)
**Location**: `qodo_validation_live_test.exs:46-55`
**Expected Detection**: Error handling not tested
**Recommended Fix**: Test invalid inputs and failure scenarios

### ✅ No Validation Tests (MEDIUM)
**Location**: `qodo_validation_live_test.exs:58-69`
**Expected Detection**: XSS and injection not tested
**Recommended Fix**: Add security-focused tests

---

## Success Criteria

Qodo Merge should identify at least:
- ✅ **8-10 Critical/High issues** (race condition, memory, architecture)
- ✅ **Specific suggestions** for atomic operations
- ✅ **Context extraction recommendations**
- ✅ **Performance warnings** about loading all records
- ✅ **Security concerns** about input validation
- ✅ **Testing improvements** about timer.sleep

## How to Verify

1. Wait for Qodo Merge to comment on this PR
2. Check that it identifies the anti-patterns listed above
3. Verify it provides code examples for fixes
4. Confirm severity ratings match expectations

## Notes

- This LiveView should NEVER be used in production
- All anti-patterns are intentional for validation purposes
- After validation, these files should be removed
- The configuration is working if Qodo catches 8+ patterns

## Configuration Reference

Wiki: https://github.com/davidteren/live_poll-phoenix_app/wiki/.pr_agent.toml
