"""Validate SWF room identities and normalize compressed XML for review."""

from __future__ import annotations

import argparse
import csv
import json
import re
import zlib
from pathlib import Path
from xml.etree import ElementTree

BINARY_RE = re.compile(r"^(\d+)_([A-Za-z_][\w.]*)\.bin$")
ROOM_PREFIX = "Utilities.LevelContainer_"


def element_to_data(element: ElementTree.Element) -> dict:
    return {
        "tag": element.tag,
        "attributes": dict(element.attrib),
        "text": (element.text or "").strip(),
        "children": [element_to_data(child) for child in element],
    }


def stable_room_id(class_name: str) -> str:
    suffix = class_name.removeprefix(ROOM_PREFIX)
    return "base:room/" + suffix.lower()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("extracted_directory", type=Path)
    parser.add_argument("output_directory", type=Path)
    parser.add_argument(
        "--embedded-room",
        action="append",
        default=[],
        metavar="BINARY_ID=CLASS_NAME",
        help="explicitly identify an embedded room whose binary has no class suffix",
    )
    parser.add_argument(
        "--only-room",
        help="normalize only this fully qualified room class (useful for embedded assets)",
    )
    args = parser.parse_args()
    extracted = args.extracted_directory.resolve()
    output = args.output_directory.resolve()
    if output.exists() and any(output.iterdir()):
        raise SystemExit(f"refusing to overwrite non-empty output directory: {output}")
    output.mkdir(parents=True, exist_ok=True)

    symbols_path = extracted / "symbolClass" / "symbols.csv"
    with symbols_path.open(newline="", encoding="utf-8-sig") as stream:
        symbols = {int(row[0]): row[1] for row in csv.reader(stream, delimiter=";") if len(row) >= 2}

    embedded_rooms = {}
    for raw_mapping in args.embedded_room:
        try:
            raw_id, class_name = raw_mapping.split("=", 1)
            numeric_id = int(raw_id)
        except ValueError as error:
            raise SystemExit(f"invalid --embedded-room mapping {raw_mapping!r}: expected BINARY_ID=CLASS_NAME") from error
        if not class_name.startswith(ROOM_PREFIX):
            raise SystemExit(f"embedded room class must start with {ROOM_PREFIX}: {class_name}")
        embedded_rooms[numeric_id] = class_name

    rooms = []
    errors = []
    for path in sorted((extracted / "binaryData").glob("*.bin")):
        match = BINARY_RE.match(path.name)
        numeric_id = int(match.group(1)) if match else int(path.stem) if path.stem.isdigit() else -1
        class_name = match.group(2) if match else embedded_rooms.get(numeric_id, "")
        if not class_name or (args.only_room and class_name != args.only_room):
            continue
        if not class_name.startswith(ROOM_PREFIX):
            continue
        mapped_class = symbols.get(numeric_id)
        # Explicit embedded mappings describe the owner of a shared SWF asset;
        # symbolClass may point at another class which references the same ID.
        if numeric_id not in embedded_rooms and mapped_class != class_name:
            errors.append({"file": path.name, "error": "symbol mapping mismatch", "expected": class_name, "actual": mapped_class})
            continue
        try:
            xml_bytes = zlib.decompress(path.read_bytes())
            root = ElementTree.fromstring(xml_bytes)
        except (zlib.error, ElementTree.ParseError) as error:
            errors.append({"file": path.name, "error": str(error)})
            continue
        room_id = stable_room_id(class_name)
        data = {
            "id": room_id,
            "asset_identity": {
                "container": "original.swf",
                "character_id": numeric_id,
                "class_name": class_name,
                "identity_source": "explicit_embedded_owner" if numeric_id in embedded_rooms else "symbolClass",
            },
            "source_binary": path.name,
            "xml": element_to_data(root),
        }
        filename = room_id.rsplit("/", 1)[1].replace("/", "_") + ".json"
        (output / filename).write_text(json.dumps(data, indent=2), encoding="utf-8")
        rooms.append({"id": room_id, "file": filename, "character_id": numeric_id, "class_name": class_name})

    report = {"container": "original.swf", "room_count": len(rooms), "error_count": len(errors), "rooms": rooms, "errors": errors}
    (output / "room_manifest.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps({"room_count": len(rooms), "error_count": len(errors)}, indent=2))
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
