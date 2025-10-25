# Task: Fix Race Condition in Vote Counting

## Category
Security, Performance

## Priority
**CRITICAL** - Data corruption risk under concurrent access

## Description
The current vote counting implementation uses a read-modify-write pattern that causes race conditions under concurrent voting. Multiple users voting simultaneously can result in lost votes due to non-atomic updates. This is a critical data integrity issue that must be fixed immediately.

## Current State
```elixir
# lib/live_poll_web/live/poll_live.ex:85-93
def handle_event("vote", %{"id" => id}, socket) do
  option = Repo.get!(Option, id)
  {:ok, updated_option} = option
    |> Ecto.Changeset.change(votes: option.votes + 1)
    |> Repo.update()
  # This pattern reads the value, modifies it, then writes back
  # Between read and write, other votes can be lost
end
```

### Problem Scenario
1. User A reads option with 10 votes
2. User B reads option with 10 votes  
3. User A writes back 11 votes
4. User B writes back 11 votes
5. Result: 11 votes instead of 12 (one vote lost)

## Proposed Solution

### Immediate Fix - Atomic Increment
```elixir
# lib/live_poll_web/live/poll_live.ex
def handle_event("vote", %{"id" => id}, socket) do
  # Validate and parse ID first
  with {int_id, ""} <- Integer.parse(id),
       # Atomic increment with RETURNING clause
       {1, [updated_option]} <- from(o in Option, 
         where: o.id == ^int_id,
         select: o
       ) |> Repo.update_all([inc: [votes: 1]], returning: true) do
    
    # Create vote event with accurate count
    vote_event = %VoteEvent{
      option_id: updated_option.id,
      language: updated_option.text,
      votes_after: updated_option.votes,
      event_type: "vote",
      inserted_at: DateTime.utc_now()
    } |> Repo.insert!()
    
    # Update socket and broadcast
    options = socket.assigns.options
      |> Enum.map(fn opt ->
        if opt.id == updated_option.id, do: updated_option, else: opt
      end)
    
    PubSub.broadcast(LivePoll.PubSub, @topic, {:poll_update, %{
      id: updated_option.id,
      votes: updated_option.votes,
      language: updated_option.text,
      timestamp: DateTime.utc_now()
    }})
    
    {:noreply, assign(socket, options: options)}
  else
    _ -> 
      {:noreply, put_flash(socket, :error, "Invalid vote option")}
  end
end
```

### Long-term Solution - Context Module
```elixir
# lib/live_poll/polls.ex
defmodule LivePoll.Polls do
  import Ecto.Query
  alias LivePoll.Repo
  alias LivePoll.Polls.{Option, VoteEvent}
  
  @doc """
  Atomically cast a vote for an option, preventing race conditions
  """
  def cast_vote(option_id) when is_integer(option_id) do
    Repo.transaction(fn ->
      # Use SELECT ... FOR UPDATE to lock the row
      query = from(o in Option, where: o.id == ^option_id, lock: "FOR UPDATE")
      
      case Repo.one(query) do
        nil -> 
          Repo.rollback(:not_found)
        
        option ->
          # Atomic increment
          {1, [updated]} = from(o in Option, 
            where: o.id == ^option_id,
            select: o
          ) |> Repo.update_all([inc: [votes: 1]], returning: true)
          
          # Record event
          event = %VoteEvent{
            option_id: updated.id,
            language: updated.text,
            votes_after: updated.votes,
            event_type: "vote"
          } |> Repo.insert!()
          
          {:ok, updated, event}
      end
    end)
  end
  
  def cast_vote(_), do: {:error, :invalid_id}
end
```

## Requirements
1. ✅ Implement atomic vote increments using `Repo.update_all` with `inc`
2. ✅ Add proper ID validation before database operations
3. ✅ Handle error cases gracefully (invalid IDs, missing options)
4. ✅ Ensure vote events accurately reflect the new vote count
5. ✅ Update broadcasts to use the returned updated option
6. ✅ Add transaction wrapper for consistency
7. ✅ Create context function for reusability

## Definition of Done
1. **Code Implementation**
   - [ ] Atomic increment implemented in `handle_event("vote", ...)`
   - [ ] ID validation added before database operations
   - [ ] Error handling for invalid/missing options
   - [ ] Vote events use accurate `votes_after` value

2. **Tests**
   - [ ] Concurrency test proves no lost votes with 100+ concurrent users
   - [ ] Test validates atomic increments work correctly
   - [ ] Test confirms vote events have accurate counts
   - [ ] Error cases tested (invalid ID, missing option)
   
3. **Verification**
   ```elixir
   # Test file: test/live_poll/concurrency_test.exs
   test "handles 100 concurrent votes without losing updates" do
     option = create_option(votes: 0)
     
     tasks = for _ <- 1..100 do
       Task.async(fn -> Polls.cast_vote(option.id) end)
     end
     
     Task.await_many(tasks, 5000)
     
     updated = Repo.get!(Option, option.id)
     assert updated.votes == 100  # Must be exactly 100, not less
   end
   ```

4. **Quality Checks**
   - [ ] `mix test` passes all tests
   - [ ] `mix format` shows no issues
   - [ ] `mix credo` shows no warnings
   - [ ] Manual testing with rapid clicking shows accurate counts

## Branch Name
`fix/atomic-vote-increments`

## Dependencies
None - This is a standalone critical fix

## Estimated Complexity
**S (Small)** - 30 minutes to 1 hour

## Testing Instructions
1. Apply the fix to `poll_live.ex`
2. Run the concurrency test to verify no lost votes
3. Open multiple browser windows and vote rapidly
4. Verify vote counts are accurate and no votes are lost
5. Check vote_events table has accurate `votes_after` values

## Rollback Plan
If issues occur, revert to the original code temporarily while investigating. The race condition has existed since launch, so a brief rollback is acceptable while fixing any issues.

## Notes
- This is the most critical issue in the codebase as it directly affects data integrity
- The fix must be deployed immediately after testing
- Monitor vote counts closely after deployment for any anomalies
- Consider adding metrics/logging to track voting patterns
