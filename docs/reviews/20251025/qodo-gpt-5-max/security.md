# LivePoll – Security & Best Practices

This document assesses security posture: CSRF, SQL injection, input validation, sanitization, and PubSub message handling.


## CSRF protection

- Router pipeline :browser includes plug :protect_from_forgery – enabled.
- root.html.heex sets <meta name="csrf-token"> and assets/js/app.js passes it into LiveSocket params – good.
- All form submissions and phx-click events operate under LiveView session with CSRF; no gaps identified.


## SQL injection

- Ecto is used with parameters; queries are parameterized (pin operator ^) where applicable (build_trend_data_from_events/1). No dynamic SQL interpolation by user input found.
- Seeding uses Ecto.Adapters.SQL.query! for UPDATE statement to adjust inserted_at. This does not include user input and is safe, but consider replacing with Repo.insert_all to avoid custom SQL entirely.


## Input validation and sanitization

- add_language: Accepts %{"name" => name}. Validates byte_size(name) > 0 but does not sanitize characters.
- The application derives CSS classes from language names (language_to_class/1) and uses those in HEEx and CSS. Current normalization handles #, +, and spaces, but other special characters might still slip through.

Risks:
- CSS selectors and HTML attributes may break or produce unexpected styles if language contains characters like /, ., [, ], (, ), @, etc.
- While LiveView escapes content in text nodes, attribute/class generation must ensure safe characters.

Recommendations:
- Strengthen language_to_class/1 to whitelist [a-z0-9_-] and replace all others with hyphen. For example:
  language
  |> String.downcase()
  |> String.replace(~r/[^a-z0-9_\-]+/u, "-")
  |> String.trim("-")
- Optionally validate language names against a policy (length limit, allowed characters) and return an error flash if invalid.


## Authorization and multi-tenant concerns

- This is a public demo app without auth. If exposing publicly, consider rate-limiting votes per client/IP and adding captcha or similar to prevent automated spam.


## PubSub message handling

- Messages are constructed by the server and broadcast; clients do not inject arbitrary messages.
- LiveView handle_info pattern matches on known tuples. No unsafe deserialization.


## Inline scripts

- root.html.heex includes an inline <script> for theme. While not a security risk per se with CSP default, project guidelines forbid inline scripts and CSP best practices typically disallow inline scripts to mitigate XSS. Moving this to assets/js and enabling a strict Content-Security-Policy would improve security.


## Error handling

- Heavy use of bang functions in LiveView handlers can crash the process on DB errors. This is not a direct security bug but can be used for disruption. Prefer non-bang operations and graceful error messages to maintain availability.


## Database integrity

- Add unique index on poll_options(text) to prevent duplicate languages due to race conditions.
- Consider NOT NULL constraints already present for vote_events; OK.


## Summary of actions

1. Strengthen language_to_class/1 sanitization; potentially validate input and show flash on invalid names.
2. Add unique index + changeset unique_constraint(:text) for options.
3. Move inline theme script to assets/js and configure CSP to disallow inline scripts.
4. Replace bang DB calls in LiveView with safe versions and report errors via flash.
5. Consider rate limiting and anti-abuse mechanisms if deployed publicly.
