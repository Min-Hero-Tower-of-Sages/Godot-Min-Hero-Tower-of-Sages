"""Emit source H4 payload/graph additions through apply_patch, preserving saves."""
import difflib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def main():
    updates = {}
    additions = {}
    for floor, prefix in [(7, "level_2_2"), (8, "level_2_3")]:
        graph_path = ROOT / f"content/base/campaigns/floor_{floor}_room_graph.json"
        graph = json.loads(graph_path.read_text(encoding="utf-8"))
        hallway_id = f"base:room/{prefix}_h4"
        payload_source = ROOT / f"development/normalized/rooms-20260908/{prefix}_h4.json"
        payload_target = ROOT / f"content/base/room_payloads/source/{prefix}_h4.json"
        payload = json.loads(payload_source.read_text(encoding="utf-8"))
        assert payload["id"] == hallway_id
        if not payload_target.exists():
            additions[payload_target] = payload_source.read_text(encoding="utf-8")
        existing = next((row for row in graph["rooms"] if row["id"] == hallway_id), None)
        if existing is None:
            eggery_index = next(i for i, row in enumerate(graph["rooms"]) if row["id"] == f"base:room/{prefix}_eggery")
            graph["rooms"].insert(eggery_index, {"id": hallway_id, "display_name": f"Floor {floor} — hatchery passage", "legacy_class_name": f"LevelContainer_{prefix.capitalize()}_H4", "source_symbol": f"Utilities.LevelContainer_{prefix.capitalize()}_H4", "source_location": f"development/extracted/full-20260908/script/scripts/Utilities/LevelContainer_{prefix.capitalize()}_H4.as", "source_payload": f"res://content/base/room_payloads/source/{prefix}_h4.json", "room_index": 9, "exits": []})
            graph["rooms"][eggery_index + 1]["room_index"] = 10
            graph["source_room_order"].insert(-1, hallway_id)
        # Restore only edges touching this omitted room. Existing other
        # edges, encounter identities, room geometry and progression stay intact.
        markers = {}
        for room in graph["rooms"]:
            path = ROOT / room["source_payload"].replace("res://", "")
            raw = json.loads(additions[path]) if path in additions else json.loads(path.read_text(encoding="utf-8"))
            for obj in raw["xml"]["children"]:
                name = obj.get("attributes", {}).get("spriteName", "")
                suffix = name.removeprefix("roomTransitionObject")
                if name.startswith("roomTransitionObject") and suffix.isdigit():
                    markers.setdefault(int(suffix), []).append(room)
        for transition, rooms in markers.items():
            if not any(room["id"] == hallway_id for room in rooms): continue
            assert len(rooms) == 2, (hallway_id, transition)
            for origin, target in [(rooms[0], rooms[1]), (rooms[1], rooms[0])]:
                if not any(int(edge["transition_id"]) == transition for edge in origin["exits"]):
                    origin["exits"].append({"transition_id": transition, "target_room_id": target["id"], "target_spawn_id": f"entry-{transition}"})
        updates[graph_path] = json.dumps(graph, ensure_ascii=False, indent=2) + "\n"
    campaign_path = ROOT / "content/base/campaigns/standard_tower.tres"
    campaign = campaign_path.read_text(encoding="utf-8")
    for prefix in ["level_2_2", "level_2_3"]:
        old = f'&"base:room/{prefix}_h3", &"base:room/{prefix}_eggery"'
        new = f'&"base:room/{prefix}_h3", &"base:room/{prefix}_h4", &"base:room/{prefix}_eggery"'
        if old in campaign: campaign = campaign.replace(old, new)
    updates[campaign_path] = campaign
    output = ["*** Begin Patch"]
    for path, text in additions.items():
        output.append(f"*** Add File: {path.as_posix()}")
        output.extend("+" + line for line in text.splitlines())
    for path, text in updates.items():
        current = path.read_text(encoding="utf-8")
        if current == text: continue
        output.append(f"*** Update File: {path.as_posix()}")
        for line in list(difflib.unified_diff(current.splitlines(), text.splitlines(), n=2, lineterm=""))[2:]:
            output.append("@@" if line.startswith("@@") else line)
    output.append("*** End Patch")
    print("\n".join(output))


if __name__ == "__main__": main()
