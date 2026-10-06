"""Emit an apply_patch patch for live standard-tower first-clear rewards.

Reward keys follow BattleScreen.OpenVictoryMenus; money follows StaticData's
1.25 growth with Math.round at retrieval (not the unrounded internal table).
Only encounters referenced by current floor 1–10 room graphs are affected.
"""
import difflib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def main():
    active_ids = set()
    for floor in range(1, 11):
        graph = json.loads((ROOT / f"content/base/campaigns/floor_{floor}_room_graph.json").read_text(encoding="utf-8"))
        for room in graph["rooms"]:
            active_ids.update(room.get("encounter_ids", []))
            active_ids.update(item["encounter_id"] for item in room.get("interactions", []) if "encounter_id" in item)
    output = ["*** Begin Patch"]
    for path in (ROOT / "content/base/encounters").glob("*.tres"):
        current = path.read_text(encoding="utf-8")
        identity = re.search(r'^id = &"([^"]+)"', current, re.MULTILINE)
        if identity is None or identity.group(1) not in active_ids:
            continue
        floor = int(re.search(r'^source_floor_index = (\d+)', current, re.MULTILINE).group(1))
        kind = re.search(r'^source_trainer_type = &"([^"]+)"', current, re.MULTILINE).group(1)
        reward_match = re.search(r'^rewards = (\{.*?\})(?=\s*\n\w+ =)', current, re.MULTILINE | re.DOTALL)
        assert reward_match is not None, path
        rewards = json.loads(reward_match.group(1))
        first = rewards.setdefault("first_clear", {})
        first["floor_money_basis"] = int(min(7.0 * 1.25 ** floor, 2000.0) + 0.5)
        for field in ["money", "floor_keys", "eggery_keys", "random_gems"]:
            first.pop(field, None)
        if kind == "TrainerType.NORMAL_TRAINER":
            first["floor_keys"] = 1
        elif kind in ["TrainerType.HARD_TRAINER", "TrainerType.EXPERT_TRAINER", "TrainerType.BOSS_TRAINER"]:
            first["eggery_keys"] = 1
        if kind in ["TrainerType.HARD_TRAINER", "TrainerType.EXPERT_TRAINER"]:
            first["random_gems"] = {"count": 1, "tier": 1 if floor < 5 else 2}
        updated = current[:reward_match.start(1)] + json.dumps(rewards, ensure_ascii=False) + current[reward_match.end(1):]
        if updated == current:
            continue
        output.append(f"*** Update File: {path.as_posix()}")
        for line in list(difflib.unified_diff(current.splitlines(), updated.splitlines(), n=2, lineterm=""))[2:]:
            output.append("@@" if line.startswith("@@") else line)
    output.append("*** End Patch")
    print("\n".join(output))


if __name__ == "__main__":
    main()
