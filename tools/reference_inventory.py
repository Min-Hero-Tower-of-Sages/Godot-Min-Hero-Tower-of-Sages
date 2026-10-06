"""Build the immutable-input inventory and initial coverage manifest.

This tool never modifies the reference checkout. It hashes the current bytes, so
uncommitted edits are part of the recorded baseline. It deliberately reports
unresolved imports instead of inventing fallback definitions.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import re
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

CLASS_RE = re.compile(r"\b(?:public\s+)?(?:class|interface)\s+([A-Za-z_]\w*)")
IMPORT_RE = re.compile(r"\bimport\s+([A-Za-z_]\w*(?:\.[A-Za-z_*]\w*)+)\s*;")
MOD_LABEL_RE = re.compile(r'm_toggleTexts\.push\((.*?)\)', re.DOTALL)
STRING_RE = re.compile(r'"([^"]+)"')


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def git_revision_from_files(repository: Path) -> str | None:
    head_path = repository / ".git" / "HEAD"
    if not head_path.is_file():
        return None
    head = head_path.read_text(encoding="utf-8").strip()
    if not head.startswith("ref: "):
        return head
    ref_name = head[5:]
    loose_ref = repository / ".git" / ref_name
    if loose_ref.is_file():
        return loose_ref.read_text(encoding="utf-8").strip()
    packed = repository / ".git" / "packed-refs"
    if packed.is_file():
        for line in packed.read_text(encoding="utf-8").splitlines():
            if line and not line.startswith(("#", "^")):
                revision, name = line.split(" ", 1)
                if name == ref_name:
                    return revision
    return None


def classify(path: Path) -> str:
    normalized = "/".join(path.parts).lower()
    if "minionmove" in normalized:
        return "move"
    if "/minions/" in f"/{normalized}":
        return "minion_or_talent"
    if "/trainers/" in f"/{normalized}":
        return "encounter"
    if "/levels/" in f"/{normalized}":
        return "room"
    if "/menus/" in f"/{normalized}" or "/mainmenu/" in f"/{normalized}":
        return "menu"
    if "/battlesystems/" in f"/{normalized}":
        return "battle_rule_or_presentation"
    if "/persistentdata/" in f"/{normalized}" or "/presistentdata/" in f"/{normalized}":
        return "progression_or_save"
    return "support"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("reference_root", type=Path, help="MinHeroMods repository root")
    parser.add_argument("output_directory", type=Path)
    parser.add_argument("--extracted-directory", type=Path, help="completed JPEXS export to reconcile")
    args = parser.parse_args()

    root = args.reference_root.resolve()
    source = root / "source"
    output = args.output_directory.resolve()
    output.mkdir(parents=True, exist_ok=True)
    if not source.is_dir():
        raise SystemExit(f"reference source directory not found: {source}")

    tracked_inputs = sorted(
        [p for p in source.rglob("*") if p.is_file()]
        + [p for p in (root / "original.swf", root / "default.swf") if p.is_file()]
        + [p for p in root.glob("*.py") if p.is_file()]
        + [p for p in (root / "utils").glob("*") if p.is_file()]
    )
    files = []
    for path in tracked_inputs:
        files.append(
            {
                "path": path.relative_to(root).as_posix(),
                "size": path.stat().st_size,
                "sha256": sha256(path),
            }
        )

    scripts = sorted((source / "scripts").rglob("*.as"))
    classes: dict[str, str] = {}
    imports: list[dict[str, str]] = []
    coverage: list[dict[str, str]] = []
    for path in scripts:
        relative = path.relative_to(source).as_posix()
        text = path.read_text(encoding="utf-8-sig", errors="replace")
        match = CLASS_RE.search(text)
        if match:
            classes[match.group(1)] = relative
            coverage.append(
                {
                    "kind": classify(Path(relative)),
                    "id_or_name": match.group(1),
                    "source": relative,
                    "recovery": "recovered_edited_source",
                    "conversion": "not_converted",
                    "validation": "not_validated",
                    "notes": "",
                }
            )
        for imported in IMPORT_RE.findall(text):
            imports.append({"owner": relative, "import": imported, "leaf": imported.rsplit(".", 1)[-1]})

    exported_classes: dict[str, str] = {}
    if args.extracted_directory:
        extracted_scripts = args.extracted_directory.resolve() / "script"
        for path in sorted(extracted_scripts.rglob("*.as")):
            relative = path.relative_to(extracted_scripts).as_posix()
            text = path.read_text(encoding="utf-8-sig", errors="replace")
            match = CLASS_RE.search(text)
            if match:
                class_name = match.group(1)
                exported_classes[class_name] = relative
                if class_name not in classes:
                    coverage.append(
                        {
                            "kind": classify(Path(relative)),
                            "id_or_name": class_name,
                            "source": f"original.swf::{relative}",
                            "recovery": "recovered_original_export",
                            "conversion": "not_converted",
                            "validation": "exported_not_behavior_validated",
                            "notes": "fills definition absent from edited source",
                        }
                    )

    available_classes = set(classes) | set(exported_classes)
    ignored_import_roots = {"flash", "mx"}
    missing = sorted(
        (item for item in imports if item["leaf"] != "*" and item["leaf"] not in available_classes and item["import"].split(".", 1)[0] not in ignored_import_roots),
        key=lambda item: (item["leaf"], item["owner"]),
    )
    for item in missing:
        coverage.append(
            {
                "kind": "missing_definition",
                "id_or_name": item["leaf"],
                "source": item["owner"],
                "recovery": "blocked_pending_swf_export",
                "conversion": "blocked",
                "validation": "blocked",
                "notes": f"unresolved import {item['import']}",
            }
        )

    mod_menu = source / "scripts" / "MainMenu" / "ModMenu.as"
    mod_groups: list[str] = []
    if mod_menu.is_file():
        match = MOD_LABEL_RE.search(mod_menu.read_text(encoding="utf-8-sig", errors="replace"))
        if match:
            mod_groups = STRING_RE.findall(match.group(1))

    extension_counts = Counter(Path(item["path"]).suffix.lower() or "<none>" for item in files)
    manifest = {
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "reference_root": str(root),
        "git_revision_from_repository_files": git_revision_from_files(root),
        "baseline_includes_current_uncommitted_bytes": True,
        "input_counts_by_extension": dict(sorted(extension_counts.items())),
        "class_count": len(classes),
        "exported_class_count": len(exported_classes),
        "unresolved_import_count": len(missing),
        "known_mod_groups": mod_groups,
        "stage": {"width": 700, "height": 525, "fps": 30, "source": "planning audit; SWF revalidation pending"},
        "files": files,
        "classes": classes,
        "unresolved_imports": missing,
    }
    (output / "reference_inventory.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    with (output / "coverage_manifest.csv").open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=["kind", "id_or_name", "source", "recovery", "conversion", "validation", "notes"])
        writer.writeheader()
        writer.writerows(coverage)
    print(json.dumps({key: manifest[key] for key in ("git_revision_from_repository_files", "input_counts_by_extension", "class_count", "unresolved_import_count", "known_mod_groups")}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
