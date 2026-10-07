extends SceneTree

## Multiplayer building blocks without sockets: world split/merge, guest
## profiles (import, fresh start, kept team, redirected saves, forgetting),
## co-op rooms, versus race states, player caps, duo double battles (setup,
## lockstep, partner settlement, layout), the arena trigger, and lockstep
## determinism of a PvP battle.

const Sync = preload("res://src/application/multiplayer_world_sync.gd")

var failures: Array[String] = []
var checks := 0

class MemorySaveRepository extends SaveRepository:
	var saved: Dictionary = {}
	func save_slot(slot: int, payload: Dictionary) -> Dictionary:
		saved[slot] = payload.duplicate(true)
		return {"ok": true}
	func load_slot(slot: int) -> Dictionary:
		return {"ok": true, "state": saved[slot].duplicate(true)} if saved.has(slot) else {"ok": false, "code": "not_found"}

func _initialize() -> void:
	_run.call_deferred()

func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)

func _run() -> void:
	await process_frame
	var runtime := root.get_node("CampaignRuntime")
	var net := root.get_node("NetSession")
	_test_delta_merge()
	_test_world_split(runtime)
	_test_guest_profiles(net, runtime)
	_test_profile_store()
	_test_import_policy(net, runtime)
	_test_versus_and_caps(net, runtime)
	_test_double_battle(net, runtime)
	_test_pvp_lockstep(net, runtime)
	_test_lockstep_stress(net, runtime)
	await _test_arena_trigger(net, runtime)
	if failures.is_empty():
		print("PASS: %d multiplayer sync checks" % checks)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("FAIL: %d of %d multiplayer sync checks" % [failures.size(), checks])
	quit(1)

func _test_delta_merge() -> void:
	var before := {"floor_keys": 2.0, "completed": {"a": true}, "taken": [1], "map_unlocked": false}
	var guest_after := {"floor_keys": 1.0, "completed": {"a": true, "b": true}, "taken": [1, 4], "map_unlocked": true}
	var host_now := {"floor_keys": 3, "completed": {"a": true, "c": true}, "taken": [1, 2], "map_unlocked": false}
	var merged: Dictionary = Sync.merge(host_now, Sync.diff(before, guest_after))
	_expect(int(merged.floor_keys) == 2, "a guest spending one key subtracts from the host's current count (got %s)" % merged.floor_keys)
	_expect(merged.completed.has("b") and merged.completed.has("c"), "concurrent encounter completions are both kept")
	_expect(1 in merged.taken and 2 in merged.taken and 4 in merged.taken, "egg slots taken by either player are unioned")
	_expect(bool(merged.map_unlocked), "a flag set by a guest reaches the host")
	_expect(Sync.diff(before, before.duplicate(true)) == null, "an unchanged world produces no delta")

func _make_state(runtime: Node, name: String, prefix: String):
	var state := CampaignState.new()
	state.campaign_id = &"base:campaign/standard_tower"
	state.current_room_id = &"base:room/level_1_1_a"
	state.character = {"name": name, "gender": "female"}
	for index in 3:
		var owned := OwnedMinionState.new()
		owned.instance_id = StringName("%s-%d" % [prefix, index])
		owned.definition_id = [&"base:minion/fire_pig_1", &"base:minion/tiger_1", &"base:minion/fire_pig_1"][index]
		owned.level = 6 + index * 3
		owned.experience = 0
		var definition := runtime.catalog.get_definition(owned.definition_id) as MinionDefinition
		owned.learned_move_ids.assign(definition.initial_move_ids)
		state.party.append(owned)
	return state

func _test_world_split(runtime: Node) -> void:
	var host = _make_state(runtime, "Host", "host")
	host.progression["currency"] = 500
	host.progression["floor_keys"] = 2
	host.progression["encounter_star_ratings"] = {"base:encounter/x": 3}
	host.progression["star_upgrades"] = {"health": 1}
	var stored := OwnedMinionState.new()
	stored.instance_id = &"guest-0" # Collides with the guest's own party member.
	stored.definition_id = &"base:minion/tiger_1"
	stored.level = 3
	host.storage.append(stored)
	var guest = _make_state(runtime, "Guest", "guest")
	guest.progression["currency"] = 40
	guest.progression["star_upgrades"] = {"speed": 2}
	guest.progression["move_select_tutorial_seen"] = true
	guest.room_state["current_location"] = {"room_id": "base:room/level_1_1_b", "position": [10, 20]}
	Sync.apply_world(guest, Sync.extract_world(host))
	_expect(int(guest.progression.currency) == 40, "money stays personal")
	_expect(guest.progression.star_upgrades == {"speed": 2}, "star upgrades stay personal")
	_expect(int(guest.progression.floor_keys) == 2, "keys come from the host world")
	_expect(guest.progression.encounter_star_ratings.has("base:encounter/x"), "earned stars are shared")
	_expect(bool(guest.progression.get("move_select_tutorial_seen", false)), "tutorial flags stay personal")
	_expect(guest.current_room_id == host.current_room_id, "the guest stands in the host's room")
	_expect(String(guest.room_state.current_location.room_id) == "base:room/level_1_1_b", "the guest keeps its own position record")
	_expect(guest.storage.size() == 1 and guest.storage[0].instance_id != &"guest-0", "colliding shared-storage IDs are renamed for the guest")
	_expect(guest.validation_errors(runtime.catalog).is_empty(), "a guest state with shared storage still validates: %s" % ", ".join(guest.validation_errors(runtime.catalog)))
	# Shared earned total, personal spending.
	guest.progression["encounter_star_ratings"] = {"a": 3, "b": 3, "c": 3, "d": 3, "e": 3, "f": 3, "g": 3}
	var available := CampaignProgressionService.available_stars(guest)
	_expect(CampaignProgressionService.total_earned_stars(guest) == 21, "earned stars count the shared ratings")
	_expect(available == maxi(0, 21 - CampaignProgressionService.spent_stars(guest)), "available stars = shared total minus own spending")

func _test_guest_profiles(net: Node, runtime: Node) -> void:
	var host = _make_state(runtime, "Host", "host")
	host.progression["floor_keys"] = 3
	host.progression["currency"] = 500
	host.progression["star_upgrades"] = {"health": 1}
	host.progression["multiplayer_world_id"] = "abc"
	host.current_room_id = &"base:room/level_1_1_c"
	var stored := OwnedMinionState.new()
	stored.instance_id = &"mp1-guest-0" # Collides with the imported guest party.
	stored.definition_id = &"base:minion/tiger_1"
	stored.level = 3
	host.storage.append(stored)
	# First join, bringing a team from the guest's own save.
	var own_save = _make_state(runtime, "Vala", "guest")
	own_save.progression["currency"] = 77
	own_save.progression["star_upgrades"] = {"speed": 4}
	own_save.progression["floor_keys"] = 9
	own_save.progression["move_select_tutorial_seen"] = true
	var imported: Dictionary = Sync.profile_from_save(own_save.to_dictionary("test"), "mp1-")
	_expect(imported.party.size() == 3 and String(imported.party[0].instance_id) == "mp1-guest-0", "imported minions get the profile prefix")
	_expect(int(imported.progression.get("currency", 0)) == 77, "money comes along on import")
	_expect(not imported.progression.has("star_upgrades"), "star upgrades stay behind (they are bought from the host world's stars)")
	_expect(not imported.progression.has("floor_keys"), "world progress from the guest's save is never imported")
	_expect(bool(imported.progression.get("move_select_tutorial_seen", false)), "tutorials already seen stay seen")
	var payload: Dictionary = Sync.guest_state_payload(host.to_dictionary("test"), imported)
	_expect(String(payload.current_room_id) == "base:room/level_1_1_c", "a guest starts in the host's room")
	_expect(int(payload.progression.floor_keys) == 3, "the guest state carries the host's world")
	_expect(not payload.progression.has("multiplayer_world_id"), "the host's world ID is not handed to guests")
	_expect(String(payload.character.name) == "Vala", "the guest keeps their character")
	# The guest plays it detached from every save slot.
	var repository := MemorySaveRepository.new()
	runtime.session.save_repository = repository
	var redirected: Array = []
	var loaded: Dictionary = runtime.load_detached_campaign(payload, net.GUEST_ID_SLOT_BASE + 1, func(data: Dictionary) -> Dictionary:
		redirected.append(data)
		return {"ok": true})
	_expect(loaded.ok, "the guest state loads detached: %s" % loaded.get("message", ""))
	var guest = runtime.session.state
	Sync.apply_world(guest, Sync.extract_world(host), true, false)
	_expect(guest.storage.size() == 1 and guest.storage[0].instance_id != &"mp1-guest-0", "shared storage colliding with the imported party is renamed")
	_expect(guest.validation_errors(runtime.catalog).is_empty(), "the guest state validates: %s" % ", ".join(guest.validation_errors(runtime.catalog)))
	guest.progression["currency"] = 999
	var saved: Dictionary = runtime.save_campaign()
	_expect(saved.ok and redirected.size() == 1, "guest saves go to the redirect")
	_expect(repository.saved.is_empty(), "a guest never writes its own save slots")
	var kept: Dictionary = Sync.extract_profile(guest)
	_expect(int(kept.progression.currency) == 999 and kept.party.size() == 3, "the kept profile has the money and team earned together")
	_expect(not kept.progression.has("floor_keys"), "the kept profile holds no world progress")
	# A returning player gets exactly the kept team.
	var back: Dictionary = Sync.guest_state_payload(host.to_dictionary("test"), kept)
	_expect(back.party == kept.party and int(back.progression.currency) == 999, "a returning username gets its team back")
	# Co-op: world updates keep the guest's own room.
	guest.current_room_id = &"base:room/level_1_1_a"
	Sync.apply_world(guest, Sync.extract_world(host), true, false)
	_expect(guest.current_room_id == &"base:room/level_1_1_a", "co-op world updates leave the guest in its own room")
	Sync.apply_world(guest, Sync.extract_world(host), true, true)
	_expect(guest.current_room_id == host.current_room_id, "follow-mode world updates move the guest to the host's room")
	# Fresh start: the new-campaign starters, numbered by the profile.
	var fresh: Dictionary = Sync.fresh_profile(runtime.catalog, {"name": "Newbie", "gender": "male"}, "slot-102-")
	_expect(fresh.party.size() == CampaignProgressionService.STARTERS.size(), "a fresh start gets the starter minions")
	_expect(String(fresh.party[0].instance_id).begins_with("slot-102-"), "fresh starters are numbered by profile, never colliding with the host's")
	runtime.session.state = null
	runtime.session.save_redirect = Callable()

const TRAINER_ROOM := &"base:room/level_1_1_a"
const TRAINER_ENCOUNTER := &"base:encounter/grass_floor1_room1_normal"

func _test_versus_and_caps(net: Node, runtime: Node) -> void:
	# Versus: a fresh run for every racer, same chests, their own world.
	var profile: Dictionary = Sync.fresh_profile(runtime.catalog, {"name": "Racer", "gender": "female"}, "slot-105-")
	profile.progression["currency"] = 40
	var race: Dictionary = Sync.race_state_payload(runtime.catalog, &"base:campaign/standard_tower", profile, 1234, String(runtime.catalog.content_version))
	var campaign := runtime.catalog.get_definition(&"base:campaign/standard_tower") as CampaignDefinition
	_expect(StringName(race.current_room_id) == campaign.starting_room_id, "a racer starts at the tower's door")
	_expect(int(race.progression.chest_seed) == 1234 and int(race.progression.floor_keys) == 0, "racers share the chest seed but start with no keys")
	_expect(int(race.progression.currency) == 40 and race.party.size() == CampaignProgressionService.STARTERS.size(), "the racer's team and money come from its profile")
	var loaded: Dictionary = runtime.load_detached_campaign(race, 105, func(_data: Dictionary) -> Dictionary: return {"ok": true})
	_expect(loaded.ok, "a race state is a valid campaign: %s" % loaded.get("message", ""))
	# Versus profiles hold whole runs; a returning racer gets its run back.
	net._profiles.open("race-%d" % randi())
	net.settings = {"mode": net.MODE_VERSUS, "allow_import": true, "max_players": 0, "double_battles": true}
	net.mode = net.Mode.HOST
	var first: Dictionary = net._guest_profile_for("Speedy", {"character": {"name": "Speedy", "gender": "male"}, "import": {}})
	_expect(first.profile.has("state") and StringName(first.profile.state.current_room_id) == campaign.starting_room_id, "a new racer's profile is a fresh run")
	var run: Dictionary = first.profile.state.duplicate(true)
	run.progression["floor_keys"] = 2
	net._profiles.store("Speedy", {"state": run})
	var again: Dictionary = net._guest_profile_for("speedy", {"character": {}, "import": {}})
	_expect(again.status == "returning" and int(again.profile.state.progression.floor_keys) == 2, "a returning racer continues its own run")
	_expect(net._race_seed() == net._race_seed(), "the race keeps one chest seed")
	# Forgetting a username (never one that is playing).
	net.players = {1: {"name": "Hosty"}, 7: {"name": "Speedy"}}
	_expect(not net.forget_profile("SPEEDY").ok, "a connected player cannot be forgotten")
	net.players.erase(7)
	_expect(net.saved_profiles().size() == 1 and not net.saved_profiles()[0].online, "saved players list who is offline")
	_expect(net.forget_profile("speedy").ok and not net._profiles.has_profile("Speedy"), "the host can forget a username")
	var fresh_again: Dictionary = net._guest_profile_for("Speedy", {"character": {"name": "Speedy", "gender": "male"}, "import": {}})
	_expect(fresh_again.status == "fresh", "a forgotten username starts over")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(net._profiles.path()))
	# Player caps.
	_expect(net.cap_label(2) == "Duo" and net.cap_label(0) == "Unlimited", "cap names")
	net.settings = {"mode": net.MODE_COOP, "allow_import": true, "max_players": 2, "double_battles": true}
	_expect(net.double_battles_enabled(), "double battles are a duo option")
	net.settings["max_players"] = 0
	_expect(not net.double_battles_enabled(), "no double battles in an unlimited game")
	_expect(net.PLAYER_CAPS == [2, 0], "games are duo or unlimited")
	net.mode = net.Mode.OFFLINE
	net.players = {}
	net.settings = net.DEFAULT_SETTINGS.duplicate()
	runtime.session.state = null
	runtime.session.save_redirect = Callable()

func _test_double_battle(net: Node, runtime: Node) -> void:
	runtime.session.save_repository = MemorySaveRepository.new()
	runtime.start_new_campaign(1, "Leader", &"male")
	var state = runtime.session.state
	state.current_room_id = TRAINER_ROOM
	var prepared: Dictionary = runtime.prepare_trainer_battle(TRAINER_ENCOUNTER, Vector2.ZERO)
	_expect(prepared.ok, "the leader prepares a trainer battle: %s" % prepared.get("message", ""))
	var ally_state = _make_state(runtime, "Partner", "partner")
	var ally_team: Dictionary = CampaignProgressionService.party_setup_combatants(ally_state, runtime.catalog)
	var base: Dictionary = runtime.prepared_battle_setup
	var base_enemies := (base.combatants as Array).filter(func(entry: Dictionary) -> bool: return int(entry.team) == 1).size()
	var built: Dictionary = MultiplayerDoubleBattle.build_setup(base, ally_team.combatants, 2)
	var combatants: Array = built.setup.combatants
	var team0 := combatants.filter(func(entry: Dictionary) -> bool: return int(entry.team) == 0)
	var team1 := combatants.filter(func(entry: Dictionary) -> bool: return int(entry.team) == 1)
	_expect(team0.size() == state.party.size() + 3, "both parties fight on team 0")
	_expect(team1.size() == base_enemies * 2, "the trainer's team is duplicated")
	_expect(built.actor_controllers.size() == 3 and built.actor_controllers.values().all(func(peer: int) -> bool: return peer == 2), "the partner controls exactly its own minions")
	var slots: Dictionary = {}
	for entry in combatants:
		slots["%d:%d" % [int(entry.team), int(entry.slot_index)]] = true
	_expect(slots.size() == combatants.size(), "every minion has its own slot")
	_expect(built.double_teams.is_empty() == (team0.size() <= 5 and team1.size() <= 5), "the dense layout is used only when a side has more than five minions")
	# Full parties on both sides: everyone moves to the ten-place layout.
	var five: Array = []
	for index in 5:
		five.append({"instance_id": "p%d" % index, "team": 0, "slot_index": index})
	var full: Dictionary = MultiplayerDoubleBattle.build_setup({"combatants": five + [{"instance_id": "e0", "team": 1, "slot_index": 2}]}, five, 2)
	var full_slots: Array = (full.setup.combatants as Array).filter(func(entry: Dictionary) -> bool: return int(entry.team) == 0).map(func(entry: Dictionary) -> int: return int(entry.slot_index))
	full_slots.sort()
	_expect(full.double_teams == [0, 1] and full_slots == [0, 1, 2, 3, 4, 5, 6, 7, 8, 9], "two full parties fill all ten places (%s)" % [full_slots])
	_expect(int((full.setup.combatants as Array).back().slot_index) == 0, "a small enemy team's copy takes a free normal slot")
	# Both machines run the same engine; turns are routed by actor.
	var rules := RuleSetDefinition.new()
	rules.party_size = 5
	rules.configuration = {"ai_teams": [1], "refill_on_activation": true, "ai_difficulty": {"trainer_type": "normal", "floor_rate": 0.5, "floor_index": 0}}
	var wire: Dictionary = bytes_to_var(var_to_bytes(built.setup))
	var engines: Array[BattleController] = [BattleController.new(), BattleController.new()]
	for controller in engines:
		_expect(controller.start(wire.duplicate(true), runtime.catalog, rules, BattleRng.new(77)).accepted, "the double battle starts")
	var partner_turns := 0
	var steps := 0
	while engines[0].engine.get_result().is_empty() and steps < 600:
		steps += 1
		var decision: Dictionary = engines[0].engine.get_decision()
		if int(decision.team) == 1:
			for controller in engines:
				controller.submit_ai_turn()
		else:
			if built.actor_controllers.has(String(decision.actor_id)):
				partner_turns += 1
			var legal: Array = decision.legal_moves
			var choice: Dictionary = legal[steps % legal.size()]
			var move := runtime.catalog.get_definition(StringName(choice.move_id)) as MoveDefinition
			var targets: Array[StringName] = []
			var count := mini(move.target_count, choice.target_ids.size()) if move.target_mode == MoveDefinition.TargetMode.CHOSEN else 0
			for index in count: targets.append(StringName(choice.target_ids[index]))
			for controller in engines:
				controller.submit(BattleCommand.new(StringName(decision.actor_id), BattleCommand.Kind.USE_MOVE, StringName(choice.move_id), targets, int(decision.revision)))
		if Sync.fingerprint(engines[0].engine.snapshot()) != Sync.fingerprint(engines[1].engine.snapshot()):
			_expect(false, "double battle engines diverged at step %d" % steps)
			break
	var result = engines[0].engine.get_result()
	_expect(not result.is_empty(), "the double battle finishes (%d steps)" % steps)
	_expect(partner_turns > 0, "the partner gets turns of its own")
	# Partner side: XP and health only, never the shared world.
	var completed_before: Dictionary = ally_state.progression.get("completed_encounters", {}).duplicate(true)
	var xp_before: int = ally_state.party[0].experience
	var encounter := runtime.catalog.get_definition(TRAINER_ENCOUNTER) as EncounterDefinition
	var settled: Dictionary = CampaignProgressionService.apply_ally_battle_result(ally_state, result, encounter, runtime.catalog, MultiplayerDoubleBattle.ALLY_PREFIX)
	_expect(settled.ok and not settled.already_applied, "the partner settles the battle: %s" % settled.get("message", ""))
	_expect(ally_state.party[0].experience > xp_before, "the partner's minions earn XP")
	_expect(ally_state.progression.get("completed_encounters", {}) == completed_before, "the partner's settlement leaves world progress to the leader")
	_expect(CampaignProgressionService.apply_ally_battle_result(ally_state, result, encounter, runtime.catalog, MultiplayerDoubleBattle.ALLY_PREFIX).already_applied, "a battle settles once")
	# The leader's own settlement ignores the partner's minions.
	var leader: Dictionary = runtime.settle_campaign_battle(result)
	_expect(leader.ok, "the leader settles the double battle: %s" % leader.get("message", ""))
	# Ten anchors per side, all on screen and distinct.
	var anchors: Dictionary = {}
	for team in 2:
		for slot in 10:
			var anchor: Vector2 = BattleCombatantView.double_anchor(team, slot)
			anchors[anchor] = true
			_expect(anchor.x > 40.0 and anchor.x < 680.0 and anchor.y > 200.0 and anchor.y <= 515.0, "double layout slot %d:%d is on screen" % [team, slot])
	_expect(anchors.size() == 20, "every double layout slot is distinct")
	runtime.session.state = null

## Host decision on join: kept team > imported save (if allowed) > starters.
func _test_import_policy(net: Node, runtime: Node) -> void:
	net._profiles.open("policy-%d" % randi())
	var own_save: Dictionary = _make_state(runtime, "Vala", "guest").to_dictionary("test")
	var request := {"character": {"name": "Vala", "gender": "female"}, "import": own_save}
	net.settings = {"mode": net.MODE_COOP, "allow_import": false}
	var blocked: Dictionary = net._guest_profile_for("Blocky", request)
	_expect(blocked.status == "fresh_blocked" and blocked.profile.party.size() == CampaignProgressionService.STARTERS.size(), "a host can make newcomers start with the starters")
	_expect(String(blocked.profile.character.name) == "Vala", "a blocked import still keeps the guest's character")
	net.settings = {"mode": net.MODE_COOP, "allow_import": true}
	var imported: Dictionary = net._guest_profile_for("Bringer", request)
	_expect(imported.status == "imported" and imported.profile.party.size() == 3, "an allowed import brings the save's team")
	var again: Dictionary = net._guest_profile_for("BLOCKY", request)
	_expect(again.status == "returning" and again.profile.party == blocked.profile.party, "returning players keep their team even once imports are allowed")
	var fresh: Dictionary = net._guest_profile_for("Newbie", {"character": {"name": "Newbie", "gender": "male"}, "import": {}})
	_expect(fresh.status == "fresh", "choosing a fresh start gives the starters")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(net._profiles.path()))
	net.settings = net.DEFAULT_SETTINGS.duplicate()

func _test_profile_store() -> void:
	var store := MultiplayerGuestProfiles.new()
	store.open("smoke-%d" % randi())
	_expect(not store.has_profile("Vala"), "a new world has no guests")
	var number := store.number_for("Vala")
	_expect(store.number_for("vala") == number, "profile numbers ignore username case")
	_expect(store.number_for("Ryder") != number, "each username gets its own number")
	store.store("VALA", {"party": [{"instance_id": "a"}]})
	store.save()
	var reopened := MultiplayerGuestProfiles.new()
	reopened.open(store.world_id)
	_expect(reopened.has_profile("vala") and reopened.profile("Vala").party.size() == 1, "profiles survive a restart")
	_expect(reopened.number_for("Newcomer") > number, "numbers keep counting after a restart")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(store.path()))

func _test_pvp_lockstep(net: Node, runtime: Node) -> void:
	var challenger = _make_state(runtime, "A", "same")
	var rival = _make_state(runtime, "B", "same") # Identical instance IDs on purpose.
	var team_a: Dictionary = CampaignProgressionService.party_setup_combatants(challenger, runtime.catalog)
	var team_b: Dictionary = CampaignProgressionService.party_setup_combatants(rival, runtime.catalog)
	_expect(team_a.ok and team_b.ok, "both parties build arena combatants")
	var spec: Dictionary = net.build_pvp_spec("battle-test", 1, team_a.combatants, 2, team_b.combatants, 4242)
	# One engine uses the spec as built, the other as it arrives over the wire.
	var wire: Dictionary = bytes_to_var(var_to_bytes(spec))
	var engines: Array[BattleController] = []
	for source in [spec, wire]:
		var rules := RuleSetDefinition.new()
		rules.id = StringName(source.rules.id)
		rules.party_size = 5
		rules.configuration = (source.rules.configuration as Dictionary).duplicate(true)
		var controller := BattleController.new()
		var started := controller.start((source.setup as Dictionary).duplicate(true), runtime.catalog, rules, BattleRng.new(int(source.seed)))
		_expect(started.accepted, "arena battle starts: %s" % started.message)
		engines.append(controller)
	var steps := 0
	var agreed := true
	while engines[0].engine.get_result().is_empty() and steps < 400:
		steps += 1
		if Sync.fingerprint(engines[0].engine.snapshot()) != Sync.fingerprint(engines[1].engine.snapshot()):
			agreed = false
			break
		var decision: Dictionary = engines[0].engine.get_decision()
		var legal: Array = decision.legal_moves
		var command: BattleCommand
		if legal.is_empty():
			command = BattleCommand.new(StringName(decision.actor_id), BattleCommand.Kind.FORFEIT, &"", [], int(decision.revision))
		else:
			var choice: Dictionary = legal[steps % legal.size()]
			var move := runtime.catalog.get_definition(StringName(choice.move_id)) as MoveDefinition
			var targets: Array[StringName] = []
			var count := mini(move.target_count, choice.target_ids.size()) if move.target_mode == MoveDefinition.TargetMode.CHOSEN else 0
			for index in count:
				targets.append(StringName(choice.target_ids[index]))
			command = BattleCommand.new(StringName(decision.actor_id), BattleCommand.Kind.USE_MOVE, StringName(choice.move_id), targets, int(decision.revision))
		var first := engines[0].submit(command)
		var second := engines[1].submit(command)
		_expect(first.accepted == second.accepted, "both engines accept or reject the same command")
	_expect(agreed, "both arena engines stay identical every turn (diverged at step %d)" % steps)
	_expect(not engines[0].engine.get_result().is_empty(), "the arena battle reaches a result within 400 commands")
	_expect(engines[0].engine.get_result().winning_team == engines[1].engine.get_result().winning_team, "both machines agree on the winner")

## Random-heavy battles: random species, levels and extra catalog moves
## (statuses, stuns, freezes, shields, charges...) and forced speed ties, over
## many seeds. A wire-decoded copy must stay bit-identical every turn.
func _test_lockstep_stress(net: Node, runtime: Node) -> void:
	var minions: Array = []
	var moves: Array = []
	for pack in runtime.catalog.packs:
		for definition in pack.definitions:
			if definition is MinionDefinition and not definition.initial_move_ids.is_empty(): minions.append(definition)
			elif definition is MoveDefinition and definition.available: moves.append(definition)
	_expect(minions.size() > 10 and moves.size() > 50, "stress test found catalog minions (%d) and moves (%d)" % [minions.size(), moves.size()])
	if minions.size() <= 10:
		return
	var diverged := 0
	var finished := 0
	var skipped_turn_kinds: Dictionary = {}
	for seed in 40:
		var picker := RandomNumberGenerator.new()
		picker.seed = 9000 + seed
		var teams: Array = [[], []]
		for team in 2:
			for slot in 5:
				var definition: MinionDefinition = minions[picker.randi() % minions.size()]
				var level := 15 + picker.randi() % 30
				var stats := LegacyMinionStats.current_stats(definition, level)
				var move_ids: Array[StringName] = definition.initial_move_ids.duplicate()
				for extra in 3:
					var move: MoveDefinition = moves[picker.randi() % moves.size()]
					if move.id not in move_ids: move_ids.append(move.id)
				teams[team].append({
					"instance_id": "m%d" % slot, "definition_id": definition.id, "team": team, "slot_index": slot,
					"level": level, "type_ids": definition.type_ids, "move_ids": move_ids,
					"base_max_health": stats.health, "max_health": stats.health, "health": stats.health,
					"base_max_energy": stats.energy, "max_energy": stats.energy, "energy": stats.energy,
					# Identical speeds on both sides force the tie-break path.
					"attack": stats.attack, "healing": stats.healing, "speed": 50 if slot < 2 else stats.speed,
					"max_attack_stat": LegacyMinionStats.max_attack_stat(definition), "max_healing_stat": LegacyMinionStats.max_healing_stat(definition),
				})
		var spec: Dictionary = net.build_pvp_spec("stress-%d" % seed, 1, teams[0], 2, teams[1], 777 + seed * 31)
		var engines: Array[BattleController] = []
		for source in [spec, bytes_to_var(var_to_bytes(spec))]:
			var rules := RuleSetDefinition.new()
			rules.configuration = (source.rules.configuration as Dictionary).duplicate(true)
			var controller := BattleController.new()
			if not controller.start((source.setup as Dictionary).duplicate(true), runtime.catalog, rules, BattleRng.new(int(source.seed))).accepted:
				break
			engines.append(controller)
		if engines.size() < 2:
			continue
		for step in 600:
			if not engines[0].engine.get_result().is_empty(): break
			if Sync.fingerprint(engines[0].engine.snapshot()) != Sync.fingerprint(engines[1].engine.snapshot()):
				diverged += 1
				break
			var decision: Dictionary = engines[0].engine.get_decision()
			var legal: Array = decision.legal_moves
			var command: BattleCommand
			if legal.is_empty():
				command = BattleCommand.new(StringName(decision.actor_id), BattleCommand.Kind.FORFEIT, &"", [], int(decision.revision))
			else:
				var choice: Dictionary = legal[picker.randi() % legal.size()]
				var move := runtime.catalog.get_definition(StringName(choice.move_id)) as MoveDefinition
				var targets: Array[StringName] = []
				var count := mini(move.target_count, choice.target_ids.size()) if move.target_mode == MoveDefinition.TargetMode.CHOSEN else 0
				for index in count: targets.append(StringName(choice.target_ids[index]))
				command = BattleCommand.new(StringName(decision.actor_id), BattleCommand.Kind.USE_MOVE, StringName(choice.move_id), targets, int(decision.revision))
			var response := engines[0].submit(command)
			engines[1].submit(command)
			for event in response.events:
				if String(event.kind).ends_with("skipped"): skipped_turn_kinds[event.kind] = true
		if engines[0].engine.get_result().is_empty() == false:
			finished += 1
			if engines[0].engine.get_result().winning_team != engines[1].engine.get_result().winning_team:
				diverged += 1
	_expect(diverged == 0, "40 random-heavy arena battles never diverge (%d diverged)" % diverged)
	_expect(finished >= 30, "most stress battles reach a result (%d/40)" % finished)
	print("stress: %d/40 finished, skipped-turn kinds seen: %s" % [finished, skipped_turn_kinds.keys()])

func _test_arena_trigger(net: Node, runtime: Node) -> void:
	var lobby := runtime.catalog.get_definition(&"base:room/main_tower_lobby") as RoomDefinition
	var view: CampaignRoomView = load("res://scenes/campaign_room_view.tscn").instantiate()
	root.add_child(view)
	net.mode = net.Mode.HOST
	view.configure(lobby, &"lobby_from_floor", lobby.spawn_positions.get("lobby_from_floor", Vector2.ZERO), {"gender": "male"}, {})
	var found := false
	for interaction in view._room_interactions:
		found = found or StringName(interaction.get("kind", "")) == &"pvp_arena"
	_expect(found, "the lobby's right-hand door becomes the arena while in multiplayer")
	# Walk the player into the arena zone: the contact must fire automatically.
	var fired: Array = []
	view.interaction_requested.connect(func(data: Dictionary) -> void: fired.append(data.kind))
	var to_top_left := -view.PLAYER_COLLISION_TOP_LEFT - view.PLAYER_COLLISION_SIZE * 0.5
	# In front of the door (where the old zone already fired) nothing happens.
	for spot in [Vector2(2880.0, 1100.0), Vector2(2945.0, 1100.0)]:
		view._player.position = spot + to_top_left
		view._refresh_nearby_interactions()
	_expect(fired.is_empty(), "walking up to the arena door does not trigger it yet")
	view._player.position = Vector2(2990.0, 1100.0) + to_top_left
	view._refresh_nearby_interactions()
	_expect(&"pvp_arena" in fired, "stepping into the arena doorway opens the opponent picker")
	net.mode = net.Mode.OFFLINE
	view.configure(lobby, &"lobby_from_floor", lobby.spawn_positions.get("lobby_from_floor", Vector2.ZERO), {"gender": "male"}, {})
	found = false
	for interaction in view._room_interactions:
		found = found or StringName(interaction.get("kind", "")) == &"pvp_arena"
	_expect(not found, "solo play has no arena trigger")
	view.queue_free()
	await process_frame
