#!/usr/bin/env bash
set -euo pipefail
SAFE_NAME="$(echo "${REPO}" | tr '/' '-')"
echo "safe=${SAFE_NAME}" >> "${GITHUB_OUTPUT}"
