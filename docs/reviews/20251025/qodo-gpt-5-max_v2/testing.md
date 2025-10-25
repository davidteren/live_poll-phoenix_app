# Testing & Quality

## Current coverage snapshot

- test/live_poll_web/live/poll_live_test.exs
  - Covers mounts, voting, PubSub fanout, reset, some pie chart logic and progress bars.
  - Some assertions target legacy SVG paths (for donut chart) that no longer reflect ECharts-driven UI. Consider updating tests to assert on LiveView push_event behavior or state changes rather than raw SVG markup.

- support modules
  - ConnCase and DataCase set up sandbox and endpoint – standard and solid.

Gaps
- No tests for add_language validations (duplicates, whitespace-only, length limits).
- No tests for change_time_range and resulting push_event payloads for trend chart.
- No tests for seeding flow (modal visibility, post-seed state, and data volume).
- No security-focused tests (e.g., escaping user-provided language names in chart tooltips).

## Recommended test cases

### LiveView interactions
- Add Language
  - submits valid language; appears in list; broadcasts language_added.
  - duplicate insert (simulate race): ensure unique constraint error handled gracefully.
  - invalid names: empty, whitespace-only, >100 chars ⇒ rejected.

- Voting
  - concurrent votes on same option (simulate multiple clicks): counts reflect number of clicks; no lost updates.

- Reset All
  - After votes present, clicking reset clears options and trend_data snapshots.

### Trend and ranges
- change_time_range
  - clicking 5m/1h/12h/24h triggers push_event("update-trend-chart") with expected bucket density (sanity checks on snapshot count).
- periodic :capture_trend
  - simulate time and events; ensure trend_data grows as expected and push_event is sent.

### Seeding
- Shows modal on seed_data, then hides after job completion.
- After seeding, options count is between 12–14, and total votes ≈ 10k ± variance.
- Trend data is non-empty and sorted by timestamp.

### Security and sanitization
- Add language with HTML-like name ("<img onerror=...>") – ensure UI renders safely and JS tooltip content does not execute. Prefer asserting that names appear escaped in DOM; for ECharts, assert push_event payload carries raw names but tooltip rendering should be escaped or handled as text.

### Performance (optional integration)
- Measure seeding duration using telemetry or time measurements; assert it completes under a generous budget in CI after batching improvements.

## Testing approaches

- Phoenix.LiveViewTest
  - Use element/2 and render_click/2 for button interactions
  - Use has_element?/2 rather than raw string search when possible
- Push events
  - You can assert that the socket assigns change as expected; for client-side behavior (ECharts), limit to ensuring the right payloads are sent (difficult to assert directly). Alternatively, expose test-only code paths or logs that capture push_event payloads.

## Tooling
- Add mix aliases for precommit including compile --warning-as-errors and test (already present: mix precommit). Keep using it.

## Maintenance
- Remove or update tests tied to legacy SVG pie chart helpers if you remove server-side SVG code.
