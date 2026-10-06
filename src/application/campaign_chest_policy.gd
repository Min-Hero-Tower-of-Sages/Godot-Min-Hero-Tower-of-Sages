class_name CampaignChestPolicy
extends RefCounted

## BaseTopDownLevel.AddObject: gold requires one seal, gem requires four;
## source rolls Math.random()*100 > 50 / > 70 once when objects are created.
## Keep a campaign's roll stable across room reconstruction and saved reloads.
static func required_seals(kind: String) -> int:
	return 4 if kind == "gem" else 1

static func spawn_chance(kind: String) -> float:
	return 0.3 if kind == "gem" else 0.5

static func spawned(room_id: StringName, kind: String, source_index: int, progression: Dictionary) -> bool:
	if kind not in ["gold", "gem"] or int(progression.get("sage_seals", 0)) < required_seals(kind):
		return false
	var seed_text := "%s:%s:%d" % [String(room_id), kind, source_index]
	# Old saves retain their established room/object rolls; new saves receive
	# a seed so independent campaigns no longer all spawn the same chests.
	if progression.has("chest_seed"):
		seed_text += ":%d" % int(progression.chest_seed)
	var rng := RandomNumberGenerator.new()
	rng.seed = absi(hash(seed_text))
	return rng.randf() < spawn_chance(kind)
