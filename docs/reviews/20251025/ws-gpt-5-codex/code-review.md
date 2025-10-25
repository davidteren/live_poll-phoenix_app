# Code Review

## Overview

LivePoll is an interactive Phoenix LiveView application that lets users vote on programming languages and visualize results in real time. The implementation delivers a polished UI and includes meaningful LiveView tests, yet several architectural, maintainability, and robustness issues surfaced during review.

## Highlights

- Clean separation of web concerns through `LivePollWeb` macros and consistent use of Phoenix conventions.@lib/live_poll_web.ex#1-110
- Comprehensive LiveView test suite covering voting, reset flows, and visual regressions for SVG output.@test/live_poll_web/live/poll_live_test.exs#1-274
- Rich front-end instrumentation with ECharts hooks that react to LiveView push events for seamless updates.@assets/js/charts.js#53-161

## Findings

### LiveView implementation

1. **Business logic embedded in the LiveView** – All poll management, seeding, and analytics occur directly in `LivePollWeb.PollLive`, leaving no reusable context layer for other clients and making the LiveView hard to unit test.@lib/live_poll_web/live/poll_live.ex#11-436
2. **Heavy seeding work blocks the LiveView process** – The `:perform_seeding` handler performs thousands of synchronous inserts and raw SQL updates on the LiveView process, risking timeouts and UI freezes. Offload to a supervised Task or GenServer and stream progress updates instead.@lib/live_poll_web/live/poll_live.ex#152-297
3. **Inefficient trend reconstruction** – Every trend refresh pulls all matching `vote_events`, groups them, and recomputes cumulative state on each interval. Consider incremental updates or pre-aggregated materialized views to keep latency predictable.@lib/live_poll_web/live/poll_live.ex#509-615
4. **Duplicate database fetches** – Multiple handlers (`:poll_reset`, `:data_seeded`, `:language_added`) reload all options and recompute totals independently. Extract shared helpers or context functions to centralize and memoize repetitive work.@lib/live_poll_web/live/poll_live.ex#357-446
5. **Unused LiveView event** – `handle_event("toggle_theme")` is defined but the template toggles theme through a global `window.toggleTheme`. Remove the unused handler or rewire the UI to call the LiveView event for consistency.@lib/live_poll_web/live/poll_live.ex#73-75 @lib/live_poll_web/live/poll_live.html.heex#50-61

### Ecto schemas & data layer

1. **Missing uniqueness guarantee for option text** – `poll_options` allow duplicate language names because the schema/changeset lacks a unique constraint. Add a database index and changeset validation to keep vote aggregation reliable.@lib/live_poll/poll/option.ex#5-18
2. **Vote events duplicate language state** – `VoteEvent` stores `language` and links to `option`, creating denormalized data that drifts if option text changes. Prefer deriving language via association or enforce immutability with database triggers.@lib/live_poll/poll/vote_event.ex#5-21
3. **Direct `Repo` calls from LiveView** – All data access happens through `Repo` calls embedded in UI code. Introduce a dedicated `LivePoll.Polls` context to encapsulate queries, easing reuse and testing.@lib/live_poll_web/live/poll_live.ex#14-436

### Templates & components

1. **Bypassing shared form components** – The add-language form uses raw `<form>` and `<input>` HTML instead of the `Phoenix.Component` helpers (`<.form>` / `<.input>`), forfeiting built-in error handling and consistent styling.@lib/live_poll_web/live/poll_live.html.heex#168-183
2. **Inline JavaScript in layout** – The root layout embeds a sizeable `<script>` block for theme handling, conflicting with Phoenix and Tailwind guidance to keep JS in asset bundles. Move the logic into a dedicated hook or module under `assets/js` and import it via `app.js`.@lib/live_poll_web/components/layouts/root.html.heex#13-48
3. **Large monolithic template** – `poll_live.html.heex` combines modal markup, dashboards, charts, and activity feeds in a single file nearing 300 lines. Splitting into function components would improve readability and reuse.@lib/live_poll_web/live/poll_live.html.heex#1-295

### JavaScript hooks

1. **Static color maps** – `languageColors` and `languageColorsDark` only enumerate a subset of potential languages. Newly added or seeded languages fall back to grey, reducing visual clarity. Derive colors dynamically or extend the palette to cover random seed selections.@assets/js/charts.js#1-43 @lib/live_poll_web/live/poll_live.ex#191-229
2. **Duplicate chart implementations** – `TrendChart` and `PercentageTrendChart` share significant logic. Refactor shared behavior (theme observers, resize listeners, zoom persistence) into utility functions to reduce maintenance cost.@assets/js/charts.js#165-400

### Configuration & dependencies

1. **Outdated database driver** – `postgrex` remains at 0.21.x, predating features and bug fixes in the 0.17/0.19 series recommended for Phoenix 1.8. Updating reduces risk of protocol incompatibilities and unlocks prepared statement improvements.@mix.lock#1-47
2. **Pinned git dependency for Heroicons** – Using a git tag requires manual updates and slows dependency resolution. Switch to the published Hex package (`{:heroicons, "~> 0.x"}`) to follow semantic versioning and repository caching.@mix.exs#52-61

## Recommendations

1. Extract a `LivePoll.Polls` context to house option/event CRUD, with transactional helpers for seeding and voting.
2. Move long-running seeding logic into background jobs (Task.Supervisor) and stream progress via PubSub or LiveView streams.
3. Introduce aggregate tables or continuous queries to serve trend data efficiently, minimizing repeated full-table scans.
4. Adopt Phoenix form components in templates and factor large sections into reusable function components for maintainability.
5. Refresh dependencies (especially `postgrex`, `phoenix_live_view`, asset builders) and prefer Hex releases over git dependencies.
6. Consolidate chart hook utilities and expand color mappings to handle dynamic language sets gracefully.
