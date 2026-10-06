"""Emit an apply_patch patch; never write content or player saves directly.

Reuse the source importer while preserving the public Floor 6 encounter IDs,
reward data, room geometry and save keys. Also repair baked level offsets in
the later-floor resources using StaticData's authoritative level table.
"""
import json
import re
import difflib
from pathlib import Path
from unittest.mock import patch

import build_floor_7_8_source_content as builder


def replace_resource_field(text, field, value):
    pattern = rf"^{re.escape(field)} = .*?$"
    line = f"{field} = {value}"
    return re.sub(pattern, lambda _match: line, text, flags=re.MULTILINE) if re.search(pattern, text, re.MULTILINE) else text.rstrip() + "\n" + line + "\n"


def main():
    root = builder.ROOT
    minions = builder.imported_ids(root / "content/imported/recovered-20260911/minions")
    moves = builder.imported_ids(root / "content/imported/recovered-20260911/moves")
    captured = {}
    def capture(target, text, **_kwargs):
        captured[target] = text
        return len(text)
    with patch.object(Path, "write_text", capture):
        records = builder.trainers_for_floor(6, 18, {}, {}, minions, moves, source_method="CreateFloor5")
    assert len(records) == 6
    updates = {}
    for path, generated in captured.items():
        current = path.read_text(encoding="utf-8")
        old_id = re.search(r'^id = &"([^"]+)"', current, re.MULTILINE).group(1)
        assert old_id.startswith("base:encounter/grass_floor6_")
        # Replace the source team, not stable identity or settlement settings.
        team = re.search(r"team_entries = .*?\]\)\n(?=ai_profile_id)", generated, re.DOTALL).group(0)
        updated = re.sub(r"team_entries = .*?\]\)\n(?=ai_profile_id)", lambda _m: team, current, flags=re.DOTALL)
        for field in ["source_trainer_id", "source_level_offset", "legacy_class_name", "source_location", "description"]:
            value = re.search(rf"^{field} = (.*)$", generated, re.MULTILINE).group(1)
            updated = replace_resource_field(updated, field, value)
        updated = re.sub(r"^battle_modifier_configuration = .*\n", "", updated, flags=re.MULTILINE)
        assert re.search(r'^id = &"([^"]+)"', updated, re.MULTILINE).group(1) == old_id
        updates[path] = updated

    graph_path = root / "content/base/campaigns/floor_6_room_graph.json"
    graph = json.loads(graph_path.read_text(encoding="utf-8"))
    by_room = {record["room"]: record for record in records}
    for room in graph["rooms"]:
        binding = room.get("trainer_binding")
        if not binding:
            continue
        record = by_room[binding["trainer_room_id"]]
        binding.update(source_method="CreateFloor5", source_floor_argument=5, source_location=record["source_location"])
        for interaction in room.get("interactions", []):
            if interaction.get("kind") != "trainer":
                continue
            interaction["first_visit_text"] = record["start_text"]
            interaction["lose_text"] = record["lose_text"]
    updates[graph_path] = json.dumps(graph, ensure_ascii=False, indent=2) + "\n"

    # Base levels are stored unadjusted; runtime applies each trainer offset.
    for floor, base_level in [(7, 21), (8, 24), (9, 33)]:
        for path in (root / "content/base/encounters").glob(f"floor_{floor}_trainer_*.tres"):
            current = path.read_text(encoding="utf-8")
            updated = re.sub(r'("level": )\d+(, "source_level_offset":)', rf'\g<1>{base_level}\2', current)
            # Hidden caster metadata agrees with its first enemy's actual level.
            offset = int(re.search(r'^source_level_offset = (-?\d+)', current, re.MULTILINE).group(1))
            updated = re.sub(r'("team": 1, "level": )\d+(, "move_ids":)', rf'\g<1>{base_level + offset}\2', updated)
            updates[path] = updated

    output = ["*** Begin Patch"]
    for path, updated in updates.items():
        current = path.read_text(encoding="utf-8")
        if current == updated:
            continue
        output.append(f"*** Update File: {path.as_posix()}")
        for line in list(difflib.unified_diff(current.splitlines(), updated.splitlines(), n=2, lineterm=""))[2:]:
            output.append("@@" if line.startswith("@@") else line)
    output.append("*** End Patch")
    print("\n".join(output))


if __name__ == "__main__":
    main()
