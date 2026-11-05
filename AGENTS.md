# Agent Instructions

## Purpose
This file provides guidance to AI agents working in this repository. Follow these instructions to maintain consistency, quality, and safety.

## Core Principles
- Understand before changing: Read relevant code, tests, and docs first
- Make minimal, focused changes that solve the stated problem
- Follow existing patterns, conventions, and architecture
- Test your changes before considering them complete
- Leave the codebase better than you found it

## Repository Exploration
Before making significant changes:
1. Read README.md, package.json/pyproject.toml, and other config files
2. Understand the project structure, build system, and dependencies
3. Look for existing tests to understand expected behavior
4. Check git history and current branch state

## Development Workflow
1. **Inspect** - Understand the codebase and identify what needs to change
2. **Plan** - Break down the task into clear steps
3. **Implement** - Make changes following existing patterns
4. **Test** - Run relevant tests and linters
5. **Verify** - Ensure changes work as expected
6. **Review** - Check for unintended side effects

## Code Quality
- Write clear, self-documenting code
- Follow the project's style guide (check existing code)
- Add/update tests for new functionality
- Keep functions small and focused
- Handle errors appropriately
- Avoid over-engineering

## Testing
- Run tests related to your changes
- Don't skip failing tests without understanding why
- If tests fail due to your changes, fix them
- If tests are outdated, update them appropriately

## Git Practices
- Make atomic, well-described commits
- Don't commit secrets, keys, or sensitive data
- Check `git status` before committing
- Keep changes focused and reviewable

## Safety Rules
- Never commit secrets or credentials
- Respect existing authentication/authorization patterns
- Don't modify unrelated code
- Be careful with destructive operations
- Ask for clarification on high-risk changes

## Communication
- Be concise and focused
- Explain what you changed and why
- Report test results and verification steps
- Flag any issues or concerns
