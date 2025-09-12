#!/usr/bin/env bash
set -euo pipefail

# Erzeugt: Dateien in triage/sub/, z. B.:
#   {idx}_npm_used.txt, {idx}_npm_unused.txt

mkdir -p triage/sub

jq -c '.include[]' <<< "${MATRIX_JSON}" | nl -ba | while read -r idx line; do
  type=$(jq -r '.type' <<<"${line}")
  path=$(jq -r '.path' <<<"${line}")

  echo "::group::Scan [${idx}] ${type} @ ${path}"

  case "${type}" in
    # ───────────────────────── JS/TS: npm, yarn, pnpm ─────────────────────────
    npm)
      pushd "${path}" >/dev/null
      if [ -f package-lock.json ]; then
        npm ci --silent || npm install --silent || true
      else
        npm install --silent || true
      fi
      npx --yes depcheck --json > depcheck.json || echo '{}' > depcheck.json
      jq -r '(.using // {}) | keys[]?' depcheck.json | sort -u > ../..//triage/sub/${idx}_npm_used.txt || true
      jq -r '((.dependencies // []) + (.devDependencies // []))[]?' depcheck.json | sort -u > ../..//triage/sub/${idx}_npm_unused.txt || true
      popd >/dev/null
      ;;

    yarn)
      pushd "${path}" >/dev/null
      if command -v yarn >/dev/null 2>&1; then
        yarn install --silent || true
      else
        # Fallback via Corepack (sollte im Setup enabled sein)
        corepack yarn install --silent || true
      fi
      npx --yes depcheck --json > depcheck.json || echo '{}' > depcheck.json
      jq -r '(.using // {}) | keys[]?' depcheck.json | sort -u > ../..//triage/sub/${idx}_yarn_used.txt || true
      jq -r '((.dependencies // []) + (.devDependencies // []))[]?' depcheck.json | sort -u > ../..//triage/sub/${idx}_yarn_unused.txt || true
      popd >/dev/null
      ;;

    pnpm)
      pushd "${path}" >/dev/null
      if command -v pnpm >/dev/null 2>&1; then
        pnpm i --silent || true
      else
        corepack pnpm i --silent || true
      fi
      npx --yes depcheck --json > depcheck.json || echo '{}' > depcheck.json
      jq -r '(.using // {}) | keys[]?' depcheck.json | sort -u > ../..//triage/sub/${idx}_pnpm_used.txt || true
      jq -r '((.dependencies // []) + (.devDependencies // []))[]?' depcheck.json | sort -u > ../..//triage/sub/${idx}_pnpm_unused.txt || true
      popd >/dev/null
      ;;

    # ───────────────────────── Python: pip, poetry, conda ─────────────────────
    pip)
      pushd "${path}" >/dev/null
      python -m pip install --upgrade pip >/dev/null 2>&1 || true
      if [ -f requirements.txt ]; then
        pip install -r requirements.txt >/dev/null 2>&1 || true
      fi
      pip install pip-check-reqs >/dev/null 2>&1 || true
      # „extra“ = deklariert aber nicht importiert → heuristisch „unused“
      (pip-extra-reqs . || true) | awk '/^\*/{print $2}' | sed 's/==.*//' | sort -u > ../..//triage/sub/${idx}_pip_extra.txt || true
      popd >/dev/null
      ;;

    poetry)
      pushd "${path}" >/dev/null
      python -m pip install --upgrade pip >/dev/null 2>&1 || true
      pip install poetry pip-check-reqs >/dev/null 2>&1 || true
      # Exportiere Poetry-Env als requirements und prüfe dann wie pip
      if poetry --version >/dev/null 2>&1; then
        poetry export -f requirements.txt --without-hashes -o /tmp/poetry-req.txt || true
        if [ -s /tmp/poetry-req.txt ]; then
          pip install -r /tmp/poetry-req.txt >/dev/null 2>&1 || true
        fi
      fi
      (pip-extra-reqs . || true) | awk '/^\*/{print $2}' | sed 's/==.*//' | sort -u > ../..//triage/sub/${idx}_poetry_extra.txt || true
      popd >/dev/null
      ;;

    conda)
      pushd "${path}" >/dev/null
      # Heuristik: liste deklarierte conda deps; wirkliche "unused"-Analyse ist nicht trivial
      if [ -f environment.yml ] || [ -f environment.yaml ]; then
        yfile=$( [ -f environment.yml ] && echo environment.yml || echo environment.yaml )
        awk '/^\s*-\s*[a-zA-Z0-9_.-]+/{gsub("- ","");print}' "$yfile" | sed 's/[=<>].*$//' | sort -u > ../..//triage/sub/${idx}_conda_deps.txt || true
      else
        : > ../..//triage/sub/${idx}_conda_deps.txt
      fi
      popd >/dev/null
      ;;

    # ───────────────────────── PHP: Composer ──────────────────────────────────
    composer)
      pushd "${path}" >/dev/null
      composer -n install || true
      composer global require composer-unused/composer-unused --no-interaction || true
      composer-unused --format=json > comp_unused.json || echo '{"unused":[]}' > comp_unused.json
      jq -r '.unused[]?' comp_unused.json | sort -u > ../..//triage/sub/${idx}_composer_unused.txt || true
      popd >/dev/null
      ;;

    # ───────────────────────── JVM: Maven, Gradle, Ivy ────────────────────────
    maven)
      pushd "${path}" >/dev/null
      mvn -q -DskipTests dependency:analyze -DfailOnWarning=false || true
      # Heuristik: aus build.log ungenutzte Artefakte extrahieren (Plugin-Format variiert)
      grep -E "Unused declared dependencies found:" -A9999 target/*/build.log 2>/dev/null \
        | awk '/^\[INFO\]/{print $3}' | sed 's/://g' | sort -u > ../..//triage/sub/${idx}_maven_unused.txt || true
      popd >/dev/null
      ;;

    gradle)
      pushd "${path}" >/dev/null
      # Falls Wrapper vorhanden, nutze den; ansonsten globales gradle
      if [ -x "./gradlew" ]; then
        ./gradlew -q help || true
        ./gradlew -q dependencies || true
      else
        if command -v gradle >/dev/null 2>&1; then
          gradle -q help || true
          gradle -q dependencies || true
        fi
      fi
      # Ohne zusätzliches Plugin ist „unused“ schwierig → leere Datei als Platzhalter
      : > ../..//triage/sub/${idx}_gradle_unused.txt
      popd >/dev/null
      ;;

    ivy)
      pushd "${path}" >/dev/null
      # Ivy-Analyse erfordert meist Ant/Ivy-Setup; wir erzeugen einen Platzhalter
      # Liste vorhandener ivy.xml-Dateien im Pfad
      find . -maxdepth 2 -name "ivy.xml" -print | sed 's|^\./||' | sort -u > ../..//triage/sub/${idx}_ivy_manifests.txt || true
      : > ../..//triage/sub/${idx}_ivy_unused.txt
      popd >/dev/null
      ;;

    # ───────────────────────── Rust: Cargo ────────────────────────────────────
    cargo)
      pushd "${path}" >/dev/null
      # "unused"-Analyse wäre mit cargo-udeps (Nightly) möglich; hier heuristisch:
      # Liste deklarierter Dependencies aus Cargo.toml
      if [ -f Cargo.toml ]; then
        awk '/^\[dependencies\]/,/^\[/{if($0 !~ /^\[/){print $0}}' Cargo.toml | \
          sed -n 's/^\s*\([A-Za-z0-9_.-]\+\)\s*=.*$/\1/p' | sort -u > ../..//triage/sub/${idx}_cargo_deps.txt || true
      else
        : > ../..//triage/sub/${idx}_cargo_deps.txt
      fi
      : > ../..//triage/sub/${idx}_cargo_unused.txt
      popd >/dev/null
      ;;

    # ───────────────────────── .NET: NuGet ────────────────────────────────────
    nuget)
      pushd "${path}" >/dev/null
      # Sammle PackageReference-Einträge aus Projekten
      {
        grep -RhoP '<PackageReference\s+Include="([^"]+)"' --include="*.csproj" --include="*.fsproj" --include="*.vbproj" 2>/dev/null | sed -n 's/.*Include="\([^"]\+\)".*/\1/p'
        grep -RhoP '<package\s+id="([^"]+)"' packages.config 2>/dev/null | sed -n 's/.*id="\([^"]\+\)".*/\1/p'
      } | sort -u > ../..//triage/sub/${idx}_nuget_refs.txt || true
      # dotnet restore (optional) – „unused“ nicht trivial → Platzhalter
      dotnet restore >/dev/null 2>&1 || true
      : > ../..//triage/sub/${idx}_nuget_unused.txt
      popd >/dev/null
      ;;

    # ───────────────────────── Go: Modules ────────────────────────────────────
    go)
      pushd "${path}" >/dev/null
      # Heuristik: tidy -v listet entfernte/unnötige Module in der Ausgabe
      tmpfile="$(mktemp)"
      (go mod tidy -v 2>&1 || true) | awk '/unused/{print $NF}' >> "${tmpfile}" || true
      # "why -m all" → Module ohne Kette zum main sind ungenutzt
      if go list -m all >/dev/null 2>&1; then
        while read -r mod; do
          [ -z "$mod" ] && continue
          if go mod why -m "$mod" 2>&1 | grep -q 'main module does not need'; then
            echo "$mod" >> "${tmpfile}"
          fi
        done < <(go list -m -f '{{if not (eq .Main true)}}{{.Path}}{{end}}' all 2>/dev/null | sort -u)
      fi
      sort -u "${tmpfile}" > ../..//triage/sub/${idx}_go_unused.txt || true
      rm -f "${tmpfile}"
      popd >/dev/null
      ;;

    # ───────────────────────── Ruby: RubyGems/Bundler ────────────────────────
    rubygems)
      pushd "${path}" >/dev/null
      # Install & Analyse – bundler-unused liefert unbenutzte Gems (best effort)
      if command -v bundle >/dev/null 2>&1; then
        bundle install --quiet || true
      fi
      gem install bundler-unused --no-document >/dev/null 2>&1 || true
      bundler-unused --format json > bundler_unused.json || echo '{"unused":[]}' > bundler_unused.json
      jq -r '.unused[]?' bundler_unused.json | sort -u > ../..//triage/sub/${idx}_rubygems_unused.txt || true
      popd >/dev/null
      ;;

    # ───────────────────────── Fallback ──────────────────────────────────────
    none)
      # nichts zu tun
      ;;
    *)
      echo "Unbekannter type='${type}', überspringe."
      ;;
  esac

  echo "::endgroup::"
done
