"""Strict value-level importer for AllBaseMovesContainer.as.

This recognizes only the small construction grammar used by the recovered file.
It never evaluates ActionScript or substitutes defaults for unknown expressions.
"""

from __future__ import annotations

import argparse
import ast
import json
import re
from pathlib import Path

from strict_content_import import ImportProblem, constants, import_move_index, split_arguments


ARRAY_RE = re.compile(r"(_loc\d+_)\s*=\s*new\s+Array\((.*?)\)\s*;?$")
STATE_RE = re.compile(r"this\.(m_curr\w+)\s*=\s*(.*?)\s*;?$")
CREATE_RE = re.compile(r"(_loc\d+_)\s*=\s*this\.(old_FireCM|old_NormalCM|old_EnergyCM|old_EarthCM|CreateMove|CopyMove|PassiveCM)\((.*?)\)\s*;?$")
PROPERTY_RE = re.compile(r"(_loc\d+_)\.(m_\w+)\s*=\s*(.*?)\s*;?$")
METHOD_RE = re.compile(r"(_loc\d+_)\.(AddStatToBuff|AddStatToBuffFirstTime|AddStatToDeBuff|AddStatToDeBuffFirstTime)\((.*?)\)\s*;?$")
MOVE_LOCAL_RE = re.compile(r"var\s+(_loc\d+_)\s*:\s*BaseMinionMove\b")
DYNAMIC_RE = re.compile(r'(MoveClassDict|MoveDict)\["([^"]+)"\]$')
CONSTANT_RE = re.compile(r"(MinionMoveClasses|MinionMoveID|MinionType|MinionVisualMoveID|StatType)\.(\w+)$")
ARRAY_VALUE_RE = re.compile(r"(_loc\d+_)\[(\d+)\]$")

DYNAMIC_FAMILIES = ["iStrike", "iFist", "iHorn", "iMelt", "iBreath", "iMicro"]
EXPECTED_UNCONSTRUCTED_IDS = set(range(135, 140))  # Declared group_reflect_t1..t5; never constructed or referenced.
STATE_NAMES = {
    "m_currMinionMoveClass", "m_currFirstMinionMoveID", "m_currMoveIconName",
    "m_currMinionMoveVisuals", "m_currMinionDOTMoveVisuals",
}
PROPERTY_MAP = {
    "m_accuracy": "accuracy", "m_isPassive": "is_passive", "m_isGlobalPassive": "is_global_passive",
    "m_moveCoolDownTime": "cooldown", "m_chanceToAddOverTimeMove": "over_time_chance",
    "m_overTimeStackAmount": "over_time_stacks", "m_overTimeTurnsActive": "over_time_turns",
    "m_additionalRandomOverTimeTurnsActive": "additional_over_time_turns", "m_chargeTime": "charge_time",
    "m_exhaustTime": "exhaust_time", "m_enemiesItHits": "enemies_hit", "m_alliesItHits": "allies_hit",
    "m_hitsRandomTargets": "hits_random", "m_onlyHitsSelf": "only_self", "m_energyUsed": "energy_used",
    "m_energyPercentageRestored": "energy_percent_restored", "m_doesHitEachEnemy": "hits_each_enemy",
    "m_isThereABufferBetweenVisualMovesOnMultipleEnemies": "visuals_have_buffer", "m_damage": "damage",
    "m_additionalRandomDamage": "additional_damage", "m_DOTDamage": "dot_damage",
    "m_additionalDOTDamage": "additional_dot_damage", "m_percentageOfHealthRemoved": "health_percent_removed",
    "m_selfDamage": "self_damage", "m_additionalRandomSelfDamage": "additional_self_damage",
    "m_selfPercentageDamage": "self_health_percent_damage", "m_healing": "healing",
    "m_additionalRandomHealing": "additional_healing", "m_HOTHealing": "hot_healing",
    "m_additionalHOTHealing": "additional_hot_healing", "m_selfHeal": "self_healing",
    "m_additionalRandomSelfHeal": "additional_self_healing", "m_stunChance": "stun_chance",
    "m_freezeChance": "freeze_chance", "m_chanceToDeBuff": "debuff_chance",
    "m_amountOfStatTypeToDeBuffPercentage": "debuff_stat_percent", "m_stagesOfStatTypeToDeBuff": "debuff_stages",
    "m_doesDeBuffTargets": "debuff_targets", "m_doesDeBuffSelf": "debuff_self", "m_reviveChance": "revive_chance",
    "m_percentageOfDamageThatGetsRedirectedAtMinion": "redirect_damage_percent", "m_chanceToBuff": "buff_chance",
    "m_amountOfStatTypeToBuffPercentage": "buff_stat_percent", "m_stagesOfStatTypeToBuff": "buff_stages",
    "m_doesBuffTargets": "buff_targets", "m_doesBuffSelf": "buff_self",
    "m_clearBuffsAndDebuffsChance": "clear_buffs_debuffs_chance", "m_armor": "armor",
    "m_setShieldAmount": "shield", "m_setReflectDamageAmount": "reflect_damage",
    "m_increasedExtraCritChance": "extra_crit_chance", "m_chanceToClearAllCooldowns": "clear_cooldowns_chance",
    "m_moveType": "type", "m_moveIcon": "icon",
}
INT_FIELDS = set(PROPERTY_MAP.values()) - {
    "is_passive", "is_global_passive", "hits_random", "only_self", "hits_each_enemy",
    "visuals_have_buffer", "debuff_targets", "debuff_self", "buff_targets", "buff_self", "icon",
}
BOOL_FIELDS = {
    "is_passive", "is_global_passive", "hits_random", "only_self", "hits_each_enemy",
    "visuals_have_buffer", "debuff_targets", "debuff_self", "buff_targets", "buff_self",
}

KIND = {name: index for index, name in enumerate([
    "damage", "heal", "energy", "stat_stage", "apply_status", "remove_status", "shield", "reflect", "revive", "cooldown",
    "periodic_damage", "periodic_heal", "armor", "self_damage", "health_percent_damage", "stun", "freeze",
    "clear_buffs_debuffs", "stat_percent", "redirect_damage", "critical_chance",
])}
SCOPE = {"actor": 0, "enemy_targets": 1, "ally_targets": 2, "both_target_groups": 3, "allied_team": 4}
PHASE = {"before_accuracy": 0, "enemy_target": 1, "ally_target": 2, "actor_after_targets": 3, "passive": 4}
SCALING = {"none": 0, "attack": 1, "healing": 2, "energy_stat_percent": 3, "health_stat_percent": 4}
ROLL_SCOPE = {"none": 0, "shared_move": 1, "per_target": 2, "per_effect_target": 3, "periodic_tick": 4}


def as_int(value: int | float) -> int:
    """ActionScript int conversion truncates toward zero."""
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise TypeError(f"expected numeric value, got {value!r}")
    return int(value)


def default_move() -> dict:
    return {
        "legacy_numeric_id": 0, "legacy_class_id": 0, "legacy_tier_index": 0, "type": 0,
        "display_name": "no name", "icon": "moveIcon_needleBarrage", "buff_icon": "moveIcon_needleBarrage",
        "accuracy": 100, "is_passive": False, "is_global_passive": False, "cooldown": 0,
        "over_time_chance": 100, "over_time_stacks": 1, "over_time_turns": 3,
        "additional_over_time_turns": 0, "charge_time": 0, "exhaust_time": 0,
        "enemies_hit": 1, "allies_hit": 0, "hits_random": False, "only_self": False,
        "energy_used": 1, "energy_percent_restored": 0, "legacy_visual_id": 0,
        "legacy_dot_visual_id": 0, "hits_each_enemy": True, "visuals_have_buffer": True,
        "damage": 0, "additional_damage": 0, "dot_damage": 0, "additional_dot_damage": 0,
        "health_percent_removed": 0, "self_damage": 0, "additional_self_damage": 0,
        "self_health_percent_damage": 0, "healing": 0, "additional_healing": 0,
        "hot_healing": 0, "additional_hot_healing": 0, "self_healing": 0,
        "additional_self_healing": 0, "stun_chance": 0, "freeze_chance": 0,
        "debuff_stats": [], "debuff_chance": 100, "debuff_stat_percent": 0, "debuff_stages": 0,
        "debuff_targets": False, "debuff_self": False, "revive_chance": 0,
        "redirect_damage_percent": 0, "buff_stats": [], "buff_chance": 100,
        "buff_stat_percent": 0, "buff_stages": 0, "buff_targets": False, "buff_self": False,
        "clear_buffs_debuffs_chance": 0, "armor": 0, "shield": 0, "reflect_damage": 0,
        "extra_crit_chance": 0, "clear_cooldowns_chance": 0,
    }


def normalize_effects(move: dict, stat_names: dict[int, str]) -> list[dict]:
    """Translate legacy fields into the exact coarse phases used by BaseMoveSystem.

    The records are typed and ordered, but remain runtime-pending until the port
    implements the legacy scaling, roll scope, redirection, and periodic hooks.
    """
    effects = []

    def add(kind: str, scope: str, phase: str, amount: int = 0, random_bonus: int = 0,
            chance: int = 100, scaling: str = "none", stat: int | None = None,
            duration: int = 0, typed: bool = False, critical: bool = False,
            shield_blocked: bool = False, roll_scope: str = "none") -> None:
        sequence = len(effects)
        effects.append({
            "id": f'{move["id"]}/effect/{sequence:02d}_{kind}_{scope}', "kind": KIND[kind],
            "kind_name": kind, "target_scope": SCOPE[scope], "phase": PHASE[phase],
            "scaling": SCALING[scaling], "roll_scope": ROLL_SCOPE[roll_scope], "amount": amount, "random_bonus": random_bonus,
            "chance_percent": chance, "stat_type_id": stat_names.get(stat, "") if stat is not None else "",
            "duration": duration, "uses_type_effectiveness": typed, "can_critical": critical,
            "blocked_by_battle_mod_shield": shield_blocked, "legacy_order": sequence,
            "implementation_status": 1,
        })

    if move["is_passive"] or move["is_global_passive"]:
        scope = "allied_team" if move["is_global_passive"] else "actor"
        for stat in move["buff_stats"]:
            if move["buff_stat_percent"] != 0:
                add("stat_percent", scope, "passive", move["buff_stat_percent"], stat=stat)
            if move["buff_stages"] != 0:
                add("stat_stage", scope, "passive", move["buff_stages"], chance=move["buff_chance"], stat=stat)
        if move["armor"] != 0: add("armor", scope, "passive", move["armor"])
        if move["shield"] != 0: add("shield", scope, "passive", move["shield"], scaling="healing")
        if move["reflect_damage"] != 0: add("reflect", scope, "passive", move["reflect_damage"])
        if move["redirect_damage_percent"] != 0: add("redirect_damage", scope, "passive", move["redirect_damage_percent"])
        if move["extra_crit_chance"] != 0: add("critical_chance", scope, "passive", move["extra_crit_chance"])
        return effects

    if move["energy_percent_restored"] > 0:
        add("energy", "actor", "before_accuracy", move["energy_percent_restored"], scaling="energy_stat_percent")
    if move["damage"] != 0 or move["additional_damage"] != 0:
        add("damage", "enemy_targets", "enemy_target", move["damage"], move["additional_damage"], scaling="attack", typed=True, critical=True, roll_scope="shared_move")
    if move["dot_damage"] != 0 or move["additional_dot_damage"] != 0:
        add("periodic_damage", "enemy_targets", "enemy_target", move["dot_damage"], move["additional_dot_damage"],
            move["over_time_chance"], "attack", duration=move["over_time_turns"], typed=True, shield_blocked=True, roll_scope="periodic_tick")
    if move["armor"] != 0: add("armor", "enemy_targets", "enemy_target", move["armor"], duration=move["over_time_turns"], shield_blocked=True)
    if move["reflect_damage"] > 0: add("reflect", "enemy_targets", "enemy_target", move["reflect_damage"], duration=move["over_time_turns"], shield_blocked=True)
    if move["clear_buffs_debuffs_chance"] > 0:
        add("clear_buffs_debuffs", "enemy_targets", "enemy_target", chance=move["clear_buffs_debuffs_chance"], roll_scope="per_target")
    if move["freeze_chance"] > 0: add("freeze", "enemy_targets", "enemy_target", chance=move["freeze_chance"], roll_scope="shared_move")
    if move["stun_chance"] > 0: add("stun", "enemy_targets", "enemy_target", chance=move["stun_chance"], roll_scope="shared_move")
    if move["healing"] != 0 or move["additional_healing"] != 0:
        add("heal", "ally_targets", "ally_target", move["healing"], move["additional_healing"], scaling="healing", typed=True, critical=True, roll_scope="shared_move")
    if move["shield"] > 0: add("shield", "ally_targets", "ally_target", move["shield"], scaling="healing")
    if move["clear_buffs_debuffs_chance"] > 0:
        add("clear_buffs_debuffs", "ally_targets", "ally_target", chance=move["clear_buffs_debuffs_chance"], roll_scope="per_target")
    if move["hot_healing"] != 0 or move["additional_hot_healing"] != 0:
        add("periodic_heal", "ally_targets", "ally_target", move["hot_healing"], move["additional_hot_healing"],
            move["over_time_chance"], "healing", duration=move["over_time_turns"], roll_scope="periodic_tick")
    if move["armor"] != 0: add("armor", "ally_targets", "ally_target", move["armor"], duration=move["over_time_turns"])
    if move["reflect_damage"] > 0: add("reflect", "ally_targets", "ally_target", move["reflect_damage"], duration=move["over_time_turns"])
    if move["self_damage"] != 0 or move["additional_self_damage"] != 0:
        add("self_damage", "actor", "actor_after_targets", move["self_damage"], move["additional_self_damage"], scaling="attack", roll_scope="shared_move")
    if move["self_health_percent_damage"] != 0:
        add("health_percent_damage", "actor", "actor_after_targets", move["self_health_percent_damage"], scaling="health_stat_percent")
    if move["self_healing"] != 0 or move["additional_self_healing"] != 0:
        add("heal", "actor", "actor_after_targets", move["self_healing"], move["additional_self_healing"], scaling="healing", roll_scope="shared_move")
    for stat in move["buff_stats"]:
        if move["buff_self"]: add("stat_stage", "actor", "actor_after_targets", move["buff_stages"], chance=move["buff_chance"], stat=stat, roll_scope="shared_move")
    for stat in move["debuff_stats"]:
        if move["debuff_self"]: add("stat_stage", "actor", "actor_after_targets", move["debuff_stages"], chance=move["debuff_chance"], stat=stat, roll_scope="shared_move")
    for stat in move["buff_stats"]:
        if move["buff_targets"]: add("stat_stage", "both_target_groups", "actor_after_targets", move["buff_stages"], chance=move["buff_chance"], stat=stat, roll_scope="shared_move")
    for stat in move["debuff_stats"]:
        if move["debuff_targets"]: add("stat_stage", "both_target_groups", "actor_after_targets", move["debuff_stages"], chance=move["debuff_chance"], stat=stat, roll_scope="shared_move")
    return effects


class ExpressionResolver:
    def __init__(self, constant_sets: dict[str, dict[str, int]], path: Path):
        self.constant_sets = constant_sets
        self.path = path
        self.arrays: dict[str, list] = {}
        self.state = {name: 0 for name in STATE_NAMES}
        self.state["m_currMoveIconName"] = ""
        self.dynamic_classes = {name: 181 + index for index, name in enumerate(DYNAMIC_FAMILIES)}
        self.dynamic_moves = {
            f"{name}_t{tier}": 893 + family_index * 5 + tier - 1
            for family_index, name in enumerate(DYNAMIC_FAMILIES) for tier in range(1, 6)
        }

    def resolve(self, expression: str, line: int):
        expression = expression.strip().rstrip(";").strip()
        if expression in ("true", "false"): return expression == "true"
        if expression == "null": return None
        if expression == "TypeID": return 15
        if expression == "this.m_armorModRate": return 0.66
        if expression.startswith("this.") and expression[5:] in self.state: return self.state[expression[5:]]
        dynamic = DYNAMIC_RE.fullmatch(expression)
        if dynamic:
            table, key = dynamic.groups()
            values = self.dynamic_classes if table == "MoveClassDict" else self.dynamic_moves
            if key not in values: raise ImportProblem(self.path, line, expression, f"unknown {table} key")
            return values[key]
        constant = CONSTANT_RE.fullmatch(expression)
        if constant:
            family, name = constant.groups()
            values = self.constant_sets[family]
            if name not in values: raise ImportProblem(self.path, line, expression, f"unknown {family} constant")
            return values[name]
        array_value = ARRAY_VALUE_RE.fullmatch(expression)
        if array_value:
            name, index_text = array_value.groups()
            index = int(index_text)
            if name not in self.arrays or index >= len(self.arrays[name]):
                raise ImportProblem(self.path, line, expression, "unknown array element")
            return self.arrays[name][index]
        if expression.startswith(("-", "+")) and len(expression) > 1:
            value = self.resolve(expression[1:].strip(), line)
            if not isinstance(value, (int, float)) or isinstance(value, bool):
                raise ImportProblem(self.path, line, expression, "unary operator requires a number")
            return -value if expression[0] == "-" else value
        try:
            parsed = ast.parse(expression, mode="eval").body
        except SyntaxError as error:
            raise ImportProblem(self.path, line, expression, "unsupported expression") from error
        return self._resolve_ast(parsed, line, expression)

    def _resolve_ast(self, node: ast.AST, line: int, expression: str):
        if isinstance(node, ast.Constant) and isinstance(node.value, (str, int, float)) and not isinstance(node.value, complex):
            return node.value
        if isinstance(node, ast.UnaryOp) and isinstance(node.op, (ast.USub, ast.UAdd)):
            value = self._resolve_ast(node.operand, line, expression)
            if not isinstance(value, (int, float)) or isinstance(value, bool):
                raise ImportProblem(self.path, line, expression, "unary operator requires a number")
            return -value if isinstance(node.op, ast.USub) else value
        if isinstance(node, ast.BinOp) and isinstance(node.op, (ast.Mult, ast.Div)):
            left = self._resolve_fragment(ast.unparse(node.left), line)
            right = self._resolve_fragment(ast.unparse(node.right), line)
            if not all(isinstance(value, (int, float)) and not isinstance(value, bool) for value in (left, right)):
                raise ImportProblem(self.path, line, expression, "arithmetic requires numbers")
            if isinstance(node.op, ast.Div) and right == 0: raise ImportProblem(self.path, line, expression, "division by zero")
            return left * right if isinstance(node.op, ast.Mult) else left / right
        raise ImportProblem(self.path, line, expression, "unsupported expression grammar")

    def _resolve_fragment(self, expression: str, line: int):
        # ast.unparse inserts spaces but otherwise preserves this limited grammar.
        return self.resolve(expression.replace("this .", "this.").replace(" . ", "."), line)


def _set_icon(move: dict, icon: str) -> None:
    move["icon"] = icon
    move["buff_icon"] = icon


def _visual_get(move: dict, same_as_class: int, key: str) -> int:
    value = move[key]
    return move["legacy_class_id"] if value == same_as_class else value


def _create(function: str, args: list, active_name: str, active: dict | None, resolver: ExpressionResolver, same_as_class: int, path: Path, line: int) -> dict:
    move = active.copy() if function == "CopyMove" and active is not None else default_move()
    if function == "CopyMove":
        if len(args) not in (2, 3) or args[0] != active_name: raise ImportProblem(path, line, ",".join(args), "CopyMove requires the current move, energy, and optional name")
        move["legacy_visual_id"] = _visual_get(move, same_as_class, "legacy_visual_id")
        move["legacy_dot_visual_id"] = _visual_get(move, same_as_class, "legacy_dot_visual_id")
        move["legacy_tier_index"] += 1
        move["legacy_numeric_id"] += 1
        move["energy_used"] = as_int(resolver.resolve(args[1], line))
        if len(args) == 3:
            name = resolver.resolve(args[2], line)
            if name is not None: move["display_name"] = name
        else:
            first_id = move["legacy_numeric_id"] - move["legacy_tier_index"]
            base = getattr(resolver, "moves", {}).get(first_id)
            if base is None: raise ImportProblem(path, line, args[0], "CopyMove cannot find its tier-1 name")
            move["display_name"] = f'{base["display_name"]}  lv.{move["legacy_tier_index"] + 1}'
        return move

    values = [resolver.resolve(argument, line) for argument in args]
    state = resolver.state
    if function == "CreateMove":
        if len(values) not in (7, 8): raise ImportProblem(path, line, ",".join(args), "CreateMove requires 7 or 8 arguments")
        name, energy, class_id, move_id, icon, type_id, visual = values[:7]
        move.update(legacy_numeric_id=as_int(move_id), legacy_class_id=as_int(class_id), legacy_tier_index=0,
                    type=as_int(type_id), display_name=name, energy_used=as_int(energy), legacy_visual_id=as_int(visual),
                    legacy_dot_visual_id=as_int(values[7] if len(values) == 8 else visual))
        _set_icon(move, icon)
        return move
    if function == "PassiveCM":
        if not 3 <= len(values) <= 5: raise ImportProblem(path, line, ",".join(args), "PassiveCM requires 3 to 5 arguments")
        tier, name, stat = values[:3]
        amount = values[3] if len(values) >= 4 else 0
        global_passive = values[4] if len(values) == 5 else False
        move.update(legacy_numeric_id=as_int(state["m_currFirstMinionMoveID"] + tier),
                    legacy_class_id=as_int(state["m_currMinionMoveClass"]), legacy_tier_index=as_int(tier),
                    display_name=name, energy_used=0, legacy_visual_id=as_int(state["m_currMinionMoveVisuals"]),
                    legacy_dot_visual_id=as_int(state["m_currMinionDOTMoveVisuals"]),
                    is_global_passive=bool(global_passive), is_passive=not bool(global_passive))
        _set_icon(move, state["m_currMoveIconName"])
        if stat != resolver.constant_sets["StatType"]["STAT_NONE"]:
            move["buff_stat_percent"] = as_int(amount)
            move["buff_stats"].append(as_int(stat))
        return move

    defaults = {
        "old_FireCM": [0, "", 0, 0, 0, 0, 1, 0, 1, False],
        "old_NormalCM": [0, "", 0, 0, 0, 1, 100, 0],
        "old_EnergyCM": [0, "", 0, 0, 1, 1, 100, 0, 0],
        "old_EarthCM": [0, "", 0, 0, 1, 0, 0, 1, False],
    }[function]
    if len(values) > len(defaults): raise ImportProblem(path, line, ",".join(args), f"too many {function} arguments")
    values += defaults[len(values):]
    tier, name = values[:2]
    move.update(legacy_numeric_id=as_int(state["m_currFirstMinionMoveID"] + tier),
                legacy_class_id=as_int(state["m_currMinionMoveClass"]), legacy_tier_index=as_int(tier),
                display_name=name, legacy_visual_id=as_int(state["m_currMinionMoveVisuals"]),
                legacy_dot_visual_id=as_int(state["m_currMinionDOTMoveVisuals"]))
    _set_icon(move, state["m_currMoveIconName"])
    if function == "old_FireCM":
        _, _, damage, add, dot, add_dot, energy, cooldown, enemies, random = values
        move.update(type=resolver.constant_sets["MinionType"]["TYPE_FIRE"], damage=as_int(damage), additional_damage=as_int(add),
                    dot_damage=as_int(dot), additional_dot_damage=as_int(add_dot), energy_used=as_int(energy),
                    cooldown=as_int(cooldown), enemies_hit=as_int(enemies), hits_random=bool(random))
    elif function == "old_NormalCM":
        _, _, damage, add, dot, energy, accuracy, cooldown = values
        move.update(type=resolver.constant_sets["MinionType"]["TYPE_NORMAL"], damage=as_int(damage), additional_damage=as_int(add),
                    dot_damage=as_int(dot), energy_used=as_int(energy), accuracy=as_int(accuracy), cooldown=as_int(cooldown))
    elif function == "old_EnergyCM":
        _, _, damage, add, energy, enemies, accuracy, cooldown, stun = values
        move.update(type=resolver.constant_sets["MinionType"]["TYPE_ENERGY"], damage=as_int(damage), additional_damage=as_int(add),
                    energy_used=as_int(energy), enemies_hit=as_int(enemies), accuracy=as_int(accuracy),
                    cooldown=as_int(cooldown), stun_chance=as_int(stun))
    else:
        _, _, damage, add, energy, armor, cooldown, enemies, random = values
        move.update(type=resolver.constant_sets["MinionType"]["TYPE_EARTH"], damage=as_int(damage), additional_damage=as_int(add),
                    energy_used=as_int(energy), armor=as_int(armor), cooldown=as_int(cooldown),
                    enemies_hit=as_int(enemies), hits_random=bool(random))
    return move


def import_moves(scripts: Path) -> tuple[list[dict], list[dict]]:
    path = scripts / "Minions" / "MinionMove" / "AllBaseMovesContainer.as"
    constant_sets = {
        family: constants(scripts / relative)
        for family, relative in {
            "MinionMoveClasses": "States/MinionMoveClasses.as", "MinionMoveID": "States/MinionMoveID.as",
            "MinionType": "States/MinionType.as", "MinionVisualMoveID": "States/MinionVisualMoveID.as",
            "StatType": "States/StatType.as",
        }.items()
    }
    index = import_move_index(scripts)
    identities = {entry["legacy_numeric_id"]: entry for entry in index}
    resolver = ExpressionResolver(constant_sets, path)
    resolver.moves = {}
    active = None
    active_name = ""
    in_content = False
    block_comment = False
    for line_number, raw in enumerate(path.read_text(encoding="utf-8-sig").splitlines(), 1):
        if "/*" in raw: block_comment = True
        if block_comment:
            if "*/" in raw: block_comment = False
            continue
        line = raw.split("//", 1)[0].strip()
        if not line: continue
        if line.startswith("public function CreateThawMoves") or re.match(r"private function Create(?:Fire|Electric|Normal|Passive|Earth|Undead|Dino|Grass|Water|Ice|Demon|Flying|Holy|Robot|Titan)Moves", line):
            in_content = True
            resolver.arrays = {}
            active = None
            active_name = ""
            continue
        if line.startswith("private function PassiveCM"):
            in_content = False
        if not in_content: continue
        local_match = MOVE_LOCAL_RE.search(line)
        if local_match:
            active_name = local_match.group(1)
            continue
        state_match = STATE_RE.fullmatch(line)
        if state_match:
            name, expression = state_match.groups()
            if name not in STATE_NAMES: raise ImportProblem(path, line_number, line, "unsupported move-construction state")
            resolver.state[name] = resolver.resolve(expression, line_number)
            continue
        array_match = ARRAY_RE.fullmatch(line)
        if array_match:
            name, expressions = array_match.groups()
            resolver.arrays[name] = [resolver.resolve(value, line_number) for value in split_arguments(expressions)]
            continue
        create_match = CREATE_RE.fullmatch(line)
        if create_match:
            variable, function, expressions = create_match.groups()
            if not active_name or variable != active_name:
                raise ImportProblem(path, line_number, line, "move construction uses an unexpected local variable")
            args = split_arguments(expressions)
            active = _create(function, args, active_name, active, resolver, constant_sets["MinionVisualMoveID"]["VISUALS_SameAsClass"], path, line_number)
            move_id = active["legacy_numeric_id"]
            if move_id in resolver.moves: raise ImportProblem(path, line_number, line, f"duplicate move value for legacy ID {move_id}")
            active["source"] = str(path)
            active["line"] = line_number
            resolver.moves[move_id] = active
            continue
        property_match = PROPERTY_RE.fullmatch(line)
        if property_match:
            if active is None: raise ImportProblem(path, line_number, line, "move property assignment without active move")
            variable, source_name, expression = property_match.groups()
            if variable != active_name: raise ImportProblem(path, line_number, line, "move property uses an unexpected local variable")
            if source_name not in PROPERTY_MAP: raise ImportProblem(path, line_number, line, "unsupported move property")
            target = PROPERTY_MAP[source_name]
            value = resolver.resolve(expression, line_number)
            if target in INT_FIELDS: value = as_int(value)
            elif target in BOOL_FIELDS:
                if not isinstance(value, bool): raise ImportProblem(path, line_number, expression, "Boolean property requires Boolean value")
            elif target == "icon":
                _set_icon(active, value)
                continue
            active[target] = value
            continue
        method_match = METHOD_RE.fullmatch(line)
        if method_match:
            if active is None: raise ImportProblem(path, line_number, line, "move method call without active move")
            variable, method, expressions = method_match.groups()
            if variable != active_name: raise ImportProblem(path, line_number, line, "move method uses an unexpected local variable")
            values = [resolver.resolve(value, line_number) for value in split_arguments(expressions)]
            if method in ("AddStatToBuff", "AddStatToDeBuff"):
                if len(values) != 1: raise ImportProblem(path, line_number, line, f"{method} requires one argument")
                active["buff_stats" if method == "AddStatToBuff" else "debuff_stats"].append(as_int(values[0]))
            else:
                if not 1 <= len(values) <= 5: raise ImportProblem(path, line_number, line, f"{method} requires 1 to 5 arguments")
                values += [False, False, 1, 100][len(values) - 1:]
                stat, targets, self_target, stages, chance = values
                prefix = "debuff" if "DeBuff" in method else "buff"
                active[f"{prefix}_stats"].append(as_int(stat))
                active[f"{prefix}_targets"] = bool(targets)
                active[f"{prefix}_self"] = bool(self_target)
                active[f"{prefix}_stages"] = -as_int(stages) if prefix == "debuff" else as_int(stages)
                active[f"{prefix}_chance"] = as_int(chance)
            continue
        if re.match(r"_loc\d+_\.", line) or re.match(r"_loc\d+_\s*=\s*this\.", line) or line.startswith("this.m_curr") or "new Array(" in line:
            raise ImportProblem(path, line_number, line, "unrecognized move-construction statement")

    results, missing = [], []
    for legacy_id, identity in sorted(identities.items()):
        move = resolver.moves.get(legacy_id)
        if move is None:
            missing.append(identity)
            continue
        move["id"] = identity["id"]
        move["family_id"] = identity["family_id"]
        move["tier"] = identity["tier"]
        type_name = next((name for name, value in constant_sets["MinionType"].items() if value == move["type"]), None)
        if type_name is None and move["type"] == 15: type_name = "TYPE_THAW"
        if type_name is None: raise ImportProblem(path, move["line"], str(move["type"]), "move has unknown type ID")
        move["type_id"] = f'base:type/{type_name.removeprefix("TYPE_").lower()}' if type_name != "TYPE_THAW" else "ice_floor:type/thaw"
        stat_names = {value: f'base:stat/{name.removeprefix("STAT_").lower()}' for name, value in constant_sets["StatType"].items()}
        move["effects"] = normalize_effects(move, stat_names)
        results.append(move)
    for legacy_id in resolver.moves.keys() - identities.keys():
        raise ImportProblem(path, resolver.moves[legacy_id]["line"], str(legacy_id), "constructed move has no declared identity")
    return results, missing


def comparable(move: dict) -> dict:
    """Remove provenance-only fields for edited-source/compiled-SWF comparison."""
    return {key: value for key, value in move.items() if key not in ("source", "line")}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("source_directory", type=Path)
    parser.add_argument("output_directory", type=Path)
    parser.add_argument("--compiled-directory", type=Path)
    args = parser.parse_args()
    output = args.output_directory.resolve()
    if output.exists() and any(output.iterdir()): raise SystemExit(f"refusing to overwrite non-empty staged output: {output}")
    output.mkdir(parents=True, exist_ok=True)
    try:
        moves, missing = import_moves(args.source_directory.resolve() / "scripts")
    except (ImportProblem, TypeError) as problem:
        payload = problem.as_dict() if isinstance(problem, ImportProblem) else {"message": str(problem)}
        (output / "import_errors.json").write_text(json.dumps([payload], indent=2), encoding="utf-8")
        print(json.dumps(payload, indent=2))
        return 1
    unexpected_missing = [entry for entry in missing if entry["legacy_numeric_id"] not in EXPECTED_UNCONSTRUCTED_IDS]
    unexpected_present = sorted(EXPECTED_UNCONSTRUCTED_IDS & {move["legacy_numeric_id"] for move in moves})
    comparison_errors = []
    if args.compiled_directory:
        try:
            compiled_moves, compiled_missing = import_moves(args.compiled_directory.resolve() / "scripts")
            edited_values = {move["legacy_numeric_id"]: comparable(move) for move in moves}
            compiled_values = {move["legacy_numeric_id"]: comparable(move) for move in compiled_moves}
            for legacy_id in sorted(edited_values.keys() | compiled_values.keys()):
                if edited_values.get(legacy_id) != compiled_values.get(legacy_id):
                    comparison_errors.append({"legacy_numeric_id": legacy_id, "message": "edited source differs from compiled SWF"})
            if [entry["legacy_numeric_id"] for entry in missing] != [entry["legacy_numeric_id"] for entry in compiled_missing]:
                comparison_errors.append({"message": "edited and compiled sources have different unconstructed identities"})
        except (ImportProblem, TypeError) as problem:
            comparison_errors.append(problem.as_dict() if isinstance(problem, ImportProblem) else {"message": str(problem)})
    (output / "moves.json").write_text(json.dumps(moves, indent=2), encoding="utf-8")
    (output / "unconstructed_move_identities.json").write_text(json.dumps(missing, indent=2), encoding="utf-8")
    errors = []
    if unexpected_missing: errors.append({"message": "unexpected declared moves have no constructed values", "moves": unexpected_missing})
    if unexpected_present: errors.append({"message": "expected tombstone move IDs were unexpectedly constructed", "legacy_numeric_ids": unexpected_present})
    errors.extend(comparison_errors)
    if errors: (output / "import_errors.json").write_text(json.dumps(errors, indent=2), encoding="utf-8")
    report = {"declared_move_count": len(moves) + len(missing), "parsed_move_count": len(moves),
              "unconstructed_identity_count": len(missing), "compiled_comparison_performed": args.compiled_directory is not None,
              "compiled_difference_count": len(comparison_errors), "error_count": len(errors), "accepted": not errors}
    (output / "import_report.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps(report, indent=2))
    return 0 if not errors else 1


if __name__ == "__main__":
    raise SystemExit(main())
