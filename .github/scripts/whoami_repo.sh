#!/usr/bin/env bash
set -euo pipefail
echo "== gh auth status =="
gh auth status || true

echo "== repo probe =="
gh api -i "repos/${REPO}" | head -n 20 || true

echo "== dependabot alerts probe =="
# erwartet 200/OK oder eine paginierte leere Liste, bei fehlenden Rechten eher 403
gh api -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  "repos/${REPO}/dependabot/alerts?per_page=1" -i | head -n 20 || true

