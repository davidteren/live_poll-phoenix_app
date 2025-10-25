# Qodo Merge GitHub Wiki Configuration Setup

## Overview
Instead of keeping `.pr_agent.toml` in your repository, you can configure Qodo Merge via GitHub Wiki. This keeps your repo cleaner and allows configuration changes without code commits.

## Setup Steps

### 1. Enable GitHub Wiki
1. Go to your repository on GitHub
2. Navigate to **Settings** → **Features**
3. Check the **Wikis** checkbox if not already enabled

### 2. Create Configuration Page
1. Go to the **Wiki** tab in your repository
2. Click **Create the first page** (or **New Page** if wiki exists)
3. **IMPORTANT**: Name the page exactly: `.pr_agent.toml`
4. Paste the configuration below

### 3. Configuration Content
Copy and paste this entire block into the wiki page:

````markdown
```toml
# Qodo Merge Configuration for LivePoll Phoenix Application
# Minimal configuration - only settings that differ from defaults

[config]
# Use gpt-4o as primary model for better performance/cost ratio
model = "gpt-4o-2024-08-06"  
fallback_models = ["gpt-4o-mini"]
verbosity_level = 0  # Reduce noise in PR comments

[pr_description]
# Keep default description settings, just add Phoenix-specific context
extra_instructions = """
- Focus on Elixir/Phoenix best practices
- Check for race conditions in database operations  
- Verify proper error handling in LiveView event handlers
- Ensure no inline scripts in templates
- Verify atomic operations for counters (Repo.update_all with inc:)
"""

[pr_code_suggestions]
num_code_suggestions = 5
# Focus on Phoenix/Elixir specific patterns
extra_instructions = """
Priority suggestions for Phoenix/Elixir:
1. Replace read-modify-write patterns with atomic operations (Repo.update_all with inc:)
2. Add unique constraints at database and changeset levels
3. Replace bang functions in event handlers with proper error handling
4. Use batch operations (Repo.insert_all) instead of individual inserts
5. Extract business logic from LiveView to context modules
"""

[pr_reviewer]
# Focus review on Phoenix/Elixir patterns
require_tests_review = true
require_security_review = true
extra_instructions = """
Focus on Phoenix/Elixir specific issues:
- Check for race conditions in counter updates
- Verify unique constraints are properly implemented
- Look for SQL injection risks (Ecto.Adapters.SQL.query!)
- Check for XSS vulnerabilities in user content
- Verify proper error handling (no bang functions in handlers)
- Check for N+1 query problems with associations
- Ensure business logic is in context modules, not LiveView
"""

[ignore]
# Phoenix/Elixir build artifacts and dependencies
glob_patterns = [
    "_build/**",
    "deps/**",
    ".elixir_ls/**",
    "node_modules/**",
    "priv/static/**",
    "*.beam",
    "mix.lock",
    "package-lock.json"
]
```
````

### 4. Save the Wiki Page
1. Add a commit message like "Add Qodo Merge configuration"
2. Click **Save Page**

## Verification

After setup, Qodo Merge will automatically:
1. Read configuration from the Wiki on each PR
2. Apply your Phoenix-specific review instructions
3. Ignore build artifacts and dependencies

## Testing

Create a test PR with some Phoenix code changes and verify:
- Qodo Merge comments on the PR
- It follows your custom instructions
- It suggests Phoenix-specific improvements

## Advantages of Wiki Configuration

✅ **No config files in repo** - Keeps codebase clean  
✅ **Easy updates** - Change config without code commits  
✅ **Version controlled** - Wiki has its own git history  
✅ **Team accessible** - Anyone with repo access can update  
✅ **Immediate effect** - Changes apply to new PRs instantly  

## Notes

- Wiki page must be named exactly `.pr_agent.toml`
- Configuration must be wrapped in ` ```toml ` code block
- Changes take effect on new PR events (not retroactive)
- You can view Wiki history to track configuration changes

## Troubleshooting

If Qodo Merge isn't picking up your Wiki configuration:
1. Verify the page name is exactly `.pr_agent.toml`
2. Check that the TOML is wrapped in ` ```toml ` blocks
3. Ensure the Wiki is public (not private)
4. Test with a new PR or PR comment command like `/describe`
