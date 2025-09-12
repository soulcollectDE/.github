#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import json, os, subprocess, sys

REPO = os.environ["REPO"]
MIN  = (os.environ.get("MIN_SEVERITY") or "low").lower()
if MIN == "medium":  # Eingabe-Synonym
    MIN = "moderate"

# Severity-Ranking (GitHub: low | moderate | high | critical)
RANK = {"low":1, "moderate":2, "high":3, "critical":4}
MIN_RANK = RANK.get(MIN, 1)

def sh(*args):
    return subprocess.run(args, capture_output=True, text=True)

def load_items(proc):
    """
    Verträgt:
    - Ein einziges JSON-Array
    - Zeilenweise Items (aus --jq '.[]')
    """
    if proc.returncode != 0 or not proc.stdout.strip():
        return []
    s = proc.stdout.strip()
    # Fall A: Ein einziges JSON-Array
    if s.startswith('['):
        try:
            arr = json.loads(s)
            return arr if isinstance(arr, list) else []
        except Exception:
            pass
    # Fall B: NDJSON / zeilenweise Items
    items = []
    for line in s.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            obj = json.loads(line)
            items.append(obj)
        except Exception:
            # Zeile ignorieren, wenn sie kein JSON ist
            pass
    return items


def sev_score(s: str) -> int:
    return RANK.get((s or "").lower(), 0)

def pick_cve(advisory: dict) -> str:
    if not advisory:
        return ""
    cve = advisory.get("cve_id") or ""
    if cve:
        return cve
    for ident in advisory.get("identifiers", []) or []:
        if (ident.get("type") or "").upper() == "CVE":
            return ident.get("value") or ""
    return ""

def extract_alert_fields(a: dict) -> dict:
    dep = a.get("dependency") or {}
    pkg = dep.get("package") or {}
    adv = a.get("security_advisory") or {}
    vul = a.get("security_vulnerability") or {}

    eco = (pkg.get("ecosystem") or "").lower()
    name = (pkg.get("name") or "")
    manifest = dep.get("manifest_path") or ""
    scope = dep.get("scope") or "unknown"  # runtime | development | unknown

    # Severity: primär aus vulnerability, sonst advisory
    severity = (vul.get("severity") or adv.get("severity") or "").lower()

    ghsa = adv.get("ghsa_id") or ""
    cve = pick_cve(adv)
    vuln_range = vul.get("vulnerable_version_range") or ""
    fixed_version = (vul.get("first_patched_version") or {}).get("identifier", "")

    return {
        "ecosystem": eco,
        "name": name,
        "manifest": manifest,
        "scope": scope,
        "ghsa": ghsa,
        "cve": cve,
        "severity": severity,
        "vuln_range": vuln_range,
        "fixed_version": fixed_version,
        "html_url": a.get("html_url") or "",
        "number": a.get("number"),
    }

# 1) Alerts via REST (paginate), state=all damit Downstream selbst entscheidet
alerts_proc = sh(
    "gh","api",
    "-H","Accept: application/vnd.github+json",
    "-H","X-GitHub-Api-Version: 2022-11-28",
    f"repos/{REPO}/dependabot/alerts?state=all&per_page=100",
    "--paginate",
    "--jq",".[]"
)
alerts_raw = load_items(alerts_proc)

# 2) Filtern nach Mindest-Severity & Felder mappen
filtered = []
for a in alerts_raw:
    severity = (
        ((a.get("security_vulnerability") or {}).get("severity"))
        or ((a.get("security_advisory") or {}).get("severity"))
        or ""
    )
    if sev_score(severity) >= MIN_RANK:
        filtered.append(extract_alert_fields(a))

# 3) Optionale, stabile Sortierung (ecosystem/name/manifest/ghsa)
filtered.sort(key=lambda x: (
    x.get("ecosystem") or "",
    x.get("name") or "",
    x.get("manifest") or "",
    x.get("ghsa") or "",
))

# 4) Speichern
os.makedirs("triage", exist_ok=True)
with open("triage/alerts.json","w",encoding="utf-8") as f:
    json.dump(filtered, f, indent=2, ensure_ascii=False)

print(f"fetched alerts: {len(filtered)} >= severity {MIN} for {REPO}")
