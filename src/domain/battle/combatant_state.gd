class_name CombatantState
extends RefCounted

var instance_id: StringName
var definition_id: StringName
var team: int
var slot_index: int = 0
var level: int = 1
var type_ids: Array[StringName] = []
var move_ids: Array[StringName] = []
var battle_bonus_global_move_ids: Array[StringName] = []
var max_health: int
var base_max_health: int
var health: int
var max_energy: int
var base_max_energy: int
var energy: int
var attack: int
var healing: int
var speed: int
var max_attack_stat: float
var max_healing_stat: float
## Native source formulas cast only AFTER passive/stage scaling. Explicit
## extension setups without these raw values keep their existing arithmetic.
var source_raw_stats: Dictionary = {}
var critical_chance: float = 6.25
var shield: int = 0
var max_shield: int = 0
var battle_mod_shield_active: bool = false
var statuses: Array[Dictionary] = []
var stat_stages: Dictionary = {}
var stunned: bool = false
var frozen: bool = false
var turns_frozen: int = 0
var current_exhaust: int = 0
var charge_move_id: StringName = &""
var charge_target_ids: Array[StringName] = []
var current_charge: int = 0
var cooldowns: Dictionary = {}
var defeated: bool = false

static func from_setup(data: Dictionary) -> CombatantState:
	var state := CombatantState.new()
	state.instance_id = StringName(data.get("instance_id", ""))
	state.definition_id = StringName(data.get("definition_id", ""))
	state.team = int(data.get("team", 0))
	state.slot_index = int(data.get("slot_index", 0))
	state.level = int(data.get("level", 1))
	state.type_ids.assign(data.get("type_ids", []))
	state.move_ids.assign(data.get("move_ids", []))
	state.battle_bonus_global_move_ids.assign(data.get("battle_bonus_global_move_ids", []))
	state.max_health = int(data.get("max_health", 1))
	state.base_max_health = int(data.get("base_max_health", state.max_health))
	state.health = int(data.get("health", state.max_health))
	state.max_energy = int(data.get("max_energy", 0))
	state.base_max_energy = int(data.get("base_max_energy", state.max_energy))
	state.energy = int(data.get("energy", state.max_energy))
	state.attack = int(data.get("attack", 0))
	state.healing = int(data.get("healing", 0))
	state.speed = int(data.get("speed", 0))
	state.max_attack_stat = float(data.get("max_attack_stat", state.attack))
	state.max_healing_stat = float(data.get("max_healing_stat", state.healing))
	state.source_raw_stats = data.get("source_raw_stats", {}).duplicate(true)
	state.critical_chance = float(data.get("critical_chance", 6.25))
	state.battle_mod_shield_active = bool(data.get("battle_mod_shield_active", false))
	state.stunned = bool(data.get("stunned", false))
	state.frozen = bool(data.get("frozen", false))
	state.turns_frozen = int(data.get("turns_frozen", 0))
	state.current_exhaust = int(data.get("current_exhaust", 0))
	state.charge_move_id = StringName(data.get("charge_move_id", ""))
	state.charge_target_ids.assign(data.get("charge_target_ids", []))
	state.current_charge = int(data.get("current_charge", 0))
	return state

func to_dict() -> Dictionary:
	return {
		"instance_id": String(instance_id), "definition_id": String(definition_id), "team": team, "slot_index": slot_index,
		"level": level, "type_ids": type_ids.duplicate(),
		"move_ids": move_ids.duplicate(), "battle_bonus_global_move_ids": battle_bonus_global_move_ids.duplicate(), "max_health": max_health, "base_max_health": base_max_health, "health": health,
		"max_energy": max_energy, "base_max_energy": base_max_energy, "energy": energy, "attack": attack, "healing": healing,
		"max_attack_stat": max_attack_stat, "max_healing_stat": max_healing_stat,
		"source_raw_stats": source_raw_stats.duplicate(true),
		"speed": speed, "critical_chance": critical_chance, "shield": shield, "max_shield": max_shield, "battle_mod_shield_active": battle_mod_shield_active, "statuses": statuses.duplicate(true),
		"stat_stages": stat_stages.duplicate(true), "stunned": stunned, "frozen": frozen,
		"turns_frozen": turns_frozen, "current_exhaust": current_exhaust,
		"charge_move_id": String(charge_move_id), "charge_target_ids": charge_target_ids.duplicate(), "current_charge": current_charge,
		"cooldowns": cooldowns.duplicate(true), "defeated": defeated
	}

static func from_snapshot(data: Dictionary) -> CombatantState:
	var state := from_setup(data)
	state.shield = int(data.shield)
	state.max_shield = int(data.get("max_shield", state.shield))
	state.statuses.assign(data.statuses)
	state.stat_stages = data.get("stat_stages", {}).duplicate(true)
	state.stunned = bool(data.get("stunned", false))
	state.frozen = bool(data.get("frozen", false))
	state.turns_frozen = int(data.get("turns_frozen", 0))
	state.current_exhaust = int(data.get("current_exhaust", 0))
	state.charge_move_id = StringName(data.get("charge_move_id", ""))
	state.charge_target_ids.assign(data.get("charge_target_ids", []))
	state.current_charge = int(data.get("current_charge", 0))
	state.cooldowns = data.cooldowns.duplicate(true)
	state.defeated = bool(data.defeated)
	return state
