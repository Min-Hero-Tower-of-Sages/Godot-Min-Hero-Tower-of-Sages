"""Audit whether supplied SWFs contain recoverable frame-based timelines.

This uses JPEXS' XML export only as a structural reader.  The XML (which may be
large) and any externally exported media are held in a temporary directory;
only the compact JSON report is retained.  No input SWF is ever modified.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import subprocess
import tempfile
import xml.etree.ElementTree as ET
from collections import Counter
from pathlib import Path


TIMELINE_TAGS = {
    "DefineSpriteTag",
    "DefineButtonTag",
    "DefineButton2Tag",
    "PlaceObjectTag",
    "PlaceObject2Tag",
    "PlaceObject3Tag",
    "PlaceObject4Tag",
    "RemoveObjectTag",
    "RemoveObject2Tag",
    "FrameLabelTag",
    "ShowFrameTag",
    "StartSoundTag",
    "StartSound2Tag",
    "SoundStreamHeadTag",
    "SoundStreamHead2Tag",
    "SoundStreamBlockTag",
    "DoActionTag",
    "DoInitActionTag",
}


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def audit_one(swf: Path, jar: Path, java: str) -> dict[str, object]:
    with tempfile.TemporaryDirectory(prefix="minhero-swf-timeline-") as temporary:
        work = Path(temporary)
        appdata = work / "roaming"
        localappdata = work / "local"
        appdata.mkdir()
        localappdata.mkdir()
        xml_path = work / "export.xml"
        environment = os.environ.copy()
        environment["APPDATA"] = str(appdata)
        environment["LOCALAPPDATA"] = str(localappdata)
        command = [
            java,
            "-jar",
            str(jar),
            "-swf2xml",
            "-external",
            "image,definesound",
            str(swf),
            str(xml_path),
        ]
        completed = subprocess.run(
            command,
            cwd=jar.parent,
            env=environment,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            check=False,
        )
        if completed.returncode != 0 or not xml_path.is_file():
            raise RuntimeError(
                f"JPEXS timeline XML export failed for {swf} "
                f"(exit {completed.returncode}):\n{completed.stdout[-6000:]}"
            )

        item_counts: Counter[str] = Counter()
        frame_labels: list[str] = []
        root_attributes: dict[str, str] = {}
        for event, element in ET.iterparse(xml_path, events=("start", "end")):
            if event == "start" and element.tag == "swf":
                root_attributes = {
                    key: element.attrib[key]
                    for key in ("version", "frameCount", "frameRate", "compression")
                    if key in element.attrib
                }
            elif event == "end":
                if element.tag == "item":
                    tag_type = element.attrib.get("type")
                    if tag_type:
                        item_counts[tag_type] += 1
                        if tag_type == "FrameLabelTag":
                            frame_labels.append(element.attrib.get("name", ""))
                element.clear()

        relevant_counts = {
            tag: item_counts[tag]
            for tag in sorted(TIMELINE_TAGS)
            if item_counts[tag]
        }
        movieclip_count = item_counts["DefineSpriteTag"]
        placement_count = sum(
            count
            for name, count in item_counts.items()
            if name.startswith("PlaceObject")
        )
        return {
            "file": swf.name,
            "size_bytes": swf.stat().st_size,
            "sha256": sha256_file(swf),
            "swf_header": root_attributes,
            "jpexs_xml_bytes": xml_path.stat().st_size,
            "total_swf_tag_count": sum(item_counts.values()),
            "frame_labels": frame_labels,
            "frame_label_count": item_counts["FrameLabelTag"],
            "show_frame_count": item_counts["ShowFrameTag"],
            "nested_movieclip_definition_count": movieclip_count,
            "display_list_placement_count": placement_count,
            "relevant_timeline_tag_counts": relevant_counts,
            "frame_based_move_animation_recoverable": bool(movieclip_count or placement_count),
        }


def audit_action_script_visual_sources(root: Path) -> dict[str, object]:
    source_directory = (
        root
        / "source"
        / "scripts"
        / "BattleSystems"
        / "Visuals"
        / "VisualMoves"
    )
    if not source_directory.is_dir():
        return {"available": False, "reason": "VisualMoves ActionScript source directory not found."}

    files = sorted(source_directory.rglob("*.as"))
    signatures = {"TweenLite": 0, "TimelineLite": 0, "CreateSprite": 0}
    animated_classes: list[str] = []
    for path in files:
        source = path.read_text(encoding="utf-8", errors="replace")
        found = [name for name in signatures if name in source]
        for name in found:
            signatures[name] += 1
        if "TweenLite" in source or "TimelineLite" in source:
            animated_classes.append(path.relative_to(source_directory).as_posix())
    return {
        "available": True,
        "source_directory": "source/scripts/BattleSystems/Visuals/VisualMoves",
        "actionscript_file_count": len(files),
        "files_containing_animation_primitive": signatures,
        "tweened_visual_move_classes": animated_classes,
        "interpretation": (
            "Battle move visuals are programmatically assembled and animated by ActionScript "
            "tween logic, rather than stored as nested SWF movie-clip timelines."
        ),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("reference_root", type=Path, help="read-only checkout with original/default SWFs")
    parser.add_argument("output", type=Path, help="JSON report output path")
    parser.add_argument("--java", default="java")
    args = parser.parse_args()

    root = args.reference_root.resolve()
    jar = root / "jpexs-custom" / "ffdec-cli.jar"
    if not jar.is_file():
        raise SystemExit(f"JPEXS CLI not found: {jar}")
    swfs = [root / name for name in ("original.swf", "default.swf") if (root / name).is_file()]
    if not swfs:
        raise SystemExit(f"no original.swf or default.swf found in {root}")

    results = [audit_one(swf, jar, args.java) for swf in swfs]
    report = {
        "purpose": "Determine whether the supplied SWFs retain frame/display-list timelines for animation recovery.",
        "reader": "JPEXS Free Flash Decompiler swf2xml structural export",
        "source_files_are_read_only": True,
        "raw_xml_retained": False,
        "results": results,
        "actionscript_visual_move_source": audit_action_script_visual_sources(root),
        "interpretation": (
            "SWFs with zero DefineSpriteTag and zero PlaceObject* tags do not contain "
            "nested movie-clip frame sequences or display-list placement records. For "
            "battle move VFX, the delivered ActionScript source contains programmatic "
            "tween sequences that are the appropriate behavior to port instead. Static "
            "images and scripts remain available."
        ),
    }
    output = args.output.resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(f"Wrote timeline audit for {len(results)} SWF(s) to {output}")
    for result in results:
        print(
            f"{result['file']}: {result['show_frame_count']} root frames, "
            f"{result['frame_label_count']} labels, "
            f"{result['nested_movieclip_definition_count']} nested clips, "
            f"{result['display_list_placement_count']} placements"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
