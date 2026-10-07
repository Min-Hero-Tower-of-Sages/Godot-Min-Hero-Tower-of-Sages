class_name BattleReplay
extends RefCounted

## A battle as a replay: the engine is deterministic (seeded BattleRng, no
## clock), so `setup + rules + seed` plus the human commands in order rebuild
## the whole fight. AI turns are not stored; they are recomputed on playback,
## exactly like multiplayer lockstep. Each command keeps a fingerprint of the
## engine state it was chosen in, so playback can tell when a newer build no
## longer reproduces the recording.
##
## A replay travels as a share code: "MHR1-" + base64(deflate(var_to_bytes)).
## Decoding never creates objects and every field is type-checked; the engine
## then validates every command like any other submission.

const FORMAT := 1
const CODE_PREFIX := "MHR1-"
## Decompressed size limit for pasted codes (a five-a-side replay is ~10 KB).
const MAX_DECODED_BYTES := 1 << 22
const MAX_COMMANDS := 4000
static var _BASE64 := RegEx.create_from_string("^[A-Za-z0-9+/]+={0,2}$")

## Practice/showcase battles reuse the playable demo packs; replays need them too.
const EXTRA_PACKS := [
	preload("res://content/base/packs/battle_demo.tres"),
	preload("res://content/base/packs/campaign_slice.tres"),
]

## A new recording. `rules` is the wire form {id, display_name, party_size,
## configuration}; `names` maps engine team -> display name; `pov` is the
## team the recorder fought for (or watched from), shown on the left.
static func create(kind: String, battle_seed: int, setup: Dictionary, rules: Dictionary, names: Dictionary, pov: int, extras: Dictionary = {}) -> Dictionary:
	var replay := {
		"v": FORMAT,
		"kind": kind,
		"seed": battle_seed,
		"setup": bytes_to_var(var_to_bytes(setup)),
		"rules": bytes_to_var(var_to_bytes(rules)),
		"names": names.duplicate(true),
		"pov": pov,
		"commands": [],
		"result": {},
		"recorded_at": int(Time.get_unix_time_from_system()),
	}
	for key in ["content", "encounter_id", "floor", "double_teams", "role"]:
		if extras.has(key):
			replay[key] = extras[key]
	return replay

## Append an accepted command. `pre_snapshot` is the engine state it was chosen in.
static func record_command(replay: Dictionary, command: BattleCommand, pre_snapshot: Dictionary) -> void:
	var targets: Array = []
	for target_id in command.target_ids:
		targets.append(String(target_id))
	(replay.commands as Array).append({
		"r": command.expected_revision,
		"a": String(command.actor_id),
		"k": "f" if command.kind == BattleCommand.Kind.FORFEIT else "m",
		"m": String(command.move_id),
		"t": targets,
		"c": state_check(pre_snapshot),
	})

## 16 bits of the state fingerprint: enough to notice a replay drifting, and
## small enough to keep share codes short (full hashes do not compress).
static func state_check(snapshot: Dictionary) -> int:
	return (MultiplayerWorldSync.fingerprint(snapshot) & 0xFFFF) | 0x10000

static func record_result(replay: Dictionary, result: BattleResult, turns: int) -> void:
	replay["result"] = {"winner": result.winning_team, "reason": String(result.reason), "rounds": result.rounds, "turns": turns}

static func to_command(entry: Dictionary) -> BattleCommand:
	var targets: Array[StringName] = []
	for raw_id in entry.get("t", []):
		targets.append(StringName(raw_id))
	var kind := BattleCommand.Kind.FORFEIT if String(entry.get("k", "m")) == "f" else BattleCommand.Kind.USE_MOVE
	return BattleCommand.new(StringName(entry.get("a", "")), kind, StringName(entry.get("m", "")), targets, int(entry.get("r", -1)))

## The ruleset a replay (or a published network battle spec) was played under.
static func make_rules(rule_data: Dictionary) -> RuleSetDefinition:
	var rules := RuleSetDefinition.new()
	rules.id = StringName(rule_data.get("id", "base:rules/replay"))
	rules.display_name = String(rule_data.get("display_name", "Battle replay"))
	rules.party_size = int(rule_data.get("party_size", 5))
	rules.configuration = (rule_data.get("configuration", {}) as Dictionary).duplicate(true)
	return rules

static func ensure_packs(catalog: ContentCatalog) -> void:
	for required_pack in EXTRA_PACKS:
		var loaded := false
		for pack in catalog.packs:
			if pack != null and pack.id == required_pack.id:
				loaded = true
				break
		if not loaded:
			catalog.packs.append(required_pack)

# --- Share codes -----------------------------------------------------------------------------

static func encode(replay: Dictionary) -> String:
	var raw := var_to_bytes(replay)
	return CODE_PREFIX + Marshalls.raw_to_base64(raw.compress(FileAccess.COMPRESSION_DEFLATE))

## {"ok": true, "replay": {...}} or {"ok": false, "message": "..."}. Accepts
## codes broken over several lines or wrapped in quotes/backticks by chat apps.
static func decode(code: String) -> Dictionary:
	var compact := ""
	for part in code.strip_edges().split("\n"):
		compact += part.strip_edges()
	compact = compact.lstrip("`\"'").rstrip("`\"'").replace(" ", "")
	if not compact.begins_with(CODE_PREFIX):
		return _bad("That isn't a battle replay code (they start with %s)." % CODE_PREFIX)
	var body := compact.trim_prefix(CODE_PREFIX)
	if body.length() % 4 != 0 or not _BASE64.search(body):
		return _bad("The replay code is incomplete or damaged. Copy all of it.")
	var packed := Marshalls.base64_to_raw(body)
	if packed.is_empty():
		return _bad("The replay code is incomplete. Copy all of it.")
	var raw := packed.decompress_dynamic(MAX_DECODED_BYTES, FileAccess.COMPRESSION_DEFLATE)
	if raw.is_empty():
		return _bad("The replay code is damaged. Copy all of it.")
	var value: Variant = bytes_to_var(raw)
	return validate(value)

## Shape check for anything read from a code or a history file.
static func validate(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return _bad("The replay code is damaged.")
	var replay: Dictionary = value
	if int(replay.get("v", 0)) > FORMAT:
		return _bad("This replay comes from a newer version of the game.")
	if not replay.get("setup") is Dictionary or not replay.get("rules") is Dictionary or not replay.get("commands") is Array:
		return _bad("The replay code is damaged.")
	if not replay.get("seed") is int or not replay.get("names", {}) is Dictionary or not replay.get("result", {}) is Dictionary:
		return _bad("The replay code is damaged.")
	if not (replay.rules as Dictionary).get("configuration", {}) is Dictionary or not (replay.setup as Dictionary).get("combatants", []) is Array:
		return _bad("The replay code is damaged.")
	if (replay.commands as Array).size() > MAX_COMMANDS:
		return _bad("This replay is too long.")
	for entry in replay.commands:
		if not entry is Dictionary or not entry.get("r") is int or not entry.get("t", []) is Array:
			return _bad("The replay code is damaged.")
	return {"ok": true, "replay": replay}

static func _bad(message: String) -> Dictionary:
	return {"ok": false, "message": message}

# --- Headless playback -----------------------------------------------------------------------

## Re-run the whole battle without presentation. Returns
## {"ok", "result": BattleResult or null, "played": commands used, "drift": first
## command whose fingerprint disagreed (-1 if none), "message"}.
static func simulate(replay: Dictionary, catalog: ContentCatalog, max_steps: int = 5000) -> Dictionary:
	ensure_packs(catalog)
	var controller := BattleController.new()
	var started := controller.start((replay.setup as Dictionary).duplicate(true), catalog, make_rules(replay.rules), BattleRng.new(int(replay.seed)))
	if not started.accepted:
		return {"ok": false, "result": null, "played": 0, "drift": -1, "message": "The battle could not start: %s" % started.message}
	var ai_teams: Array = (replay.rules.get("configuration", {}) as Dictionary).get("ai_teams", [])
	var commands: Array = replay.commands
	var cursor := 0
	var drift := -1
	var steps := 0
	while controller.engine.get_result().is_empty() and steps < max_steps:
		steps += 1
		var decision := controller.engine.get_decision()
		if decision.is_empty():
			break
		if int(decision.team) in ai_teams:
			controller.submit_ai_turn()
			continue
		if cursor >= commands.size():
			break # Recorded before the battle ended.
		var entry: Dictionary = commands[cursor]
		if drift < 0 and int(entry.get("c", 0)) != 0 and state_check(controller.engine.snapshot()) != int(entry.c):
			drift = cursor
		var response := controller.submit(to_command(entry))
		if not response.accepted:
			return {"ok": false, "result": null, "played": cursor, "drift": cursor, "message": "This replay no longer matches the game (turn %d)." % (cursor + 1)}
		cursor += 1
	var result = controller.engine.get_result()
	return {"ok": true, "result": null if result.is_empty() else result, "played": cursor, "drift": drift, "message": ""}

# --- Display ---------------------------------------------------------------------------------

static func team_name(replay: Dictionary, team: int) -> String:
	var names: Dictionary = replay.get("names", {})
	return String(names.get(team, names.get(str(team), "Team %d" % (team + 1))))

static func title(replay: Dictionary) -> String:
	var pov := int(replay.get("pov", 0))
	return "%s vs %s" % [team_name(replay, pov), team_name(replay, 1 - pov)]

## "Victory", "Defeat", "Forfeited", "Unfinished", or "<name> won" for watched fights.
static func outcome(replay: Dictionary) -> String:
	var result: Dictionary = replay.get("result", {})
	if result.is_empty():
		return "Unfinished"
	var winner := int(result.get("winner", -1))
	var pov := int(replay.get("pov", 0))
	if String(replay.get("role", "fighter")) == "watcher":
		return "%s won" % team_name(replay, winner)
	if String(result.get("reason", "")) == "forfeit" and winner != pov:
		return "Forfeited"
	return "Victory" if winner == pov else "Defeat"

static func kind_label(replay: Dictionary) -> String:
	match String(replay.get("kind", "")):
		"pvp": return "Arena"
		"double": return "Double"
		"practice": return "Practice"
	var floor_index := int(replay.get("floor", -1))
	return "Floor %d" % (floor_index + 1) if floor_index >= 0 else "Trainer"

static func turn_count(replay: Dictionary) -> int:
	return int((replay.get("result", {}) as Dictionary).get("turns", (replay.get("commands", []) as Array).size()))
