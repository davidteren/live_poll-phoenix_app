# Security & Best Practices

## Strengths

- **CSRF protection** – Browser pipeline includes `protect_from_forgery` and forms render CSRF tokens via `Phoenix.Component.form` helpers, shielding POST events from cross-site submission.@lib/live_poll_web/router.ex#4-21 @lib/live_poll_web/live/poll_live.html.heex#167-183
- **Sessions** – Cookies are signed (not encrypted) with SameSite=Lax, matching Phoenix defaults. No sensitive data is stored in session assigns.@lib/live_poll_web/endpoint.ex#4-52
- **SQL access** – Ecto is used for all data operations, parameterizing queries and reducing SQL injection risk.

## Observations & risks

- **Unauthenticated control actions** – Anyone can trigger seeding, resets, and language additions. In a public deployment this allows prank users to wipe or flood data. Add authentication/authorization or throttle destructive events.@lib/live_poll_web/live/poll_live.html.heex#64-182
- **Inline scripts** – The theme management script is injected into the layout, expanding the XSS surface and conflicting with CSP best practices. Move logic into bundled JS to leverage nonce-based protections.@lib/live_poll_web/components/layouts/root.html.heex#13-48
- **Lack of input validation** – `add_language` only checks for non-empty strings; no length limits or normalization guard against oversized payloads or spoofed names. Introduce changeset validation (length caps, trimming).@lib/live_poll_web/live/poll_live.ex#98-118
- **Raw SQL update** – Seeding uses `Ecto.Adapters.SQL.query!` with positional parameters, which is safe but bypasses schema constraints. Wrap in transactions to prevent partial writes and ensure consistent state.@lib/live_poll_web/live/poll_live.ex#271-274
- **PubSub exposure** – Topic names are predictable. While Phoenix PubSub is internal, consider namespacing or scoping topics when introducing multi-tenant features to prevent accidental cross-talk.

## Recommendations

1. Gate seeding/reset operations behind admin authentication or feature flags; add rate limiting to public vote endpoints.
2. Replace inline scripts with bundled modules and adopt CSP headers with script nonces in production.
3. Validate language names via changesets (`validate_length`, `validate_format`) and normalize case to avoid duplicates.
4. Wrap seeding and reset flows in `Repo.transaction/1`, handling errors gracefully and logging outcomes.
5. Document PubSub topics and prepare for future access controls if rooms or scopes expand.
