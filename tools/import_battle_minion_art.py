"""Package source-identical minion sprites needed by the battle surface."""

from __future__ import annotations

import json
import re
import shutil
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
PRESENTATION_DIR = ROOT / "content/imported/recovered-20260911/presentations"
EXPORT_IMAGE_DIR = ROOT / "development/extracted/full-20260908/image"
OUTPUT_DIR = ROOT / "content/base/art/battle/minions"
CATALOG_OUTPUT = ROOT / "content/base/art/battle/minion_battle_assets.json"
PRESENTATION_FIELD = re.compile(r'^legacy_sprite_name = &"([^\"]+)"$', re.MULTILINE)
ID_FIELD = re.compile(r'^id = &"([^\"]+)"$', re.MULTILINE)
EXPORTED_IMAGE = re.compile(r"^\d+_Utilities\.SpriteHandler_(.+)\.png$")
SUPPORT_SPRITES = ("battleScreenMenus_healthFillBar_background",)


def read_presentation_symbols() -> dict[str, str]:
    presentations: dict[str, str] = {}
    for path in sorted(PRESENTATION_DIR.glob("*.tres")):
        source = path.read_text(encoding="utf-8")
        sprite_match = PRESENTATION_FIELD.search(source)
        id_match = ID_FIELD.search(source)
        if sprite_match is None or id_match is None:
            raise ValueError(f"Missing sprite name or content ID in {path}")
        sprite_name = sprite_match.group(1)
        presentation_id = id_match.group(1)
        previous = presentations.get(presentation_id)
        if previous is not None and previous != sprite_name:
            raise ValueError(f"Presentation {presentation_id} has multiple sprite names")
        presentations[presentation_id] = sprite_name
    return presentations


def read_export_images() -> dict[str, list[Path]]:
    images: dict[str, list[Path]] = {}
    for path in EXPORT_IMAGE_DIR.glob("*_Utilities.SpriteHandler_*.png"):
        match = EXPORTED_IMAGE.match(path.name)
        if match is not None:
            images.setdefault(match.group(1), []).append(path)
    return images


def copy_exact_symbol(sprite_name: str, candidates: list[Path]) -> tuple[Path, list[int]]:
    if not candidates:
        raise FileNotFoundError(f"No exported SpriteHandler image for {sprite_name}")
    candidates = sorted(candidates)
    baseline = candidates[0].read_bytes()
    for duplicate in candidates[1:]:
        if duplicate.read_bytes() != baseline:
            raise ValueError(
                f"SpriteHandler symbol {sprite_name} has different exported images: "
                + ", ".join(path.name for path in candidates)
            )

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    target = OUTPUT_DIR / f"{sprite_name}.png"
    if target.exists():
        if target.read_bytes() != baseline:
            raise FileExistsError(f"Refusing to overwrite different local artwork: {target}")
    else:
        shutil.copyfile(candidates[0], target)
    numeric_ids = [int(path.name.split("_", 1)[0]) for path in candidates]
    return target, numeric_ids


def build_catalog(presentations: dict[str, str], image_map: dict[str, list[Path]]) -> dict[str, Any]:
    catalog: dict[str, Any] = {"format_version": 1, "presentations": {}, "support_sprites": {}}
    requested = set(presentations.values()) | set(SUPPORT_SPRITES)
    for sprite_name in sorted(requested):
        candidates = image_map.get(sprite_name, [])
        if not candidates:
            if sprite_name in SUPPORT_SPRITES:
                raise FileNotFoundError(f"Required battle UI sprite is missing: {sprite_name}")
            continue
        target, character_ids = copy_exact_symbol(sprite_name, candidates)
        entry = {
            "sprite_name": sprite_name,
            "resource_path": f"res://{target.relative_to(ROOT).as_posix()}",
            "symbol_character_ids": character_ids,
            "source_export": candidates[0].relative_to(ROOT).as_posix(),
        }
        if sprite_name in SUPPORT_SPRITES:
            catalog["support_sprites"][sprite_name] = entry
        else:
            for presentation_id, presentation_sprite in presentations.items():
                if presentation_sprite == sprite_name:
                    catalog["presentations"][presentation_id] = entry
    for presentation_id, sprite_name in presentations.items():
        if presentation_id not in catalog["presentations"]:
            catalog["presentations"][presentation_id] = {
                "sprite_name": sprite_name,
                "resource_path": "",
                "symbol_character_ids": [],
                "source_export": "",
            }
    return catalog


def main() -> int:
    presentations = read_presentation_symbols()
    catalog = build_catalog(presentations, read_export_images())
    CATALOG_OUTPUT.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    entries = catalog["presentations"]
    resolved = sum(bool(value["resource_path"]) for value in entries.values())
    missing = sorted(value["sprite_name"] for value in entries.values() if not value["resource_path"])
    size = sum(path.stat().st_size for path in OUTPUT_DIR.glob("*.png"))
    print(f"Resolved {resolved}/{len(entries)} presentation sprites")
    print(f"Packaged {len(list(OUTPUT_DIR.glob('*.png')))} unique minion/UI sprites ({size:,} bytes)")
    print(f"Asset index: {CATALOG_OUTPUT.relative_to(ROOT).as_posix()}")
    if missing:
        print("Missing sprites: " + ", ".join(missing))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
