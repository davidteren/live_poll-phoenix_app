# Code Review – LivePoll (Phoenix 1.8 / LiveView 1.1)

This review covers Elixir modules, LiveView components, Ecto code, and JS hooks. It highlights strengths, flags issues with precise references, and proposes pragmatic improvements.

## Highlights
- Clean Phoenix 1.8 project setup with Bandit and colocated assets.
- Solid LiveView + PubSub real-time flow; push_event used correctly for charts.
- Time-series bucketing implemented server-side with carry-forward logic.
- ECharts integration encapsulated in JS hooks with phx-update="ignore" and teardown.

## LiveView and HEEx

- lib/live_poll_web/live/poll_live.html.heex
  - Uses phx-hook="TrendChart" on a container with phx-update="ignore" – correct when JS manages DOM (lines ≈286–291).
  - The template does not start with <Layouts.app flash={@flash} ...>. Project guidelines request it for every LiveView template. Consider wrapping contents with:
    
        <Layouts.app flash={@flash}>
          ...
        </Layouts.app>
    
    Or, alternatively, render <.flash_group> from Layouts in the root layout (since it already lives under the Layouts module). Root currently does not render it.
  - The Add New Language form is a raw <form> without <.form> and to_form. Project guidelines recommend using to_form in the LiveView and <.input> components. See “Forms” suggestions below.
  - Inline onclick="toggleTheme()" calls into a global function from the layout. Prefer a LiveView event or a JS hook; avoid inline JS in templates per project rules.

- lib/live_poll_web/components/layouts/root.html.heex
  - Contains an inline <script> for theme management. Project rules discourage inline scripts; move this logic into assets/js/app.js (e.g., a small boot function) and keep only data attributes in markup.
  - Does not render <.flash_group>. Given the rule that <.flash_group> must live in layouts.ex, it’s reasonable to render it here, so LiveViews don’t need to wrap with Layouts.app.

- lib/live_poll_web/components/layouts.ex
  - Provides <Layouts.app> and defines <.flash_group> within the proper module – good. However, <Layouts.app> is not used by PollLive nor root. Either render <Layouts.app> in templates or render <.flash_group> in root.

- lib/live_poll_web/components/core_components.ex
  - Uses daisyUI-oriented classes (btn, alert, toast) in examples and components. Project guidance prefers bespoke Tailwind over daisyUI. Consider removing daisyUI and adjusting classes accordingly.

## LiveView module (server side)

- lib/live_poll_web/live/poll_live.ex
  - mount/3 subscribes to PubSub and seeds assigns – good. Periodic timers every 5s for stats and trend capture – consider consolidating or making intervals configurable to reduce churn under load.
  - handle_event("vote") updates an Option and inserts a VoteEvent. Consider using Repo.update_all for atomic increments if you ever expect heavy concurrency, or explicit SELECT ... FOR UPDATE (with Ecto) to avoid lost updates.
  - handle_event("add_language"): checks for duplicates via Repo.get_by/2 but lacks a DB uniqueness constraint; race conditions can lead to duplicate languages. Add a unique index on poll_options(text) and handle {:error, changeset} on insert.
  - handle_event("change_time_range"): recomputes trend data on each click and pushes updates via push_event – good. See performance notes on recompute.
  - handle_event("seed_data"): schedules :perform_seeding and shows modal – good UX.
  - handle_info(:perform_seeding): inserts ~10k events one-by-one and then updates inserted_at with 10k individual UPDATE statements. This is very slow and DB-heavy. See Performance section for batched insert_all and pre-setting timestamps to avoid UPDATEs.
  - build_trend_data_from_events/1 (≈lines 536–606 and following):
    - Uses dynamic bucket sizing with carry-forward to produce snapshots – nice. For large datasets, the per-bucket reduce in Elixir will be expensive; consider DB aggregation (GROUP BY bucket) or an incremental cache.
    - Preload: the query preloads :option but the association isn’t used; remove preload to reduce overhead.

## Ecto Schemas & DB

- lib/live_poll/poll/option.ex
  - Simple schema with fields :text and :votes – fine.
  - Missing constraints/validations:
    - validate_length(:text, max: 100) and a trimmed input to avoid extremely large values.
    - unique_constraint(:text) if a DB unique index is added.

- lib/live_poll/poll/vote_event.ex
  - Validates inclusion for :event_type – good.
  - Consider a check constraint on votes_after >= 0.

- priv/repo/migrations
  - 20251023072711_create_vote_events.exs defines indices on option_id, inserted_at, language – good coverage for query patterns.
  - Missing a unique index on poll_options(text) if uniqueness is desired.

## JS Hooks and Integration

- assets/js/app.js
  - Imports colocated hooks and registers PieChart and TrendChart – good.
  - CSRF token wiring for LiveSocket – correct.

- assets/js/charts.js
  - PieChart and TrendChart hooks properly initialize, listen for theme changes via MutationObserver, respond to LiveView push_event, handle window resize, and dispose on destroyed – excellent lifecycle management.
  - Tooltip formatter uses HTML string interpolation with seriesName and values derived from user-provided language names. This can be XSS-prone if HTML is interpreted. Consider escaping seriesName or using ECharts rich text/escape mechanisms. See Security.
  - PercentageTrendChart is exported but unused by templates. Remove to reduce bundle size and cognitive load.
  - Color maps duplicated in CSS and JS; consider centralizing mapping (e.g., data attributes + CSS or a single source of truth) to avoid drift.

## Forms (guideline alignment)

- Current Add New Language form is a raw <form>. Project rules recommend:
  - In LiveView: assign(form: to_form(...))
  - In template: <.form for={@form} ...> and <.input field={@form[:name]} ...>
  - Use unique DOM IDs for forms (e.g., id="language-form").

## Code Smells / Dead Code
- PollLive has helpers for drawing SVG pie/trend lines (e.g., pie_slice_path/3, trend_line_points/2) that no longer drive the UI as charts moved to ECharts. Consider removing these helpers and related tests tied to old SVG output to reduce confusion.
- PercentageTrendChart in charts.js is not used in the template.

## Error handling and edges
- Seed operation has no failure path or progress updates; if it fails mid-way, the UI only hides after 800ms. Consider transactions and progress push events for better UX.
- add_language accepts any string; add trim and length caps; reject whitespace-only names; normalize case if needed.

---

## Actionable Recommendations (summary)
- Forms: migrate Add Language to <.form>/<.input> with to_form.
- Layout: move inline theme script into assets/js; render <.flash_group> in root layout or wrap LiveViews with <Layouts.app>.
- DB: add unique index on poll_options(text) + unique_constraint; add validate_length and case/whitespace normalization.
- Performance: batch seeding with insert_all and preset timestamps; remove preload in trend events; consider DB aggregation for trend bucketing.
- JS: sanitize tooltip content; remove unused PercentageTrendChart; centralize color mapping.
- Tests: update tests to reflect ECharts-based charts rather than SVG paths.

## Suggested code changes (illustrative)

1) Database uniqueness and validations

- Migration to add unique index:

    defmodule LivePoll.Repo.Migrations.AddUniqueIndexOnPollOptionsText do
      use Ecto.Migration
      def change do
        create unique_index(:poll_options, [:text])
      end
    end

- Update Option.changeset/2 to normalize and enforce uniqueness:

    def changeset(option, attrs) do
      option
      |> cast(attrs, [:text, :votes])
      |> update_change(:text, fn t -> t |> String.trim() end)
      |> validate_required([:text, :votes])
      |> validate_length(:text, max: 100)
      |> unique_constraint(:text)
    end

2) Remove unused preload in trend query

- lib/live_poll_web/live/poll_live.ex (in build_trend_data_from_events/1):

    events =
      from(e in VoteEvent,
        where: e.inserted_at >= ^cutoff_time,
        order_by: [asc: e.inserted_at]
        # preload: :option   # remove this, not used
      )
      |> Repo.all()

3) Convert Add Language form to to_form + <.input>

- live: assign a form on mount or before render:

    socket = assign(socket, form: to_form(%{"name" => ""}, as: :language))

- template (replace raw <form>):

    <.form for={@form} id="language-form" phx-submit="add_language">
      <.input field={@form[:name]} placeholder="e.g., Kotlin, C#, PHP..." required />
      <.button class="btn btn-primary">Add</.button>
    </.form>

- handle_event to pattern match nested params:

    def handle_event("add_language", %{"language" => %{"name" => name}}, socket) do
      # ... existing logic ...
    end

4) Sanitize ECharts tooltip labels in assets/js/charts.js

- Escape helper:

    function esc(s) {
      return String(s)
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;")
        .replace(/\"/g, "&quot;")
        .replace(/'/g, "&#39;");
    }

- Use in tooltip formatter:

    formatter: function(params){
      let result = `<strong>${esc(params[0].axisValue)}</strong><br/>`;
      params.forEach(param => {
        result += `<span style="display:inline-block;width:10px;height:10px;border-radius:50%;background-color:${param.color};margin-right:5px;"></span>`;
        result += `${esc(param.seriesName)}: ${Number(param.value).toFixed(1)}%<br/>`;
      });
      return result;
    }

5) Batch insert seeding (outline; full version in performance.md)

- Build a list of maps with inserted_at precomputed and call Repo.insert_all/3 in chunks to avoid 10k individual UPDATEs.
