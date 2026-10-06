"""Emit registration only after all floor-11–30 resources are present."""
import difflib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def main():
    floors = []
    for floor in range(11, 31):
        graph = json.loads((ROOT / f"content/base/campaigns/floor_{floor}_room_graph.json").read_text(encoding="utf-8"))
        for kind in ["slice", "trainers"]:
            assert (ROOT / f"content/base/packs/floor_{floor}_{kind}.tres").exists()
        for room in graph["rooms"]:
            assert (ROOT / room["source_payload"].removeprefix("res://")).exists()
        rows = ", ".join('&"' + room_id + '"' for room_id in graph["source_room_order"])
        floors.append('{\n"floor_index": ' + str(floor - 1) + ',\n"eggery_minion_base_level": ' + str(graph["eggery_source"]["source_minion_level_base"]) + ',\n"room_ids": Array[StringName]([' + rows + ']),\n"start_room_id": &"' + graph["entry_room_id"] + '",\n"start_spawn_id": &"entry-0"\n}')
    updates = {}
    path = ROOT / "content/base/campaigns/standard_tower.tres"
    text = path.read_text(encoding="utf-8")
    assert '"floor_index": 10,' not in text, "extension already registered"
    text = text.replace('\n}])\nstarting_room_id', '\n}, ' + ', '.join(floors) + '])\nstarting_room_id', 1)
    updates[path] = text
    path = ROOT / "src/application/campaign_runtime.gd"
    text = path.read_text(encoding="utf-8")
    declarations = "\n".join(f'\tpreload("res://content/base/packs/floor_{floor}_{kind}.tres"),' for floor in range(11, 31) for kind in ["slice", "trainers"])
    text = text.replace('const BATTLE_DEMO_PACK =', 'const EXTENDED_TOWER_PACKS = [\n' + declarations + '\n]\nconst BATTLE_DEMO_PACK =', 1)
    text = text.replace('\tvar errors := catalog.rebuild_index()', '\tfor pack in EXTENDED_TOWER_PACKS:\n\t\t_add_pack_once(pack)\n\tvar errors := catalog.rebuild_index()', 1)
    updates[path] = text
    print("*** Begin Patch")
    for path, text in updates.items():
        current = path.read_text(encoding="utf-8")
        print(f"*** Update File: {path.as_posix()}")
        for line in list(difflib.unified_diff(current.splitlines(), text.splitlines(), n=2, lineterm=""))[2:]:
            print("@@" if line.startswith("@@") else line)
    print("*** End Patch")


if __name__ == "__main__":
    main()
