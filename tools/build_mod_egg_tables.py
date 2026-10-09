"""Emit source-authored egg-table variants as an apply_patch document.

No runtime ActionScript interpretation and no writes to reference sources.
Only the four acquisition flags and literal AddMinionToEggery calls are read.
"""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "development/extracted/full-20260908/script/scripts"
ALIASES = {"holyBirb1": "holyBird1", "HolyBirb1": "holyBird1", "holyBirb2": "holyBird2"}
FLAGS = ["dirtFish", "waterRay1", "holyBird1", "HolyEye1"]


def block(text, opening):
    depth = 1
    end = opening + 1
    while depth:
        depth += (text[end] == "{") - (text[end] == "}")
        end += 1
    return text[opening + 1:end - 1], end


def select(text, enabled):
    output, position = "", 0
    pattern = r'\bif\s*\(([^\n]+)\)\s*\{'
    while match := re.search(pattern, text[position:]):
        start = position + match.start()
        output += text[position:start]
        condition = match.group(1)
        branches = []
        body, cursor = block(text, position + match.end() - 1)
        branches.append((condition, body))
        while alt := re.match(r'\s*else\s+if\s*\(([^\n]+)\)\s*\{', text[cursor:]):
            condition = alt.group(1)
            body, cursor = block(text, cursor + alt.end() - 1)
            branches.append((condition, body))
        if alt := re.match(r'\s*else\s*\{', text[cursor:]):
            body, cursor = block(text, cursor + alt.end() - 1)
            branches.append((None, body))
        for condition, body in branches:
            keys = re.findall(r'm_isMod\["([^"]+)"\]', condition or "")
            if condition is not None and not keys:
                raise ValueError(f"Unsupported source condition: {condition}")
            if condition is None or all(ALIASES.get(k, k) in enabled for k in keys):
                output += select(body, enabled)
                break
        position = cursor
    return output + text[position:]


def main():
    dex = dict((name, int(value)) for name, value in re.findall(
        r'DEX_ID_(\w+):int\s*=\s*(\d+)', (SOURCE / "States/MinionDexID.as").read_text()))
    minions = {}
    for path in (ROOT / "content/imported/recovered-20260911/minions").glob("base*.tres"):
        text = path.read_text()
        if numeric := re.search(r'^legacy_numeric_id = (\d+)', text, re.M):
            minions[int(numeric.group(1))] = re.search(r'^id = &"([^"]+)"', text, re.M).group(1)
    custom = {"dirtFish": "zanyu:minion/dirtfish", "waterRay1": "stingaray:minion/waterray1", "waterRay2": "stingaray:minion/waterray2", "holyBird1": "arkvian:minion/holybird1", "holyBird2": "arkvian:minion/holybird2", "HolyEye1": "ophan:minion/holyeye1", "HolyEye2": "ophan:minion/holyeye2", "HolyEye3": "ophan:minion/holyeye3"}
    text = (SOURCE / "PresistentData/StaticData.as").read_text()
    start = text.index("private function SetupTheEggeryInfo()")
    body = text[start:text.index("private function AddMinionToEggery", start)]
    output = {}
    for mask in range(1, 16):
        enabled = {flag for i, flag in enumerate(FLAGS) if mask & (1 << i)}
        selected = select(body, enabled)
        floors = {}
        for match in re.finditer(r'_loc2_ = (\d+);(.*?)(?=\s*_loc2_ = \d+;|\Z)', selected, re.S):
            floor, section = match.groups()
            if not any(f'ModToDexID["{flag}"]' in section for flag in list(custom) + list(ALIASES)):
                continue
            candidates, weights = [], []
            for entry in re.finditer(r'AddMinionToEggery\((MinionDexID\.DEX_ID_(\w+)|this\.ModToDexID\["([^"]+)"\]),([\d.]+),_loc2_\)', section):
                _, base, mod, weight = entry.groups()
                if mod and mod.startswith("BMod"):
                    continue
                if base:
                    # Reference typo: its Ophan branch names a missing base Dex
                    # constant instead of ModToDexID. Resolve its stated minion.
                    identity = custom["HolyEye1"] if base == "holy_eye_1" else minions[dex[base]]
                else:
                    identity = custom[ALIASES.get(mod, mod)]
                candidates.append(identity)
                weights.append(int(float(weight)))
            if candidates:
                floors[floor] = {"candidates": candidates, "weights": weights}
        output[str(mask)] = floors
    payload = json.dumps(output, indent=2)
    print("*** Begin Patch\n*** Add File: C:/Dev/Godot/min-hero-port/content/mods/source_egg_tables.json")
    print("\n".join("+" + line for line in payload.splitlines()))
    print("*** End Patch")


if __name__ == "__main__":
    main()
