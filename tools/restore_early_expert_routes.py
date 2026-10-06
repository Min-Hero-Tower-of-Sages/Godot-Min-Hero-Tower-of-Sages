"""Emit source-authored early expert rooms needed by the hard tower."""
import difflib
import json
import re
from standard_tower_source_plan import ROOT, SOURCE


def main():
    updates = {}
    campaign_path = ROOT / "content/base/campaigns/standard_tower.tres"
    campaign = campaign_path.read_text(encoding="utf-8")
    for floor in range(1, 5):
        graph_path = ROOT / f"content/base/campaigns/floor_{floor}_room_graph.json"
        graph = json.loads(graph_path.read_text(encoding="utf-8"))
        room_id = f"base:room/floor_{floor}_expert_room_" + ("grass" if floor < 4 else "fire")
        source_rel = "TopDown/Levels/Grass/Floor1_1/Room1_1_expertRoom.as" if floor < 4 else "TopDown/Levels/MainTower/ExpertRoom_fire.as"
        script = (SOURCE / source_rel).read_text(encoding="utf-8")
        bounds = re.search(r"drawRect\(0,0,([\d.]+),([\d.]+)\)", script)
        symbol = source_rel.removesuffix(".as").replace("/", ".")
        objects = []
        for match in re.finditer(r'AddObject\("([^"]+)",(-?[\d.]+),(-?[\d.]+),(-?[\d.]+),(-?[\d.]+),(-?[\d.]+)\)', script):
            objects.append({"tag": "levelObject", "attributes": dict(zip(["spriteName", "xPos", "yPos", "xScale", "yScale", "rotation"], match.groups())), "text": "", "children": []})
        payload_path = ROOT / f"content/base/room_payloads/source/early_floor_{floor}_expert.json"
        payload = {"id": room_id, "asset_identity": {"class_name": symbol, "identity_source": "script_authored_AddObject_calls"}, "source_binary": "", "xml": {"tag": "level", "attributes": {"width": bounds[1], "height": bounds[2]}, "text": "", "children": objects}}
        updates[payload_path] = json.dumps(payload, ensure_ascii=False, separators=(",", ":")) + "\n"
        host = None
        for row in graph["rooms"]:
            if "source_payload" not in row: continue
            embedded = json.loads((ROOT / row["source_payload"].removeprefix("res://")).read_text(encoding="utf-8"))
            if any(obj.get("attributes", {}).get("spriteName") == "expert_roomTransitionObject" for obj in embedded["xml"]["children"]):
                host = row
        if host is None: raise ValueError(f"missing expert host: {floor}")
        host.setdefault("source_spawns", []).append({"id": "expert-return", "source_marker": "expert_roomTransitionObject"})
        host["exits"].append({"transition_id": 99, "target_room_id": room_id, "target_spawn_id": "entry-expert", "requires_tower_mode": "hard"})
        encounter_text = (ROOT / f"content/base/encounters/floor_{floor}_trainer_5_expert.tres").read_text(encoding="utf-8")
        encounter_id = re.search(r'^id = &"([^"]+)"', encounter_text, re.M)[1]
        row = {"id": room_id, "display_name": f"Floor {floor} — expert trial", "legacy_class_name": symbol.rsplit(".", 1)[1], "source_symbol": symbol, "source_location": "development/extracted/full-20260908/script/scripts/" + source_rel, "source_payload": "res://" + payload_path.relative_to(ROOT).as_posix(), "room_index": 5, "encounter_ids": [encounter_id], "exits": [{"transition_id": 99, "target_room_id": host["id"], "target_spawn_id": "expert-return", "requires_tower_mode": "hard"}], "interactions": [{"id": f"floor-{floor}-expert-trainer", "kind": "trainer", "source_zone_id": 0, "trainer_room_id": 5, "encounter_id": encounter_id, "requires_tower_mode": "hard"}]}
        if any(existing["id"] == room_id for existing in graph["rooms"]): raise ValueError("early expert routes already restored")
        graph["rooms"].append(row)
        graph.pop("source_only_rooms", None)
        graph.pop("source_only_exits", None)
        if floor == 1:
            map_row = next(existing for existing in graph["rooms"] if existing["id"] == "base:room/level_1_1_d")
            map_row["encounter_ids"] = ["base:encounter/grass_floor1_room4_hard"]
            map_row["interactions"].append({"id": "floor-1-trainer-4-hard", "kind": "trainer", "source_zone_id": 0, "trainer_room_id": 4, "encounter_id": "base:encounter/grass_floor1_room4_hard", "requires_tower_mode": "hard"})
        updates[graph_path] = json.dumps(graph, ensure_ascii=False, indent=2) + "\n"
        pattern = rf'("floor_index": {floor - 1},\n"room_ids": Array\[StringName\]\(\[)([^\n]+)(\]\))'
        def insert(match):
            return match[1] + match[2] + f', &"{room_id}"' + match[3]
        campaign, count = re.subn(pattern, insert, campaign, count=1)
        if count != 1: raise ValueError(f"missing campaign floor {floor}")
    updates[campaign_path] = campaign
    print("*** Begin Patch")
    for path, text in updates.items():
        current = path.read_text(encoding="utf-8") if path.exists() else None
        print(f"*** {'Update' if current is not None else 'Add'} File: {path.as_posix()}")
        if current is None: print("\n".join("+" + line for line in text.splitlines()))
        else:
            for line in list(difflib.unified_diff(current.splitlines(), text.splitlines(), n=2, lineterm=""))[2:]: print("@@" if line.startswith("@@") else line)
    print("*** End Patch")


if __name__ == "__main__": main()
