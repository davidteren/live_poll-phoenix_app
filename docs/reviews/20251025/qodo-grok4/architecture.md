# Architecture & Design Patterns Analysis

## Overall Application Structure
- **Framework**: Phoenix 1.8.1 with LiveView 1.1.0, using Ecto for database interactions and PostgreSQL as the backend (via postgrex).
- **Monolithic Structure**: The app is a single Phoenix application with code organized under `lib/live_poll` (business logic, schemas) and `lib/live_poll_web` (web layer, LiveView, router).
- **Key Modules**:
  - `PollLive` (lib/live_poll_web/live/poll_live.ex): Central LiveView handling UI, voting, seeding, and real-time updates.
  - Ecto Schemas: `Option` (poll options with votes) and `VoteEvent` (time-series vote events).
  - Router: Simple browser pipeline with a single LiveView route at "/".
  - Assets: Tailwind CSS, ECharts for charts, custom JS hooks in assets/js/charts.js and app.js.

- **Data Flow**:
  - Client -> LiveView (phx-click/phx-submit) -> Database updates via Repo -> PubSub broadcast -> All clients update via handle_info.
  - Real-time: Votes trigger PubSub broadcasts, updating pie charts and activity feeds without full page reloads.
  - Trend data: Periodically rebuilt from VoteEvent table and pushed to JS via push_event.

## PubSub Implementation for Real-Time Updates
- Uses Phoenix.PubSub with a single topic "poll:updates".
- Broadcasting events: :poll_update (vote), :poll_reset, :data_seeded, :language_added.
- Subscription in mount/3, handling in handle_info.
- Effective for real-time synchronization across clients, but single topic might limit scalability for multiple polls (file: lib/live_poll_web/live/poll_live.ex, lines 15-20, 55-60).

## Time-Series Event System and Data Bucketing
- **VoteEvent Schema**: Captures each vote with timestamp, language, votes_after (file: lib/live_poll/poll/vote_event.ex).
- **Bucketing**: In build_trend_data_from_events, events are grouped into dynamic buckets (e.g., 30s for 1h range) and snapshots calculated cumulatively (lines 630-710 in poll_live.ex).
- **Periodic Updates**: Timer sends :capture_trend every 5s to rebuild and push trend data to JS.
- Design: Efficient for historical trends but queries all events in range each time (potential perf issue for long ranges, see performance.md).

## Separation of Concerns
- **LiveView**: Handles UI state, events, and orchestration (PollLive).
- **Ecto/Repo**: Database operations isolated in Repo calls within LiveView.
- **Business Logic**: Mixed in LiveView (e.g., seeding logic lines 200-320), could be extracted to a context module for better separation.
- **JS Integration**: Hooks for ECharts (pie and trend charts), keeping heavy rendering client-side.

## Chart Integration Strategy
- ECharts via JS hook ("PieChart", "TrendChart") in template (lines 300-310, 200-210 in poll_live.html.heex).
- Data pushed via push_event("update-pie-chart", "update-trend-chart").
- Pros: Offloads rendering to client; Cons: Tight coupling between Elixir and JS data formats.

Overall, clean single-page app architecture leveraging LiveView strengths, but could benefit from extracting business logic to contexts for better modularity.
