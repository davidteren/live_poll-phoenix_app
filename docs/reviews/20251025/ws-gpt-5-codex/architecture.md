# Architecture & Design Patterns

## Application structure

- **Entry points** – `LivePoll.Application` supervises telemetry, database access, PubSub, and the web endpoint, following Phoenix defaults.@lib/live_poll/application.ex#1-30
- **Web interface** – `LivePollWeb` defines controller/component macros and imports, while `LivePollWeb.Router` exposes a single LiveView route at `/` under the browser pipeline.@lib/live_poll_web.ex#1-110 @lib/live_poll_web/router.ex#1-45
- **Domain modules** – The `LivePoll.Poll` namespace includes simple Ecto schemas (`Option`, `VoteEvent`) but lacks a context module; business rules live inside the LiveView, blending UI and domain concerns.@lib/live_poll/poll/option.ex#1-18 @lib/live_poll/poll/vote_event.ex#1-21 @lib/live_poll_web/live/poll_live.ex#11-436

## Data flow

1. **Initial load** – On mount, the LiveView fetches all options via `Repo.all/1`, calculates aggregates, and derives trend data from historical `vote_events`, assigning state directly to the socket.@lib/live_poll_web/live/poll_live.ex#11-43
2. **Voting** – `handle_event("vote")` increments the option via `Repo.update!`, persists a `VoteEvent`, and broadcasts a PubSub message consumed by all connected LiveViews to update charts and activity feeds.@lib/live_poll_web/live/poll_live.ex#45-71
3. **Trend capture** – A periodic `:capture_trend` message recomputes the full trend snapshot by scanning recent vote events and bucketing them into time series slices for chart consumption.@lib/live_poll_web/live/poll_live.ex#357-372 @lib/live_poll_web/live/poll_live.ex#509-615
4. **Seeding / reset** – Long-running event handlers orchestrate data resets, random option creation, and high-volume vote backfills, then broadcast results for LiveView refreshes.@lib/live_poll_web/live/poll_live.ex#152-299

## Real-time & PubSub usage

- **Topic** – All LiveViews subscribe to `"poll:updates"`. Voting, language additions, resets, and seeding emit event-specific tuples that each view handles to refresh state and charts.@lib/live_poll_web/live/poll_live.ex#9-436
- **Client updates** – Visual updates rely on `push_event/3` to trigger ECharts hooks (`PieChart`, `TrendChart`) that read JSON payloads and mutate charts without re-rendering HEEx markup.@lib/live_poll_web/live/poll_live.ex#329-401 @assets/js/charts.js#53-206

## Time-series processing

- **Backfill** – Seeding generates thousands of `VoteEvent` entries with randomized timestamps over the last hour, then rewrites `inserted_at` using direct SQL for chronological accuracy.@lib/live_poll_web/live/poll_live.ex#200-278
- **Bucketing** – Trend reconstruction computes bucket sizes based on the selected range, grouping events by rounded timestamps and carrying forward vote totals to build percentage snapshots for charts.@lib/live_poll_web/live/poll_live.ex#535-615
- **Scalability concerns** – Recomputing entire time windows on every refresh scales poorly as `vote_events` grows; an incremental approach or materialized views would reduce load.

## Separation of concerns

- **LiveView-centric logic** – The LiveView module handles CRUD, analytics, scheduling, and presentation, which complicates testing and reuse. Introducing a dedicated context (e.g., `LivePoll.Polls`) would isolate persistence and business rules while leaving the LiveView focused on state orchestration.
- **Front-end responsibilities** – ECharts hooks encapsulate chart rendering and respond to LiveView events, providing a clean integration point between Phoenix and the JS library, yet they duplicate logic (trend and percentage charts) that could be shared.

## Chart integration (ECharts)

- **Hook architecture** – Each chart is a LiveView hook that initializes an ECharts instance, listens for theme mutations, window resizes, and LiveView `push_event` payloads, ensuring smooth updates without re-rendering HEEx markup.@assets/js/charts.js#53-206
- **State persistence** – Hooks cache zoom state between updates and reapply it after data refreshes, preserving user interactions during live updates.@assets/js/charts.js#190-321
- **Customization** – Color schemes are hard-coded per language and theme; dynamic language additions fall back to a neutral grey, suggesting room for a palette service tied to the LiveView’s seeded languages.
