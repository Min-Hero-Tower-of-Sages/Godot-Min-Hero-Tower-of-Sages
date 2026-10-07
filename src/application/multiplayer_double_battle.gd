class_name MultiplayerDoubleBattle
extends RefCounted

## Duo double battle: both players fight one trainer together. The player who
## touched the trainer runs the campaign battle; the partner's party joins
## team 0 and the trainer's team is duplicated, so it stays a fair 2-on-"2".
##
## Layout: when both sides still fit the normal five places, the new minions
## take the free slots. Otherwise the whole battle switches to the ten-place
## layout (BattleCombatantView.double_anchor): slots 0-4 (front) for the
## starting player or the original enemies, 5-9 for the partner or the copies.

const ALLY_PREFIX := "ally:"
const ENEMY_COPY_SUFFIX := "#2"
const SLOTS_PER_PLAYER := 5

## Returns {"setup", "actor_controllers", "double_teams"}: the battle setup with
## the partner's team and the enemy copies added, which combatants the partner
## controls, and which teams need the ten-place layout.
static func build_setup(setup: Dictionary, ally_team: Array, ally_peer: int) -> Dictionary:
	var result := setup.duplicate(true)
	var combatants: Array = result.get("combatants", [])
	var leaders: Array = combatants.filter(func(entry: Dictionary) -> bool: return int(entry.get("team", 0)) == 0)
	var enemies: Array = combatants.filter(func(entry: Dictionary) -> bool: return int(entry.get("team", 0)) == 1)
	var controllers: Dictionary = {}
	var allies: Array = []
	for index in mini(ally_team.size(), SLOTS_PER_PLAYER):
		var ally: Dictionary = (ally_team[index] as Dictionary).duplicate(true)
		ally["team"] = 0
		ally["instance_id"] = ALLY_PREFIX + String(ally.get("instance_id", ""))
		controllers[String(ally.instance_id)] = ally_peer
		allies.append(ally)
	var copies: Array = []
	for enemy in enemies:
		var copy: Dictionary = (enemy as Dictionary).duplicate(true)
		copy["instance_id"] = String(copy.get("instance_id", "")) + ENEMY_COPY_SUFFIX
		copies.append(copy)
	var double_teams: Array = []
	if not _fill_free_slots(leaders, allies):
		double_teams.append(0)
	if not _fill_free_slots(enemies, copies):
		double_teams.append(1)
	if not double_teams.is_empty():
		# One scale for the whole battlefield; a small side keeps the front column.
		double_teams = [0, 1]
	combatants.append_array(allies)
	combatants.append_array(copies)
	result["combatants"] = combatants
	return {"setup": result, "actor_controllers": controllers, "double_teams": double_teams}

## Give `added` the free normal slots beside `existing`. When they do not fit,
## move everyone to the ten-place layout instead and return false.
static func _fill_free_slots(existing: Array, added: Array) -> bool:
	var used: Dictionary = {}
	for entry in existing:
		used[int(entry.get("slot_index", 0))] = true
	if existing.size() + added.size() <= SLOTS_PER_PLAYER:
		var slot := 0
		for entry in added:
			while used.has(slot):
				slot += 1
			entry["slot_index"] = slot
			used[slot] = true
		return true
	# Each newcomer stands behind the matching original, then any free column.
	var back: Array[int] = []
	for entry in existing:
		back.append(int(entry.get("slot_index", 0)))
	for slot in SLOTS_PER_PLAYER:
		if slot not in back:
			back.append(slot)
	for index in added.size():
		added[index]["slot_index"] = SLOTS_PER_PLAYER + back[index]
	return false
