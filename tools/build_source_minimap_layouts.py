#!/usr/bin/env python3
"""Transcribe authored minimap geometry from recovered StaticData.SetupLevels."""

from __future__ import annotations

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "development/extracted/full-20260908/script/scripts/PresistentData/StaticData.as"
OUTPUT = ROOT / "content/base/ui/source_minimap_layouts.tres"
START_MARKER = "private function SetupLevels()"
END_MARKER = "private function SetupTextFormats()"

FLOOR_ASSIGNMENT = re.compile(r"^\s*(?:var\s+)?_loc2_(?::int)?\s*=\s*(\d+)\s*;\s*$", re.MULTILINE)
POSITION = re.compile(r"m_miniMapPositions\[_loc2_\]\s*=\s*new Point\((-?\d+)\s*,\s*(-?\d+)\)")
SCALE = re.compile(r"m_miniMapScales\[_loc2_\]\s*=\s*([0-9.]+)")
PIECE = re.compile(
    r'new MiniMapDataObject\("([^\"]+)"\s*,\s*(-?\d+)\s*,\s*(-?\d+)\s*,\s*(-?\d+)'
    r'(?:\s*,\s*(-?\d+))?(?:\s*,\s*(true|false))?(?:\s*,\s*(-?[0-9.]+))?\)'
)


def gd_quote(value: str) -> str:
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def to_gd_number(value: str) -> str:
    return value if "." in value else value + ".0"


def extract_layouts(source_text: str) -> list[dict]:
    start = source_text.index(START_MARKER)
    end = source_text.index(END_MARKER, start)
    section = source_text[start:end]
    starts = list(FLOOR_ASSIGNMENT.finditer(section))
    layouts: list[dict] = []
    seen: set[int] = set()
    for index, match in enumerate(starts):
        floor_index = int(match.group(1))
        if floor_index in seen:
            continue
        seen.add(floor_index)
        block_end = starts[index + 1].start() if index + 1 < len(starts) else len(section)
        block = section[match.end() : block_end]
        position = POSITION.search(block)
        scale = SCALE.search(block)
        if position is None or scale is None:
            continue
        pieces = []
        for piece in PIECE.finditer(block):
            sprite, x, y, room, group, eggery, override = piece.groups()
            pieces.append(
                {
                    "sprite_name": sprite,
                    "x": int(x),
                    "y": int(y),
                    "room_index": int(room),
                    "group_id": int(group) if group is not None else 0,
                    "is_eggery": eggery == "true" if eggery is not None else False,
                    "override_scale": float(override) if override is not None else -99.0,
                }
            )
        if not pieces:
            continue
        layouts.append(
            {
                "floor_index": floor_index,
                "position": (int(position.group(1)), int(position.group(2))),
                "scale": float(scale.group(1)),
                "pieces": pieces,
            }
        )
    layouts.sort(key=lambda item: item["floor_index"])
    expected = list(range(31))
    actual = [item["floor_index"] for item in layouts]
    if actual != expected:
        raise SystemExit(f"Expected source minimap floors 0..30, found {actual}")
    return layouts


def serialize(layouts: list[dict]) -> str:
    lines = [
        '[gd_resource type="Resource" script_class="SourceMinimapLayouts" load_steps=2 format=3]',
        '',
        '[ext_resource type="Script" path="res://src/content/source_minimap_layouts.gd" id="1"]',
        '',
        '[resource]',
        'script = ExtResource("1")',
        'provenance = "StaticData.as :: SetupLevels / MiniMapDataObject.as constructor defaults; recovered 2026-09-08"',
        'layouts = [',
    ]
    for layout_index, layout in enumerate(layouts):
        px, py = layout["position"]
        lines.extend(
            [
                '\t{',
                f'\t"floor_index": {layout["floor_index"]},',
                f'\t"position": Vector2({px}, {py}),',
                f'\t"scale": {layout["scale"]:.6g},',
                '\t"pieces": [',
            ]
        )
        for piece in layout["pieces"]:
            lines.append(
                '\t\t{' + ", ".join(
                    [
                        f'"sprite_name": {gd_quote(piece["sprite_name"])}',
                        f'"x": {piece["x"]}',
                        f'"y": {piece["y"]}',
                        f'"room_index": {piece["room_index"]}',
                        f'"group_id": {piece["group_id"]}',
                        f'"is_eggery": {str(piece["is_eggery"]).lower()}',
                        f'"override_scale": {piece["override_scale"]:.6g}',
                    ]
                ) + '},'
            )
        lines.extend(['\t]', '\t},' if layout_index < len(layouts) - 1 else '\t}'])
    lines.extend([']', ''])
    return "\n".join(lines)


def main() -> None:
    layouts = extract_layouts(SOURCE.read_text(encoding="utf-8"))
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(serialize(layouts), encoding="utf-8", newline="\n")
    piece_count = sum(len(layout["pieces"]) for layout in layouts)
    print(f"Wrote {len(layouts)} source layouts and {piece_count} pieces to {OUTPUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
