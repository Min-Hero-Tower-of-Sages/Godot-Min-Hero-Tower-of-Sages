"""Describe the original-export + edited-source overlay without copying either."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path


IMAGE_EXTENSIONS = {".png", ".jpg", ".jpeg", ".bmp", ".webp"}


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("reference_root", type=Path)
    parser.add_argument("extracted_directory", type=Path)
    parser.add_argument("output_file", type=Path)
    args = parser.parse_args()
    root = args.reference_root.resolve()
    extracted = args.extracted_directory.resolve()

    original_scripts_root = extracted / "script"
    edited_scripts_root = root / "source"
    original_scripts = {p.relative_to(original_scripts_root).as_posix(): p for p in original_scripts_root.rglob("*.as")}
    edited_scripts = {p.relative_to(edited_scripts_root).as_posix(): p for p in (edited_scripts_root / "scripts").rglob("*.as")}
    script_overlay = []
    for relative, edited in sorted(edited_scripts.items()):
        original = original_scripts.get(relative)
        script_overlay.append(
            {
                "identity": relative.removesuffix(".as").replace("/", "."),
                "path": relative,
                "authority": "edited",
                "original_present": original is not None,
                "changed_from_original": original is None or digest(edited) != digest(original),
            }
        )

    original_images = {p.name: p for p in (extracted / "image").glob("*") if p.is_file() and p.suffix.lower() in IMAGE_EXTENSIONS}
    edited_images = {p.name: p for p in (root / "source" / "images").glob("*") if p.is_file() and p.suffix.lower() in IMAGE_EXTENSIONS}
    image_overlay = []
    for name, edited in sorted(edited_images.items()):
        original = original_images.get(name)
        match = re.fullmatch(r"(?P<character_id>\d+)_(?P<qualified_name>.+)\.(?:png|jpg|jpeg|bmp|webp)", name, re.IGNORECASE)
        character_id = int(match.group("character_id")) if match else None
        qualified_name = match.group("qualified_name") if match else edited.stem
        if original:
            identity_status = "matched_qualified_export" if match else "matched_unqualified_export_filename"
        else:
            identity_status = "edited_only_qualified_asset" if match else "edited_only_unqualified_asset"
        image_overlay.append(
            {
                "filename": name,
                "identity": {"container": "original.swf" if original or match else "edited_source", "character_id": character_id, "qualified_name": qualified_name},
                "identity_status": identity_status,
                "authority": "edited",
                "original_present": original is not None,
                "changed_from_original": original is None or digest(edited) != digest(original),
            }
        )

    result = {
        "policy": "original export fills gaps; edited source wins by qualified class/symbol identity",
        "scripts": {
            "original_export_count": len(original_scripts),
            "edited_count": len(edited_scripts),
            "edited_with_original_match": sum(row["original_present"] for row in script_overlay),
            "edited_changed_or_added": sum(row["changed_from_original"] for row in script_overlay),
            "overlay": script_overlay,
        },
        "images": {
            "original_export_count": len(original_images),
            "edited_count": len(edited_images),
            "edited_with_original_match": sum(row["original_present"] for row in image_overlay),
            "edited_changed_or_added": sum(row["changed_from_original"] for row in image_overlay),
            "edited_only_qualified": sum(row["identity_status"] == "edited_only_qualified_asset" for row in image_overlay),
            "edited_only_unqualified": sum(row["identity_status"] == "edited_only_unqualified_asset" for row in image_overlay),
            "matched_unqualified_export_filenames": sum(row["identity_status"] == "matched_unqualified_export_filename" for row in image_overlay),
            "overlay": image_overlay,
        },
    }
    args.output_file.parent.mkdir(parents=True, exist_ok=True)
    args.output_file.write_text(json.dumps(result, indent=2), encoding="utf-8")
    print(json.dumps({"scripts": {k: v for k, v in result["scripts"].items() if k != "overlay"}, "images": {k: v for k, v in result["images"].items() if k != "overlay"}}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
