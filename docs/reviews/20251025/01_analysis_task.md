Perform a comprehensive technical analysis of the LivePoll Phoenix application and document your findings in the 
`wip/qodo-gpt-5-max/ directory. Create separate, well-organized markdown files for each analysis area.

Your analysis should include:

1. **Code Review** (`code-review.md`):
    - Review all Elixir modules in `lib/` for code quality, best practices, and potential improvements
    - Analyze LiveView components for proper use of Phoenix LiveView patterns
    - Check Ecto schemas and queries for optimization opportunities
    - Review JavaScript hooks in `assets/js/` for proper integration with LiveView
    - Identify any code smells, anti-patterns, or violations of Elixir/Phoenix conventions
    - Assess error handling and edge case coverage

2. **Deprecated Code & Dependencies** (`deprecations.md`):
    - Identify any deprecated Phoenix, Ecto, or Elixir functions/patterns currently in use
    - Check for outdated LiveView patterns (e.g., `live_redirect` vs `push_navigate`)
    - Review `mix.exs` dependencies for outdated versions
    - Check `assets/package.json` for outdated npm packages
    - Flag any security vulnerabilities in dependencies
    - Identify DaisyUI usage and whether it's necessary given minimal adoption

3. **Architecture & Design Patterns** (`architecture.md`):
    - Document the overall application structure and data flow
    - Analyze the PubSub implementation for real-time updates
    - Review the time-series event system and data bucketing approach
    - Assess the separation of concerns between LiveView, Ecto, and business logic
    - Evaluate the chart integration strategy (ECharts with Phoenix hooks)

4. **Performance & Optimization** (`performance.md`):
    - Identify potential performance bottlenecks in database queries
    - Review the seeding process (10,000 votes) for efficiency
    - Analyze the trend data calculation and bucketing logic
    - Check for N+1 query problems
    - Assess memory usage patterns with LiveView streams

5. **Testing & Quality** (`testing.md`):
    - Review existing test coverage (if any)
    - Identify untested critical paths
    - Suggest test cases for LiveView interactions, voting, and real-time updates
    - Recommend integration tests for the seeding and trend calculation features

6. **Security & Best Practices** (`security.md`):
    - Review CSRF protection and authentication (if applicable)
    - Check for SQL injection vulnerabilities
    - Assess input validation and sanitization
    - Review PubSub message handling for potential security issues

7. **Summary & Recommendations** (`summary.md`):
    - Provide an executive summary of findings
    - Prioritize issues by severity (critical, high, medium, low)
    - Offer actionable recommendations for improvements
    - Suggest a roadmap for addressing technical debt

Be thorough and specific in your analysis. Include code examples where relevant, reference specific file paths and line numbers, and provide concrete recommendations for improvements. Focus on practical, actionable insights rather than theoretical concerns.