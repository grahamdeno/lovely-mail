#!/usr/bin/env python3
"""Turns the UI audit's xcresult bundle into screenshots and audit-summary.json.

  export_audit.py export  <xcresult> <out-dir>   Export attachments and write audit-summary.json
  export_audit.py selftest                        Check the name and summary logic on made-up data (no Xcode needed)

Written defensively: the xcresult formats change between Xcode releases, so every step records its own errors in the
summary instead of stopping, and the raw manifest and metrics are kept next to the summary.
"""
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

SUFFIX = re.compile(r"_\d+_[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$")
IMAGE_EXT = {".png", ".jpg", ".jpeg", ".heic"}


def clean_name(suggested):
    """'01-morning-s02-email-open-light_1_ABCD...' -> '01-morning-s02-email-open-light'."""
    stem = Path(suggested).stem if Path(suggested).suffix.lower() in IMAGE_EXT | {".json"} else suggested
    return SUFFIX.sub("", stem)


def attachments_from_manifest(manifest):
    """Yields (test identifier, exported file name, human name) from either manifest shape."""
    entries = manifest if isinstance(manifest, list) else manifest.get("tests", manifest.get("attachments", []))
    for entry in entries:
        test = entry.get("testIdentifier") or entry.get("testName") or ""
        for a in entry.get("attachments", []):
            yield test, a.get("exportedFileName", ""), a.get("suggestedHumanReadableName") or a.get("name") or a.get("exportedFileName", "")


def run(cmd):
    r = subprocess.run(cmd, capture_output=True, text=True)
    return r.returncode, r.stdout, r.stderr


def find_metrics(node, path=""):
    """Collects (path, name, value, unit) from any nested structure that looks like a metric."""
    found = []
    if isinstance(node, dict):
        if "name" in node and ("value" in node or "measurements" in node or "average" in node):
            found.append({"path": path, "name": node.get("name"), "value": node.get("value", node.get("average")),
                          "unit": node.get("unit") or node.get("unitOfMeasurement"), "measurements": node.get("measurements")})
        for k, v in node.items():
            found += find_metrics(v, path + "/" + str(k))
    elif isinstance(node, list):
        for i, v in enumerate(node):
            found += find_metrics(v, path + f"[{i}]")
    return found


def build_summary(jobs, errors, metrics, test_summary):
    jobs = sorted(jobs, key=lambda j: (j["number"], j["condition"]))
    out = {"jobs": [], "crawler": None, "accessibility": [], "metrics": metrics, "tests": test_summary, "exporterErrors": errors}
    seen = set()
    for j in jobs:
        failed = [a for a in j.get("assertions", []) if not a["passed"]]
        entry = {
            "job": j["number"], "name": j["title"], "slug": j["slug"], "condition": j["condition"],
            "taps": j.get("taps", 0), "typedEntries": j.get("typedEntries", 0), "marks": j.get("marks", {}),
            "seconds": round(j.get("seconds", 0), 1), "steps": len(j.get("steps", [])),
            "assertionsPassed": len(j.get("assertions", [])) - len(failed), "assertionsFailed": len(failed),
            "failedAssertions": failed, "notes": j.get("notes", []), "requests": j.get("requests", []),
            "screenshots": [s["screenshot"] for s in j.get("steps", [])],
        }
        out["jobs"].append(entry)
        if j["slug"] == "crawler":
            out["crawler"] = {"screens": j.get("screens", []), "findings": j.get("findings", []), "notes": j.get("notes", []),
                              "crashes": [f for f in j.get("findings", []) if f["kind"] == "crash"],
                              "noWayBack": [f for f in j.get("findings", []) if f["kind"] == "no-way-back"],
                              "doNothing": [f for f in j.get("findings", []) if f["kind"] == "does-nothing"]}
        for a in j.get("accessibility", []):
            key = (a["screen"], a["type"], a["detail"], a["element"], j["condition"])
            if key not in seen:
                seen.add(key)
                out["accessibility"].append(dict(a, job=j["number"], condition=j["condition"]))
    out["totals"] = {
        "jobRuns": len(out["jobs"]),
        "assertionsPassed": sum(e["assertionsPassed"] for e in out["jobs"]),
        "assertionsFailed": sum(e["assertionsFailed"] for e in out["jobs"]),
        "accessibilityIssues": len(out["accessibility"]),
    }
    return out


def export(xcresult, out):
    out = Path(out)
    raw = out / "raw"
    shots = out / "screenshots"
    for d in (raw, shots):
        d.mkdir(parents=True, exist_ok=True)
    errors, jobs = [], []

    code, so, se = run(["xcrun", "xcresulttool", "export", "attachments", "--path", str(xcresult), "--output-path", str(raw)])
    (out / "export-attachments.log").write_text(so + se)
    if code != 0:
        errors.append(f"export attachments failed ({code}): {se[:400]}")
    manifest_path = raw / "manifest.json"
    manifest = []
    if manifest_path.exists():
        try:
            manifest = json.loads(manifest_path.read_text())
            print("manifest.json (first 1500 chars):", manifest_path.read_text()[:1500])
        except Exception as e:  # noqa: BLE001
            errors.append(f"manifest unreadable: {e}")
    else:
        errors.append("no manifest.json was exported")

    copied = 0
    for test, exported, human in attachments_from_manifest(manifest):
        src = raw / exported
        if not src.exists():
            continue
        name = clean_name(human or exported)
        suffix = src.suffix.lower()
        if suffix in IMAGE_EXT:
            dest = shots / (name + ".png")
            if suffix == ".png":
                shutil.copy(src, dest)
            else:
                rc, _, _ = run(["sips", "-s", "format", "png", str(src), "--out", str(dest)])
                if rc != 0:
                    shutil.copy(src, shots / (name + suffix))
            copied += 1
        elif suffix == ".json" and name.startswith("result-"):
            try:
                jobs.append(json.loads(src.read_text()))
            except Exception as e:  # noqa: BLE001
                errors.append(f"{name}: {e}")
    print(f"{copied} screenshots, {len(jobs)} job result files")

    metrics, test_summary = [], {}
    code, so, se = run(["xcrun", "xcresulttool", "get", "test-results", "metrics", "--path", str(xcresult)])
    (out / "metrics-raw.json").write_text(so or se)
    if code == 0 and so.strip():
        try:
            metrics = find_metrics(json.loads(so))
        except Exception as e:  # noqa: BLE001
            errors.append(f"metrics unreadable: {e}")
    else:
        errors.append(f"metrics not available ({code}): {se[:300]}")
    code, so, se = run(["xcrun", "xcresulttool", "get", "test-results", "summary", "--path", str(xcresult)])
    (out / "test-summary-raw.json").write_text(so or se)
    if code == 0 and so.strip():
        try:
            s = json.loads(so)
            test_summary = {k: s.get(k) for k in ("result", "passedTests", "failedTests", "skippedTests", "totalTestCount", "expectedFailures") if k in s}
            test_summary["failures"] = [f.get("testName") or f.get("text") for f in s.get("testFailures", [])][:80]
        except Exception as e:  # noqa: BLE001
            errors.append(f"test summary unreadable: {e}")

    summary = build_summary(jobs, errors, metrics, test_summary)
    (out / "audit-summary.json").write_text(json.dumps(summary, indent=2))
    # A short list for the workflow to print into the job log (artifact downloads may be blocked for reviewers).
    keep = [p.name for p in sorted(shots.glob("*.png")) if p.stem.endswith(("-light", "-firstlaunch")) or "-s01-" in p.name]
    (out / "log-shots.txt").write_text("\n".join(keep))
    print(json.dumps(summary["totals"]))
    for e in summary["jobs"]:
        print(f"job {e['job']:>2} {e['condition']:<12} taps={e['taps']:<3} steps={e['steps']:<2} ok={e['assertionsPassed']} bad={e['assertionsFailed']}")


def selftest():
    assert clean_name("01-morning-s02-email-open-light_1_1A2B3C4D-1111-2222-3333-444455556666.png") == "01-morning-s02-email-open-light"
    assert clean_name("result-01-morning-light_0_1A2B3C4D-1111-2222-3333-444455556666.json") == "result-01-morning-light"
    assert clean_name("plain") == "plain"
    m = [{"testIdentifier": "AuditJobs/testJob01()", "attachments": [{"exportedFileName": "a.png", "suggestedHumanReadableName": "x_0_1A2B3C4D-1111-2222-3333-444455556666.png"}]}]
    assert list(attachments_from_manifest(m)) == [("AuditJobs/testJob01()", "a.png", "x_0_1A2B3C4D-1111-2222-3333-444455556666.png")]
    jobs = [{"number": 1, "slug": "morning", "title": "Morning", "condition": "light", "taps": 9, "assertions": [{"name": "a", "passed": True, "detail": ""}, {"name": "b", "passed": False, "detail": "x"}],
             "steps": [{"screenshot": "01-morning-s01-home-light"}], "accessibility": [{"screen": "Home", "type": "1", "detail": "Contrast", "element": "Done"}] * 2},
            {"number": 11, "slug": "crawler", "title": "Crawl", "condition": "light", "findings": [{"kind": "crash", "screen": "s", "control": "c", "detail": "d"}], "screens": ["Home"]}]
    s = build_summary(jobs, [], find_metrics({"a": [{"name": "Hitches", "value": 1.5, "unit": "ms"}]}), {})
    assert s["totals"] == {"jobRuns": 2, "assertionsPassed": 1, "assertionsFailed": 1, "accessibilityIssues": 1}
    assert s["crawler"]["crashes"] and s["metrics"][0]["name"] == "Hitches"
    print("export_audit selftest: ok")


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    if cmd == "selftest":
        selftest()
    elif cmd == "export" and len(sys.argv) == 4:
        export(sys.argv[2], sys.argv[3])
    else:
        sys.exit("usage: export_audit.py export <xcresult> <out-dir> | selftest")
