#!/usr/bin/env bash
set -euo pipefail

items=$(jq -c '
  ([.npm[]?      | {type:"npm",      path:.}] // []) +
  ([.yarn[]?     | {type:"yarn",     path:.}] // []) +
  ([.pnpm[]?     | {type:"pnpm",     path:.}] // []) +
  ([.pip[]?      | {type:"pip",      path:.}] // []) +
  ([.poetry[]?   | {type:"poetry",   path:.}] // []) +
  ([.conda[]?    | {type:"conda",    path:.}] // []) +
  ([.composer[]? | {type:"composer", path:.}] // []) +
  ([.maven[]?    | {type:"maven",    path:.}] // []) +
  ([.gradle[]?   | {type:"gradle",   path:.}] // []) +
  ([.ivy[]?      | {type:"ivy",      path:.}] // []) +
  ([.cargo[]?    | {type:"cargo",    path:.}] // []) +
  ([.nuget[]?    | {type:"nuget",    path:.}] // []) +
  ([.go[]?       | {type:"go",       path:.}] // []) +
  ([.rubygems[]? | {type:"rubygems", path:.}] // [])
' manifests.json)

if [ -z "${items}" ] || [ "$(jq 'length' <<<"${items}")" -eq 0 ]; then
  items='[{"type":"none","path":"."}]'
fi

echo "matrix={\"include\":$(echo "${items}")}" >> "${GITHUB_OUTPUT}"
jq -r <<< "{\"include\": ${items}}"

#steps.matrix.outputs.matrix enthält die JSON-Matrix
