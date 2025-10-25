# Performance & Optimization

## Database workload

- **Trend recomputation** – `build_trend_data_from_events/1` scans every vote event in the selected window, buckets them in Elixir, and rebuilds cumulative state on each interval. With larger datasets this becomes CPU heavy and adds DB pressure. Consider precomputing rollups or using windowed SQL queries with `SUM OVER` to offload aggregation to Postgres.@lib/live_poll_web/live/poll_live.ex#509-615
- **Seeding process** – The seeding handler deletes and reinserts options and 10k+ vote events synchronously, executing thousands of individual inserts and `UPDATE` statements from the LiveView process. Batched inserts, `Repo.insert_all`, and background Tasks would dramatically reduce lock contention and response time.@lib/live_poll_web/live/poll_live.ex#187-286
- **Repeated full reloads** – After each PubSub event (`:poll_reset`, `:data_seeded`, `:language_added`) the LiveView re-fetches all options, re-sorts them, and rebuilds trend data, duplicating work already performed earlier. Cache totals or stream updates incrementally to avoid redundant queries.@lib/live_poll_web/live/poll_live.ex#357-433

## Application layer

- **LiveView scheduling** – Two `:timer.send_interval` calls run every five seconds, both of which perform DB queries. Aligning their cadence or coalescing them into a single periodic task would reduce wake-ups and keep the socket responsive under load.@lib/live_poll_web/live/poll_live.ex#36-40
- **Blocking handlers** – Long-running handlers (`:perform_seeding`) block the LiveView mailbox, preventing other messages from being processed. Offload heavy tasks to supervised processes and stream updates via `handle_info` callbacks instead.@lib/live_poll_web/live/poll_live.ex#152-299
- **Percentage calculations** – `calculate_percentages/2` recomputes percentages on demand but returns maps for every call. Memoize results alongside options or compute once per update to lower GC churn.@lib/live_poll_web/live/poll_live.ex#464-477

## Front-end & streaming

- **Chart data volume** – Trend snapshots can reach 144 points per language (24h range). Sending entire datasets on every update pushes large JSON payloads through `push_event/3`. Incremental updates or LiveView streams would reduce payload size and latency.@lib/live_poll_web/live/poll_live.ex#357-401
- **Hook reinitialization** – ECharts hooks recreate options for every update, which is necessary today but becomes costly with many series. Investigate incremental `setOption` updates with `notMerge: false` to reuse existing chart state.@assets/js/charts.js#214-364

## Seeding & seeds script

- **Seed script simplicity** – `priv/repo/seeds.exs` inserts only four options, while runtime seeding handles realistic workloads. Align offline seeds with runtime expectations (e.g., using `Repo.insert_all`) to speed up test database preparation.@priv/repo/seeds.exs#13-19
- **Transaction usage** – Neither the seed script nor runtime seeding wrap operations in transactions, risking partial state if an error occurs mid-process. Encapsulate bulk operations in `Repo.transaction/1` to maintain data integrity and reduce overhead from repeated DB round trips.
