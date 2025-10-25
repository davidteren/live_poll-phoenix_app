# LivePoll – Summary & Recommendations

This executive summary synthesizes findings from code review, deprecations, architecture, performance, testing, and security analyses.


## Top findings

- Concurrency integrity: Voting uses read-modify-write updates leading to potential lost increments under concurrent clicks.
- Data seeding performance: ~10k events inserted with per-row insert + follow-up UPDATE; no transaction and high round-trip cost.
- Project guideline violations: Inline <script> in root layout; <Layouts.flash_group> used in a page template; LiveView template not wrapped with <Layouts.app>.
- Missing uniqueness constraints: poll_options(text) lacks a unique index; race in add_language.
- Trend query inefficiency: Unnecessary preload :option in events query.
- Error handling: Bang functions used broadly in LiveView; failures can crash the process and degrade UX.
- DaisyUI usage: Contrary to project guidance to prefer Tailwind-only custom components.


## Prioritized issues

1) Critical
- Atomic vote increments (prevent lost updates).
- Add unique index and unique_constraint for poll_options(text).

2) High
- Seeding: switch to Repo.transaction + Repo.insert_all with precomputed inserted_at; batch operations.
- Remove inline scripts; move theme logic to assets/js; ensure <Layouts.app> wrapping and avoid calling <.flash_group> outside layouts.
- Remove unnecessary preload in trend query.

3) Medium
- Extract trend logic into a domain module for testability.
- Replace bang DB calls with safe variants and flash-based error reporting.
- Harden language_to_class/1 sanitization.

4) Low
- Consolidate color mappings to avoid duplication across CSS/JS.
- Consider LiveView streams for large collections.


## Actionable recommendations

- Voting
  - Use Repo.update_all with inc: [votes: 1] and fetch the updated row via RETURNING.
  - Broadcast updated state and update assigns accordingly.

- Options
  - Migration: create unique_index(:poll_options, [:text]).
  - Changeset: unique_constraint(:text).

- Seeding
  - Wrap in Repo.transaction.
  - Build a list of vote_event maps with inserted_at set; Repo.insert_all in chunks.
  - Insert options via Repo.insert_all and compute final counts to update in bulk.

- LiveView and templates
  - Wrap poll_live.html.heex in <Layouts.app flash={@flash}>.
  - Remove direct <Layouts.flash_group> references in page templates; rely on layout.
  - Move theme inline script to assets/js/theme.js and import it in assets/js/app.js.

- Trend logic
  - Remove preload; optionally extract to LivePoll.Poll.Trends and write unit tests.

- Security & validation
  - Harden language_to_class/1 and validate input names.
  - Replace bang functions in LiveView callbacks; surface errors via flash.

- Dependencies
  - Pin postgrex to a recent stable minor and update phoenix_live_view to latest 1.1.x.
  - Run npm audit in assets; consider bumping tslib.


## Testing roadmap

- LiveView tests: vote flow, add_language, reset, time-range changes.
- Trend unit tests: bucket computation, carry-forward, snapshot caps.
- Seeding tests: small-volume integration (100 votes) for speed.


## Suggested implementation order

1. DB integrity and concurrency: unique index + atomic vote increment.
2. Template/layout compliance and inline script removal.
3. Seeding performance overhaul (transaction + insert_all).
4. Trend query cleanup and extraction to context.
5. Error handling improvements and input sanitization.
6. Test suite: add LiveView and domain tests.


## Expected outcomes

- Correct vote counts under load; improved DB integrity.
- Faster, more reliable seeding flows.
- Cleaner separation of concerns and better test coverage.
- Compliance with project guidelines and improved security posture.
