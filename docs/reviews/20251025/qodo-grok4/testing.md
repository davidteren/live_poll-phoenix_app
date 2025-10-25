# Testing & Quality Analysis

## Existing Test Coverage
- **Unit/Integration Tests**: Basic controller tests (error_html_test.exs, error_json_test.exs, page_controller_test.exs) cover error handling and static pages.
- **LiveView Tests**: poll_live_test.exs (test/live_poll_web/live/poll_live_test.exs) covers:
  - Mounting and loading options.
  - Voting increments and broadcasts.
  - Reset functionality.
  - Pie chart calculations and rendering.
  - Progress bars and bar chart color usage.
- **Support Files**: conn_case.ex and data_case.ex for test helpers.
- Overall coverage is partial, focusing on core voting and UI rendering, but missing several features.

## Untested Critical Paths
- **Seeding Process**: No tests for data seeding (poll_live.ex lines 200-320), including event backfilling and timestamp manipulation.
- **Trend Calculation**: build_trend_data_from_events (lines 630-710) untested, including bucketing, percentage calculations, and edge cases like empty events.
- **Add Language**: handle_event("add_language") untested, including duplicate prevention and broadcast.
- **Time Range Changes**: handle_event("change_time_range") and trend updates untested.
- **PubSub Edge Cases**: No tests for concurrent votes or high-load broadcasts.
- **JS Hooks**: No integration tests for ECharts hooks (PieChart, TrendChart).

## Suggested Test Cases
- **LiveView Interactions**:
  - Test adding a new language and verifying it's broadcasted and appears in UI.
  - Test voting from multiple simulated clients and verify real-time updates.
- **Voting and Real-Time Updates**:
  - Concurrent voting stress test.
  - Verify recent_activity list limits to 10 items.
- **Seeding and Trend Calculation**:
  - Integration test for seeding: Verify 10,000 votes distributed, events inserted with correct timestamps.
  - Test trend bucketing for different time ranges (5m, 1h, etc.), including empty states and partial buckets.
  - Verify trend updates on timer (:capture_trend).
- **Edge Cases**:
  - Zero votes state for charts and percentages.
  - Single language with 100% votes.
  - Error handling for invalid inputs (e.g., empty language name).

Recommendations: Aim for 80%+ coverage. Add ExUnit tags for focused testing. Use LazyHTML for complex HTML assertions in LiveView tests.
