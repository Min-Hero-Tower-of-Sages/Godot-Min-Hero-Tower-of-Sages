"""Emit a narrow patch preserving saved room/encounter identities."""
import difflib
import json
from copy import deepcopy
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def main():
    updates = {}
    template = json.loads((ROOT / "content/base/room_payloads/source/expert_room_floor9_fire.json").read_text(encoding="utf-8"))
    for floor in [7, 8]:
        path = ROOT / f"content/base/campaigns/floor_{floor}_room_graph.json"
        graph = json.loads(path.read_text(encoding="utf-8"))
        expert = next(row for row in graph["rooms"] if row["room_index"] == 5)
        payload = deepcopy(template)
        payload["id"] = expert["id"]
        payload_name = f"expert_room_floor{floor}_fire.json"
        updates[ROOT / "content/base/room_payloads/source" / payload_name] = json.dumps(payload, ensure_ascii=False, indent=2) + "\n"
        expert.update(legacy_class_name="ExpertRoom_fire", source_symbol="TopDown.Levels.MainTower.ExpertRoom_fire", source_location="development/extracted/full-20260908/script/scripts/TopDown/Levels/MainTower/ExpertRoom_fire.as", source_payload=f"res://content/base/room_payloads/source/{payload_name}")
        graph["expert_layout_source"]["source_location"] = expert["source_location"]
        if floor == 8 and graph["source_room_order"][3].endswith("_c"):
            rooms = {row["room_index"]: row for row in graph["rooms"]}
            # Move trainer metadata with its source room index, not its old geometry.
            fields = ["encounter_ids", "trainer_binding", "interactions"]
            originals = {index: deepcopy(rooms[index]) for index in [3, 4]}
            for index, old_index in [(3, 4), (4, 3)]:
                row = rooms[old_index]
                row["room_index"] = index
                for field in fields:
                    if field in originals[index]:
                        row[field] = deepcopy(originals[index][field])
                    else:
                        row.pop(field, None)
            graph["rooms"].sort(key=lambda row: row["room_index"])
            graph["source_room_order"] = [row["id"] for row in graph["rooms"]]
        updates[path] = json.dumps(graph, ensure_ascii=False, indent=2) + "\n"
    tower = ROOT / "content/base/campaigns/standard_tower.tres"
    updates[tower] = tower.read_text(encoding="utf-8").replace('&"base:room/level_2_3_c", &"base:room/level_2_3_d"', '&"base:room/level_2_3_d", &"base:room/level_2_3_c"')
    print("*** Begin Patch")
    for path, updated in updates.items():
        if not path.exists():
            print(f"*** Add File: {path.as_posix()}")
            print("\n".join("+" + line for line in updated.splitlines()))
            continue
        current = path.read_text(encoding="utf-8")
        if current == updated:
            continue
        print(f"*** Update File: {path.as_posix()}")
        for line in list(difflib.unified_diff(current.splitlines(), updated.splitlines(), n=2, lineterm=""))[2:]:
            print("@@" if line.startswith("@@") else line)
    print("*** End Patch")


if __name__ == "__main__":
    main()
