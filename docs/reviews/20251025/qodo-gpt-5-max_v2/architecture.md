# Architecture & Design Patterns

## Overview

- Phoenix 1.8 with LiveView 1.1
- Single LiveView (PollLive) handling all poll UX
- Ecto with PostgreSQL; two tables: poll_options and vote_events
- Phoenix PubSub for real-time fanout
- ECharts via JS hooks for charts
- Tailwind v4 CSS; daisyUI vendor plugin present but optional

## Module structure

- lib/live_poll/
  - application.ex: supervision tree (Repo, PubSub, Endpoint, Telemetry)
  - repo.ex: Ecto repo
  - poll/option.ex: language options with vote counts
  - poll/vote_event.ex: time-series events with inserted_at timestamp
- lib/live_poll_web/
  - router.ex: routes; single live "/", PollLive
  - endpoint.ex: sockets, Plug pipeline, static
  - components/core_components.ex: UI components (forms, table, icon)
  - components/layouts.ex + layouts/root.html.heex: layout and flash
  - live/poll_live.ex + poll_live.html.heex: main LiveView and markup

## Data flow

1. Mount
   - Subscribe to "poll:updates"
   - Load options; compute total and sorted lists
   - Build trend_data from recent vote_events (default 60 minutes)
   - Start timers every 5s: :update_stats, :capture_trend

2. Events
   - vote
     - Increment option.votes; insert VoteEvent (event_type: "vote")
     - Broadcast {:poll_update, data} over PubSub
   - reset_votes
     - delete_all VoteEvents; set all votes=0; broadcast {:poll_reset}
   - add_language
     - Insert Option(text, votes=0) unless exists; broadcast {:language_added}
   - change_time_range
     - Recompute trend_data; push_event("update-trend-chart", ...)
   - seed_data
     - Show seeding modal; schedule :perform_seeding

3. Info messages
   - :perform_seeding
     - Delete existing options/events
     - Randomly select 12–14 languages; insert options
     - Distribute ~10k votes by weighted popularity
     - Insert events in timestamp order; update inserted_at per event
     - Update final votes; hide modal; broadcast {:data_seeded}
   - :capture_trend
     - Recompute trend_data for current range; push_event
   - {:poll_update | :poll_reset | :language_added | :data_seeded}
     - Refresh assigns and push chart updates as relevant

## PubSub usage

- Topic: "poll:updates"
- Broadcasts propagate to all connected clients; each handle_info updates assigns and pushes chart payloads to JS hooks. This decouples rendering from charts, minimizing HEEx diffs.

## Time-series and bucketing

- Source of truth: vote_events, with inserted_at timestamps
- build_trend_data_from_events(minutes_back)
  - Select events >= cutoff ordered asc
  - Choose bucket_seconds based on minutes_back (5s, 30s, 5m, 10m)
  - Group events by rounded timestamp to bucket
  - Generate full bucket timeline from cutoff to now
  - Carry-forward state to produce snapshots with percentages and counts
  - Cap snapshots to max_snapshots per range

Observations
- Preloading :option is unused – safe to remove for performance
- All calculations are in Elixir; consider DB-side aggregation when data grows

## Separation of concerns

- LiveView contains business logic (seeding, bucketing) and persistence calls
- No separate context modules beyond schemas; acceptable for a demo, but for growth, consider a Poll context with functions:
  - list_options/0, add_language/1, cast_vote/1, reset/0
  - seed_data(range, total_votes), trend(minutes_back)

## Chart integration strategy

- ECharts initialized in hooks (assets/js/charts.js)
- DOM nodes using phx-update="ignore"
- LiveView communicates via push_event("update-...", payload)
- Hooks listen with handleEvent, update chart option via setOption
- Theme sensitivity via MutationObserver on [data-theme]
- Zoom persistence captured via dataZoom and reapplied

Pros
- Minimal LiveView diffs; charts fully managed in JS
- Clear separation and lifecycle handling (dispose on destroyed)

Cons
- Duplicate color mapping across CSS and JS
- Unused PercentageTrendChart exported (dead code)

## Suggested refinements

- Move seeding and trend logic to a Poll context/service
- Remove :option preload in event query
- Optionally compute aggregation in SQL (GROUP BY bucket) and return percentages
- Centralize color mapping (e.g., CSS variables or a single mapping source)
- Remove unused chart hook
