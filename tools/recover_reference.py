"""Stage original SWF exports without touching the reference repository."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
from datetime import datetime, timezone
from pathlib import Path

EXPORTS = ("script", "image", "sound", "font", "binaryData", "symbolClass")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("reference_root", type=Path)
    parser.add_argument("staging_directory", type=Path)
    parser.add_argument("--java", default="java")
    args = parser.parse_args()
    root = args.reference_root.resolve()
    staging = args.staging_directory.resolve()
    jar = root / "jpexs-custom" / "ffdec-cli.jar"
    swf = root / "original.swf"
    if not jar.is_file() or not swf.is_file():
        raise SystemExit("JPEXS CLI or original.swf is missing")
    if staging.exists() and any(staging.iterdir()):
        raise SystemExit(f"refusing to overwrite non-empty staging directory: {staging}")
    staging.mkdir(parents=True, exist_ok=True)
    profile = staging / ".jpexs-profile"
    roaming = profile / "roaming"
    local = profile / "local"
    roaming.mkdir(parents=True)
    local.mkdir(parents=True)
    environment = os.environ.copy()
    environment["APPDATA"] = str(roaming)
    environment["LOCALAPPDATA"] = str(local)
    report = {"started_at_utc": datetime.now(timezone.utc).isoformat(), "swf": str(swf), "exports": []}
    for kind in EXPORTS:
        destination = staging / kind
        destination.mkdir()
        command = [args.java, "-jar", str(jar), "-export", kind, str(destination), str(swf)]
        completed = subprocess.run(command, cwd=jar.parent, env=environment, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        report["exports"].append({"kind": kind, "returncode": completed.returncode, "output": completed.stdout})
        (staging / "recovery_report.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
        if completed.returncode:
            print(completed.stdout)
            print(f"recovery stopped at {kind}; see {staging / 'recovery_report.json'}")
            return completed.returncode
    report["completed_at_utc"] = datetime.now(timezone.utc).isoformat()
    (staging / "recovery_report.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
