"""Build source-derived room graphs and encounters for the standard tower slice."""

from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "development/extracted/full-20260908/script/scripts"
NORMALIZED = ROOT / "development/normalized/rooms-20260908"
PAYLOADS = ROOT / "content/base/room_payloads/source"
GRAPHS = ROOT / "content/base/campaigns"
ENCOUNTERS = ROOT / "content/base/encounters"
TRAINER_SOURCE = SOURCE / "TopDown/Trainers/TrainerSystem.as"


def enum_values(path: Path, prefix: str, suffix: str) -> dict[int, str]:
    found: dict[int, str] = {}
    for name, value in re.findall(rf"{re.escape(prefix)}([A-Za-z0-9_]+){re.escape(suffix)}\s*:\s*int\s*=\s*(\d+)", path.read_text(encoding="utf-8")):
        found[int(value)] = name
    return found


def imported_ids(folder: Path) -> dict[int, str]:
    result: dict[int, str] = {}
    for path in folder.glob("*.tres"):
        text = path.read_text(encoding="utf-8")
        numeric = re.search(r"legacy_numeric_id\s*=\s*(\d+)", text)
        identifiers = re.findall(r'^id\s*=\s*&"([^"]+)"', text, re.MULTILINE)
        if numeric and identifiers:
            result[int(numeric.group(1))] = identifiers[-1]
    return result


def object_records(path: Path) -> list[dict]:
    data = json.loads(path.read_text(encoding="utf-8"))
    return data["xml"]["children"]


def build_graph(floor_index: int, level_name: str, expert_type: str, expert_encounter: str, trainers: list[dict], eggery_candidates: list[tuple[str, int]], eggery_base_level: int, eggery_source_binary: str = "1543.bin", eggery_owner: str = "Utilities.LevelContainer_Level_2_2_Eggery", expert_room_id: str = "", expert_room_payload: str = "") -> dict:
    prefix = level_name.lower()
    room_symbols = ["h1", "a", "b", "c", "d", "expert", "e", "h2", "h3", "eggery"]
    if floor_index in [6, 7]:
        room_symbols.insert(-1, "h4")
    if floor_index == 7:
        room_symbols[3:5] = ["d", "c"]
    ids = {symbol: f"base:room/{prefix}_{symbol}" if symbol != "expert" else (expert_room_id or f"base:room/floor_2_expert_room_{expert_type}") for symbol in room_symbols}
    paths = {symbol: PAYLOADS / f"{prefix}_{symbol}.json" for symbol in room_symbols if symbol != "expert"}
    for symbol, path in paths.items():
        if not path.exists():
            source_path = NORMALIZED / f"{prefix}_{symbol}.json"
            path.write_text(source_path.read_text(encoding="utf-8"), encoding="utf-8")

    order = room_symbols
    symbols_at_transition: dict[int, list[str]] = {}
    room_objects = {symbol: object_records(paths[symbol]) for symbol in room_symbols if symbol != "expert"}
    for symbol, objects in room_objects.items():
        for obj in objects:
            sprite = obj.get("attributes", {}).get("spriteName", "")
            match = re.fullmatch(r"roomTransitionObject(\d+)", sprite)
            if match:
                symbols_at_transition.setdefault(int(match.group(1)), []).append(symbol)

    trainer_by_room = {entry["room"]: entry for entry in trainers}
    expert_return_hosts = [
        symbol
        for symbol, objects in room_objects.items()
        if any(obj.get("attributes", {}).get("spriteName") == "expert_roomTransitionObject" for obj in objects)
    ]
    if len(expert_return_hosts) != 1:
        raise ValueError(f"expected one expert return marker for floor {floor_index + 1}, found {expert_return_hosts}")
    expert_return_host = expert_return_hosts[0]
    rooms: list[dict] = []
    for room_index, symbol in enumerate(order):
        room_id = ids[symbol]
        if symbol == "expert":
            continue
        exits: list[dict] = []
        for obj in room_objects[symbol]:
            sprite = obj.get("attributes", {}).get("spriteName", "")
            match = re.fullmatch(r"roomTransitionObject(\d+)", sprite)
            if match:
                transition = int(match.group(1))
                targets = [other for other in symbols_at_transition.get(transition, []) if other != symbol]
                if len(targets) == 1:
                    exits.append({"transition_id": transition, "target_room_id": ids[targets[0]], "target_spawn_id": f"entry-{transition}"})
            elif sprite == "expert_roomTransitionObject":
                exits.append({"transition_id": 99, "target_room_id": ids["expert"], "target_spawn_id": "entry-expert"})
            elif sprite == "roomTransitionObject_startingRoomToLobby":
                pass

        row = {
            "id": room_id,
            "display_name": f"Floor {floor_index + 1} — {symbol.replace('_', ' ').title()}",
            "legacy_class_name": f"LevelContainer_{level_name[0].upper() + level_name[1:]}_{symbol.upper()}" if symbol != "eggery" else f"LevelContainer_{level_name[0].upper() + level_name[1:]}_Eggery",
            "source_symbol": f"Utilities.LevelContainer_{level_name[0].upper() + level_name[1:]}_{symbol.upper() if symbol != 'eggery' else 'Eggery'}",
            "source_location": f"development/extracted/full-20260908/script/scripts/Utilities/LevelContainer_{level_name[0].upper() + level_name[1:]}_{symbol.upper() if symbol != 'eggery' else 'Eggery'}.as",
            "source_payload": f"res://content/base/room_payloads/source/{prefix}_{symbol}.json",
            "room_index": room_index,
            "exits": exits,
        }
        if symbol == "h1":
            pass
        trainer = trainer_by_room.get(room_index)
        if trainer:
            encounter_id = trainer["id"]
            row["encounter_ids"] = [encounter_id]
            row["trainer_binding"] = {"trainer_room_id": room_index, "trainer_type": trainer["type"], "source_location": "development/extracted/full-20260908/script/scripts/TopDown/Trainers/TrainerSystem.as", "source_method": trainer["source_method"], "source_floor_argument": trainer["source_trainer_floor"]}
            interaction = {"id": f"floor-{floor_index + 1}-trainer-{room_index}", "kind": "trainer", "source_zone_id": 0, "trainer_room_id": room_index, "trainer_type": trainer["type"], "source_trigger": "buttonZoneObject", "encounter_id": encounter_id}
            if trainer.get("start_text"):
                interaction["first_visit_text"] = trainer["start_text"]
            if trainer.get("lose_text"):
                interaction["lose_text"] = trainer["lose_text"]
            row["interactions"] = [interaction]
        if any(obj.get("attributes", {}).get("spriteName") == "expert_roomTransitionObject" for obj in room_objects[symbol]):
            row["source_spawns"] = [{"id": "expert-return", "source_marker": "expert_roomTransitionObject"}]
        for exit_data in row["exits"]:
            if exit_data.get("target_room_id") == ids["eggery"]:
                exit_data["requires_progression_flag"] = "eggery_door_unlocked"
        if symbol == "expert":
            pass
        if symbol == "eggery":
            row["interactions"] = [{"id": f"floor-{floor_index + 1}-egg-slot-{slot}", "kind": "egg_pick", "source_zone_id": slot, "candidates": [key for key, _weight in eggery_candidates], "weights": [weight for _key, weight in eggery_candidates]} for slot in range(9)]
        rooms.append(row)

    expert_row = {
        "id": ids["expert"],
        "display_name": f"Floor {floor_index + 1} — expert trial room",
        "legacy_class_name": f"ExpertRoom_{expert_type}",
        "source_symbol": f"TopDown.Levels.MainTower.ExpertRoom_{expert_type}",
        "source_location": f"development/extracted/full-20260908/script/scripts/TopDown/Levels/MainTower/ExpertRoom_{expert_type}.as",
        "source_payload": f"res://content/base/room_payloads/source/{expert_room_payload or f'expert_room_{expert_type}.json'}",
        "room_index": 5,
        "encounter_ids": [expert_encounter],
        "exits": [{"transition_id": 99, "target_room_id": ids[expert_return_host], "target_spawn_id": "expert-return"}],
        "trainer_binding": {"trainer_room_id": 5, "trainer_type": "TrainerType.EXPERT_TRAINER", "source_location": "development/extracted/full-20260908/script/scripts/TopDown/Trainers/TrainerSystem.as", "source_method": next(record["source_method"] for record in trainers if record["room"] == 5), "source_floor_argument": next(record["source_trainer_floor"] for record in trainers if record["room"] == 5)},
        "interactions": [{"id": f"floor-{floor_index + 1}-trainer-5", "kind": "trainer", "source_zone_id": 0, "trainer_room_id": 5, "trainer_type": "TrainerType.EXPERT_TRAINER", "source_trigger": "buttonZoneObject", "encounter_id": expert_encounter}],
    }
    rooms.insert(5, expert_row)
    graph = {
        "floor_index": floor_index,
        "source_floor_index": floor_index,
        "source_room_order": [ids[symbol] for symbol in order],
        "entry_room_id": ids["h1"],
        "expert_layout_source": {"source_location": expert_row["source_location"], "source_payload_status": "literal AddObject/drawRect calls normalized without geometry changes"},
        "normalized_embedded_payloads": [{"room_id": ids["eggery"], "source_binary": f"development/extracted/full-20260908/binaryData/{eggery_source_binary}", "normalized_payload": f"content/base/room_payloads/source/{prefix}_eggery.json", "identity_source": "shared_embedded_binary_explicit_owner", "owner_class_name": eggery_owner, "source_payload_status": f"source wrapper {eggery_owner} explicitly embeds {eggery_source_binary}; payload id and owner are floor-local while geometry is retained"}],
        "external_transitions": [{"room_id": ids["h1"], "transition_id": 101, "source_sprite": "roomTransitionObject_startingRoomToLobby", "target_route": "lobby"}, {"room_id": ids["eggery"], "transition_id": 100, "source_sprite": "roomTransitionObject_lobbyFromEggery", "target_route": "lobby"}],
        "rooms": rooms,
        "eggery_source": {"source_location": "development/extracted/full-20260908/script/scripts/PresistentData/StaticData.as", "source_method": "SetupTheEggeryInfo", "source_floor_index": floor_index, "source_minion_level_base": eggery_base_level, "source_minion_level_random_offset": [0, 2], "source_candidates": [{"source_minion": key.split("/")[-1], "weight": weight} for key, weight in eggery_candidates]},
    }
    return graph


def trainers_for_floor(floor: int, base_level: int, dex_ids: dict[int, str], move_ids: dict[int, str], minion_definitions: dict[int, str], move_definitions: dict[int, str], source_method: str | None = None) -> list[dict]:
    text = TRAINER_SOURCE.read_text(encoding="utf-8")
    source_method = source_method or f"CreateFloor{floor}"
    start = text.index(f"private function {source_method}()")
    end_match = re.search(r"\n      private function ", text[start + 1:])
    method = text[start:start + 1 + end_match.start()] if end_match else text[start:]
    blocks = re.split(r"_loc2_ = this\.AddTrainerToFloor\(TrainerType\.(\w+),(\d+),(\d+)\);", method)
    result: list[dict] = []
    type_names = {"NORMAL_TRAINER": "TrainerType.NORMAL_TRAINER", "HARD_TRAINER": "TrainerType.HARD_TRAINER", "EXPERT_TRAINER": "TrainerType.EXPERT_TRAINER", "BOSS_TRAINER": "TrainerType.BOSS_TRAINER"}
    ai_names = {"NORMAL_TRAINER": "normal", "HARD_TRAINER": "hard", "EXPERT_TRAINER": "expert", "BOSS_TRAINER": "boss"}
    encounter_suffix = {"NORMAL_TRAINER": "", "HARD_TRAINER": "_hard", "EXPERT_TRAINER": "_expert", "BOSS_TRAINER": "_boss"}
    for index in range(1, len(blocks), 4):
        trainer_type, floor_raw, room_raw = blocks[index:index + 3]
        body = blocks[index + 3]
        room = int(room_raw)
        entries: list[dict] = []
        level_offset_match = re.search(r"m_extraMinionLevels\s*=\s*(-?\d+)", body)
        level_offset = int(level_offset_match.group(1)) if level_offset_match else 0
        for team_slot, (source_minion, source_moves) in enumerate(re.findall(r"AddMinion\(MinionDexID\.DEX_ID_(\w+),\[([^\]]+)\]\)", body)):
            # Dex names resolve by enum source token, then by imported numeric id.
            enum_match = re.search(rf"DEX_ID_{re.escape(source_minion)}:int\s*=\s*(\d+)", (SOURCE / "States/MinionDexID.as").read_text(encoding="utf-8"))
            if enum_match is None:
                raise ValueError(f"unresolved source minion {source_minion}")
            dex_value = int(enum_match.group(1))
            minion_id = minion_definitions.get(dex_value)
            if minion_id is None:
                raise ValueError(f"no imported minion definition for source dex {source_minion} ({dex_value})")
            source_numeric_moves = [int(value.strip()) for value in source_moves.split(",") if value.strip()]
            resolved_moves = [move_definitions[value] for value in source_numeric_moves if value in move_definitions]
            if len(resolved_moves) != len(source_numeric_moves):
                missing = [value for value in source_numeric_moves if value not in move_definitions]
                raise ValueError(f"missing imported move IDs {missing} in {source_minion}")
            # CampaignProgressionService applies source_level_offset once.
            entries.append({"definition_id": minion_id, "level": base_level, "source_level_offset": level_offset, "slot_index": team_slot, "move_ids": resolved_moves})
        if not entries:
            raise ValueError(f"trainer {floor}/{room} has no parsed team")
        start_line = re.search(r'm_whatTrainerSaysAtStart_notBeaten\s*=\s*"((?:\\.|[^"\\])*)"', body)
        lose_line = re.search(r'm_whatTrainerSaysAtLose\s*=\s*"((?:\\.|[^"\\])*)"', body)
        start_text = start_line.group(1).replace("\\'", "'").replace("\\n", "\n") if start_line else ""
        lose_text = lose_line.group(1).replace("\\'", "'").replace("\\n", "\n") if lose_line else ""
        encounter_id = f"base:encounter/floor{floor}_trainer_{room}{encounter_suffix.get(trainer_type, '')}"
        kind = type_names.get(trainer_type, f"TrainerType.{trainer_type}")
        ai = ai_names.get(trainer_type, "normal")
        reward = {"floor_keys": 1} if trainer_type == "NORMAL_TRAINER" else {"eggery_keys": 1}
        if trainer_type in ["HARD_TRAINER", "EXPERT_TRAINER"]:
            reward["random_gems"] = {"count": 1, "tier": 1 if floor - 1 < 5 else 2 if floor - 1 < 10 else 3}
        record = {"id": encounter_id, "room": room, "type": kind, "start_text": start_text, "lose_text": lose_text, "entries": entries, "ai": ai, "level_offset": level_offset, "source_floor_index": floor - 1, "source_trainer_floor": int(floor_raw), "source_method": source_method, "source_location": f"development/extracted/full-20260908/script/scripts/TopDown/Trainers/TrainerSystem.as:{text[:start].count(chr(10)) + method[:method.index(body)].count(chr(10)) + 1}", "reward": reward}
        timer_match = re.search(r"AddMod_MoveTimer\(MinionMoveID\.(\w+),(\d+),(\d+),MinionMoveID\.(\w+)\)", body)
        if timer_match:
            move_name, interval, source_power, buff_name = timer_match.groups()
            move_enum = (SOURCE / "States/MinionMoveID.as").read_text(encoding="utf-8")
            resolved = []
            for token in [move_name, buff_name]:
                numeric = re.search(rf"public static const {re.escape(token)}:int\s*=\s*(\d+)", move_enum)
                if numeric is None or int(numeric.group(1)) not in move_definitions:
                    raise ValueError(f"unmapped timer move {token} for {encounter_id}")
                resolved.append(move_definitions[int(numeric.group(1))])
            record["move_timer"] = {"interval": int(interval), "source_power": int(source_power), "move_id": resolved[0], "buff_move_id": resolved[1]}
        write_encounter(record, base_level)
        result.append(record)
    return result


def write_encounter(record: dict, base_level: int) -> None:
    entries_text = []
    for entry in record["entries"]:
        moves = ", ".join(f'&"{move}"' for move in entry["move_ids"])
        entries_text.append("{\n" + f'"definition_id": &"{entry["definition_id"]}", "level": {entry["level"]}, "source_level_offset": {entry["source_level_offset"]}, "slot_index": {entry["slot_index"]},\n' + f'"move_ids": Array[StringName]([{moves}])' + "\n}")
    money_basis = 7.0
    for _floor in range(int(record["source_floor_index"])):
        money_basis = min(money_basis * 1.25, 2000.0)
    money_basis = int(money_basis + 0.5)
    rewards = {"first_clear": {"floor_money_basis": money_basis, **record["reward"]}}
    dialogue_description = json.dumps("Source start dialogue: " + record["start_text"] + "\nSource defeat dialogue: " + record["lose_text"], ensure_ascii=False)
    body = (
        '[gd_resource type="Resource" script_class="EncounterDefinition" format=3]\n\n'
        '[ext_resource type="Script" path="res://src/content/encounter_definition.gd" id="1_encounter"]\n\n'
        '[resource]\nscript = ExtResource("1_encounter")\n'
        f'team_entries = Array[Dictionary]([{", ".join(entries_text)}])\n'
        f'ai_profile_id = &"base:ai/trainer/{record["ai"]}"\n'
        f'rewards = {json.dumps(rewards, separators=(", ", ": "))}\n'
        f'source_trainer_id = &"base:trainer/standard/{record["source_trainer_floor"]}/{record["room"]}"\n'
        f'source_floor_index = {record["source_floor_index"]}\nsource_level_offset = {record["level_offset"]}\n'
        f'source_trainer_type = &"{record["type"]}"\nid = &"{record["id"]}"\n'
        f'display_name = "Floor {record["source_floor_index"] + 1} — source trainer {record["room"]}"\n'
        f'description = {dialogue_description}\n'
        f'legacy_class_name = "TrainerSystem.{record["source_method"]}"\n'
        f'source_location = "{record["source_location"]}"\n'
    )
    if record.get("move_timer"):
        timer = record["move_timer"]
        actor = record["entries"][0]
        body += (
            'battle_modifier_configuration = {"move_timer": {'
            f'"interval": {timer["interval"]}, "move_id": &"{timer["move_id"]}", '
            f'"buff_move_id": &"{timer["buff_move_id"]}", "source_power": {timer["source_power"]}, '
            f'"actor": {{"instance_id": "floor{record["source_floor_index"] + 1}-trainer{record["room"]}-move-timer", "definition_id": &"internal:minion/bmod_{timer["source_power"] + 1}", '
            f'"team": 1, "level": {actor["level"]}, "move_ids": Array[StringName]([&"{timer["move_id"]}"])'
            '}}}\n'
        )
    suffix = record.get("suffix", "_hard" if "HARD" in record["type"] else "_expert" if "EXPERT" in record["type"] else "_boss" if "BOSS" in record["type"] else "")
    target = ENCOUNTERS / f"floor_{record['source_floor_index'] + 1}_trainer_{record['room']}{suffix}.tres"
    target.write_text(body, encoding="utf-8")


def trainer_for_gym(base_level: int, dex_enum: str, minion_definitions: dict[int, str], move_definitions: dict[int, str]) -> dict:
    text = TRAINER_SOURCE.read_text(encoding="utf-8")
    method_name = "CreateFloor_Boss2"
    start = text.index(f"private function {method_name}()")
    end_match = re.search(r"\n      private function ", text[start + 1:])
    method = text[start:start + 1 + end_match.start()] if end_match else text[start:]
    trainer = re.search(r"AddTrainerToFloor\(TrainerType\.(\w+),(\d+),(\d+)\)", method)
    if trainer is None:
        raise ValueError("CreateFloor_Boss2 has no source trainer binding")
    trainer_type, source_floor, room_raw = trainer.groups()
    entries: list[dict] = []
    for slot, (source_minion, source_moves) in enumerate(re.findall(r"AddMinion\(MinionDexID\.DEX_ID_(\w+),\[([^\]]+)\]\)", method)):
        source_dex_match = re.search(rf"DEX_ID_{re.escape(source_minion)}:int\s*=\s*(\d+)", dex_enum)
        if source_dex_match is None:
            raise ValueError(f"unresolved gym minion {source_minion}")
        dex_value = int(source_dex_match.group(1))
        if dex_value not in minion_definitions:
            raise ValueError(f"missing imported minion {source_minion} (dex {dex_value})")
        numeric_moves = [int(value.strip()) for value in source_moves.split(",") if value.strip()]
        missing = [value for value in numeric_moves if value not in move_definitions]
        if missing:
            raise ValueError(f"missing imported gym move IDs {missing}")
        entries.append({"definition_id": minion_definitions[dex_value], "level": base_level, "source_level_offset": 0, "slot_index": slot, "move_ids": [move_definitions[value] for value in numeric_moves]})
    start_line = re.search(r'm_whatTrainerSaysAtStart_notBeaten\s*=\s*"((?:\\.|[^"\\])*)"', method)
    lose_line = re.search(r'm_whatTrainerSaysAtLose\s*=\s*"((?:\\.|[^"\\])*)"', method)
    move_timer_match = re.search(r"AddMod_MoveTimer\(MinionMoveID\.(\w+),(\d+),(\d+),MinionMoveID\.(\w+)\)", method)
    move_enum = (SOURCE / "States/MinionMoveID.as").read_text(encoding="utf-8")
    timer_data = None
    if move_timer_match:
        move_name, interval, source_power, buff_name = move_timer_match.groups()
        move_numeric = re.search(rf"public static const {re.escape(move_name)}:int\s*=\s*(\d+)", move_enum)
        buff_numeric = re.search(rf"public static const {re.escape(buff_name)}:int\s*=\s*(\d+)", move_enum)
        if move_numeric is None or buff_numeric is None:
            raise ValueError("gym move timer references an unmapped source move")
        timer_data = {"interval": int(interval), "source_power": int(source_power), "move_id": move_definitions[int(move_numeric.group(1))], "buff_move_id": move_definitions[int(buff_numeric.group(1))]}
    record = {
        "id": "base:encounter/floor10_fire_sage",
        "room": int(room_raw),
        "type": f"TrainerType.{trainer_type}",
        "start_text": start_line.group(1).replace("\\'", "'").replace("\\n", "\n") if start_line else "",
        "lose_text": lose_line.group(1).replace("\\'", "'").replace("\\n", "\n") if lose_line else "",
        "entries": entries,
        "ai": "boss",
        "level_offset": 0,
        "source_floor_index": 9,
        "source_trainer_floor": int(source_floor),
        "source_method": method_name,
        "source_location": f"development/extracted/full-20260908/script/scripts/TopDown/Trainers/TrainerSystem.as:{text[:start].count(chr(10)) + 1}",
        "reward": {"sage_seals": 1},
        "move_timer": timer_data,
        "sage_boss": True,
        "suffix": "_sage",
    }
    write_encounter(record, base_level)
    return record


def build_gym_graph(trainer: dict) -> dict:
    return {
        "floor_index": 9,
        "source_floor_index": 9,
        "source_room_order": ["base:room/level_2_gym"],
        "entry_room_id": "base:room/level_2_gym",
        "external_transitions": [{"room_id": "base:room/level_2_gym", "transition_id": 101, "source_sprite": "roomTransitionObject_startingRoomToLobby", "target_route": "lobby"}],
        "rooms": [{
            "id": "base:room/level_2_gym",
            "display_name": "Floor 10 — Fire Sage gym",
            "legacy_class_name": "LevelContainer_Level_2_gym",
            "source_symbol": "Utilities.LevelContainer_Level_2_gym",
            "source_location": "development/extracted/full-20260908/script/scripts/Utilities/LevelContainer_Level_2_gym.as",
            "source_payload": "res://content/base/room_payloads/source/level_2_gym.json",
            "room_index": 0,
            "encounter_ids": [trainer["id"]],
            "trainer_binding": {"trainer_room_id": 0, "trainer_type": trainer["type"], "source_location": trainer["source_location"], "source_method": trainer["source_method"], "source_floor_argument": trainer["source_trainer_floor"]},
            "interactions": [{"id": "floor-10-fire-sage", "kind": "trainer", "source_zone_id": 0, "trainer_room_id": 0, "trainer_type": trainer["type"], "source_trigger": "buttonZoneObject", "encounter_id": trainer["id"], "first_visit_text": trainer["start_text"], "lose_text": trainer["lose_text"]}],
        }],
        "eggery_source": {
            "source_location": "development/extracted/full-20260908/script/scripts/PresistentData/StaticData.as",
            "source_method": "SetupTheEggeryInfo",
            "source_floor_index": 9,
            "room_order_note": "Level_2_gym has no Eggery room. Pool index 9 is conditional BMod 1 only and is not available in the base catalog.",
            "source_candidates": [{"source_minion": "BMod 1", "weight": 60, "conditional_mod_only": True, "available_in_base_catalog": False}],
        },
    }


def main() -> None:
    dex_enum = SOURCE / "States/MinionDexID.as"
    dex_lookup = {int(value): symbol for symbol, value in re.findall(r"DEX_ID_([A-Za-z0-9_]+):int\s*=\s*(\d+)", dex_enum.read_text(encoding="utf-8"))}
    minion_definitions = imported_ids(ROOT / "content/imported/recovered-20260911/minions")
    move_definitions = imported_ids(ROOT / "content/imported/recovered-20260911/moves")
    dex_symbol_ids = {symbol: value for value, symbol in dex_lookup.items()}
    candidates = {
        6: [("base:minion/fire_frog_2", 50), ("base:minion/demonic_cat_2", 30), ("base:minion/chameleon_1", 20)],
        7: [("base:minion/worm_1", 55), ("base:minion/fire_bear_2", 40), ("base:minion/tortoise_1", 5)],
        8: [("base:minion/holyfox_1", 50), ("base:minion/raptor_2", 30), ("base:minion/robobull_1", 20)],
    }
    floor7_trainers = trainers_for_floor(7, 21, dex_lookup, {}, minion_definitions, move_definitions, source_method="CreateFloor6")
    floor7_expert = next(record["id"] for record in floor7_trainers if record["room"] == 5)
    floor7_graph = build_graph(6, "level_2_2", "fire", floor7_expert, floor7_trainers, candidates[6], 21, eggery_owner="Utilities.LevelContainer_Level_2_2_Eggery", expert_room_id="base:room/floor_2_expert_room_electric", expert_room_payload="expert_room_floor7_fire.json")
    (GRAPHS / "floor_7_room_graph.json").write_text(json.dumps(floor7_graph, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    floor8_trainers = trainers_for_floor(8, 24, dex_lookup, {}, minion_definitions, move_definitions, source_method="CreateFloor7")
    floor8_expert = next(record["id"] for record in floor8_trainers if record["room"] == 5)
    floor8_graph = build_graph(7, "level_2_3", "fire", floor8_expert, floor8_trainers, candidates[7], 24, eggery_owner="Utilities.LevelContainer_Level_2_3_Eggery", expert_room_id="base:room/floor_2_expert_room_undead", expert_room_payload="expert_room_floor8_fire.json")
    (GRAPHS / "floor_8_room_graph.json").write_text(json.dumps(floor8_graph, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    # Source room index 8 (visible floor 9): Level_2_4 is backed by
    # CreateFloor8, whose AddTrainerToFloor argument is the matching index 8.
    floor9_trainers = trainers_for_floor(9, 33, dex_lookup, {}, minion_definitions, move_definitions, source_method="CreateFloor8")
    if len(floor9_trainers) != 6:
        raise ValueError(f"expected six source trainers for Level_2_4, parsed {len(floor9_trainers)}")
    floor9_expert = next(record["id"] for record in floor9_trainers if record["room"] == 5)
    floor9_graph = build_graph(8, "level_2_4", "fire", floor9_expert, floor9_trainers, candidates[8], 33, eggery_source_binary="1543.bin", eggery_owner="Utilities.LevelContainer_Level_2_4_Eggery", expert_room_id="base:room/floor_2_4_expert_room_fire", expert_room_payload="expert_room_floor9_fire.json")
    (GRAPHS / "floor_9_room_graph.json").write_text(json.dumps(floor9_graph, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    dex_enum_text = dex_enum.read_text(encoding="utf-8")
    gym_trainer = trainer_for_gym(26, dex_enum_text, minion_definitions, move_definitions)
    gym_graph = build_gym_graph(gym_trainer)
    (GRAPHS / "floor_10_room_graph.json").write_text(json.dumps(gym_graph, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Floor 7: {len(floor7_graph['rooms'])} rooms, {len(floor7_trainers)} encounters (CreateFloor6/index 6); Floor 8: {len(floor8_graph['rooms'])} rooms, {len(floor8_trainers)} encounters (CreateFloor7/index 7); Floor 9: {len(floor9_graph['rooms'])} rooms, {len(floor9_trainers)} encounters (CreateFloor8/index 8); Floor 10: 1 gym room/encounter")


if __name__ == "__main__":
    main()
