# AI Review Template

Starter template for new coding projects with an AI pull request reviewer already wired in.

## What this template includes

- GitHub Actions workflow for PR review: `.github/workflows/ai-review.yml`
- Review rubric: `REVIEW.md`

## What you must do after creating a repo from this template

1. Open your new repository on GitHub.
2. Go to **Settings** → **Secrets and variables** → **Actions**.
3. Add a repository secret named `GEMINI_API_KEY`.
4. Open or update a pull request to trigger the reviewer.

## How it works

On each pull request open/update, GitHub Actions:

1. Checks out the repository
2. Reads `REVIEW.md` and selected repo context files if present
3. Collects the PR changed-file patches
4. Sends the review prompt to Gemini
5. Posts the result as a PR comment via `github-actions[bot]`

## Notes

- This starter posts a PR comment; it does not auto-approve or auto-request-changes yet.
- You can customize `REVIEW.md` per project.
- You can extend the workflow later to add stricter gating or line comments.

## Author-side follow-up with Claude CLI

After the AI reviewer comments on a PR, you can ask local Claude CLI to address the feedback:

```bash
./scripts/address-pr-review.sh <pr-number>
```

The script fetches PR comments and reviews from GitHub, builds a focused prompt, and runs `claude -p ...` in the repo.

You can pass extra Claude CLI arguments after the PR number if needed.
