"""Emit apply_patch changes for source-derived standard floors 11–30.

Generation is read-only until the emitted patch is applied. It does not
regenerate early floors, edit saves, or guess room order from level names.
"""
import argparse
import difflib
import json
import re
import zlib
from pathlib import Path
from unittest.mock import patch
from xml.etree import ElementTree

import build_floor_7_8_source_content as importer
from normalize_rooms import element_to_data
from standard_tower_source_plan import ROOT, SOURCE, source_floors


def base_mod_branch(text):
    """Select the no-extension branches of the source egg table."""
    output = ""
    position = 0
    while match := re.search(r"\bif\s*\([^\n]+\)\s*\{", text[position:]):
        start = position + match.start()
        output += text[position:start]
        cursor = position + match.end()
        depth = 1
        while depth:
            depth += (text[cursor] == "{") - (text[cursor] == "}")
            cursor += 1
        # Skip the false if and each false else-if, retain the final else.
        while alternative := re.match(r"\s*else\s+if\s*\([^\n]+\)\s*\{", text[cursor:]):
            cursor += alternative.end()
            depth = 1
            while depth:
                depth += (text[cursor] == "{") - (text[cursor] == "}")
                cursor += 1
        alternative = re.match(r"\s*else\s*\{", text[cursor:])
        if alternative:
            body_start = cursor + alternative.end()
            cursor = body_start
            depth = 1
            while depth:
                depth += (text[cursor] == "{") - (text[cursor] == "}")
                cursor += 1
            output += base_mod_branch(text[body_start:cursor - 1])
        position = cursor
    return output + text[position:]


def egg_pool(index, dex, minions):
    static = (SOURCE / "PresistentData/StaticData.as").read_text(encoding="utf-8")
    start = static.index("private function SetupTheEggeryInfo()")
    end = static.index("private function ", start + 30)
    body = static[start:end]
    match = re.search(rf"_loc2_ = {index};(.*?)(?=\s*_loc2_ = \d+;|\Z)", body, re.S)
    if not match:
        raise ValueError(f"no egg pool for source floor {index}")
    entries = re.findall(r"AddMinionToEggery\(MinionDexID\.DEX_ID_(\w+),([\d.]+),_loc2_\)", base_mod_branch(match.group(1)))
    return [(minions[dex[name]], float(weight)) for name, weight in entries]


def payload_for(token, floor):
    if token.startswith("ExpertRoom_"):
        name = "expert_room_" + token.removeprefix("ExpertRoom_")
        path = ROOT / f"content/base/room_payloads/source/{name}.json"
        if not path.exists() and token == "ExpertRoom_fire":
            path = ROOT / "content/base/room_payloads/source/expert_room_floor9_fire.json"
        payload = json.loads(path.read_text(encoding="utf-8"))
        payload["id"] = f"base:room/floor_{floor}_expert"
        return f"floor_{floor}_expert", payload
    name = token.lower()
    path = ROOT / f"development/normalized/rooms-20260908/{name}.json"
    if path.exists():
        return name, json.loads(path.read_text(encoding="utf-8"))
    wrapper = (SOURCE / f"Utilities/LevelContainer_{token}.as").read_text(encoding="utf-8")
    binary = re.search(r'Embed\(source="/_assets/([^"]+)"', wrapper).group(1)
    raw = ROOT / "development/extracted/full-20260908/binaryData" / binary
    payload = {"id": f"base:room/{name}", "asset_identity": {"class_name": f"Utilities.LevelContainer_{token}", "identity_source": "explicit_embedded_owner"}, "source_binary": binary, "xml": element_to_data(ElementTree.fromstring(zlib.decompress(raw.read_bytes())))}
    return name, payload


def modifiers(record, body, dex, minions, moves, base_level):
    config = {}
    shield = re.search(r"AddMod_Shield\((\d+)(?:,(\d+))?\)", body)
    if shield:
        config["shield"] = {"enemy": int(shield[1]), "player": int(shield[2] or 0)}
    resurrection = re.search(r"AddMod_Resurection\((\d+)\)", body)
    if resurrection:
        config["resurrection"] = {"team": 1, "turns": int(resurrection[1])}
    if timer := record.get("move_timer"):
        config["move_timer"] = {**timer, "actor": {"instance_id": f"floor{record['source_floor_index'] + 1}-timer-{record['room']}", "definition_id": f"internal:minion/bmod_{timer['source_power'] + 1}", "team": 1, "level": base_level + record["level_offset"], "move_ids": [timer["move_id"]]}}
    for match in re.finditer(r"AddMod_ExtraMinions_(Opponent|Player)\(MinionDexID\.DEX_ID_(\w+),(\d+),\[([^\]]*)\],(-?\d+)\)", body):
        side, name, count, raw_moves, offset = match.groups()
        config.setdefault("extra_minions", {})["enemy" if side == "Opponent" else "player"] = {"count": int(count), "templates": [{"definition_id": minions[dex[name]], "level": base_level + int(offset), "move_ids": [moves[int(value.strip())] for value in raw_moves.split(",") if value.strip()], "source_derive_stats": True}]}
    expected = re.findall(r"AddMod_(\w+)\(", body)
    actual = int("shield" in config) + int("resurrection" in config) + int("move_timer" in config) + len(config.get("extra_minions", {}))
    if len(expected) != actual:
        raise ValueError(f"unhandled modifier calls for {record['id']}: {expected}")
    return config


def build_floor(floor_data, updates, minions, moves, dex):
    floor, index, base = floor_data["floor"], floor_data["source_floor_index"], floor_data["base_level"]
    capture = {}
    with patch.object(Path, "write_text", lambda path, text, **kwargs: capture.__setitem__(path, text)):
        records = importer.trainers_for_floor(floor, base, {}, {}, minions, moves, source_method=floor_data["trainer_method"])
    source_text = importer.TRAINER_SOURCE.read_text(encoding="utf-8")
    method = re.search(rf"private function {floor_data['trainer_method']}\(\).*?(?=\n      (?:private|public) function|\Z)", source_text, re.S).group(0)
    trainer_bodies = {int(room): body for _kind, _index, room, body in re.findall(r"AddTrainerToFloor\(TrainerType\.(\w+),(\d+),(\d+)\);(.*?)(?=_loc2_ = this\.AddTrainerToFloor|\Z)", method, re.S)}
    paths = []
    for record in records:
        if "TRAINER_GYM_" in record["type"]:
            record["ai"] = "boss"
            record["reward"] = {"sage_seals": 1}
        elif record["type"] == "TrainerType.TRAINER_GRAND_SAGE":
            record["ai"] = "boss"
            record["reward"] = {}
        elif "random_gems" in record["reward"]:
            record["reward"]["random_gems"]["tier"] = min(5, index // 5 + 1)
        capture.clear()
        with patch.object(Path, "write_text", lambda path, text, **kwargs: capture.__setitem__(path, text)):
            importer.write_encounter(record, base)
        path, text = next(iter(capture.items()))
        text = re.sub(r"^battle_modifier_configuration = .*\n", "", text, flags=re.M)
        config = modifiers(record, trainer_bodies[record["room"]], dex, minions, moves, base)
        if config:
            text += "battle_modifier_configuration = " + json.dumps(config) + "\n"
        updates[path] = text
        paths.append(path)
    trainer_by_room = {record["room"]: record for record in records}
    rows, payloads = [], {}
    for entry in floor_data["rooms"]:
        token, room_index = entry["source_class"], entry["room_index"]
        name, payload = payload_for(token, floor)
        payloads[payload["id"]] = payload
        updates[ROOT / f"content/base/room_payloads/source/{name}.json"] = json.dumps(payload, ensure_ascii=False, separators=(",", ":")) + "\n"
        expert = token.startswith("ExpertRoom_")
        symbol = f"TopDown.Levels.MainTower.{token}" if expert else f"Utilities.LevelContainer_{token}"
        row = {"id": payload["id"], "display_name": f"Floor {floor} — {token}", "legacy_class_name": token if expert else "LevelContainer_" + token, "source_symbol": symbol, "source_location": f"development/extracted/full-20260908/script/scripts/{'TopDown/Levels/MainTower/' + token if expert else 'Utilities/LevelContainer_' + token}.as", "source_payload": f"res://content/base/room_payloads/source/{name}.json", "room_index": room_index, "exits": []}
        if record := trainer_by_room.get(room_index):
            row["encounter_ids"] = [record["id"]]
            row["trainer_binding"] = {"trainer_room_id": room_index, "trainer_type": record["type"], "source_location": record["source_location"], "source_method": record["source_method"], "source_floor_argument": index}
            row["interactions"] = [{"id": f"floor-{floor}-trainer-{room_index}", "kind": "trainer", "source_zone_id": 0, "trainer_room_id": room_index, "trainer_type": record["type"], "source_trigger": "buttonZoneObject", "encounter_id": record["id"], "first_visit_text": record["start_text"], "lose_text": record["lose_text"]}]
            if expert:
                row["interactions"][0]["requires_tower_mode"] = "hard"
        if token.endswith("Eggery"):
            pool = egg_pool(index, dex, minions)
            if not pool:
                raise ValueError(f"empty native egg pool on floor {floor}")
            row["interactions"] = [{"id": f"floor-{floor}-egg-slot-{slot}", "kind": "egg_pick", "source_zone_id": slot, "candidates": [key for key, _ in pool], "weights": [weight for _, weight in pool]} for slot in range(9)]
        if any(obj.get("attributes", {}).get("spriteName") == "generalRoom_healStone" for obj in payload["xml"]["children"]):
            row.setdefault("interactions", []).append({"id": f"floor-{floor}-heal-{room_index}", "kind": "heal_party", "source_zone_id": 1, "trigger_on_enter": True})
        rows.append(row)
    markers, external = {}, []
    expert_row = next((row for row in rows if row["source_symbol"].startswith("TopDown.Levels.MainTower.ExpertRoom")), None)
    expert_host = None
    for row in rows:
        for obj in payloads[row["id"]]["xml"]["children"]:
            sprite = obj.get("attributes", {}).get("spriteName", "")
            if match := re.fullmatch(r"(?:teleport_|telport_)?roomTransitionObject(\d+)", sprite):
                markers.setdefault(int(match[1]), []).append(row)
            elif sprite == "expert_roomTransitionObject" and row is not expert_row:
                expert_host = row
                row["source_spawns"] = [{"id": "expert-return", "source_marker": sprite}]
            elif sprite in ["roomTransitionObject_startingRoomToLobby", "roomTransition_startingRoomToLobby", "roomTransitionObject_lobbyFromEggery"]:
                external.append({"room_id": row["id"], "transition_id": 101 if "startingRoom" in sprite else 100, "source_sprite": sprite, "target_route": "lobby"})
    for transition, hosts in markers.items():
        if len(hosts) != 2:
            raise ValueError(f"floor {floor}: transition {transition} has {len(hosts)} hosts")
        for origin, target in [hosts, list(reversed(hosts))]:
            origin["exits"].append({"transition_id": transition, "target_room_id": target["id"], "target_spawn_id": f"entry-{transition}"})
    if expert_row:
        if expert_host is None:
            raise ValueError(f"floor {floor}: missing expert teleporter host")
        expert_host["exits"].append({"transition_id": 99, "target_room_id": expert_row["id"], "target_spawn_id": "entry-expert", "requires_tower_mode": "hard"})
        expert_row["exits"].append({"transition_id": 99, "target_room_id": expert_host["id"], "target_spawn_id": "expert-return", "requires_tower_mode": "hard"})
    graph = {"floor_index": index, "source_floor_index": index, "source_room_order": [row["id"] for row in rows], "entry_room_id": rows[0]["id"], "rooms": rows, "external_transitions": external, "eggery_source": {"source_floor_index": index, "source_minion_level_base": base, "source_minion_level_random_offset": [0, 2]}}
    updates[ROOT / f"content/base/campaigns/floor_{floor}_room_graph.json"] = json.dumps(graph, ensure_ascii=False, indent=2) + "\n"
    common = '[gd_resource type="Resource" script_class="ContentPackDefinition" format=3]\n\n[ext_resource type="Script" path="res://src/content/content_pack_definition.gd" id="1_pack"]\n[ext_resource type="Script" path="res://src/content/content_definition.gd" id="2_definition"]\n'
    updates[ROOT / f"content/base/packs/floor_{floor}_slice.tres"] = common + f'\n[resource]\nscript = ExtResource("1_pack")\ndependencies = Array[StringName]([&"base:pack/recovered", &"base:pack/campaign_slice"])\ndefinitions = Array[ExtResource("2_definition")]([])\nsource_room_graph_path = "res://content/base/campaigns/floor_{floor}_room_graph.json"\nid = &"base:pack/floor_{floor}_slice"\ndisplay_name = "Standard tower — floor {floor}"\n'
    resources = "".join(f'[ext_resource type="Resource" path="res://{path.relative_to(ROOT).as_posix()}" id="{i + 3}_encounter"]\n' for i, path in enumerate(paths))
    refs = ", ".join(f'ExtResource("{i + 3}_encounter")' for i in range(len(paths)))
    updates[ROOT / f"content/base/packs/floor_{floor}_trainers.tres"] = common + resources + f'\n[resource]\nscript = ExtResource("1_pack")\ndependencies = Array[StringName]([&"base:pack/recovered", &"base:pack/floor_{floor}_slice"])\ndefinitions = Array[ExtResource("2_definition")]([{refs}])\nid = &"base:pack/floor_{floor}_trainers"\ndisplay_name = "Standard tower — floor {floor} trainers"\n'
    return graph


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--floor", type=int, required=True, choices=range(11, 32))
    parser.add_argument("--summary", action="store_true")
    parser.add_argument("--part", type=int, default=0)
    parser.add_argument("--metadata-only", action="store_true")
    args = parser.parse_args()
    minions = importer.imported_ids(ROOT / "content/imported/recovered-20260911/minions")
    moves = importer.imported_ids(ROOT / "content/imported/recovered-20260911/moves")
    dex = {name: int(value) for name, value in re.findall(r"DEX_ID_(\w+):int\s*=\s*(\d+)", (SOURCE / "States/MinionDexID.as").read_text(encoding="utf-8"))}
    updates = {}
    graph = build_floor(source_floors(max(30, args.floor))[args.floor - 1], updates, minions, moves, dex)
    groups = [[]]
    size = 0
    for path, text in updates.items():
        if args.metadata_only and "room_payloads" in path.parts:
            continue
        if size and size + len(text) > 120000:
            groups.append([])
            size = 0
        groups[-1].append((path, text))
        size += len(text)
    if args.summary:
        print(json.dumps({"floor": args.floor, "rooms": len(graph["rooms"]), "exits": sum(len(row["exits"]) for row in graph["rooms"]), "files": len(updates), "parts": len(groups)}))
        return
    print("*** Begin Patch")
    for path, text in groups[args.part]:
        current = path.read_text(encoding="utf-8") if path.exists() else None
        if current == text:
            continue
        print(f"*** {'Update' if current is not None else 'Add'} File: {path.as_posix()}")
        if current is None:
            print("\n".join("+" + line for line in text.splitlines()))
        else:
            for line in list(difflib.unified_diff(current.splitlines(), text.splitlines(), n=2, lineterm=""))[2:]:
                print("@@" if line.startswith("@@") else line)
    print("*** End Patch")


if __name__ == "__main__":
    main()
