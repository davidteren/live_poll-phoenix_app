# LivePoll – Deprecated Code & Dependencies

This document identifies deprecated or discouraged patterns and outdated dependencies across Elixir/Phoenix/Ecto and the JS toolchain.


## Phoenix/LiveView patterns

- Deprecated navigation helpers: No usage of live_redirect or live_patch found. The template uses buttons and push_event. OK.
- phx-update usage: Correctly uses phx-update="ignore" for chart elements, which is the recommended pattern. OK.
- Flash group usage: Per project guidelines, <.flash_group> must only be used inside layouts.ex. We found instances rendered directly in a page template (lib/live_poll_web/controllers/page_html/home.html.heex: first line). This is a project convention violation, not a Phoenix deprecation.


## Inline scripts (forbidden by project guidelines)

- lib/live_poll_web/components/layouts/root.html.heex includes an inline <script> block to manage theme switching. Project guidelines forbid inline scripts; move this into assets/js and import from app.js.


## DaisyUI usage (discouraged by project guidelines)

- The codebase integrates daisyUI via Tailwind plugins in assets/css/app.css and vendor files (assets/vendor/daisyui.js, daisyui-theme.js). The project guidelines state: “Always manually write your own tailwind-based components instead of using daisyUI.”
  - Action: Consider removing daisyUI plugins and replacing .btn, .alert, .toast, etc., with bespoke Tailwind classes. If you choose to keep daisyUI, document the rationale and scope to avoid half-adoption.


## Mix dependencies (mix.exs)

- Phoenix ~> 1.8.1 – current as of 1.8 line, OK.
- phoenix_live_view ~> 1.1.0 – Use the latest 1.1.x (1.1.10+) to pick up bug fixes. Check lock; if behind, update.
- phoenix_html ~> 4.1 – OK for Phoenix 1.8.
- phoenix_live_dashboard ~> 0.8.3 – OK for Phoenix 1.7/1.8.
- ecto_sql ~> 3.13 – OK.
- postgrex >= 0.0.0 – Consider pinning to a modern minor (e.g., ~> 0.17 or 0.18) to improve reproducibility and security posture.
- esbuild ~> 0.10, tailwind ~> 0.3 (dev runtime) – OK for Phoenix generators.
- bandit ~> 1.5 – OK.
- req ~> 0.5 – OK.
- dns_cluster ~> 0.2.0 – OK.
- swoosh ~> 1.16 – OK.
- heroicons via git – fine for CSS plugin usage.

Security notes:
- Ensure mix.lock is audited periodically (mix hex.audit if available; otherwise manual review). No high-risk packages stand out by name, but lock-level audit is recommended.


## NPM dependencies (assets/package.json)

- echarts ^6.0.0 – 6.x is the current major; ensure no breaking API changes affect usage. Periodically run npm audit in assets/ to check for CVEs in transitive deps (tslib, zrender). Current lock shows tslib 2.3.0 and zrender 6.0.0; consider bumping tslib to a more recent 2.x if compatible.


## Other deprecations and patterns

- No usage of Phoenix.View modules or deprecated LiveView APIs detected.
- No usage of deprecated phx-update values like append/prepend detected.


## Summary of recommended actions

1. Remove inline scripts from root.html.heex; move to assets/js.
2. Decide on daisyUI: remove and replace with Tailwind-only per project guidelines, or document its intentional use.
3. Add unique index and constraint to poll_options(text); update changesets.
4. Pin postgrex to a newer stable minor and update phoenix_live_view to the latest 1.1.x.
5. Run npm audit in assets and consider bumping tslib.
6. Run mix deps.audit or equivalent to check for known vulnerabilities (manual step if tooling not installed).
