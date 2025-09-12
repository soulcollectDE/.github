#!/usr/bin/env bash
set -euo pipefail

kept_n=$(jq 'length' triage/kept.json 2>/dev/null || echo 0)
ign_n=$(jq 'length' triage/ignored.json 2>/dev/null || echo 0)

{
  echo "### Dependabot Auto-Triage – ${REPO}"
  echo
  echo "**Alerts (gefiltert nach min_severity=${MIN_SEVERITY}):** kept=${kept_n}, ignored=${ign_n}"
  echo
  echo "#### Kandidaten zum Entfernen (unused ∩ alerts / dev-noncritical)"
  jq -r '.[] | "- `\(.ecosystem):\(.package)` (sev: \(.severity), dev: \(.dev), used: \(.used)) \(.manifest)"' triage/ignored.json || true
  echo
  echo "#### Relevante Alerts (bleiben offen)"
  jq -r '.[] | "- `\(.ecosystem):\(.package)` (sev: \(.severity), dev: \(.dev), used: \(.used)) \(.manifest)"' triage/kept.json || true
} | tee triage/report.md
