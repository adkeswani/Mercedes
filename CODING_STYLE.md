# Coding Style Rules for This Repository

## General Principles
- Prioritize clarity and maintainability over brevity.
- Keep changes focused and minimal; avoid unrelated refactors.
- Use consistent, descriptive naming for all symbols.

## Formatting
- Use 2 spaces for indentation (or follow language default if enforced by tooling).
- Limit lines to 100 characters where possible.
- Always use UTF-8 encoding.

## Blocks and Newlines
- Insert a blank line after any block (e.g., after a multiline if/else, loop, or function/method/class definition).
- Insert a blank line between logically distinct steps or concepts within a function or method.
- Do not add unnecessary blank lines between consecutive single-line statements that are tightly related.
- Place a blank line before return statements unless returning immediately after a block.

## Braces and Control Flow
- Always use braces for if, else, for, while, and do/while blocks, even for single statements.
- The opening brace should be on the same line as the control statement.

## Imports and File Structure
- Group imports: standard library, third-party, then project-local, each separated by a blank line.
- Place all exports at the top of the file, after imports.

## Comments
- Use comments to explain why, not what, when the intent is not obvious.
- Use TODO and FIXME tags for actionable items.
- Document all public classes, methods, and exported symbols with doc comments.

## Dart/Flutter Specific
- Use trailing commas in multiline collection literals and parameter lists to enable automatic formatting.
- Prefer const constructors where possible.
- Use named constructors for alternate creation patterns.

## Git and Workflow
- Never commit directly to main; use topic branches and fast-forward merges.
- Update licensing and dependency docs with any dependency changes.

---

_These rules are intended to keep the codebase readable, maintainable, and consistent. Use automated linters and formatters where possible, but always review for clarity and intent._
