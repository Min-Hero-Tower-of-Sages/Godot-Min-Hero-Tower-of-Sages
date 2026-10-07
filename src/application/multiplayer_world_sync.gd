class_name MultiplayerWorldSync
extends RefCounted

## Splits a CampaignState into the host-owned shared "world" and the fields each
## player keeps for themselves, and merges concurrent world edits as deltas.
##
## Shared (host world): tower progress, keys, seals, doors, eggs, encounter
## completion and star ratings (so the earned-star total is shared), room
## state and the minion storage.
## Personal: party, gems, money, star upgrades (spent from the shared total),
## tutorials, minion-pedia history and the player's own position. A guest's
## personal part is its "profile", which the host keeps per username.

const PERSONAL_PROGRESSION_KEYS := [
	"currency",
	"star_upgrades",
	"gem_inventory_slots",
	"gem_shop_stock",
	"gem_shop_refresh_count",
	"gem_instance_sequence",
	"seen_minion_ids",
	"owned_minion_ids",
	"deaths_since_victory",
	"previous_region_music",
	"lobby_titan_sequence",
	"eggery_pick_sequence",
	# Identifies the host's world for its guest-profile file; never shared.
	"multiplayer_world_id",
]
## Personal progression a guest may bring from their own save on first join.
## Star upgrades stay behind: they are bought from the host world's stars.
const IMPORTED_PROGRESSION_KEYS := [
	"currency",
	"gem_inventory_slots",
	"gem_instance_sequence",
	"seen_minion_ids",
	"owned_minion_ids",
]
const PROFILE_BATTLE_ID_LIMIT := 64
## room_state keys that describe one player rather than the shared room.
const PERSONAL_ROOM_STATE_KEYS := ["current_location", "current_room_id"]

static func is_personal_progression_key(key: String) -> bool:
	return key in PERSONAL_PROGRESSION_KEYS or key.ends_with("_seen")

## Host world snapshot, transportable over the network (plain Variants only).
static func extract_world(state) -> Dictionary:
	var progression: Dictionary = {}
	for key in state.progression:
		if not is_personal_progression_key(String(key)):
			progression[String(key)] = _copy(state.progression[key])
	var room_state: Dictionary = {}
	for key in state.room_state:
		if String(key) not in PERSONAL_ROOM_STATE_KEYS:
			room_state[String(key)] = _copy(state.room_state[key])
	var storage: Array = []
	for owned in state.storage:
		storage.append(owned.to_dictionary())
	return {
		"current_room_id": String(state.current_room_id),
		"progression": progression,
		"room_state": room_state,
		"storage": storage,
	}

## The part of the world that clients may edit through ordinary play. Room
## choice and storage use their own host-arbitrated messages instead.
static func editable_world(world: Dictionary) -> Dictionary:
	return {"progression": world.get("progression", {}), "room_state": world.get("room_state", {})}

## Replace the world portion of `state` with `world`, keeping personal fields.
## Storage IDs that collide with this player's party are renamed locally so
## campaign validation (unique instance IDs) keeps passing. `apply_room` is
## false in co-op, where each player walks their own rooms.
static func apply_world(state, world: Dictionary, apply_storage: bool = true, apply_room: bool = true) -> void:
	var progression: Dictionary = {}
	for key in state.progression:
		if is_personal_progression_key(String(key)):
			progression[key] = state.progression[key]
	for key in world.get("progression", {}):
		progression[key] = _copy(world.progression[key])
	state.progression = progression
	var room_state: Dictionary = {}
	for key in PERSONAL_ROOM_STATE_KEYS:
		if state.room_state.has(key):
			room_state[key] = state.room_state[key]
	for key in world.get("room_state", {}):
		room_state[key] = _copy(world.room_state[key])
	state.room_state = room_state
	var room_id := StringName(world.get("current_room_id", ""))
	if apply_room and not room_id.is_empty():
		state.current_room_id = room_id
		state.room_state["current_room_id"] = String(room_id)
	if apply_storage and world.has("storage"):
		state.storage.clear()
		var party_ids: Dictionary = {}
		for owned in state.party:
			party_ids[String(owned.instance_id)] = true
		for raw in world.storage:
			if not raw is Dictionary:
				continue
			var owned = OwnedMinionState.from_dictionary(raw)
			while party_ids.has(String(owned.instance_id)):
				owned.instance_id = StringName("%s@shared" % String(owned.instance_id))
			party_ids[String(owned.instance_id)] = true
			state.storage.append(owned)

# --- Guest profiles ---------------------------------------------------------------------
# A profile is everything one guest owns inside a host's world: character,
# party, gems and personal progression. The host keeps one per username so a
# returning guest gets their team back, independent of their own solo saves.

static func extract_profile(state) -> Dictionary:
	var progression: Dictionary = {}
	for key in state.progression:
		if is_personal_progression_key(String(key)) and String(key) != "multiplayer_world_id":
			progression[String(key)] = _copy(state.progression[key])
	var party: Array = []
	for owned in state.party:
		party.append(owned.to_dictionary())
	var battle_ids: Array = state.applied_battle_ids.slice(maxi(0, state.applied_battle_ids.size() - PROFILE_BATTLE_ID_LIMIT))
	return {
		"character": state.character.duplicate(true),
		"party": party,
		"owned_gems": _copy(state.owned_gems),
		"progression": progression,
		"active_mods": state.active_mods.duplicate(true),
		"battle_sequence": state.battle_sequence,
		"applied_battle_ids": battle_ids,
	}

## First join with a team brought from the guest's own save (a raw save dict).
## Minion IDs get the profile prefix so they never collide in shared storage.
static func profile_from_save(save: Dictionary, id_prefix: String) -> Dictionary:
	var party: Array = []
	var renamed: Dictionary = {}
	for raw in save.get("party", []):
		if raw is Dictionary:
			var copy: Dictionary = raw.duplicate(true)
			copy["instance_id"] = "%s%s" % [id_prefix, String(copy.get("instance_id", ""))]
			party.append(copy)
	var progression: Dictionary = {}
	var source: Dictionary = save.get("progression", {})
	for key in source:
		if String(key) in IMPORTED_PROGRESSION_KEYS or String(key).ends_with("_seen"):
			progression[String(key)] = _copy(source[key])
	var gems: Array = []
	for gem in save.get("owned_gems", []):
		if gem is Dictionary:
			gems.append(gem.duplicate(true))
	return {
		"character": (save.get("character", {}) as Dictionary).duplicate(true),
		"party": party,
		"owned_gems": gems,
		"progression": progression,
		"active_mods": {},
		"battle_sequence": 0,
		"applied_battle_ids": [],
	}

## First join without bringing a team: the same starters as a new campaign.
static func fresh_profile(catalog: ContentCatalog, character: Dictionary, id_prefix: String) -> Dictionary:
	var party: Array = []
	for owned in CampaignProgressionService.starter_party(catalog, id_prefix):
		party.append(owned.to_dictionary())
	return {
		"character": character.duplicate(true),
		"party": party,
		"owned_gems": [],
		"progression": {},
		"active_mods": {},
		"battle_sequence": 0,
		"applied_battle_ids": [],
	}

## A complete save-shaped state for a guest: the host's world (without its
## storage, applied separately so colliding IDs are renamed) around the
## guest's profile, standing where the host stands.
static func guest_state_payload(host_state: Dictionary, profile: Dictionary) -> Dictionary:
	var data := host_state.duplicate(true)
	var progression: Dictionary = {}
	for key in host_state.get("progression", {}):
		if not is_personal_progression_key(String(key)):
			progression[key] = _copy(host_state.progression[key])
	for key in profile.get("progression", {}):
		progression[key] = _copy(profile.progression[key])
	data["progression"] = progression
	data["character"] = (profile.get("character", {}) as Dictionary).duplicate(true)
	data["party"] = _copy(profile.get("party", []))
	data["owned_gems"] = _copy(profile.get("owned_gems", []))
	data["storage"] = []
	data["active_mods"] = (profile.get("active_mods", {}) as Dictionary).duplicate(true)
	data["pending_mods"] = {}
	data["pending_battle"] = {}
	data["pending_defeat_return"] = {}
	data["last_battle_result"] = {}
	data["battle_sequence"] = int(profile.get("battle_sequence", 0))
	data["applied_battle_ids"] = _copy(profile.get("applied_battle_ids", []))
	return data

## Versus: a brand-new run of the campaign around a profile (team, gems,
## money, tutorials). Everyone in a race gets the same chest seed, so the
## tower hands out the same treasure to every racer.
static func race_state_payload(catalog: ContentCatalog, campaign_id: StringName, profile: Dictionary, chest_seed: int, content_version: String) -> Dictionary:
	var campaign := catalog.get_definition(campaign_id) as CampaignDefinition
	var room := catalog.get_definition(campaign.starting_room_id) as RoomDefinition if campaign != null else null
	if room == null:
		return {}
	var spawn_id := String(room.spawn_ids[0]) if not room.spawn_ids.is_empty() else ""
	var position: Vector2 = room.spawn_positions.get(spawn_id, Vector2.ZERO)
	var state := CampaignState.new()
	state.campaign_id = campaign_id
	state.current_room_id = room.id
	state.progression["eggery_picks_remaining"] = 1
	state.progression["chest_seed"] = chest_seed
	state.room_state = {"current_room_id": String(room.id), "flags": {}, "current_location": {"room_id": String(room.id), "spawn_id": spawn_id, "position": [position.x, position.y], "facing": String(room.spawn_directions.get(spawn_id, ""))}}
	state.safe_location = {"room_id": String(room.id), "spawn_id": spawn_id, "position": position}
	var data := state.to_dictionary(content_version)
	for key in profile.get("progression", {}):
		data.progression[key] = _copy(profile.progression[key])
	data["character"] = (profile.get("character", {}) as Dictionary).duplicate(true)
	data["party"] = _copy(profile.get("party", []))
	data["owned_gems"] = _copy(profile.get("owned_gems", []))
	return data

## Build a delta that turns `before` into `after`. Numbers carry their
## difference, so two players spending keys at once both count.
static func diff(before: Variant, after: Variant) -> Variant:
	if before is Dictionary and after is Dictionary:
		var changes: Dictionary = {}
		for key in after:
			if not before.has(key):
				changes[key] = {"set": _copy(after[key])}
				continue
			var nested: Variant = diff(before[key], after[key])
			if nested != null:
				changes[key] = nested
		for key in before:
			if not after.has(key):
				changes[key] = {"erase": true}
		return {"dict": changes} if not changes.is_empty() else null
	if _is_number(before) and _is_number(after):
		if before == after:
			return null
		# JSON saves decode integers as floats; whole numbers are still counters.
		if float(before) == floorf(float(before)) and float(after) == floorf(float(after)):
			return {"add": int(after) - int(before)}
		return {"set": after}
	if before is Array and after is Array:
		if before == after:
			return null
		var added: Array = []
		var removed: Array = []
		for value in after:
			if value not in before: added.append(_copy(value))
		for value in before:
			if value not in after: removed.append(_copy(value))
		return {"union": added, "remove": removed}
	if typeof(before) == typeof(after) and before == after:
		return null
	return {"set": _copy(after)}

## Apply a delta produced by diff() onto `target` and return the merged value.
static func merge(target: Variant, delta: Variant) -> Variant:
	if not delta is Dictionary:
		return target
	if delta.has("dict"):
		var result: Dictionary = (target as Dictionary).duplicate(true) if target is Dictionary else {}
		for key in delta.dict:
			var change: Dictionary = delta.dict[key]
			if change.has("erase"):
				result.erase(key)
			else:
				result[key] = merge(result.get(key), change)
		return result
	if delta.has("add"):
		return (int(target) if _is_number(target) else 0) + int(delta.add)
	if delta.has("union"):
		var result: Array = (target as Array).duplicate(true) if target is Array else []
		for value in delta.get("remove", []):
			result.erase(value)
		for value in delta.union:
			if value not in result: result.append(value)
		return result
	if delta.has("set"):
		if target is Dictionary and delta.set is Dictionary:
			return merge(target, diff(target, delta.set))
		return _copy(delta.set)
	return target

## Deterministic content hash for change detection and desync checks.
static func fingerprint(value: Variant) -> int:
	return hash(var_to_bytes(value))

static func _is_number(value: Variant) -> bool:
	return value is int or value is float

static func _copy(value: Variant) -> Variant:
	if value is Dictionary or value is Array:
		return value.duplicate(true)
	return value
