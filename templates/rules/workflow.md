# Development workflow (automatic)

Follow this for every coding task — scale rigor to size. No slash commands needed; invoke the matching behavior yourself.

## Scale by size
- **Trivial** (typo, one-liner, rename): do it, then verify.
- **Small** (single function/file): implement test-first, run tests, self-review the diff.
- **Medium** (multiple files, new behavior): clarify if ambiguous → plan → test-first → review → verify.
- **Large** (3+ independent tasks, structural): plan with an architect → subagent-driven implementation → review each piece → verify.

## The loop
1. **Clarify** — if requirements are ambiguous, ask 2-3 focused questions before coding.
2. **Plan** — for medium+, bite-sized steps with exact file paths. Challenge the plan once (devil's advocate).
3. **Implement** — test-first (RED → GREEN → REFACTOR). Smallest change that works.
4. **Review** — spec compliance first, then code quality, in a fresh perspective.
5. **Verify** — never claim done/fixed/passing without fresh evidence: run it, show the output.

## Non-negotiables
- After 2 failed attempts at the same approach, stop and rethink — don't brute-force.
- Stay on the task in the current message; don't silently expand scope.
- Pre-existing failures aren't yours to fix mid-task — surface them, then proceed.
- Delegate verbose operations (test runs, log analysis) to subagents to preserve context.
- Capture non-obvious fixes as durable learnings so they're never relearned.
