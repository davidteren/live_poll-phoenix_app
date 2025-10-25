# Qodo Configuration Review and Cleanup

## Date: October 25, 2025

## Summary
Reviewed and cleaned up Qodo configuration files for the LivePoll Phoenix application. Removed invalid configurations and kept only what's necessary given that Qodo Merge is already installed via the GitHub app.

## Changes Made

### 1. **Removed Invalid Files**
- ✅ **Deleted `.qodo.yaml`** - This is NOT a valid Qodo configuration file. Qodo Merge uses `.pr_agent.toml` format only.
- ✅ **Deleted `.github/workflows/qodo-review.yml`** - Non-existent GitHub Action. The Qodo Merge GitHub app handles all PR automation.

### 2. **Cleaned Up `.pr_agent.toml`**
- ✅ Removed invalid model names (claude-41-opus, gpt-5-max, etc.)
- ✅ Removed non-existent configuration sections
- ✅ Reduced from 381 lines to 60 lines
- ✅ Kept only Phoenix/Elixir-specific instructions for:
  - PR descriptions
  - Code suggestions
  - Reviews
  - Ignore patterns for build artifacts

### 3. **Updated `.pre-commit-config.yaml`**
- ✅ Removed invalid Qodo CLI reference
- ✅ Consolidated multiple mix commands into `mix precommit` alias
- ✅ Kept useful Phoenix-specific checks

## What Qodo Merge GitHub App Provides

When you have Qodo Merge installed via GitHub app, it automatically:
- **Runs on PRs**: Automatically describes and reviews pull requests
- **Responds to commands**: `/describe`, `/review`, `/improve`, `/ask`, etc.
- **Uses default settings**: No configuration needed for basic functionality
- **Supports customization**: Via `.pr_agent.toml` for project-specific needs

## Final Configuration

### **UPDATE: Using GitHub Wiki Configuration**
We've moved the configuration to GitHub Wiki instead of keeping it in the repository. This provides cleaner separation of config from code. See `QODO_WIKI_SETUP.md` for setup instructions.

### Configuration Content (Now in Wiki, not in repo)
```toml
[config]
model = "gpt-4o-2024-08-06"  
fallback_models = ["gpt-4o-mini"]
verbosity_level = 0

[pr_description]
extra_instructions = """
- Focus on Elixir/Phoenix best practices
- Check for race conditions in database operations
- Verify proper error handling in LiveView event handlers
- Ensure no inline scripts in templates
- Verify atomic operations for counters
"""

[pr_code_suggestions]
num_code_suggestions = 5
extra_instructions = """
Priority suggestions for Phoenix/Elixir:
1. Replace read-modify-write patterns with atomic operations
2. Add unique constraints at database and changeset levels
3. Replace bang functions in event handlers with proper error handling
4. Use batch operations instead of individual inserts
5. Extract business logic from LiveView to context modules
"""

[pr_reviewer]
require_tests_review = true
require_security_review = true
extra_instructions = """
Focus on Phoenix/Elixir specific issues:
- Check for race conditions in counter updates
- Verify unique constraints are properly implemented
- Look for SQL injection risks
- Check for XSS vulnerabilities
- Verify proper error handling
- Check for N+1 query problems
- Ensure business logic is in context modules, not LiveView
"""

[ignore]
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

## Recommendations

1. **Keep it minimal**: Only configure what differs from defaults
2. **Use GitHub app**: Let Qodo Merge handle automation via the GitHub app
3. **Focus on language-specific**: Use `extra_instructions` for Phoenix/Elixir patterns
4. **No redundant tools**: Don't create workflows or pre-commit hooks for what the GitHub app already does

## Benefits of This Approach

- ✅ **Cleaner codebase**: No invalid or unnecessary configuration files
- ✅ **Reduced maintenance**: Fewer configurations to maintain
- ✅ **Leverages defaults**: Uses Qodo's battle-tested default settings
- ✅ **Phoenix-focused**: Customizations target specific Elixir/Phoenix patterns
- ✅ **No duplication**: GitHub app handles what it should, config only adds specifics

## Next Steps

1. Commit these changes
2. Test on your next PR to verify Qodo Merge works correctly
3. Adjust `extra_instructions` based on your team's specific needs
4. Consider adding team-specific patterns as you discover them
