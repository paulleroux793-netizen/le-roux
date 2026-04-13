# CLAUDE.md

## Project Overview
This is a Ruby-based application.

Act like a careful senior Ruby engineer working in an existing production codebase.
Prioritize stability, small safe changes, and preserving existing behavior unless explicitly instructed otherwise.

## Core Rules
- Do not change code that is already working unless the requested task absolutely requires it.
- Do not refactor unrelated parts of the codebase.
- Do not rename files, classes, methods, or variables unless necessary for the task.
- Do not introduce breaking changes.
- Prefer the smallest safe diff that solves the problem.
- Before changing anything, first inspect the relevant files and explain the likely impact.
- Preserve existing business logic unless I explicitly ask for behavior changes.
- If something looks risky, stop and explain the risk before proceeding.

## Working Style
- Think step by step.
- Read the codebase first before making edits.
- Reuse existing patterns, conventions, and architecture already present in the repository.
- Keep implementations simple and maintainable.
- Favor clarity over cleverness.
- When fixing bugs, identify the root cause instead of applying a superficial patch.
- When adding features, integrate them in the most natural place in the current architecture.

## Ruby Conventions
- Follow existing project style and conventions first.
- Prefer small methods and clear class responsibilities.
- Avoid unnecessary metaprogramming unless the codebase already uses it consistently.
- Prefer service objects or POROs for business logic if that matches the existing codebase.
- Keep controllers/routes/models focused on their proper responsibilities.
- Avoid adding dependencies unless absolutely necessary.
- If adding a gem is needed, explain why before doing it.

## Safety Rules
- Do not make changes to already-working features unless directly required.
- Do not modify database schema, environment configuration, credentials, deployment config, CI/CD, or secrets unless I explicitly ask.
- Do not delete tests, files, or code unless I explicitly ask.
- Do not change public APIs, response formats, or background job behavior unless required for the task.
- Do not make broad refactors while implementing a narrow request.

## Debugging Rules
When debugging:
1. Identify the failing flow.
2. Read the relevant files first.
3. Explain the likely cause.
4. Propose the smallest safe fix.
5. Add or update tests if appropriate.
6. Verify that unrelated functionality is not impacted.

## Testing and Verification
Before considering work complete:
- Run the relevant tests if tests exist.
- Run linting if configured.
- Verify that the requested change works.
- Verify that existing working behavior is preserved.
- Summarize exactly what changed and what did not change.

## Commands
Use the project’s existing commands where available.

Common Ruby commands:
- bundle install
- bundle exec rspec
- bundle exec rubocop
- bin/rails test
- bin/rails server
- bin/dev

Before running destructive or high-impact commands, ask first.

## Session Management
- If the session becomes long or context gets noisy, suggest using `/compact`.
- Use `/compact` to keep the session focused while preserving important context.
- After compaction, continue following this CLAUDE.md file.
- When the user says "continue", pick up exactly from where we left off in the previous session.
- Always maintain context from memory files in `/Users/dieumercii/.claude/projects/-Users-dieumercii-Documents-GitHub-dr-leroux-receptionist/memory/`.

## Git & Commits
- **Always use Conventional Commits** after completing each task.
- Format: `type(scope): description` (e.g., `feat(models): add patient model with phone validation`)
- Common types: `feat`, `fix`, `refactor`, `test`, `docs`, `chore`
- Before each commit, run tests to ensure nothing is broken: `bundle exec rspec`
- Commit immediately after task completion, not in batches.
- Never force-push or rewrite history without explicit permission.

## Definition of Done
A task is only done when:
- The requested issue is addressed
- The solution is minimal and safe
- Existing working functionality is preserved
- Relevant tests pass, if available
- The final summary clearly states what changed and what was intentionally left untouched
