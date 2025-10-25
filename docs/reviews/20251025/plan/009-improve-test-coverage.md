# Task: Improve Test Coverage from 25% to 80%+

## Category
Testing, Quality

## Priority
**MEDIUM** - Current 25% coverage poses high regression risk

## Description
The application has minimal test coverage (~25%), missing entire categories of tests including concurrency, integration, performance, and security testing. This makes the codebase fragile and risky to modify. Comprehensive test suite must be added.

## Current State
```elixir
# Only basic LiveView tests exist
# No context tests (context doesn't exist yet)
# No concurrency tests for race conditions
# No integration tests
# No security tests
# Tests use anti-patterns like timer.sleep
```

### Coverage Gaps
- Business logic: 0% (no context to test)
- Concurrency: 0% (race conditions untested)
- Integration: 0% (multi-client scenarios untested)
- Security: 0% (no validation tests)
- Performance: 0% (no load tests)

## Proposed Solution

### Phase 1: Critical Concurrency Tests
```elixir
# test/live_poll/concurrency_test.exs
defmodule LivePoll.ConcurrencyTest do
  use LivePoll.DataCase, async: false
  alias LivePoll.Polls
  
  describe "concurrent voting" do
    @tag :critical
    test "handles 100 concurrent votes without losing updates" do
      option = insert(:option, votes: 0)
      
      # Simulate 100 concurrent votes
      tasks = for _ <- 1..100 do
        Task.async(fn ->
          Polls.cast_vote(option.id)
        end)
      end
      
      results = Task.await_many(tasks, 5000)
      
      # All votes should succeed
      assert Enum.all?(results, fn
        {:ok, _, _} -> true
        _ -> false
      end)
      
      # Final count must be exactly 100
      updated = Polls.get_option!(option.id)
      assert updated.votes == 100
    end
    
    @tag :critical
    test "atomic increments prevent duplicate counts" do
      option = insert(:option, votes: 0)
      parent = self()
      
      # Spawn processes to vote simultaneously
      for i <- 1..50 do
        spawn(fn ->
          {:ok, result, _} = Polls.cast_vote(option.id)
          send(parent, {:voted, i, result.votes})
        end)
      end
      
      # Collect all vote counts
      counts = for _ <- 1..50 do
        receive do
          {:voted, _i, count} -> count
        after
          1000 -> flunk("Timeout waiting for vote")
        end
      end
      
      # Each count should be unique (1,2,3...50)
      assert Enum.sort(counts) == Enum.to_list(1..50)
    end
    
    test "handles concurrent language additions" do
      tasks = for i <- 1..10 do
        Task.async(fn ->
          Polls.add_language("Language #{i}")
        end)
      end
      
      results = Task.await_many(tasks, 5000)
      
      # All should succeed
      assert Enum.all?(results, fn
        {:ok, _} -> true
        _ -> false
      end)
      
      # Verify all languages created
      options = Polls.list_options()
      names = Enum.map(options, & &1.text)
      
      for i <- 1..10 do
        assert "Language #{i}" in names
      end
    end
  end
end
```

### Phase 2: Context/Business Logic Tests
```elixir
# test/live_poll/polls_test.exs
defmodule LivePoll.PollsTest do
  use LivePoll.DataCase
  alias LivePoll.Polls
  
  describe "options" do
    test "list_options/0 returns all options sorted by id" do
      opt1 = insert(:option, id: 2)
      opt2 = insert(:option, id: 1)
      
      assert [^opt2, ^opt1] = Polls.list_options()
    end
    
    test "get_option!/1 returns option with given id" do
      option = insert(:option)
      assert Polls.get_option!(option.id).id == option.id
    end
    
    test "get_option/1 returns nil for invalid id" do
      assert is_nil(Polls.get_option(999999))
    end
  end
  
  describe "add_language/1" do
    test "creates option with valid name" do
      assert {:ok, option} = Polls.add_language("Rust")
      assert option.text == "Rust"
      assert option.votes == 0
    end
    
    test "rejects duplicate language names" do
      {:ok, _} = Polls.add_language("Go")
      assert {:error, message} = Polls.add_language("Go")
      assert message =~ "already exists"
    end
    
    test "rejects invalid characters" do
      assert {:error, _} = Polls.add_language("<script>")
      assert {:error, _} = Polls.add_language("'; DROP TABLE")
    end
    
    test "enforces length limits" do
      assert {:error, _} = Polls.add_language("")
      assert {:error, _} = Polls.add_language(String.duplicate("a", 51))
    end
    
    test "normalizes whitespace" do
      {:ok, option} = Polls.add_language("  Ruby  on  Rails  ")
      assert option.text == "Ruby On Rails"
    end
  end
  
  describe "cast_vote/1" do
    test "increments vote count" do
      option = insert(:option, votes: 5)
      assert {:ok, updated, _event} = Polls.cast_vote(option.id)
      assert updated.votes == 6
    end
    
    test "creates vote event with correct data" do
      option = insert(:option, votes: 10)
      {:ok, _option, event} = Polls.cast_vote(option.id)
      
      assert event.option_id == option.id
      assert event.votes_after == 11
      assert event.event_type == "vote"
    end
    
    test "handles invalid option id" do
      assert {:error, :option_not_found} = Polls.cast_vote(999999)
      assert {:error, :invalid_id} = Polls.cast_vote("invalid")
      assert {:error, :invalid_id} = Polls.cast_vote(-1)
    end
  end
  
  describe "calculate_percentages/1" do
    test "calculates correct percentages" do
      opt1 = build(:option, text: "Python", votes: 60)
      opt2 = build(:option, text: "JavaScript", votes: 40)
      
      percentages = Polls.calculate_percentages([opt1, opt2])
      
      assert percentages["Python"] == 60.0
      assert percentages["JavaScript"] == 40.0
    end
    
    test "handles zero total votes" do
      opt1 = build(:option, text: "Ruby", votes: 0)
      opt2 = build(:option, text: "Elixir", votes: 0)
      
      percentages = Polls.calculate_percentages([opt1, opt2])
      
      assert percentages["Ruby"] == 0.0
      assert percentages["Elixir"] == 0.0
    end
    
    test "rounds to one decimal place" do
      opt1 = build(:option, votes: 1)
      opt2 = build(:option, votes: 2)
      
      percentages = Polls.calculate_percentages([opt1, opt2])
      values = Map.values(percentages)
      
      assert Enum.all?(values, fn v ->
        Float.round(v, 1) == v
      end)
    end
  end
  
  describe "reset_all_votes/0" do
    test "resets all vote counts to zero" do
      opt1 = insert(:option, votes: 10)
      opt2 = insert(:option, votes: 20)
      
      assert {:ok, _} = Polls.reset_all_votes()
      
      assert Polls.get_option!(opt1.id).votes == 0
      assert Polls.get_option!(opt2.id).votes == 0
    end
    
    test "deletes all vote events" do
      insert_list(10, :vote_event)
      
      assert {:ok, _} = Polls.reset_all_votes()
      assert Polls.list_vote_events() == []
    end
    
    test "creates reset events" do
      options = insert_list(3, :option)
      
      {:ok, _} = Polls.reset_all_votes()
      
      events = Polls.list_vote_events()
      assert length(events) == 3
      assert Enum.all?(events, & &1.event_type == "reset")
    end
  end
end
```

### Phase 3: Integration Tests
```elixir
# test/live_poll_web/integration_test.exs
defmodule LivePollWeb.IntegrationTest do
  use LivePollWeb.ConnCase
  import Phoenix.LiveViewTest
  
  describe "multi-client voting" do
    @tag :integration
    test "updates propagate to all connected clients", %{conn: conn} do
      # Connect multiple clients
      {:ok, view1, _} = live(conn, "/")
      {:ok, view2, _} = live(build_conn(), "/")
      {:ok, view3, _} = live(build_conn(), "/")
      
      # Initial state
      assert render(view1) =~ "0 votes"
      assert render(view2) =~ "0 votes"
      assert render(view3) =~ "0 votes"
      
      # Client 1 votes
      view1
      |> element("[data-testid='vote-elixir']")
      |> render_click()
      
      # All clients should see update
      assert_push_event(view1, "update-pie-chart", %{})
      assert_push_event(view2, "update-pie-chart", %{})
      assert_push_event(view3, "update-pie-chart", %{})
      
      # Verify counts updated
      assert render(view1) =~ "1 vote"
      assert render(view2) =~ "1 vote"
      assert render(view3) =~ "1 vote"
    end
    
    @tag :integration
    test "handles rapid voting from multiple clients", %{conn: conn} do
      views = for _ <- 1..10 do
        {:ok, view, _} = live(build_conn(), "/")
        view
      end
      
      # Each view votes 5 times rapidly
      tasks = Enum.flat_map(views, fn view ->
        for _ <- 1..5 do
          Task.async(fn ->
            view
            |> element("[data-testid='vote-python']")
            |> render_click()
          end)
        end
      end)
      
      Task.await_many(tasks, 10000)
      
      # Verify total is correct (10 clients * 5 votes = 50)
      {:ok, view, _} = live(conn, "/")
      assert render(view) =~ "50 votes"
    end
  end
  
  describe "real-time features" do
    @tag :integration
    test "trend chart updates in real-time", %{conn: conn} do
      {:ok, view, _} = live(conn, "/")
      
      # Vote and check for trend update
      view
      |> element("[data-testid='vote-rust']")
      |> render_click()
      
      assert_push_event(view, "update-trend-chart", %{data: data})
      assert is_list(data)
    end
    
    test "recent activity updates live", %{conn: conn} do
      {:ok, view, _} = live(conn, "/")
      
      refute render(view) =~ "voted for Elixir"
      
      view
      |> element("[data-testid='vote-elixir']")
      |> render_click()
      
      # Should see in recent activity
      assert render(view) =~ "voted for Elixir"
    end
  end
end
```

### Phase 4: Test Infrastructure
```elixir
# test/support/factory.ex
defmodule LivePoll.Factory do
  use ExMachina.Ecto, repo: LivePoll.Repo
  
  def option_factory do
    %LivePoll.Polls.Option{
      text: sequence(:text, &"Language #{&1}"),
      votes: 0
    }
  end
  
  def vote_event_factory do
    option = build(:option)
    %LivePoll.Polls.VoteEvent{
      option_id: option.id,
      language: option.text,
      votes_after: sequence(:votes_after, & &1),
      event_type: "vote",
      inserted_at: DateTime.utc_now()
    }
  end
  
  def with_votes(option, count) do
    %{option | votes: count}
    |> insert()
    |> tap(fn opt ->
      insert(:vote_event, option_id: opt.id, votes_after: count)
    end)
  end
end

# test/support/test_helpers.ex
defmodule LivePoll.TestHelpers do
  import Phoenix.LiveViewTest
  
  def vote_for(view, language) do
    view
    |> element("[data-testid='vote-#{String.downcase(language)}']")
    |> render_click()
  end
  
  def add_language(view, name) do
    view
    |> form("#language-form", %{name: name})
    |> render_submit()
  end
  
  def get_vote_count(view, language) do
    html = render(view)
    case Regex.run(~r/#{language}.*?(\d+)\s+votes?/, html) do
      [_, count] -> String.to_integer(count)
      _ -> 0
    end
  end
  
  def assert_broadcast_received(topic, message) do
    assert_receive {^topic, ^message}, 1000
  end
end
```

### Phase 5: Performance & Security Tests
```elixir
# test/live_poll/performance_test.exs
defmodule LivePoll.PerformanceTest do
  use LivePoll.DataCase, async: false
  
  @tag :performance
  @tag timeout: 60_000
  test "handles 1000 votes efficiently" do
    option = insert(:option)
    
    {time, _} = :timer.tc(fn ->
      tasks = for _ <- 1..1000 do
        Task.async(fn -> Polls.cast_vote(option.id) end)
      end
      Task.await_many(tasks, 30_000)
    end)
    
    # Should complete in under 5 seconds
    assert time < 5_000_000
    
    # Verify count
    assert Polls.get_option!(option.id).votes == 1000
  end
  
  @tag :performance
  test "seeding scales linearly" do
    insert_list(10, :option)
    
    times = for count <- [100, 1000, 10_000] do
      {time, _} = :timer.tc(fn ->
        Polls.seed_votes(count)
      end)
      Repo.delete_all(VoteEvent)
      time
    end
    
    # Verify linear scaling
    [t1, t2, t3] = times
    assert t2 / t1 < 15  # ~10x
    assert t3 / t2 < 15  # ~10x
  end
end

# test/live_poll_web/security_test.exs
defmodule LivePollWeb.SecurityTest do
  use LivePollWeb.ConnCase
  
  describe "input validation" do
    test "prevents XSS in language names", %{conn: conn} do
      {:ok, view, _} = live(conn, "/")
      
      add_language(view, "<script>alert('xss')</script>")
      
      html = render(view)
      refute html =~ "<script>"
      assert html =~ "Invalid"
    end
    
    test "handles SQL injection attempts", %{conn: conn} do
      {:ok, view, _} = live(conn, "/")
      
      add_language(view, "'; DROP TABLE options; --")
      
      # Should reject, not crash
      assert render(view) =~ "Invalid"
      
      # Tables should still exist
      assert Polls.list_options() |> is_list()
    end
  end
end
```

## Requirements
1. ✅ Add critical concurrency tests for race conditions
2. ✅ Create comprehensive context/business logic tests
3. ✅ Add integration tests for multi-client scenarios
4. ✅ Implement security tests for validation
5. ✅ Add performance benchmarks
6. ✅ Create test factories and helpers
7. ✅ Achieve 80%+ test coverage

## Definition of Done
1. **Test Coverage Goals**
   - [ ] Overall coverage >80%
   - [ ] Context functions 100% covered
   - [ ] Critical paths 100% covered
   - [ ] Concurrency tests passing

2. **Test Categories**
   - [ ] Unit tests for all public functions
   - [ ] Integration tests for workflows
   - [ ] Concurrency tests for race conditions
   - [ ] Security tests for validation
   - [ ] Performance tests for scaling

3. **Quality Metrics**
   ```bash
   # Run coverage report
   mix coveralls.html
   
   # Coverage should show:
   - lib/live_poll/polls.ex: 100%
   - lib/live_poll_web/live/poll_live.ex: >80%
   - Overall: >80%
   ```

4. **CI/CD Integration**
   - [ ] Tests run automatically on push
   - [ ] Coverage reports generated
   - [ ] Failing tests block merge
   - [ ] Performance tests run nightly

## Branch Name
`test/comprehensive-test-suite`

## Dependencies
- Task 004 (Extract Context) - Need context to test
- Task 001 (Fix Race Condition) - Need fix to test

## Estimated Complexity
**L (Large)** - 2-3 days

## Testing Instructions
1. Install test dependencies (ExMachina, etc.)
2. Run individual test files to verify
3. Run full test suite: `mix test`
4. Generate coverage: `mix coveralls.html`
5. Open coverage report in browser
6. Verify all critical paths covered
7. Run performance tests separately

## Test Execution Strategy
```bash
# Run all tests
mix test

# Run specific categories
mix test --only unit
mix test --only integration
mix test --only critical
mix test --only performance
mix test --only security

# Run with coverage
mix coveralls
mix coveralls.detail
mix coveralls.html

# Run specific file
mix test test/live_poll/polls_test.exs

# Run with seed for reproducibility
mix test --seed 12345
```

## Notes
- Start with critical concurrency tests
- Use factories for consistent test data
- Avoid sleep/timer in tests
- Use async: false for integration tests
- Tag slow tests appropriately
- Consider property-based testing for complex logic
