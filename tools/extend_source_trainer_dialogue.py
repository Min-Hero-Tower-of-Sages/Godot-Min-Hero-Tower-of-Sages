"""Emit later-floor dialogue without replacing already-correct early entries."""
import difflib
import json
import re

from standard_tower_source_plan import ROOT, SOURCE, source_floors


def quoted(body, field, fallback=""):
    match = re.search(rf'{field}\s*=\s*"((?:\\.|[^"\\])*)"', body)
    return match[1].replace("\\'", "'").replace("\\n", "\n") if match else fallback


def main():
    path = ROOT / "content/base/campaigns/source_trainer_dialogue.json"
    current = path.read_text(encoding="utf-8")
    entries = json.loads(current)
    source = (SOURCE / "TopDown/Trainers/TrainerSystem.as").read_text(encoding="utf-8")
    names = {"NORMAL_TRAINER": "Student", "HARD_TRAINER": "Hard Sage", "EXPERT_TRAINER": "Expert Sage", "BOSS_TRAINER": "Minor Sage", "TRAINER_GYM_3": "Electric Sage", "TRAINER_GYM_4": "Undead Sage", "TRAINER_GYM_5": "Talo Sage", "TRAINER_GYM_6": "Daco Sage"}
    names["TRAINER_GRAND_SAGE"] = "Grand Sage"
    for floor in source_floors(31)[10:]:
        method = re.search(rf"private function {floor['trainer_method']}\(\).*?(?=\n      (?:private|public) function|\Z)", source, re.S).group(0)
        for kind, index, room, body in re.findall(r"AddTrainerToFloor\(TrainerType\.(\w+),(\d+),(\d+)\);(.*?)(?=_loc2_ = this\.AddTrainerToFloor|\Z)", method, re.S):
            entries[f"base:trainer/standard/{index}/{room}"] = {"first_visit_text": quoted(body, "m_whatTrainerSaysAtStart_notBeaten"), "repeat_text": quoted(body, "m_whatTrainerSaysAtStart_alreadyBeaten", "You already beat me!   Retry for three stars?"), "after_win_text": quoted(body, "m_whatTrainerSaysAtLose"), "trainer_name": quoted(body, "m_trainerName", names[kind])}
    updated = json.dumps(entries, ensure_ascii=False, indent=2) + "\n"
    print("*** Begin Patch")
    if current != updated:
        print(f"*** Update File: {path.as_posix()}")
        for line in list(difflib.unified_diff(current.splitlines(), updated.splitlines(), n=2, lineterm=""))[2:]:
            print("@@" if line.startswith("@@") else line)
    print("*** End Patch")


if __name__ == "__main__":
    main()
