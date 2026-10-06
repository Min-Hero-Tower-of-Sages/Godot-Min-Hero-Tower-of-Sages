"""Strictly normalize type and minion definitions from edited ActionScript.

This is intentionally a small recognized grammar, not an ActionScript runtime.
Every definition includes source locations and unsupported expressions are errors.
"""

from __future__ import annotations

import argparse
import json
import re
from dataclasses import dataclass
from pathlib import Path

CONST_RE = re.compile(r"public\s+static\s+const\s+(\w+)\s*:\s*\w+\s*=\s*(-?\d+)\s*;")
FUNCTION_RE = re.compile(r"private\s+function\s+(\w+)\s*\(\s*\)\s*:\s*void\s*\{")
TALENT_FUNCTION_RE = re.compile(r"public\s+function\s+(\w+)\s*\(\s*\)\s*:\s*MinionTalentTree\s*\{")
CM_RE = re.compile(r"(?:var\s+_loc1_\s*:\s*BaseMinion\s*=\s*)?this\.CM\s*\((.*?)\)\s*;", re.DOTALL)
ASSIGN_RE = re.compile(r"_loc1_\.(m_\w+)\s*=\s*([^;\r\n]+?)\s*;?(?:\r?\n|$)")
START_MOVE_RE = re.compile(r"_loc1_\.AddStartingMove\s*\((.*?)\)\s*;")
SPEC_RE = re.compile(r"_loc1_\.SetSpeacilizaionMoves\s*\((.*?)\)\s*;")
TREE_LOAD_RE = re.compile(r"_loc2_\s*=\s*Singleton\.staticData\.m_baseTalentTreesList\.(\w+)\(\)\s*;")
TREE_SET_RE = re.compile(r"_loc1_\.SetTalentTree\s*\(\s*(\d+)\s*,\s*_loc2_\s*\)\s*;")
TREE_CONSTRUCTOR_RE = re.compile(r'_loc1_\s*:\s*MinionTalentTree\s*=\s*new\s+MinionTalentTree\s*\(\s*"([^"]+)"\s*\)\s*;')
DIRECT_TREE_CONSTRUCTOR_RE = re.compile(r'return\s+new\s+MinionTalentTree\s*\(\s*"([^"]+)"\s*\)\s*;')
TREE_MOVE_RE = re.compile(r"_loc1_\.AddMoveToTree\s*\((.*?)\)\s*;")
MOD_LOOKUP_RE = re.compile(r'Singleton\.staticData\.(ModToDexID|ModToTypeID|ModToMoveID)\[\s*"([^"]+)"\s*\]$')
REFERENCE_RE = re.compile(r"(MinionDexID|MinionType|MinionMoveID|ExpGainRates)\.(\w+)$")
TYPE_CHART_ASSIGN_RE = re.compile(
    r"this\.m_typeEffectivenessArray\[MinionType\.(TYPE_[A-Z]+)\]"
    r"\[MinionType\.(TYPE_[A-Z]+)\]\s*=\s*this\."
    r"(NOT_EFFECTIVE_MODIFIER|SUPER_EFFECTIVE_MODIFIER)\s*;"
)
THAW_CHART_ASSIGN_RE = re.compile(
    r"this\.m_typeEffectivenessArray\[MinionType\.(TYPE_[A-Z]+)\]"
    r"\[tempModType\]\s*=\s*this\."
    r"(NOT_EFFECTIVE_MODIFIER|SUPER_EFFECTIVE_MODIFIER)\s*;"
)

TYPE_NAMES = {
    "TYPE_NONE": "none", "TYPE_ENERGY": "energy", "TYPE_UNDEAD": "undead",
    "TYPE_ROBOT": "robot", "TYPE_FIRE": "fire", "TYPE_WATER": "water",
    "TYPE_ICE": "ice", "TYPE_DEMONIC": "demonic", "TYPE_HOLY": "holy",
    "TYPE_EARTH": "earth", "TYPE_PLANT": "plant", "TYPE_FLYING": "flying",
    "TYPE_TITAN": "titan", "TYPE_NORMAL": "normal", "TYPE_DINO": "dino",
}
MOD_NAMESPACE = {
    "dirtFish": "zanyu", "waterRay1": "stingaray", "waterRay2": "stingaray",
    "holyBirb1": "arkvian", "holyBirb2": "arkvian",
    "HolyEye1": "ophan", "HolyEye2": "ophan", "HolyEye3": "ophan",
    "BMod 1": "internal", "BMod 2": "internal", "BMod 3": "internal",
}

# Port-facing stable IDs correct the exact Arkvian source spellings while the
# imported records retain their unmodified source class/sprite names.
PORT_IDENTIFIER_ALIASES = {
    "holyBirb1": "holyBird1",
    "HolyBirb1": "holyBird1",
    "holyBirb2": "holyBird2",
    "holyBirb_Flying": "holyBird_Flying",
}

# Deliberately narrow source corrections approved for the maintained port.  These
# are exact-expression rewrites, not aliases or fuzzy lookup rules.  Every use is
# emitted to import_corrections.json with its original source location.
MOVE_REFERENCE_CORRECTIONS = {
    "MinionMoveID.holyLight_t1": {
        "id": "base:move/holy_light/tier1",
        "reason": "Correct the two Arkvian-family references to the declared holy_light_t1 constant.",
    },
    'Singleton.staticData.ModToMoveID["mud_blast_t3"]': {
        "id": "base:move/mud_blast/tier3",
        "reason": "Mud Blast is a base move family; Ice Floor never registers this dynamic dictionary key.",
    },
    'Singleton.staticData.ModToMoveID["mud_blast_t4"]': {
        "id": "base:move/mud_blast/tier4",
        "reason": "Mud Blast is a base move family; Ice Floor never registers this dynamic dictionary key.",
    },
    'Singleton.staticData.ModToMoveID["mud_blast_t5"]': {
        "id": "base:move/mud_blast/tier5",
        "reason": "Mud Blast is a base move family; Ice Floor never registers this dynamic dictionary key.",
    },
}
MINION_PROPERTIES = {
    "m_minionIconPositioningX": "icon_offset_x",
    "m_minionIconPositioningY": "icon_offset_y",
    "m_expGainRate": "experience_gain_rate",
    "m_numberOfGems": "gem_slots",
    "m_numberOfLockedGems": "locked_gem_slots",
    "m_evolutionLevel": "evolution_level",
}


@dataclass
class ImportProblem(Exception):
    path: Path
    line: int
    expression: str
    message: str

    def as_dict(self) -> dict:
        return {"source": str(self.path), "line": self.line, "expression": self.expression, "message": self.message}


def line_at(text: str, offset: int) -> int:
    return text.count("\n", 0, offset) + 1


def strip_comments(text: str) -> str:
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.DOTALL)
    return re.sub(r"//[^\n]*", "", text)


def split_arguments(text: str) -> list[str]:
    result, current = [], []
    quote = None
    bracket_depth = 0
    escaped = False
    for character in text:
        if quote:
            current.append(character)
            if escaped:
                escaped = False
            elif character == "\\":
                escaped = True
            elif character == quote:
                quote = None
        elif character in "\"'":
            quote = character
            current.append(character)
        elif character in "[(":
            bracket_depth += 1
            current.append(character)
        elif character in "])":
            bracket_depth -= 1
            current.append(character)
        elif character == "," and bracket_depth == 0:
            result.append("".join(current).strip())
            current = []
        else:
            current.append(character)
    if quote or bracket_depth != 0:
        raise ValueError(f"unbalanced argument list: {text}")
    if current or text.strip():
        result.append("".join(current).strip())
    return result


def extract_functions(text: str, path: Path, pattern: re.Pattern = FUNCTION_RE) -> list[tuple[str, str, int]]:
    functions = []
    for match in pattern.finditer(text):
        depth = 1
        cursor = match.end()
        quote = None
        while cursor < len(text) and depth:
            character = text[cursor]
            if quote:
                if character == quote and text[cursor - 1] != "\\": quote = None
            elif character in "\"'": quote = character
            elif character == "{": depth += 1
            elif character == "}": depth -= 1
            cursor += 1
        if depth:
            raise ImportProblem(path, line_at(text, match.start()), match.group(1), "unterminated function body")
        functions.append((match.group(1), text[match.end():cursor - 1], line_at(text, match.start())))
    return functions


def constants(path: Path) -> dict[str, int]:
    text = path.read_text(encoding="utf-8-sig")
    found = {name: int(value) for name, value in CONST_RE.findall(text)}
    if not found:
        raise ImportProblem(path, 1, "", "no supported constants found")
    return found


def slug(value: str) -> str:
    value = PORT_IDENTIFIER_ALIASES.get(value, value)
    value = re.sub(r"[^A-Za-z0-9]+", "_", value).strip("_").lower()
    return value


def move_id(expression: str, path: Path, line: int, corrections: list[dict] | None = None) -> str:
    expression = expression.strip()
    correction = MOVE_REFERENCE_CORRECTIONS.get(expression)
    if correction:
        if corrections is not None:
            corrections.append({
                "source": str(path),
                "line": line,
                "expression": expression,
                "corrected_id": correction["id"],
                "reason": correction["reason"],
            })
        return correction["id"]
    reference = REFERENCE_RE.fullmatch(expression)
    if reference and reference.group(1) == "MinionMoveID":
        name = reference.group(2)
        match = re.fullmatch(r"(.+)_t(\d+)", name)
        if not match: raise ImportProblem(path, line, expression, "move ID has no explicit tier suffix")
        return f"base:move/{slug(match.group(1))}/tier{match.group(2)}"
    dynamic = MOD_LOOKUP_RE.fullmatch(expression)
    if dynamic and dynamic.group(1) == "ModToMoveID":
        name = dynamic.group(2)
        match = re.fullmatch(r"(.+)_t(\d+)", name)
        if not match: raise ImportProblem(path, line, expression, "mod move ID has no explicit tier suffix")
        return f"ice_floor:move/{slug(match.group(1))}/tier{match.group(2)}"
    raise ImportProblem(path, line, expression, "unsupported move reference")


def type_id(expression: str, path: Path, line: int) -> str:
    expression = expression.strip()
    reference = REFERENCE_RE.fullmatch(expression)
    if reference and reference.group(1) == "MinionType":
        normalized = reference.group(2).upper()
        if normalized not in TYPE_NAMES: raise ImportProblem(path, line, expression, "unknown minion type")
        return f"base:type/{TYPE_NAMES[normalized]}"
    dynamic = MOD_LOOKUP_RE.fullmatch(expression)
    if dynamic and dynamic.group(1) == "ModToTypeID":
        return f"ice_floor:type/{slug(dynamic.group(2))}"
    if expression == "0": return "base:type/none"
    raise ImportProblem(path, line, expression, "unsupported type reference")


def literal(expression: str, constant_sets: dict[str, dict[str, int]], path: Path, line: int):
    expression = expression.strip()
    if re.fullmatch(r"-?\d+", expression): return int(expression)
    if re.fullmatch(r'"(?:\\.|[^"\\])*"', expression):
        return bytes(expression[1:-1], "utf-8").decode("unicode_escape")
    reference = REFERENCE_RE.fullmatch(expression)
    if reference:
        family, name = reference.groups()
        values = constant_sets.get(family, {})
        lookup = name if name in values else name.upper()
        if lookup in values: return values[lookup]
        raise ImportProblem(path, line, expression, f"unknown {family} constant")
    raise ImportProblem(path, line, expression, "unsupported expression")


def minion_identity(expression: str, dex: dict[str, int], path: Path, line: int) -> tuple[str, int | None, str, str]:
    expression = expression.strip()
    reference = REFERENCE_RE.fullmatch(expression)
    if reference and reference.group(1) == "MinionDexID":
        name = reference.group(2)
        if name not in dex: raise ImportProblem(path, line, expression, "unknown dex constant")
        local = name.removeprefix("DEX_ID_")
        return f"base:minion/{slug(local)}", dex[name], "base", name
    dynamic = MOD_LOOKUP_RE.fullmatch(expression)
    if dynamic and dynamic.group(1) == "ModToDexID":
        key = dynamic.group(2)
        namespace = "ice_floor" if key.startswith("i") else MOD_NAMESPACE.get(key)
        if not namespace: raise ImportProblem(path, line, expression, "mod key has no content-pack namespace")
        return f"{namespace}:minion/{slug(key)}", None, namespace, key
    raise ImportProblem(path, line, expression, "unsupported minion identity")


def import_types(scripts: Path) -> list[dict]:
    path = scripts / "States" / "MinionType.as"
    values = constants(path)
    definitions = []
    for constant_name, name in TYPE_NAMES.items():
        if constant_name not in values: raise ImportProblem(path, 1, constant_name, "required type constant is missing")
        definitions.append({"id": f"base:type/{name}", "display_name": name.replace("_", " ").title(), "legacy_numeric_id": values[constant_name], "legacy_constant": constant_name, "source": str(path)})
    definitions.append({"id": "ice_floor:type/thaw", "display_name": "Thaw", "legacy_numeric_id": None, "legacy_constant": 'ModToTypeID["Thaw"]', "source": str(scripts / "PresistentData" / "StaticData.as")})
    return definitions


def import_type_chart(scripts: Path, expected_raw: int = 89, expected_unique: int = 83) -> dict:
    path = scripts / "PresistentData" / "StaticData.as"
    text = path.read_text(encoding="utf-8-sig")
    values = {"NOT_EFFECTIVE_MODIFIER": 0.66666666667, "SUPER_EFFECTIVE_MODIFIER": 1.5}
    multipliers: dict[str, float] = {}
    raw_assignment_count = 0

    def register_key(key: str, modifier: str, offset: int) -> None:
        nonlocal raw_assignment_count
        raw_assignment_count += 1
        value = values[modifier]
        if key in multipliers and multipliers[key] != value:
            raise ImportProblem(path, line_at(text, offset), key, "conflicting duplicate effectiveness assignment")
        multipliers[key] = value

    def register(attacker: str, defender: str, modifier: str, offset: int) -> None:
        if attacker not in TYPE_NAMES or defender not in TYPE_NAMES:
            raise ImportProblem(path, line_at(text, offset), f"{attacker}>{defender}", "unknown type in effectiveness assignment")
        key = f"base:type/{TYPE_NAMES[attacker]}>base:type/{TYPE_NAMES[defender]}"
        register_key(key, modifier, offset)

    for match in TYPE_CHART_ASSIGN_RE.finditer(text):
        register(match.group(1), match.group(2), match.group(3), match.start())
    for match in THAW_CHART_ASSIGN_RE.finditer(text):
        thaw_key = f"base:type/{TYPE_NAMES[match.group(1)]}>ice_floor:type/thaw"
        register_key(thaw_key, match.group(2), match.start())

    if raw_assignment_count != expected_raw or len(multipliers) != expected_unique:
        raise ImportProblem(path, 825, "SetupTypeEffectivenessArray", f"expected {expected_raw} source assignments and {expected_unique} unique pairs, got {raw_assignment_count} and {len(multipliers)}")
    return {
        "id": "base:type_chart/classic",
        "display_name": "Classic type chart",
        "source": str(path),
        "default_multiplier": 1.0,
        "not_effective_multiplier": values["NOT_EFFECTIVE_MODIFIER"],
        "super_effective_multiplier": values["SUPER_EFFECTIVE_MODIFIER"],
        "raw_assignment_count": raw_assignment_count,
        "multipliers": dict(sorted(multipliers.items())),
    }


def import_move_index(scripts: Path) -> list[dict]:
    path = scripts / "States" / "MinionMoveID.as"
    values = constants(path)
    if sorted(values.values()) != list(range(893)):
        raise ImportProblem(path, 1, "", "base move IDs are not exactly 0..892")
    entries = []
    for name, legacy_id in sorted(values.items(), key=lambda item: item[1]):
        match = re.fullmatch(r"(.+)_t(\d+)", name)
        if not match: raise ImportProblem(path, 1, name, "base move constant has no explicit tier")
        entries.append({"id": f"base:move/{slug(match.group(1))}/tier{match.group(2)}", "family_id": f"base:move_family/{slug(match.group(1))}", "tier": int(match.group(2)), "legacy_numeric_id": legacy_id, "legacy_constant": name, "source": str(path)})
    static_path = scripts / "PresistentData" / "StaticData.as"
    text = static_path.read_text(encoding="utf-8-sig")
    family_match = re.search(r'all_iceFloor_move\.push\((.*?)\)', text, re.DOTALL)
    if not family_match: raise ImportProblem(static_path, 1, "all_iceFloor_move.push", "dynamic move-family registration not found")
    families = re.findall(r'"([^"]+)"', family_match.group(1))
    next_legacy_id = 893
    for family in families:
        for tier in range(1, 6):
            entries.append({"id": f"ice_floor:move/{slug(family)}/tier{tier}", "family_id": f"ice_floor:move_family/{slug(family)}", "tier": tier, "legacy_numeric_id": next_legacy_id, "legacy_constant": f'ModToMoveID["{family}_t{tier}"]', "source": str(static_path)})
            next_legacy_id += 1
    return entries


def import_talents(scripts: Path, corrections: list[dict] | None = None) -> list[dict]:
    path = scripts / "Minions" / "BaseTalentTreeContainer.as"
    text = strip_comments(path.read_text(encoding="utf-8-sig"))
    results = []
    for function_name, body, function_line in extract_functions(text, path, TALENT_FUNCTION_RE):
        constructor = TREE_CONSTRUCTOR_RE.search(body)
        if not constructor: constructor = DIRECT_TREE_CONSTRUCTOR_RE.search(body)
        if not constructor: raise ImportProblem(path, function_line, function_name, "talent tree has no recognized constructor")
        tree_id = f"base:talent_tree/{slug(function_name)}"
        nodes: dict[tuple[int, int], dict] = {}
        for call in TREE_MOVE_RE.finditer(body):
            call_line = function_line + line_at(body, call.start())
            args = split_arguments(call.group(1))
            if len(args) not in (3, 4): raise ImportProblem(path, call_line, call.group(1), "AddMoveToTree requires 3 or 4 arguments")
            if not re.fullmatch(r"\d+", args[0]) or not re.fullmatch(r"\d+", args[1]):
                raise ImportProblem(path, call_line, call.group(1), "talent coordinates must be integer literals")
            column, row = int(args[0]), int(args[1])
            if not 0 <= column < 3 or not 0 <= row < 4: raise ImportProblem(path, call_line, call.group(1), "talent coordinates outside 3x4 grid")
            dependent = False
            if len(args) == 4:
                if args[3] not in ("true", "false"): raise ImportProblem(path, call_line, args[3], "dependency flag must be a Boolean literal")
                dependent = args[3] == "true"
            node = nodes.setdefault((column, row), {"id": f"{tree_id}/node/{column}_{row}", "column": column, "row": row, "move_ids": [], "prerequisite_node_ids": [], "source_lines": []})
            node["move_ids"].append(move_id(args[2], path, call_line, corrections))
            node["source_lines"].append(call_line)
            if dependent and row > 0: node["prerequisite_node_ids"] = [f"{tree_id}/node/{column}_{row - 1}"]
        results.append({"id": tree_id, "display_name": constructor.group(1), "legacy_function": function_name, "nodes": [nodes[key] for key in sorted(nodes, key=lambda pair: (pair[1], pair[0]))], "source": str(path), "line": function_line})
    if len(results) != 167: raise ImportProblem(path, 1, "", f"expected 167 talent trees, found {len(results)}")
    if len({item['id'] for item in results}) != len(results): raise ImportProblem(path, 1, "", "duplicate talent-tree IDs")
    return results


def import_minions(scripts: Path, corrections: list[dict] | None = None) -> list[dict]:
    path = scripts / "Minions" / "AllMinionsContainer.as"
    raw = path.read_text(encoding="utf-8-sig")
    text = strip_comments(raw)
    dex = constants(scripts / "States" / "MinionDexID.as")
    constant_sets = {
        "MinionDexID": dex,
        "MinionType": {k: v for k, v in constants(scripts / "States" / "MinionType.as").items()} | {k.lower().upper(): v for k, v in constants(scripts / "States" / "MinionType.as").items()},
        "MinionMoveID": constants(scripts / "States" / "MinionMoveID.as"),
        "ExpGainRates": constants(scripts / "States" / "ExpGainRates.as"),
    }
    results = []
    for function_name, body, function_line in extract_functions(text, path):
        cm = CM_RE.search(body)
        if not cm: continue
        cm_line = function_line + line_at(body, cm.start())
        args = split_arguments(cm.group(1))
        if len(args) not in (9, 10): raise ImportProblem(path, cm_line, cm.group(1), "CM requires 9 or 10 arguments")
        stable_id, legacy_id, namespace, legacy_identity = minion_identity(args[0], dex, path, cm_line)
        minion = {
            "id": stable_id, "display_name": literal(args[1], constant_sets, path, cm_line),
            "types": [type_id(args[8], path, cm_line)],
            "base_stats": {"health": literal(args[3], constant_sets, path, cm_line), "energy": literal(args[4], constant_sets, path, cm_line), "attack": literal(args[5], constant_sets, path, cm_line), "healing": literal(args[6], constant_sets, path, cm_line), "speed": literal(args[7], constant_sets, path, cm_line)},
            "initial_move_ids": [], "specialization_move_ids": [], "talent_tree_ids": [None, None, None],
            "presentation_id": f"{namespace}:presentation/minion/{slug(literal(args[2], constant_sets, path, cm_line))}",
            "evolution_id": None, "evolution_level": 999, "experience_gain_rate": 1,
            "gem_slots": 0, "locked_gem_slots": 0, "icon_offset_x": 0, "icon_offset_y": 0,
            "migration": {"legacy_numeric_id": legacy_id, "legacy_identity": legacy_identity, "legacy_function": function_name, "source": str(path), "line": cm_line, "source_mod": namespace},
        }
        minion["migration"]["legacy_sprite"] = literal(args[2], constant_sets, path, cm_line)
        if len(args) == 10:
            second = type_id(args[9], path, cm_line)
            if second != "base:type/none": minion["types"].append(second)
        for assignment in ASSIGN_RE.finditer(body):
            prop, expression = assignment.groups()
            if prop not in MINION_PROPERTIES: raise ImportProblem(path, function_line + line_at(body, assignment.start()), assignment.group(0), "unsupported minion property")
            minion[MINION_PROPERTIES[prop]] = literal(expression, constant_sets, path, function_line + line_at(body, assignment.start()))
        for move in START_MOVE_RE.finditer(body):
            minion["initial_move_ids"].append(move_id(move.group(1), path, function_line + line_at(body, move.start()), corrections))
        spec = SPEC_RE.search(body)
        if spec:
            spec_args = split_arguments(spec.group(1))
            if len(spec_args) != 3: raise ImportProblem(path, function_line + line_at(body, spec.start()), spec.group(1), "specialization requires exactly three moves")
            minion["specialization_move_ids"] = [move_id(value, path, function_line + line_at(body, spec.start()), corrections) for value in spec_args]
        pending_tree = None
        statements = sorted([(m.start(), "load", m) for m in TREE_LOAD_RE.finditer(body)] + [(m.start(), "set", m) for m in TREE_SET_RE.finditer(body)])
        for _, kind, match in statements:
            if kind == "load": pending_tree = match.group(1)
            elif pending_tree is None: raise ImportProblem(path, function_line + line_at(body, match.start()), match.group(0), "talent tree set without preceding load")
            else:
                index = int(match.group(1))
                if not 0 <= index < 3: raise ImportProblem(path, function_line + line_at(body, match.start()), match.group(0), "talent index outside 0..2")
                minion["talent_tree_ids"][index] = f"base:talent_tree/{slug(pending_tree)}"
                pending_tree = None
        results.append(minion)
    if not results: raise ImportProblem(path, 1, "", "no minion definitions found")
    if len({item["id"] for item in results}) != len(results): raise ImportProblem(path, 1, "", "duplicate stable minion IDs")
    by_function = {item["migration"]["legacy_function"].lower(): item for item in results}
    for item in results:
        function = item["migration"]["legacy_function"]
        match = re.fullmatch(r"(.+)_stage(\d+)", function, re.IGNORECASE)
        if match:
            successor = by_function.get(f"{match.group(1)}_stage{int(match.group(2)) + 1}".lower())
            if successor: item["evolution_id"] = successor["id"]
    return results


def validate(types: list[dict], moves: list[dict], talents: list[dict], minions: list[dict]) -> list[dict]:
    errors = []
    type_ids = {item["id"] for item in types}
    minion_ids = {item["id"] for item in minions}
    move_ids = {item["id"] for item in moves}
    talent_ids = {item["id"] for item in talents}
    if len(type_ids) != len(types): errors.append({"message": "duplicate type IDs"})
    if len(minion_ids) != len(minions): errors.append({"message": "duplicate minion IDs"})
    for tree in talents:
        for node in tree["nodes"]:
            for referenced in node["move_ids"]:
                if referenced not in move_ids: errors.append({"source": tree["source"], "line": node["source_lines"][0], "message": f"{node['id']} references unknown move {referenced}"})
    legacy_base_ids = []
    for item in minions:
        source = item["migration"]["source"]
        line = item["migration"]["line"]
        for referenced in item["types"]:
            if referenced not in type_ids: errors.append({"source": source, "line": line, "message": f"{item['id']} references unknown type {referenced}"})
        for referenced in item["initial_move_ids"] + item["specialization_move_ids"]:
            if referenced not in move_ids: errors.append({"source": source, "line": line, "message": f"{item['id']} references unknown move {referenced}"})
        for referenced in (value for value in item["talent_tree_ids"] if value):
            if referenced not in talent_ids: errors.append({"source": source, "line": line, "message": f"{item['id']} references unknown talent tree {referenced}"})
        if any(value < 0 for value in item["base_stats"].values()) or item["base_stats"]["health"] <= 0:
            errors.append({"source": source, "line": line, "message": f"{item['id']} has invalid base stats"})
        if not item["initial_move_ids"]: errors.append({"source": source, "line": line, "message": f"{item['id']} has no initial moves"})
        if len(item["specialization_move_ids"]) not in (0, 3): errors.append({"source": source, "line": line, "message": f"{item['id']} has an invalid specialization count"})
        if item["locked_gem_slots"] + item["gem_slots"] > 8: errors.append({"source": source, "line": line, "message": f"{item['id']} has an implausible combined gem socket count"})
        if item["evolution_id"] and item["evolution_id"] not in minion_ids: errors.append({"source": source, "line": line, "message": f"{item['id']} references missing evolution {item['evolution_id']}"})
        if item["migration"]["source_mod"] == "base": legacy_base_ids.append(item["migration"]["legacy_numeric_id"])
    if sorted(legacy_base_ids) != list(range(102)):
        errors.append({"message": "base minion legacy IDs are not exactly 0..101"})
    return errors


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("source_directory", type=Path)
    parser.add_argument("output_directory", type=Path)
    args = parser.parse_args()
    scripts = args.source_directory.resolve() / "scripts"
    output = args.output_directory.resolve()
    if output.exists() and any(output.iterdir()): raise SystemExit(f"refusing to overwrite non-empty staged output: {output}")
    output.mkdir(parents=True, exist_ok=True)
    corrections = []
    try:
        types = import_types(scripts)
        type_chart = import_type_chart(scripts)
        moves = import_move_index(scripts)
        talents = import_talents(scripts, corrections)
        minions = import_minions(scripts, corrections)
    except ImportProblem as problem:
        (output / "import_errors.json").write_text(json.dumps([problem.as_dict()], indent=2), encoding="utf-8")
        print(json.dumps(problem.as_dict(), indent=2))
        return 1
    (output / "types.json").write_text(json.dumps(types, indent=2), encoding="utf-8")
    (output / "type_chart.json").write_text(json.dumps(type_chart, indent=2), encoding="utf-8")
    (output / "move_index.json").write_text(json.dumps(moves, indent=2), encoding="utf-8")
    (output / "talent_trees.json").write_text(json.dumps(talents, indent=2), encoding="utf-8")
    (output / "minions.json").write_text(json.dumps(minions, indent=2), encoding="utf-8")
    (output / "import_corrections.json").write_text(json.dumps(corrections, indent=2), encoding="utf-8")
    validation_errors = validate(types, moves, talents, minions)
    report = {"type_count": len(types), "type_chart_pair_count": len(type_chart["multipliers"]), "type_chart_source_assignment_count": type_chart["raw_assignment_count"], "move_identity_count": len(moves), "talent_tree_identity_count": len(talents), "minion_count": len(minions), "base_minion_count": sum(item["migration"]["source_mod"] == "base" for item in minions), "mod_minion_count": sum(item["migration"]["source_mod"] not in ("base", "internal") for item in minions), "internal_minion_count": sum(item["migration"]["source_mod"] == "internal" for item in minions), "evolution_link_count": sum(item["evolution_id"] is not None for item in minions), "correction_count": len(corrections), "error_count": len(validation_errors), "accepted": not validation_errors}
    (output / "import_report.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    if validation_errors:
        (output / "import_errors.json").write_text(json.dumps(validation_errors, indent=2), encoding="utf-8")
        print(json.dumps(report, indent=2))
        print(json.dumps(validation_errors, indent=2))
        return 1
    print(json.dumps(report, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
