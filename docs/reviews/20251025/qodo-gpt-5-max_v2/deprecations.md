# Deprecated Code & Dependencies

This document identifies deprecated or discouraged patterns and flags out-of-date or risky dependencies.

## Phoenix/LiveView Patterns

- live_redirect / live_patch
  - Search result: none found. Good – templates use <.link> when needed (via core_components) and navigate through LiveView standard APIs.

- phx-update usage
  - Charts use phx-update="ignore" (lib/live_poll_web/live/poll_live.html.heex lines ≈286–294, 305–314). Correct for JS-managed DOM.

- Flash component placement
  - Phoenix v1.8 moved flash_group to Layouts. The project includes <.flash_group> in LivePollWeb.Layouts – correct. However, root.html.heex does not render it, and PollLive template does not wrap in <Layouts.app>. While not a deprecation, it is a v1.8 convention to centralize flash in Layouts.

## Ecto / Elixir

- Access on structs with []
  - Not used. All struct fields accessed via dot or Ecto getters – good.

- validate_number allow_nil
  - Not used – good; guidelines note this is unsupported.

- Enum access via index syntax mylist[i]
  - Not used – good.

## Dependencies (Mix)

mix.exs
- {:phoenix, "~> 1.8.1"} – Current stable within 1.8.x; check for 1.8.x latest patch.
- {:phoenix_live_view, "~> 1.1.0"} – 1.1 is current major as of 2025. Minor/patch updates may exist; consider bumping to latest 1.1.x.
- {:heroicons, github: "tailwindlabs/heroicons", tag: "v2.2.0", ...} – Git dependency. Recommendation: switch to Hex package {:heroicons, "~> 0.5"} which provides Phoenix components and versioned releases. If keeping vendor-based CSS plugin, document rationale.
- {:req, "~> 0.5"} – Preferred HTTP client per guidelines – OK.
- {:esbuild, "~> 0.10"}, {:tailwind, "~> 0.3"} – Within typical ranges for Phoenix generators. Verify latest minor.
- Others (ecto_sql 3.13, swoosh 1.16, finch via req transitive, etc.) – Up-to-date within majors. Run mix hex.outdated to confirm patch bumps.

Security considerations
- Keep bandit, postgrex, plug_crypto, telemetry_* on latest patches. Run mix deps.audit (if available) or use external audit in CI.

## Front-end (NPM)

assets/package.json
- echarts: ^6.0.0 – New major (6.x) with API shifts. Hooks rely on basic setOption which likely remains compatible, but breaking changes may affect extensions. Consider pinning to a known-good minor (e.g., ^5.5.0) if you haven’t verified 6.x thoroughly, or add tests around chart lifecycle.
- No other packages listed – vendor bundles exist for topbar, heroicons CSS plugin, and daisyUI (assets/vendor/*).

Security
- Run npm audit --omit=dev in assets to check transitive CVEs (e.g., zrender, tslib). Lockfile is not present in repository; ensure one is committed to pin sub-deps.

## Discouraged: DaisyUI

- Project guidelines: “Always manually write your own tailwind-based components instead of using daisyUI.”
- Current state: app.css imports @plugin "../vendor/daisyui" and "../vendor/daisyui-theme". Components and docs reference daisyUI classes (btn, alert, toast), but templates mostly use Tailwind classes. DaisyUI appears optional and adds ~300KB CSS/JS.
- Recommendation: remove daisyUI plugins and vendor files to follow guideline and reduce bundle size. Replace classes (btn, alert, toast, card) with bespoke Tailwind utilities.

## Summary of Actions

- Replace Git heroicons dep with Hex package or keep CSS plugin approach but document it.
- Decide on echarts major: verify v6 or pin to 5.x.
- Remove daisyUI plugins and adjust classnames.
- Add mix and npm audit steps to CI; commit lockfiles.
- Ensure flash placement aligns with Phoenix 1.8 conventions (Layouts).
