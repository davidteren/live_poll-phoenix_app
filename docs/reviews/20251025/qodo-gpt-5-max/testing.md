# LivePoll – Testing & Quality

This document reviews current test coverage and proposes a practical testing plan with concrete examples for LiveView interactions and domain logic.


## Current coverage

- test/test_helper.exs – ExUnit and SQL sandbox configured.
- test/support/conn_case.ex, data_case.ex – Standard helpers are present.
- No feature/integration tests for PollLive, seeding, or trend calculations exist in test/.

Conclusion: Minimal coverage. Critical paths are currently untested.


## Critical untested paths

1. Live interactions
   - Voting flow (button click increments vote and updates pie chart data).
   - Add language (input + submit creates option and updates list).
   - Reset all (clears events and votes to zero).
   - Change time range (push_event for trend chart with expected payload).

2. Trend calculation
   - Bucketing logic for 5m, 1h, 12h, 24h.
   - Carry-forward when buckets have no events.
   - Correct percentage computations and max snapshot limits.

3. Seeding workflow
   - Modal visibility while seeding.
   - Data volume and distribution sanity checks (optional, timeboxed tests).

4. Error handling
   - Invalid IDs/ranges handled gracefully (no crash, flash error if implemented).


## Recommended test cases

### LiveView tests (Phoenix.LiveViewTest)

- Setup: use LivePollWeb.ConnCase, async: false. Create options via Repo in setup.

1) Renders initial state
- Visit "/" and assert presence of key elements:
  - Buttons: Seed Data, Reset All.
  - Trend chart container: #trend-chart.
  - Pie chart container: #pie-chart.
  - Stats widgets show zeros when empty.

2) Vote increments
- Insert an option (e.g., "Elixir").
- Mount the LiveView, click the Vote button for that option:
  - view |> element("button[phx-click=vote][phx-value-id=#{id}]") |> render_click()
  - Assert the option vote count increments in the rendered HTML.
  - Optionally assert a push_event for update-pie-chart using assert_patch/assert_hook? For push_event, use Phoenix.LiveViewTest.with_target? Alternatively, verify text and percentages updated.

3) Add language
- Submit the add language form: render_submit(form_selector, %{name: "Rust"}).
- Assert new language appears with 0 votes.
- Assert duplication attempts are handled (after adding uniqueness constraints).

4) Reset all
- Seed some votes; click Reset All.
- Assert all options' votes show zero; recent activity cleared.

5) Change time range
- Click time range button for 5m/12h/24h; assert no crash and push_event occurs.
  - You can instrument the hook or assert that assigns.time_range changed in the LiveView by fetching HTML and verifying active button class toggles.

Note: Prefer asserting presence/absence of key elements and classes rather than literal text.


### Domain tests for trend logic

- Move build_trend_data_from_events/1 to a domain module (e.g., LivePoll.Poll.Trends) for unit testing.
- Seed small sets of VoteEvent with fixed timestamps and verify:
  - Buckets computed correctly for a given range.
  - Carry-forward when no events in a bucket.
  - Percentages sum to ~100% when there are votes.
  - Snapshot count respects max_snapshots for each range.


### Seeding tests

- Wrap seeding into a function returning {:ok, info} with counts.
- Test that after seeding, Option counts match aggregated VoteEvent rows for each option.
- Test modal visibility (assign :seeding_progress.show) toggles around seeding messages.


## Tooling and guidance

- Run tests with mix test (or the project alias mix precommit which compiles with warnings as errors, formats, and runs tests).
- Use LazyHTML (already included) to assert against specific selectors when you need to introspect complex HTML.


## Example skeletons

LiveView test outline:

  test "vote increments", %{conn: conn} do
    opt = Repo.insert!(%Option{text: "Elixir", votes: 0})
    {:ok, view, _html} = live(conn, "/")

    view
    |> element("button[phx-click=vote][phx-value-id=#{opt.id}]")
    |> render_click()

    assert has_element?(view, "div", "Elixir")
    # Optionally re-fetch HTML and assert count increased
  end

Trend logic outline (after extraction):

  test "carry-forward across empty buckets" do
    # Insert events at t0, t0+60s, query 5m range and assert snapshots fill gaps
  end


## Roadmap

1. Extract trend logic and implement unit tests.
2. Add core LiveView feature tests for vote/add/reset/time-range.
3. Add error-path tests (invalid input handling).
4. Add seeding integration tests with reduced volume (e.g., 100 votes) for speed.
