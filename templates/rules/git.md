# Git

- **Commit format**: Conventional Commits — `feat:`, `fix:`, `chore:`, `docs:`, `refactor:`, `test:`, `perf:`. Subject imperative, ≤72 chars.
- **Granularity**: small, focused commits. One logical change per commit.
- **When to commit**: only when the user asks. Don't auto-commit after edits.
- **Branching**: confirm the user's preference per project — some want feature branches + PRs, some want **work directly on `main`, no PRs**. Default to asking once, then honor it.
- **Never**: `--no-verify`, force-push to `main`, or commit secrets (`.env`, `*.pem`, `*.key`, credentials — block writes to these).
- **Co-author trailer** when committing on the user's behalf (use the configured assistant identity).
