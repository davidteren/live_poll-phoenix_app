# Summary & Recommendations

## Executive Summary
LivePoll is a clean Phoenix LiveView demo showcasing real-time votes with charts. It uses PubSub effectively and integrates ECharts via hooks with proper lifecycle handling. The time-series bucketing logic is well-considered for realistic trends. Main improvement areas are: form conventions, layout/flash placement, seeding performance, DB constraints, DaisyUI removal, and minor security hardening for chart tooltips.

## Priority Breakdown

- Critical
  - Seeding performance: O(N) inserts + O(N) updates; switch to batch insert_all with preset timestamps.
  - Input validation & constraints: add unique index on poll_options(text); trim/length validations to prevent duplicates and junk data.
  - Tooltip XSS risk: escape language names or render as text-only in ECharts tooltips.

- High
  - Follow Phoenix 1.8 form conventions: use to_form + <.form> + <.input> for Add Language; assign id="language-form".
  - Remove :option preload in trend events query to reduce overhead.
  - Layout script hygiene: move inline theme script from root.html.heex into assets/js and expose a small API; render <.flash_group> from Layouts in root or wrap template with <Layouts.app>.

- Medium
  - Remove daisyUI plugins and replace classes with Tailwind utilities; reduces bundle weight and aligns with project guidance.
  - Consolidate/adjust periodic timers (trend capture every 10–15s, compute-on-change).
  - Remove unused PercentageTrendChart hook and dead SVG helpers in PollLive and tests.

- Low
  - Centralize language color mapping to avoid CSS/JS drift.
  - Consider extracting a Poll context for business logic as the app grows.

## Actionable Roadmap

1. Data & Security (critical)
   - Migration: add unique index on poll_options(text)
   - Update Option.changeset with unique_constraint(:text), trim, length limits
   - Escape tooltip labels in assets/js/charts.js

2. Performance (critical/high)
   - Refactor seeding to build a list of events with inserted_at and Repo.insert_all/3 in chunks; one transaction
   - Remove preload from build_trend_data_from_events; consider DB aggregation for buckets later

3. UX & Conventions (high)
   - Convert Add Language form to to_form and <.input>
   - Render <.flash_group> in root layout or wrap template in <Layouts.app>
   - Move theme toggle script into app.js and expose window.toggleTheme via a small module or LiveView Hook

4. Front-end cleanup (medium)
   - Remove PercentageTrendChart export; prune unused code
   - Remove daisyUI plugins and vendor files; update classes in core_components accordingly

5. Testing (medium)
   - Add tests for add_language validations and duplicate handling
   - Add tests for change_time_range push_event payload shape (approximate snapshot count)
   - Add seeding flow test asserting modal visibility and final state

## Closing Note
These changes will improve robustness, performance, and alignment with Phoenix 1.8 best practices without changing core functionality. Start with constraints and seeding refactor; then address forms and layout conventions, followed by front-end cleanup and test expansion.
