#!/usr/bin/env python3
import json, os, subprocess, hashlib

dest = os.environ.get("DEST_REPO","")
kept = json.load(open("triage/kept.json","r",encoding="utf-8"))

def sh(*args):
    return subprocess.run(args, capture_output=True, text=True)

for r in kept:
    key = f"{dest}|{r.get('ecosystem')}|{r.get('package')}|{r.get('severity')}|{r.get('manifest')}"
    slug = hashlib.sha1(key.encode()).hexdigest()[:10]
    title = f"[Dependabot Triage] {r.get('ecosystem')}:{r.get('package')} ({r.get('severity')}) [{slug}]"
    scope = "dev" if r.get("dev")=="yes" else "runtime/unknown"
    body = (
        "Automatische Triage – Alert bleibt offen (kein Dismiss).\n\n"
        f"- **Repo**: {dest}\n"
        f"- **Paket**: `{r.get('package','')}` ({r.get('ecosystem','')})\n"
        f"- **Severity**: {r.get('severity','')}\n"
        f"- **Scope**: {scope}\n"
        f"- **Used**: {r.get('used','')}\n"
        f"- **Manifest**: {r.get('manifest','')}\n"
        f"- **Alert**: {r.get('url','')}\n"
    )
    labels = ["security","dependabot","needs-triage"]
    labels.append("dev" if scope=="dev" else "runtime")

    lst = sh("gh","issue","list","-R",dest,"--search",title,"--json","number,title")
    try:
        existing = [i["title"] for i in json.loads(lst.stdout or "[]")]
    except Exception:
        existing = []
    if title not in existing:
        sh("gh","issue","create","-R",dest,"--title",title,"--body",body,"--label",",".join(labels))
