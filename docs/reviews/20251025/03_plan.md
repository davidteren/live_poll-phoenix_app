Based on the comprehensive code review documents located in `docs/reviews/20251025/collated/`, analyze all identified issues and recommendations across the following files:

1. `docs/reviews/20251025/collated/architecture.md`
2. `docs/reviews/20251025/collated/code-review.md`
3. `docs/reviews/20251025/collated/deprecations.md`
4. `docs/reviews/20251025/collated/model-analysis.md`
5. `docs/reviews/20251025/collated/performance.md`
6. `docs/reviews/20251025/collated/security.md`
7. `docs/reviews/20251025/collated/summary.md`
8. `docs/reviews/20251025/collated/testing.md`

Generate a comprehensive implementation plan that addresses ALL issues and recommendations found in these review documents. The plan should be organized into individual task files saved in `docs/reviews/20251025/plan/`.

Each task file must include:

1. **Task Title**: A clear, descriptive title
2. **Category**: Which review area this addresses (architecture, security, performance, testing, etc.)
3. **Priority**: High/Medium/Low based on severity and impact
4. **Description**: Detailed explanation of what needs to be done and why
5. **Current State**: Description of the existing problematic code/pattern
6. **Proposed Solution**: Specific implementation approach with code examples showing:
    - Before/after code snippets where applicable
    - Exact file paths that need modification
    - Specific functions, modules, or components to change
7. **Requirements**: Explicit list of what must be accomplished
8. **Definition of Done**: Clear, testable acceptance criteria including:
    - Specific tests that must pass
    - Code quality checks (bin/check must pass)
    - Any performance benchmarks or security validations
9. **Branch Name**: Suggested git branch name following the format `fix/descriptive-name` or `feature/descriptive-name`
10. **Dependencies**: Any tasks that must be completed before this one
11. **Estimated Complexity**: T-shirt sizing (S/M/L/XL) or story points

Organize the tasks logically by:
- Creating separate markdown files for each distinct task or closely related group of tasks
- Using a naming convention like `001-task-name.md`, `002-task-name.md`, etc.
- Grouping related tasks that should be tackled together
- Ordering tasks by priority and dependencies

Ensure the plan is actionable, comprehensive, and covers every issue mentioned in the review documents without omitting any recommendations.