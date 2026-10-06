"""Emit hard tower rosters/dialogue as apply_patch; never write saves/content."""
import argparse
import difflib
import json
import re
from pathlib import Path
from unittest.mock import patch

import build_floor_7_8_source_content as importer
from extend_standard_tower import modifiers
from extend_source_trainer_dialogue import quoted
from standard_tower_source_plan import ROOT, SOURCE


def build():
    original = Path.read_text
    source = importer.TRAINER_SOURCE.read_text(encoding="utf-8")
    methods = list(re.finditer(r"private function (CreateFloor\w+_hardMode)\(\).*?(?=\n      (?:private|public) function|\Z)", source, re.S))
    normalized = source
    floors = {}
    bodies = {}
    for method in methods:
        offset = re.search(r"_loc1_(?::int)?\s*=\s*(\d+)\s*\+ this\.m_extraHardModeModifier", method[0])
        if offset is None:
            raise ValueError(f"missing hard floor index: {method[1]}")
        index = int(offset[1]) + 31
        if index in floors:
            raise ValueError(f"duplicate hard floor: {index}")
        floors[index] = method[1]
        body = re.sub(r"(AddTrainerToFloor\(TrainerType\.\w+,)_loc1_,", rf"\g<1>{index},", method[0])
        normalized = normalized.replace(method[0], body)
        bodies[index] = {int(room): block for _, room, block in re.findall(r"AddTrainerToFloor\(TrainerType\.(\w+),\d+,(\d+)\);(.*?)(?=_loc2_ = this\.AddTrainerToFloor|\Z)", body, re.S)}
    if set(floors) != set(range(31, 62)):
        raise ValueError("incomplete hard-mode source table")
    minions = importer.imported_ids(ROOT / "content/imported/recovered-20260911/minions")
    moves = importer.imported_ids(ROOT / "content/imported/recovered-20260911/moves")
    dex = {name: int(value) for name, value in re.findall(r"DEX_ID_(\w+):int\s*=\s*(\d+)", (SOURCE / "States/MinionDexID.as").read_text(encoding="utf-8"))}
    updates = {}
    paths = []
    dialogue_path = ROOT / "content/base/campaigns/source_trainer_dialogue.json"
    dialogue = json.loads(dialogue_path.read_text(encoding="utf-8"))
    captured = {}
    names = {"NORMAL_TRAINER": "Student", "HARD_TRAINER": "Hard Sage", "EXPERT_TRAINER": "Expert Sage", "BOSS_TRAINER": "Minor Sage", "TRAINER_GYM_1": "Grass Sage", "TRAINER_GYM_2": "Fire Sage", "TRAINER_GYM_3": "Electric Sage", "TRAINER_GYM_4": "Undead Sage", "TRAINER_GYM_5": "Talo Sage", "TRAINER_GYM_6": "Daco Sage", "TRAINER_GRAND_SAGE": "Grand Sage"}
    def read(path, *args, **kwargs):
        return normalized if path == importer.TRAINER_SOURCE else original(path, *args, **kwargs)
    with patch.object(Path, "read_text", read), patch.object(Path, "write_text", lambda path, text, **kwargs: captured.__setitem__(path, text)):
        for index, method in sorted(floors.items()):
            base = 58 if index == 31 else 59 if index == 32 else 60
            records = importer.trainers_for_floor(index + 1, base, {}, {}, minions, moves, source_method=method)
            for record in records:
                captured.clear()
                record["ai"] = "boss" if "TRAINER_GYM_" in record["type"] or "GRAND_SAGE" in record["type"] else record["ai"]
                if "TRAINER_GYM_" in record["type"] or "GRAND_SAGE" in record["type"]:
                    record["reward"] = {}
                elif "random_gems" in record["reward"]:
                    record["reward"]["random_gems"]["tier"] = 6
                importer.write_encounter(record, base)
                _, text = next(iter(captured.items()))
                trainer_id = f"base:trainer/hard/{index - 30}/room/{record['room']}"
                text = re.sub(r'^source_trainer_id = .*$', f'source_trainer_id = &"{trainer_id}"', text, flags=re.M)
                text = re.sub(r"^battle_modifier_configuration = .*\n", "", text, flags=re.M)
                body = bodies[index][record["room"]]
                # TrainerDataObject setters overwrite earlier values. Keep the
                # last call for each modifier, e.g. Hard Floor 3's 3/3 -> 1/1.
                calls = list(re.finditer(r"_loc2_\.AddMod_(\w+)\([^;]*\);", body))
                last = {call[1]: call.start() for call in calls}
                effective_body = re.sub(r"_loc2_\.AddMod_(\w+)\([^;]*\);", lambda match: match[0] if last[match[1]] == match.start() else "", body)
                config = modifiers(record, effective_body, dex, minions, moves, base)
                if config:
                    text += "battle_modifier_configuration = " + json.dumps(config) + "\n"
                path = ROOT / f"content/base/encounters/hard_floor_{index - 30}_trainer_{record['room']}.tres"
                updates[path] = text
                paths.append(path)
                body = bodies[index][record["room"]]
                kind = record["type"].removeprefix("TrainerType.")
                dialogue[trainer_id] = {"trainer_name": quoted(body, "m_trainerName", names[kind]), "first_visit_text": record["start_text"], "after_win_text": record["lose_text"], "repeat_text": quoted(body, "m_whatTrainerSaysAtStart_alreadyBeaten", "You already beat me!   Retry for three stars?")}
    prefix = '[gd_resource type="Resource" script_class="ContentPackDefinition" format=3]\n\n[ext_resource type="Script" path="res://src/content/content_pack_definition.gd" id="1_pack"]\n[ext_resource type="Script" path="res://src/content/content_definition.gd" id="2_definition"]\n'
    prefix += "".join(f'[ext_resource type="Resource" path="res://{path.relative_to(ROOT).as_posix()}" id="{index + 3}_encounter"]\n' for index, path in enumerate(paths))
    refs = ", ".join(f'ExtResource("{index + 3}_encounter")' for index in range(len(paths)))
    updates[ROOT / "content/base/packs/hard_tower_trainers.tres"] = prefix + f'\n[resource]\nscript = ExtResource("1_pack")\ndependencies = Array[StringName]([&"base:pack/recovered"])\ndefinitions = Array[ExtResource("2_definition")]([{refs}])\nid = &"base:pack/hard_tower_trainers"\ndisplay_name = "Source hard tower — 31 floors"\n'
    updates[dialogue_path] = json.dumps(dialogue, ensure_ascii=False, indent=2) + "\n"
    return updates, len(paths)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--summary", action="store_true")
    parser.add_argument("--part", type=int, default=0)
    args = parser.parse_args()
    updates, count = build()
    groups = [[]]
    size = 0
    for path, text in updates.items():
        if size and size + len(text) > 100000:
            groups.append([])
            size = 0
        groups[-1].append((path, text))
        size += len(text)
    if args.summary:
        print(json.dumps({"floors": 31, "encounters": count, "parts": len(groups)}))
        return
    print("*** Begin Patch")
    for path, text in groups[args.part]:
        current = path.read_text(encoding="utf-8") if path.exists() else None
        if current == text: continue
        print(f"*** {'Update' if current is not None else 'Add'} File: {path.as_posix()}")
        if current is None:
            print("\n".join("+" + line for line in text.splitlines()))
        else:
            for line in list(difflib.unified_diff(current.splitlines(), text.splitlines(), n=2, lineterm=""))[2:]:
                print("@@" if line.startswith("@@") else line)
    print("*** End Patch")


if __name__ == "__main__":
    main()
