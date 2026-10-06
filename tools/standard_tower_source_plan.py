"""Read the original tables to describe the floor-1–30 conversion scope.

No content or save files are written. Room order and trainer method selection
come from source floor indices, never inferred from a floor's visual theme.
"""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "development/extracted/full-20260908/script/scripts"
NORMALIZED = ROOT / "development/normalized/rooms-20260908"


def source_floors(floor_count=30):
    static = (SOURCE / "PresistentData/StaticData.as").read_text(encoding="utf-8")
    trainers = (SOURCE / "TopDown/Trainers/TrainerSystem.as").read_text(encoding="utf-8")
    methods = {}
    for match in re.finditer(r"private function (CreateFloor\w+)\(\).*?(?=\n      (?:private|public) function|\Z)", trainers, re.S):
        name, body = match.group(1), match.group(0)
        if "hardMode" in name:
            continue
        bindings = re.findall(r"AddTrainerToFloor\(TrainerType\.(\w+),(\d+),(\d+)\)", body)
        indices = {int(floor) for _, floor, _ in bindings}
        if len(indices) != 1:
            raise ValueError(f"ambiguous source floor for {name}: {indices}")
        index = indices.pop()
        if index in methods:
            raise ValueError(f"duplicate standard trainer table {index}")
        methods[index] = (name, body, bindings)
    blocks = re.findall(r"_loc2_ = (\d+);(.*?)(?=\s*_loc2_ = \d+;|\Z)", static, re.S)
    floors = {}
    for index_raw, body in blocks:
        room_tokens = re.findall(r"m_normalRooms\[_loc2_\]\.push\(new (?:BaseTopDownLevel\(LevelContainer\.(\w+)\)|BaseEggery\(LevelContainer\.(\w+)\)|(ExpertRoom_\w+)\(\))\);", body)
        if not room_tokens:
            continue
        index = int(index_raw)
        if index >= floor_count:
            continue
        order = [next(token for token in group if token) for group in room_tokens]
        method, trainer_body, bindings = methods[index]
        level = re.search(rf"m_minionLevelsForFloors\[{index}\] = (\d+);", static)
        rooms = []
        for room_index, token in enumerate(order):
            expert = token.startswith("ExpertRoom_")
            payload = NORMALIZED / (token.lower() + ".json")
            rooms.append({"room_index": room_index, "source_class": token, "payload_exists": payload.exists() if not expert else (ROOT / "content/base/room_payloads/source" / ("expert_room_" + token.removeprefix("ExpertRoom_") + ".json")).exists(), "script_exists": (SOURCE / ("TopDown/Levels/MainTower" if expert else "Utilities") / (token + ".as" if expert else "LevelContainer_" + token + ".as")).exists()})
        floors[index] = {"floor": index + 1, "source_floor_index": index, "base_level": int(level.group(1)), "trainer_method": method, "rooms": rooms, "trainers": [{"room_index": int(room), "type": kind} for kind, _, room in bindings], "modifier_calls": re.findall(r"AddMod_\w+\([^;]+\)", trainer_body)}
    if set(floors) != set(range(floor_count)):
        raise ValueError(f"missing source floors: {sorted(set(range(floor_count)) - set(floors))}")
    for index, floor in floors.items():
        for trainer in floor["trainers"]:
            if not 0 <= trainer["room_index"] < len(floor["rooms"]):
                raise ValueError(f"floor {index + 1}: trainer outside source room order")
    return [floors[index] for index in range(floor_count)]


if __name__ == "__main__":
    print(json.dumps(source_floors(), ensure_ascii=False, indent=2))
