"""Package recovered move-effect symbols and their visual-ID lookup for Godot."""

from __future__ import annotations

import csv
import json
import re
import shutil
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "development/inventory/reachable_content_manifest.csv"
EXPORT_DIR = ROOT / "development/extracted/full-20260908"
OUTPUT_DIR = ROOT / "content/base/art/battle/visual_moves"
CATALOG_OUTPUT = ROOT / "content/base/art/battle/visual_move_assets.json"


def read_manifest() -> list[dict[str, str]]:
    csv.field_size_limit(20_000_000)
    with MANIFEST.open("r", encoding="utf-8-sig", newline="") as stream:
        return list(csv.DictReader(stream))


def load_animation_families(rows: list[dict[str, str]]) -> dict[str, dict[str, Any]]:
    families: dict[str, dict[str, Any]] = {}
    for row in rows:
        if row["kind"] != "animation_family":
            continue
        notes = json.loads(row["notes"])
        visual_id = str(int(notes["numeric_visual_id"]))
        family = families.setdefault(visual_id, {
            "visual_id_name": notes["visual_id_name"],
            "static_dispatch_status": notes["static_dispatch_status"],
            "texture_paths": [],
        })
        if family["visual_id_name"] != notes["visual_id_name"]:
            raise ValueError(f"Visual ID {visual_id} is assigned to multiple names")
        for binding in notes.get("asset_symbol_bindings", []):
            exported_image_id = binding.get("exported_image_id")
            exported_source = binding.get("exported_image_source")
            if not exported_image_id or not exported_source:
                continue
            relative_export = Path(exported_source.removeprefix("original.swf/").replace("/", "\\"))
            source = (EXPORT_DIR / relative_export).resolve()
            if not source.is_relative_to(EXPORT_DIR.resolve()) or not source.is_file():
                raise FileNotFoundError(f"Manifest image is missing or outside the export: {exported_source}")
            character_id = int(binding["symbol_character_id"])
            qualified_class = str(binding["symbol_class"])
            safe_class = re.sub(r"[^A-Za-z0-9_-]+", "_", qualified_class)
            target = OUTPUT_DIR / f"{character_id}_{safe_class}.png"
            resource_path = f"res://{target.relative_to(ROOT).as_posix()}"
            family["texture_paths"].append(resource_path)
    for family in families.values():
        family["texture_paths"] = sorted(set(family["texture_paths"]))
    return families


def copy_symbols(
    rows: list[dict[str, str]],
    families: dict[str, dict[str, Any]],
) -> tuple[int, int]:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    source_by_target: dict[Path, Path] = {}
    for row in rows:
        if row["kind"] != "animation_family":
            continue
        notes = json.loads(row["notes"])
        for binding in notes.get("asset_symbol_bindings", []):
            exported_image_id = binding.get("exported_image_id")
            exported_source = binding.get("exported_image_source")
            if not exported_image_id or not exported_source:
                continue
            character_id = int(binding["symbol_character_id"])
            safe_class = re.sub(r"[^A-Za-z0-9_-]+", "_", str(binding["symbol_class"]))
            target = OUTPUT_DIR / f"{character_id}_{safe_class}.png"
            relative_export = Path(exported_source.removeprefix("original.swf/").replace("/", "\\"))
            source_by_target[target] = EXPORT_DIR / relative_export

    written = 0
    for target, source in sorted(source_by_target.items()):
        if target.exists():
            if target.read_bytes() != source.read_bytes():
                raise FileExistsError(f"Refusing to overwrite a different local asset: {target}")
            continue
        shutil.copyfile(source, target)
        written += 1
    return len(source_by_target), written


def main() -> int:
    rows = read_manifest()
    families = load_animation_families(rows)
    copied_count, new_count = copy_symbols(rows, families)
    CATALOG_OUTPUT.write_text(
        json.dumps({"format_version": 1, "families": families}, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"Wrote {len(families)} visual ID records and {copied_count} unique source-art references")
    print(f"Copied {new_count} PNG files into {OUTPUT_DIR.relative_to(ROOT).as_posix()}")
    print(f"Catalog: {CATALOG_OUTPUT.relative_to(ROOT).as_posix()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
