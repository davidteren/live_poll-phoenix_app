# LivePoll – Code Review

This review covers Elixir modules under lib/, LiveView components, Ecto schemas, JavaScript hooks, and general code quality. It highlights strengths, issues, and actionable improvements with references to concrete files and lines.


## Highlights

- Clear, readable LiveView implementation with regular updates and push_event integration for charts (lib/live_poll_web/live/poll_live.ex).
- Sound database schema for time-series events with appropriate indexes on vote_events (priv/repo/migrations/20251023072711_create_vote_events.exs).
- Proper LiveView-JS integration using phx-update="ignore" and push_event for ECharts hooks (lib/live_poll_web/live/poll_live.html.heex and assets/js/charts.js).
- Sensible telemetry setup and project aliases (lib/live_poll_web/telemetry.ex, mix.exs aliases).


## Elixir modules and contexts

### Application and Repo
- lib/live_poll/application.ex – Supervision tree is standard and correct. PubSub named process is set up properly.
- lib/live_poll/repo.ex – Standard Ecto repo.

No issues.


### Context and schemas
- lib/live_poll/poll/option.ex – Minimal schema with fields text and votes. No changeset validations beyond required fields.
  - Recommendation: Enforce uniqueness on :text at the DB level and via a changeset. Add a unique index and constraint to avoid race conditions when adding a language:
    - DB: create unique_index(:poll_options, [:text]).
    - Changeset: |> unique_constraint(:text).

- lib/live_poll/poll/vote_event.ex – Reasonable event schema with belongs_to :option and fields language, votes_after, event_type.
  - Good: validate_inclusion/3 for event_type.
  - Good: indexes on option_id, inserted_at, and language (see migration).
  - Improvement: Consider whether language duplication is intended. If you want immutable event history even after renames, duplicating the language string is acceptable (denormalization). Otherwise, you could drop language and always join via option_id.


### LiveView (PollLive)
File: lib/live_poll_web/live/poll_live.ex

Key functions:
- mount/3: subscribes to PubSub topic and initializes assigns with trend data. OK.
- Voting (def handle_event("vote", ...)) at ~line 45 (ripgrep):
  - Issue: Read-modify-write race condition. Two concurrent clicks may both read the same votes value and then each write votes+1, losing increments.
  - Action: Use a DB-side atomic increment to prevent lost updates, e.g.:
    from(o in Option, where: o.id == ^id, update: [inc: [votes: 1]], select: struct(o, [:id, :text, :votes]))
    |> Repo.update_all([])
    Then fetch the updated row (or use RETURNING where applicable) and broadcast.

- Reset (def handle_event("reset_votes", ...)) at ~line 77:
  - Deletes all VoteEvent rows and resets votes to 0.
  - OK for demo; for production you might wrap in Repo.transaction/1 to ensure atomic state changes.

- Add language (def handle_event("add_language", %{"name" => name}, ...) when byte_size(name) > 0) at ~line 98:
  - Issue: Repo.get_by + Repo.insert! is racy without a unique index; two concurrent inserts can create duplicates or raise.
  - Action: Add unique index on poll_options(text) and handle changeset unique_constraint(:text). If insert fails due to uniqueness, return {:noreply, socket} without crashing.
  - Sanitization: See security notes for allowed characters in CSS-derived classes.

- Time range change (def handle_event("change_time_range", ...)) at ~line 125:
  - Consider validating allowed ranges (5, 60, 720, 1440) and handling invalid inputs gracefully.

- Seeding (def handle_event("seed_data", ...), def handle_info(:perform_seeding, ...)) at ~line 142 and ~152:
  - Issue: N+1 style inserts – up to 10,000 votes → 10,000 Repo.insert + 10,000 UPDATE inserted_at queries. This is heavy and slow.
  - Action: Batch using Repo.insert_all/3 for vote_events with precomputed inserted_at and votes_after values. At minimum, use Ecto.Multi or Repo.transaction and chunk inserts (e.g., 500–1,000 per batch) to reduce overhead.
  - Action: Consider removing preload: :option in the event query (see below); it’s not used.

- Periodic stats/trend capture (handle_info :update_stats, :capture_trend) ~line 344 and ~357:
  - OK and guarded by connected?(socket) in mount.

- Trend calculation (defp build_trend_data_from_events/1) at ~line 510:
  - Good: Dynamic bucket sizing and snapshot limit; carrying forward state to produce flat lines between event buckets is solid.
  - Improvement: Remove preload: :option since only event.language and votes_after are used. That saves a join/query per event line:
    from(e in VoteEvent, where: e.inserted_at >= ^cutoff, order_by: [asc: e.inserted_at])
  - Improvement: Extract this function (and related helpers) into a context module (e.g., LivePoll.Poll.Trends) to keep LiveView lean. Right now, LiveView contains substantial domain logic.

- Helpers (trend_line_points/2 around ~line 480, pie_slice_path/3 around ~line 619):
  - These are used for SVG drawing paths if retained. With ECharts for graphs, the SVG helpers seem unused at the moment; consider removing dead code for clarity if not referenced anywhere.


### LiveView template
File: lib/live_poll_web/live/poll_live.html.heex

- Integration: Uses phx-hook="PieChart" and phx-hook="TrendChart" with phx-update="ignore" – correct pattern to manage chart DOM in JS.
- Buttons: phx-click handlers for vote/reset/seed/time range – all good.
- Project guideline violation: Templates in this repo are expected to begin with <Layouts.app flash={@flash} ...>. This template is not wrapped with Layouts.app.
  - Action: Wrap the top-level content in <Layouts.app flash={@flash}>...</Layouts.app> per project rules (even though router root layout is set). Ensure current_scope is passed if applicable.
- Forms/inputs: Custom plain HTML inputs are used here instead of the imported <.input> component from core_components.ex. For consistency with project conventions, consider replacing the add-language form input with <.input>.


### Web modules, layouts, and components
- lib/live_poll_web.ex – Modern Phoenix 1.8 style; good.
- endpoint/router – Correct pipelines and dev routes.
- layouts (lib/live_poll_web/components/layouts.ex and layouts/root.html.heex):
  - Layouts.flash_group is correctly implemented and used inside the layout.
  - Project guideline violation: An inline <script> block exists in root.html.heex to manage theme switching. The project explicitly forbids inline <script> tags – scripts should live in assets/js and be imported via app.js.
    - Action: Move the theme toggling code to assets/js (e.g., theme.js) and import it from assets/js/app.js.
  - In lib/live_poll_web/controllers/page_html/home.html.heex, <Layouts.flash_group ... /> is rendered directly in a page template. Project guidelines forbid calling <.flash_group> outside layouts.ex; instead wrap content with <Layouts.app ...>.

- core_components.ex: The components and classes rely on daisyUI (btn, alert, toast, etc.). See Deprecations/Dependencies section regarding daisyUI adoption.


## Ecto queries and optimization

- Queries for trend data are already restricted by cutoff and ordered; good.
- Preloading :option for events is unnecessary; remove to reduce overhead (see above).
- Consider adding indexes:
  - poll_options(text) unique index to support uniqueness and fast lookup for add_language.


## JavaScript hooks and integration

- File: assets/js/charts.js
  - Good: Uses ECharts; re-renders when receiving push_event updates; listens for theme changes via MutationObserver; cleans up on destroyed.
  - Improvement: Store languages → color mapping in CSS variables or a shared map to avoid duplication with CSS color classes. Current duplication across CSS/JS increases maintenance cost.
  - Minor: In Tooltip formatter, param.value may be a number; guard for undefined (already ok via toFixed call but ensure param.value is number). The data ensures numbers.

- File: assets/js/app.js
  - Good: LiveSocket setup, hooks registration, topbar integration in dev, colocated hooks import.
  - Security/robustness: Ensure document.querySelector meta csrf-token exists; it does in root.html.heex.


## Error handling and resilience

- Multiple places use bang functions (Repo.update!, Repo.insert!) inside event handlers. Any DB error will crash the LiveView process and disconnect the client.
  - Action: Prefer non-bang versions and handle {:ok, struct} | {:error, changeset} gracefully with flash messages for user feedback.
  - Add guardrails for change_time_range and vote id parsing to avoid crashes from malformed inputs.


## Separation of concerns

- Significant trend analytics logic is embedded in the LiveView. Extract into a context module (e.g., LivePoll.Poll or LivePoll.Poll.Trends) and call it from the LiveView. This keeps rendering/event handling separate from analytics/business logic and eases unit testing.


## Code smells and anti-patterns

- Read-modify-write increments without DB atomicity (vote): risk of lost updates.
- Lack of unique constraint for Option.text (add_language race conditions).
- Unused preload in event query.
- Inline script in layout (project guideline violation).
- Direct <Layouts.flash_group> usage in a page template (project guideline violation).
- Heavy per-row insert/update in seeding for 10k votes; no batching.
- Missing graceful error handling (heavy use of bang functions in LiveView callbacks).
- Lack of input normalization for "language" beyond #, +, space – CSS classes derived from user input may still contain problematic characters.


## Actionable recommendations (summary)

1. Voting: Replace read-modify-write with DB-side atomic increment and broadcast the updated row.
2. Uniqueness: Add unique index and constraint on poll_options(text); handle insert conflicts.
3. Trend query: Drop preload: :option; consider moving trend logic into domain/context module.
4. Seeding: Batch inserts with Repo.insert_all inside a Repo.transaction and compute inserted_at and votes_after in-memory before bulk insert.
5. Templates: Wrap LiveView template in <Layouts.app ...> per project rules; remove inline scripts from root.html.heex in favor of assets/js/theme.js imported in app.js.
6. Input sanitization: Expand language_to_class/1 to normalize to [a-z0-9_-] only, stripping other characters.
7. Error handling: Replace bang functions in event handlers and show flash for errors.
8. Tests: Add LiveView tests for vote flow, add_language, reset, seeding, and trend range switching (see testing.md).
