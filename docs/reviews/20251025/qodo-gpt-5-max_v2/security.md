# Security & Best Practices

## CSRF protection
- Router pipeline :browser includes plug :protect_from_forgery – enabled (lib/live_poll_web/router.ex line 9).
- assets/js/app.js passes _csrf_token in LiveSocket params – correct.
- root.html.heex includes <meta name="csrf-token" ...> – correct.

## Authentication/Authorization
- App is public; no auth. If adding admin-only features (e.g., destructive seed/reset), consider auth or rate limiting to avoid abuse.

## SQL injection
- Ecto used throughout with changesets and Repo – safe by default.
- No Repo.query/SQL fragments except Ecto.Adapters.SQL.query! used to update inserted_at in seeding. This query uses parameterized arguments ([timestamp, id]) – safe.

## Input validation / sanitization
- add_language accepts raw name:
  - Add trim, presence, and length caps (e.g., 1..100 chars)
  - Normalize case (optional) and enforce uniqueness (DB unique index + unique_constraint)
- Tooltip content in ECharts uses HTML formatter building strings with seriesName and value. If language names contain HTML or scripts, they could be rendered as HTML in the tooltip. Mitigations:
  - Escape seriesName before interpolation (e.g., a small helper to replace &, <, >, ", ') or use ECharts formatter that escapes by default (rich text without HTML) or set tooltip.renderMode = 'richText'/'html' carefully with text-only content.

## PubSub message handling
- Broadcast payloads are controlled by server events only. Avoid echoing user-generated strings into push_event/tooltip HTML without escaping.
- Topic names are static ("poll:updates") – fine. If you later use per-user topics, ensure authorization checks.

## Other headers and transport
- Endpoint session same_site: "Lax" – okay for typical apps. Consider Secure and proper cookie options in prod.
- Consider CSP header via Plug to reduce XSS surface, especially with ECharts and any future third-party code. Example minimal CSP can allow self scripts/styles and data: images.

## Recommendations
- Add unique index on poll_options(text); enforce unique_constraint in changeset; trim and validate length.
- Escape or sanitize language names before inserting in ECharts tooltip formatter. Prefer plain text labels or use ECharts' rich text to avoid HTML.
- Add basic rate limiting on vote/add_language endpoints if exposed publicly.
- Add Content-Security-Policy header in Endpoint or a plug.
