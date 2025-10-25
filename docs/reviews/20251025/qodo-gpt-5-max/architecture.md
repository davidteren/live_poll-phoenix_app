# LivePoll – Architecture & Design Patterns

This document describes the overall application structure, data flow, real-time update strategy, time-series event model, and chart integration approach.


## High-level structure

- Phoenix application with a single main LiveView (PollLive) that renders the poll UI and orchestrates all interactions.
- Contexts and schemas under lib/live_poll/poll/:
  - Option – poll option (language) with current vote counter.
  - VoteEvent – immutable time-series event capturing each vote with timestamp and cumulative count after the event.
- PubSub (LivePoll.PubSub) – broadcasts updates to all connected LiveViews for real-time UI synchronization.
- Assets – Two JS hooks (PieChart, TrendChart) using Apache ECharts; Tailwind CSS v4 for styling; vendor plugins (heroicons, daisyUI).


## Request and data flow

1. Client connects to LiveView (GET / → PollLive, see router).
2. mount/3 subscribes to topic "poll:updates" and loads:
   - options: Repo.all(Option) sorted by id.
   - total_votes: sum(options.votes).
   - sorted_options: options sorted by votes desc (used for legend/pie mapping).
   - trend_data: build_trend_data_from_events(60) – time-series snapshots for last hour.
3. Live timers:
   - Every 5s, :update_stats – compute votes_per_minute from last_minute_votes.
   - Every 5s, :capture_trend – rebuild trend snapshots and push updates to JS hook.
4. Interactions:
   - vote(id): increment option votes (currently read-modify-write), insert VoteEvent, broadcast {:poll_update, ...} via PubSub.
   - reset_votes: clear VoteEvent and set all Option.votes=0, broadcast {:poll_reset}.
   - add_language(name): insert Option if not exists, broadcast {:language_added}.
   - change_time_range(range): recompute trend data and push update to JS.
   - seed_data: async process to backfill ~10k VoteEvent rows over the last hour with weighted distributions, then broadcast {:data_seeded}.

5. Update propagation:
   - On PubSub messages (:poll_update, :poll_reset, :data_seeded, :language_added), each LiveView instance updates assigns and pushes chart updates via push_event.


## PubSub implementation

- Topic: "poll:updates".
- Broadcasts:
  - {:poll_update, %{id, votes, language, timestamp}}
  - {:poll_reset, %{timestamp}}
  - {:data_seeded, %{timestamp}}
  - {:language_added, %{name}}
- mount subscribes; handle_info patterns update assigns. This is a straightforward, scalable fan-out for read-mostly UIs.


## Time-series event system

- Table vote_events with fields: option_id (FK), language (string), votes_after (int), event_type (vote|seed|reset), inserted_at (ts, no updated_at).
- Indexes on option_id, inserted_at, language for query performance.
- build_trend_data_from_events(minutes_back):
  - Loads events after cutoff, orders by inserted_at.
  - Optionally preloaded option – can be dropped since not used.
  - Groups events by time bucket (5s, 30s, 5m, 10m depending on range).
  - Builds a complete list of bucket timestamps from cutoff to now.
  - Carries forward state (vote_counts per language) when no events in a bucket to produce flat lines.
  - Computes percentages per bucket snapshot.
  - Returns at most max_snapshots per range (e.g., 120 for last hour).

This approach yields smooth, consistent time-series lines while preserving temporal fidelity.


## Separation of concerns

- LiveView currently contains analytics logic for trend building. For maintainability and testability, consider extracting this into a dedicated module (e.g., LivePoll.Poll.Trends) with pure functions operating on events to produce snapshots.


## Chart integration (ECharts + LiveView hooks)

- PieChart hook:
  - Mounted on a container with phx-update="ignore".
  - Receives data updates via push_event("update-pie-chart", %{data: ...}).
  - Recreates options and calls chart.setOption.

- TrendChart hook:
  - Mounted with phx-update="ignore".
  - Receives push_event("update-trend-chart", %{trendData, languages}).
  - Maintains a zoomState by listening to ECharts dataZoom events and re-applies start/end on updates.
  - Theme-aware via MutationObserver on documentElement[data-theme].

- Colors:
  - Color mapping is duplicated between CSS class names (for legend chips) and JS (for ECharts series). Consider centralizing to reduce drift.


## Error handling

- LiveView event handlers use bang (!) DB calls. Move to non-bang calls and surface errors via flash.


## Suggested future design refinements

- Extract and unit-test a Trends module.
- Add an Options context with functions: increment_vote(option_id), reset_all(), create_language(name) that encapsulate DB operations and atomicity.
- Introduce Repo.transaction/Ecto.Multi for grouped ops (reset, seed).
- Consider streaming large seed inserts with Repo.insert_all for performance.

