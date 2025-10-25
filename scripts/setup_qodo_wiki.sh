#!/bin/bash

# Setup Qodo Merge configuration via GitHub Wiki
# This script creates or updates the .pr_agent.toml page in your GitHub Wiki

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Setting up Qodo Merge configuration in GitHub Wiki...${NC}"

# Get repository info
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
echo "Repository: $REPO"

# Create temporary directory for wiki
WIKI_DIR="/tmp/${REPO##*/}-wiki-$$"
WIKI_URL="https://github.com/${REPO}.wiki.git"

# Clone the wiki
echo "Cloning wiki..."
git clone "$WIKI_URL" "$WIKI_DIR" 2>/dev/null || {
    echo "Wiki doesn't exist yet. Creating first..."
    mkdir -p "$WIKI_DIR"
    cd "$WIKI_DIR"
    git init
    git remote add origin "$WIKI_URL"
    cd -
}

# Create the configuration file
cat > "$WIKI_DIR/.pr_agent.toml.md" << 'EOF'
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
EOF

# Commit and push
cd "$WIKI_DIR"
git add .
git commit -m "Update Qodo Merge configuration for Phoenix app" || echo "No changes to commit"
git push origin master 2>/dev/null || git push --set-upstream origin master

# Cleanup
cd -
rm -rf "$WIKI_DIR"

echo -e "${GREEN}✅ Wiki configuration complete!${NC}"
echo "View your wiki at: https://github.com/${REPO}/wiki"
echo "Configuration page: https://github.com/${REPO}/wiki/.pr_agent.toml"
