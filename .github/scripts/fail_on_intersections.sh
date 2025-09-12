#!/usr/bin/env bash
set -euo pipefail
cnt=$(jq 'length' triage/ignored.json 2>/dev/null || echo 0)
if [ "${cnt}" -gt 0 ]; then
  echo "Unused/dev-noncritical Alerts vorhanden (${cnt}). Policy verlangt Fail."
  exit 1
fi
