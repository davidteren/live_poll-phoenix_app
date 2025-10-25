# Testing & Quality

## Existing coverage

- **LiveView integration tests** – `LivePollWeb.PollLiveTest` exercises mount, voting, reset flows, SVG rendering, and activity feed markup, providing strong confidence in UI behavior.@test/live_poll_web/live/poll_live_test.exs#1-276
- **Controller scaffolding** – Generated tests for error pages and the static page controller exist but add little value for core poll functionality.@test/live_poll_web/controllers/page_controller_test.exs#1-20 @test/live_poll_web/controllers/error_html_test.exs#1-22

## Gaps & risks

- **Context-less domain logic** – Because business rules live inside the LiveView, there are no unit-level tests for seeding, vote aggregation, or trend bucketing. A context module would enable focused tests around data manipulation.@lib/live_poll_web/live/poll_live.ex#152-615
- **Concurrency edge cases** – No tests ensure idempotency of `add_language` or concurrent voting consistency (e.g., two clients voting simultaneously). Race conditions could surface under load.@lib/live_poll_web/live/poll_live.ex#98-118 @lib/live_poll_web/live/poll_live_test.exs#42-82
- **Time-series accuracy** – The trend reconstruction logic lacks dedicated tests to validate bucket boundaries, state carry-over, and percentage rounding.
- **Seeding workflow** – No tests cover `:perform_seeding`, leaving the large data generation path unverified.

## Recommendations

1. Introduce a `LivePoll.Polls` context and add unit tests for option creation, vote recording, and trend aggregation (including edge buckets and empty datasets).
2. Add LiveView tests for `add_language` conflicts and concurrency by simulating simultaneous submissions with `Task.async_stream`.
3. Validate `build_trend_data_from_events/1` via isolated tests that seed controlled vote events and assert bucketed output.
4. Create integration tests for the seeding flow, using `capture_log` to manage output and asserting final vote totals and option counts.
5. Add regression tests for JSON payloads sent to chart hooks, ensuring data shape remains stable as the front-end evolves.
