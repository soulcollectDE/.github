#!/usr/bin/env bash
set -euo pipefail

#ignorieren weniger ballast
prune='-path "./.git" -prune -o -path "*/node_modules/*" -prune -o -path "*/vendor/*" -prune -o -path "*/.venv/*" -prune -o -path "*/venv/*" -prune -o -path "*/build/*" -prune -o -path "*/dist/*" -prune -o -path "*/target/*" -prune'

find_dirs_json() {
  # usage: find_dirs_json "pattern1" "pattern2" ...
  if [ "$#" -eq 0 ]; then echo "[]"; return; fi
  local q; q=$(printf ' -o -name %q' "$@")
  # shellcheck disable=SC2086
  bash -lc "find . $prune $q -print | xargs -I{} dirname {} | sort -u | jq -R . | jq -s ."
}

npm_paths="[]"; yarn_paths="[]"; pnpm_paths="[]"
pip_paths="[]"; poetry_paths="[]"; conda_paths="[]"
composer_paths="[]"
maven_paths="[]"; gradle_paths="[]"; ivy_paths="[]"
cargo_paths="[]"
nuget_paths="[]"
go_paths="[]"
rubygems_paths="[]"

#javascript / node.js
# npm
if ${INCLUDE_NPM:-true}; then
  # package.json primär, package-lock.json als Fallback/Signal
  npm_paths=$(find_dirs_json "package.json" "package-lock.json")
fi
# yarn
if ${INCLUDE_YARN:-true}; then
  yarn_paths=$(find_dirs_json "package.json" "yarn.lock")
fi
# pnpm
if ${INCLUDE_PNPM:-true}; then
  pnpm_paths=$(find_dirs_json "package.json" "pnpm-lock.yaml")
fi

#python
# pip / requirements.txt
if ${INCLUDE_PIP:-true}; then
  pip_paths=$(find_dirs_json "requirements.txt")
fi
# poetry (pyproject.toml, poetry.lock)
if ${INCLUDE_POETRY:-false}; then
  poetry_paths=$(find_dirs_json "pyproject.toml" "poetry.lock")
fi
# conda (environment.yml/.yaml)
if ${INCLUDE_CONDA:-false}; then
  conda_paths=$(find_dirs_json "environment.yml" "environment.yaml")
fi

#php
# composer
if ${INCLUDE_COMPOSER:-true}; then
  composer_paths=$(find_dirs_json "composer.json" "composer.lock")
fi

#java
# maven
if ${INCLUDE_MAVEN:-false}; then
  maven_paths=$(find_dirs_json "pom.xml")
fi
# gradle (build.gradle(.kts), optional gradle.lockfile)
if ${INCLUDE_GRADLE:-false}; then
  gradle_paths=$(find_dirs_json "build.gradle" "build.gradle.kts" "gradle.lockfile")
fi
# ivy
if ${INCLUDE_IVY:-false}; then
  ivy_paths=$(find_dirs_json "ivy.xml")
fi

# rust
if ${INCLUDE_CARGO:-false}; then
  cargo_paths=$(find_dirs_json "Cargo.toml" "Cargo.lock")
fi

#.net
if ${INCLUDE_NUGET:-false}; then
  nuget_paths=$(bash -lc "
    {
      find . $prune -o -name '*.csproj' -print
      find . $prune -o -name '*.fsproj' -print
      find . $prune -o -name '*.vbproj' -print
      find . $prune -o -name 'packages.config' -print
      find . $prune -o -name 'packages.lock.json' -print
      find . $prune -o -name 'Directory.Packages.props' -print
      find . $prune -o -name 'Directory.Packages.targets' -print
    } | xargs -I{} dirname {} | sort -u | jq -R . | jq -s .
  ")
fi

# go 
if ${INCLUDE_GO:-true}; then
  go_paths=$(find_dirs_json "go.mod" "go.sum")
fi

# Ruby
if ${INCLUDE_RUBYGEMS:-false}; then
  rubygems_paths=$(find_dirs_json "Gemfile" "Gemfile.lock" "*.gemspec")
fi

# Emit combined JSON
jq -n \
  --argjson npm      "$npm_paths" \
  --argjson yarn     "$yarn_paths" \
  --argjson pnpm     "$pnpm_paths" \
  --argjson pip      "$pip_paths" \
  --argjson poetry   "$poetry_paths" \
  --argjson conda    "$conda_paths" \
  --argjson composer "$composer_paths" \
  --argjson maven    "$maven_paths" \
  --argjson gradle   "$gradle_paths" \
  --argjson ivy      "$ivy_paths" \
  --argjson cargo    "$cargo_paths" \
  --argjson nuget    "$nuget_paths" \
  --argjson go       "$go_paths" \
  --argjson rubygems "$rubygems_paths" \
  '{
     npm: $npm,
     yarn: $yarn,
     pnpm: $pnpm,
     pip: $pip,
     poetry: $poetry,
     conda: $conda,
     composer: $composer,
     maven: $maven,
     gradle: $gradle,
     ivy: $ivy,
     cargo: $cargo,
     nuget: $nuget,
     go: $go,
     rubygems: $rubygems
   }' > manifests.json

echo "Generated manifests.json:"
cat manifests.json
