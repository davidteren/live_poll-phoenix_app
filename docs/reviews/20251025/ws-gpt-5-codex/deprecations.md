# Deprecated Code & Dependencies

## Phoenix & LiveView patterns

- **Inline theme toggling script** – The root layout embeds imperative JavaScript to manage themes, contradicting Phoenix 1.8 guidance to keep behavior inside asset bundles or hooks. Migrate the `toggleTheme` logic into a LiveView hook or dedicated JS module imported via `app.js`.@lib/live_poll_web/components/layouts/root.html.heex#13-48 @assets/js/app.js#20-84
- **LiveView event stub** – `handle_event("toggle_theme")` remains in the LiveView module even though the template no longer calls it, leaving dead code and hinting at outdated approaches to client-side theme control.@lib/live_poll_web/live/poll_live.ex#73-75

## Dependency versions

- **`phoenix_live_view` 1.1.16** – Current Phoenix generators ship with 1.1.18+, which include fixups for LiveView streams and pubsub reconnect edge cases. Upgrade to stay aligned with security and bugfix releases.@mix.lock#1-47
- **`phoenix_live_dashboard` 0.8.7`** – This version predates instrumentation fixes delivered in 0.8.3+, but 0.8.4+ now expect LiveView 1.1.18. Plan a coordinated bump with LiveView to retain compatibility.@mix.lock#1-47
- **`postgrex` 0.21.1`** – Significantly behind the 0.17/0.19 series recommended for Ecto 3.13; newer releases improve protocol negotiation and telemetry. Upgrade alongside database config validation.@mix.lock#1-47
- **`phoenix_live_reload` 1.6.1`** – Upgrade to 1.7.x to match Phoenix 1.8 defaults and benefit from faster file-system polling.@mix.lock#1-47
- **Git-based `heroicons` dependency** – Using a git tag hinders Dependabot and Hex version resolution. Switch to `{:heroicons, "~> 0.5"}` from Hex for managed upgrades.@mix.exs#52-61
- **DaisyUI vendor bundle** – The Tailwind pipeline ships with DaisyUI plugins despite minimal usage in templates, adding maintenance overhead. If the design relies primarily on bespoke Tailwind classes, consider removing the plugin to simplify updates.@assets/css/app.css#15-94 @lib/live_poll_web/live/poll_live.html.heex#1-295

## Front-end packages

- **`echarts` ^6.0.0** – v6 was released recently with breaking API changes. Confirm compatibility of the custom hooks or pin to a stable minor (e.g., `^5.5.0`) to avoid unexpected chart regressions when reinstalling dependencies.@assets/package.json#1-5
