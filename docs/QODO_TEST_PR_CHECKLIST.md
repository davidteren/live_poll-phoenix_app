# Qodo Merge Wiki Configuration Test Checklist

## PR Link
https://github.com/davidteren/live_poll-phoenix_app/pull/3

## Test Patterns Included

### In `lib/live_poll/test_qodo.ex`:
- [ ] **Race Condition Pattern**: `increment_vote_count/1` - Should suggest atomic operations
- [ ] **Bulk Operations**: `create_multiple_votes/1` - Should suggest `Repo.insert_all`
- [ ] **Memory Issue**: `get_all_events/0` - Should warn about loading all records
- [ ] **Good Pattern**: `atomic_increment/1` - Should recognize as correct

### In `lib/live_poll_web/live/test_live.ex`:
- [ ] **Bang Functions**: `handle_event("create_option")` - Should warn about bang functions in handlers
- [ ] **Business Logic**: `handle_event("complex_calculation")` - Should suggest moving to context

## Expected Qodo Merge Responses

### 1. Auto-Generated PR Description
- [ ] Uses Phoenix/Elixir terminology
- [ ] Identifies the test patterns correctly
- [ ] Follows our custom instructions from Wiki

### 2. Code Review Comments
- [ ] Detects race condition and suggests atomic operations
- [ ] Identifies bulk insert opportunity
- [ ] Warns about loading all records into memory
- [ ] Flags bang functions in event handlers
- [ ] Suggests extracting business logic to contexts

### 3. Configuration Verification
- [ ] Uses `gpt-4o-2024-08-06` model (check in logs/output)
- [ ] Shows reduced verbosity (verbosity_level = 0)
- [ ] Ignores build artifacts (_build/**, deps/**, etc.)

## Commands to Test

After Qodo Merge's initial review, test these commands in PR comments:

```
/describe
```
- Should regenerate description with Phoenix focus

```
/review
```
- Should provide detailed Phoenix-specific review

```
/improve
```
- Should suggest Phoenix/Elixir improvements

```
/ask What are the race conditions in this code?
```
- Should identify the read-modify-write pattern

## Success Criteria

✅ PR is successful if:
1. Qodo Merge comments on the PR automatically
2. It identifies at least 3 of the problematic patterns
3. It uses Phoenix/Elixir-specific language in suggestions
4. The suggestions match our Wiki configuration instructions

## Troubleshooting

If Qodo Merge doesn't respond or doesn't use Wiki config:
1. Check Wiki page exists: https://github.com/davidteren/live_poll-phoenix_app/wiki/.pr_agent.toml
2. Verify page name is exactly `.pr_agent.toml`
3. Check TOML is wrapped in ` ```toml ` blocks
4. Try command `/config` in PR to see active configuration
5. Check Qodo Merge app installation: https://github.com/settings/installations

## Notes

- Qodo Merge typically responds within 1-2 minutes
- Initial auto-review happens on PR creation
- Manual commands can be used to trigger additional reviews
- Wiki changes apply to new PR events (not retroactive)
