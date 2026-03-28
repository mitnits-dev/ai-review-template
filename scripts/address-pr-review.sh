#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <pr-number> [claude-extra-args...]" >&2
  exit 1
fi

PR_NUMBER="$1"
shift || true

if ! command -v gh >/dev/null 2>&1; then
  echo "gh CLI is required" >&2
  exit 1
fi

if ! command -v claude >/dev/null 2>&1; then
  echo "claude CLI is required" >&2
  exit 1
fi

REPO_JSON="$(gh repo view --json nameWithOwner,defaultBranchRef,currentBranch)"
REPO="$(printf '%s' "$REPO_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin)["nameWithOwner"])')"
DEFAULT_BRANCH="$(printf '%s' "$REPO_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin)["defaultBranchRef"]["name"])')"
CURRENT_BRANCH="$(git branch --show-current)"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

COMMENTS_JSON="$TMP_DIR/comments.json"
REVIEWS_JSON="$TMP_DIR/reviews.json"
PROMPT_FILE="$TMP_DIR/prompt.txt"

# PR issue comments (includes github-actions[bot] comments posted by the review workflow)
gh api "repos/$REPO/issues/$PR_NUMBER/comments" > "$COMMENTS_JSON"
# PR reviews (useful if later the workflow starts submitting real reviews)
gh api "repos/$REPO/pulls/$PR_NUMBER/reviews" > "$REVIEWS_JSON"

python3 <<'PY' "$REPO" "$PR_NUMBER" "$DEFAULT_BRANCH" "$CURRENT_BRANCH" "$COMMENTS_JSON" "$REVIEWS_JSON" "$PROMPT_FILE"
import json, sys
repo, pr_number, default_branch, current_branch, comments_path, reviews_path, prompt_path = sys.argv[1:]

with open(comments_path, 'r', encoding='utf-8') as f:
    comments = json.load(f)
with open(reviews_path, 'r', encoding='utf-8') as f:
    reviews = json.load(f)

def simplify_comments(items):
    out = []
    for item in items:
        body = (item.get('body') or '').strip()
        if not body:
            continue
        out.append({
            'author': item.get('user', {}).get('login'),
            'created_at': item.get('created_at'),
            'body': body,
        })
    return out

def simplify_reviews(items):
    out = []
    for item in items:
        body = (item.get('body') or '').strip()
        state = item.get('state')
        if not body and not state:
            continue
        out.append({
            'author': item.get('user', {}).get('login'),
            'submitted_at': item.get('submitted_at'),
            'state': state,
            'body': body,
        })
    return out

comments_simple = simplify_comments(comments)
reviews_simple = simplify_reviews(reviews)

prompt = f"""You are the author agent working in the local git repository.

Repository: {repo}
PR number: {pr_number}
Default branch: {default_branch}
Current branch: {current_branch}

Task:
1. Read the PR feedback below.
2. Identify which comments contain valid, actionable issues.
3. Fix the code for valid issues only. Do not blindly obey weak or incorrect suggestions.
4. Update tests/docs if needed.
5. Show a concise summary of what you changed.
6. Commit your changes to the current branch and push them.

Important constraints:
- Stay on the current branch.
- Do not merge the PR.
- Do not switch to the default branch.
- If there are no valid issues, explain why and do not make unnecessary edits.

PR issue comments:
{json.dumps(comments_simple, ensure_ascii=False, indent=2)}

PR reviews:
{json.dumps(reviews_simple, ensure_ascii=False, indent=2)}
"""

with open(prompt_path, 'w', encoding='utf-8') as f:
    f.write(prompt)
PY

claude -p "$(cat "$PROMPT_FILE")" "$@"
