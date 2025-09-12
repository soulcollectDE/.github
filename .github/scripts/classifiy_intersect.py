#!/usr/bin/env python3
import json, pathlib

alerts = json.load(open("triage/alerts.json","r",encoding="utf-8"))
tri = pathlib.Path("triage"); sub = tri / "sub"

node_used=set(); node_unused=set(); py_extra=set(); comp_unused=set(); mvn_unused=set()

for p in sub.glob("*_node_used.txt"):
    node_used |= {x.strip() for x in p.read_text().splitlines() if x.strip()}
for p in sub.glob("*_node_unused.txt"):
    node_unused |= {x.strip() for x in p.read_text().splitlines() if x.strip()}
for p in sub.glob("*_py_extra.txt"):
    py_extra |= {x.strip() for x in p.read_text().splitlines() if x.strip()}
for p in sub.glob("*_comp_unused.txt"):
    comp_unused |= {x.strip() for x in p.read_text().splitlines() if x.strip()}
for p in sub.glob("*_mvn_unused.txt"):
    mvn_unused |= {x.strip() for x in p.read_text().splitlines() if x.strip()}

def sev(a):
    return (a.get("security_advisory") or {}).get("severity") or a.get("severity") or ""

def is_dev(eco, manifest):
    m=(manifest or "").lower()
    if eco in ("npm","pnpm","yarn"):
        return "test" in m or "examples" in m or (m.endswith("package.json") and "dev" in m)
    if eco in ("pip","pypi"):
        return "test" in m or "dev" in m or "docs" in m
    if eco in ("composer",):
        return "test" in m or "dev" in m
    if eco in ("maven","gradle"):
        return "test" in m
    return False

kept=[]; ignored=[]
for a in alerts:
    dep = a.get("dependency") or {}
    pkginfo = dep.get("package") or {}
    pkg = pkginfo.get("name") or ""
    eco = (pkginfo.get("ecosystem") or "").lower()
    manifest = dep.get("manifest_path") or ""
    used=False

    if eco in ("npm","pnpm","yarn"):
        used = pkg in node_used
        unused_hit = (pkg in node_unused)
    elif eco in ("pip","pypi"):
        unused_hit = (pkg in py_extra)
        used = not unused_hit
    elif eco in ("composer",):
        unused_hit = (pkg in comp_unused)
        used = not unused_hit
    elif eco in ("maven", "gradle"):
        unused_hit = (pkg in mvn_unused)
        used = not unused_hit
    else:
        unused_hit = False

    row = {
      "package": pkg,
      "ecosystem": eco,
      "severity": sev(a),
      "manifest": manifest,
      "url": a.get("html_url") or "",
      "dev": "yes" if is_dev(eco, manifest) else "no",
      "used": "yes" if used else "no"
    }

    if not used or unused_hit:
        row["reason"]="unused"
        ignored.append(row)
    elif row["dev"]=="yes" and row["severity"].lower() not in ("critical","high"):
        row["reason"]="dev-noncritical"
        ignored.append(row)
    else:
        kept.append(row)

tri.joinpath("kept.json").write_text(json.dumps(kept, indent=2, ensure_ascii=False), encoding="utf-8")
tri.joinpath("ignored.json").write_text(json.dumps(ignored, indent=2, ensure_ascii=False), encoding="utf-8")
