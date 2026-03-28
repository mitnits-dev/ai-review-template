# CLAUDE.md

## PR review follow-up workflow

When working on a branch with an open GitHub pull request and the user asks to address review feedback:

1. Stay on the current branch.
2. Do not merge the PR.
3. Fetch the latest PR review briefing with:

```bash
/home/mitnits/.openclaw/workspace/skills/gh-address-pr-review/scripts/fetch-pr-review.sh <pr-number>
```

4. Read the generated file under `.ai/pr-review-<pr-number>.md`.
5. Fix only valid, actionable findings.
6. Update tests or docs if needed.
7. Commit and push the follow-up changes.
8. Briefly explain which comments were applied and which were intentionally ignored.

## Notes

- Prefer human reviewer comments over bot comments when they conflict.
- Avoid churn edits when the review contains no real issues.
- Keep changes targeted to the review findings unless the user asks for broader refactoring.
