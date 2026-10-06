"""Normalize a script-authored Flash room's literal AddObject calls."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

OBJECT_RE = re.compile(
    r'AddObject\("([^"\r\n]+)"\s*,\s*'
    r'(-?(?:\d+(?:\.\d*)?|\.\d+))\s*,\s*'
    r'(-?(?:\d+(?:\.\d*)?|\.\d+))\s*,\s*'
    r'(-?(?:\d+(?:\.\d*)?|\.\d+))\s*,\s*'
    r'(-?(?:\d+(?:\.\d*)?|\.\d+))\s*,\s*'
    r'(-?(?:\d+(?:\.\d*)?|\.\d+))\s*\)'
)
BOUNDS_RE = re.compile(r"drawRect\(0\s*,\s*0\s*,\s*([\d.]+)\s*,\s*([\d.]+)\s*\)")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--class-name", required=True)
    parser.add_argument("--room-id", required=True)
    args = parser.parse_args()

    source_text = args.source.read_text(encoding="utf-8")
    bounds = BOUNDS_RE.search(source_text)
    if bounds is None:
        raise SystemExit("source room has no literal m_roomBounds drawRect(0,0,width,height)")
    objects = []
    for match in OBJECT_RE.finditer(source_text):
        sprite, x_pos, y_pos, x_scale, y_scale, rotation = match.groups()
        objects.append({
            "tag": "levelObject",
            "attributes": {
                "spriteName": sprite,
                "xPos": x_pos,
                "yPos": y_pos,
                "xScale": x_scale,
                "yScale": y_scale,
                "rotation": rotation,
            },
            "text": "",
            "children": [],
        })
    if not objects:
        raise SystemExit("source room has no literal AddObject calls")

    document = {
        "id": args.room_id,
        "asset_identity": {
            "class_name": args.class_name,
            "identity_source": "script_authored_AddObject_calls",
        },
        "source_binary": "",
        "xml": {
            "tag": "level",
            "attributes": {"width": bounds.group(1), "height": bounds.group(2)},
            "text": "",
            "children": objects,
        },
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(document, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"room_id": args.room_id, "dimensions": bounds.groups(), "object_count": len(objects)}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
