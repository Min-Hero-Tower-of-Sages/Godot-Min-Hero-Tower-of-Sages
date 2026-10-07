class_name MultiplayerShellController
extends Node

## Connects the application shell to NetSession: player list HUD and toasts,
## the multiplayer panel beside the in-game menu, guests following the host
## (between floors in co-op, between rooms in follow mode, never in versus),
## watching battles in follow mode, duo double battles, consent prompts, the
## lobby arena, and the shared Minion Keeper lock. The shell stays the owner of
## all screens; this node only calls into it at well-defined points.

const JOIN_VIEW := preload("res://src/presentation/multiplayer_join_view.gd")
const HOST_VIEW := preload("res://src/presentation/multiplayer_host_view.gd")
const ARENA_PICKER := preload("res://src/presentation/multiplayer_arena_picker.gd")
const PROFILES_VIEW := preload("res://src/presentation/multiplayer_profiles_view.gd")
const PROMPT_VIEW := preload("res://src/presentation/multiplayer_prompt_view.gd")
const NOTICE_VIEW := preload("res://src/presentation/multiplayer_notice_view.gd")
const TRAINER_DIALOGUE := preload("res://src/application/source_trainer_dialogue.gd")
const BATTLE_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TOAST_SECONDS := 3.5
const BLOCKED_NOTICE_COOLDOWN_MSEC := 2500

var shell: Control
## Resolved at runtime so this script compiles before autoloads exist.
var net: Node:
	get: return get_node_or_null("/root/NetSession")
var _hud_layer: CanvasLayer
var _status_label: Label
var _roster_label: RichTextLabel
var _toasts: VBoxContainer
var _prompt_layer: CanvasLayer
## prompt_id -> the question panel on screen.
var _prompt_views: Dictionary = {}
var _join_view: Control
var _pending_spec: Dictionary = {}
var _held_battle_key := ""
var _held_battle_armed := false
var _holding_storage := false
var _storage_request_active := false
var _refresh_pending := false
var _room_signature := 0
var _blocked_notice_msec := -100000
var _following := false
var _hud_timer := 0.0
## Co-op guest: the host floor we last moved to ([floor, in lobby, mode]).
var _coop_floor: Array = []

func _ready() -> void:
	_hud_layer = CanvasLayer.new()
	_hud_layer.name = "MultiplayerHud"
	_hud_layer.layer = 12
	add_child(_hud_layer)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_layer.add_child(root)
	_status_label = MultiplayerUi.hud_label(root, "", Vector2(8.0, 38.0), Vector2(300.0, 18.0), 13, Color8(255, 236, 160))
	_roster_label = RichTextLabel.new()
	_roster_label.bbcode_enabled = true
	_roster_label.fit_content = true
	_roster_label.scroll_active = false
	_roster_label.position = Vector2(8.0, 56.0)
	_roster_label.size = Vector2(240.0, 160.0)
	_roster_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_roster_label.add_theme_font_override("normal_font", MultiplayerUi.FONT)
	_roster_label.add_theme_font_size_override("normal_font_size", 14)
	_roster_label.add_theme_color_override("font_outline_color", Color(0.06, 0.05, 0.1, 0.95))
	_roster_label.add_theme_constant_override("outline_size", 5)
	root.add_child(_roster_label)
	_toasts = VBoxContainer.new()
	_toasts.position = Vector2(100.0, 64.0)
	_toasts.size = Vector2(500.0, 120.0)
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toasts.alignment = BoxContainer.ALIGNMENT_BEGIN
	root.add_child(_toasts)
	# Questions sit above every menu and screen transition.
	_prompt_layer = CanvasLayer.new()
	_prompt_layer.name = "MultiplayerPrompts"
	_prompt_layer.layer = 30
	add_child(_prompt_layer)
	net.notice.connect(toast)
	net.prompt_requested.connect(_on_prompt_requested)
	net.prompt_closed.connect(_on_prompt_closed)
	net.campaign_replaced.connect(_on_campaign_replaced)
	net.status_changed.connect(_refresh_hud)
	net.world_changed.connect(_on_world_changed)
	net.battle_spec_received.connect(_on_battle_spec)
	net.battle_aborted.connect(_on_battle_aborted)
	net.disconnected.connect(_on_disconnected)
	net.join_finished.connect(_on_join_finished)
	_refresh_hud()

# --- HUD ------------------------------------------------------------------------------------

func toast(text: String) -> void:
	var label := MultiplayerUi.hud_label(_toasts, text, Vector2.ZERO, Vector2(500.0, 22.0), 16)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.custom_minimum_size = Vector2(500.0, 22.0)
	while _toasts.get_child_count() > 3:
		_toasts.get_child(0).free()
	var fade := label.create_tween()
	fade.tween_interval(TOAST_SECONDS)
	fade.tween_property(label, "modulate:a", 0.0, 0.6)
	fade.tween_callback(label.queue_free)

func _refresh_hud() -> void:
	var active: bool = net.is_active() and _in_game()
	# Menus cover the corner the roster sits in; the menu panel has its own list.
	var shown: bool = active and shell.interaction_dialog == null
	_status_label.visible = shown
	_roster_label.visible = shown
	if not active:
		return
	_status_label.text = "● " + net.status_text()
	_roster_label.text = "\n".join(_roster_lines("#bbbbbb"))

## One BBCode line per player: colored name, host star, you, in battle, and
## (when players can be apart) where they are.
func _roster_lines(you_color: String) -> PackedStringArray:
	var lines := PackedStringArray()
	for peer_id in _sorted_ids():
		var line := "[color=#%s]%s[/color]" % [net.player_color(peer_id).to_html(false), _escape(net.player_name(peer_id))]
		if peer_id == 1: line += " [color=#d8c27a]★[/color]"
		if peer_id == net.local_peer_id(): line += " [color=%s](you)[/color]" % you_color
		if net.player_battling(peer_id): line += " [color=#ff9a7a]⚔[/color]"
		if net.is_versus():
			var where := location_label(net.player_location(peer_id))
			if not where.is_empty():
				line += " [color=#a8b0be]%s · %d★[/color]" % [where, int(net.players.get(peer_id, {}).get("stars", 0))]
		lines.append(line)
	return lines

static func location_label(where: Dictionary) -> String:
	if where.is_empty():
		return ""
	if bool(where.get("lobby", false)):
		return "Lobby"
	return "Floor %d" % (int(where.get("floor", 0)) + 1)

func _escape(text: String) -> String:
	return text.replace("[", "[lb]")

func _sorted_ids() -> Array[int]:
	var ids: Array[int] = []
	for id in net.players:
		ids.append(int(id))
	ids.sort()
	return ids

# --- Per frame ------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_hud_timer += delta
	if _hud_timer >= 0.5:
		_hud_timer = 0.0
		_refresh_hud()
	if not net.is_active():
		return
	var room = shell.current_room
	var exploring: bool = is_instance_valid(room) and room.room != null and shell.current_battle == null
	if exploring:
		net.update_local_presence(room.room.id, room.player_position(), room.player_presence())
	else:
		net.clear_local_presence()
	_report_status()
	if not _held_battle_key.is_empty():
		if shell.current_battle != null:
			_held_battle_armed = true
		elif _held_battle_armed and exploring and not shell._room_transition_active:
			net.release_battle(_held_battle_key)
			_held_battle_key = ""
			_held_battle_armed = false
	var idle: bool = exploring and shell.interaction_dialog == null and not shell._room_transition_active and not (is_instance_valid(shell._seal_fusion) and shell._seal_fusion.active)
	if _holding_storage and idle:
		_holding_storage = false
		net.release_storage()
	if not _pending_spec.is_empty() and _in_game() and not shell._room_transition_active and shell.current_battle == null:
		var spec := _pending_spec
		_pending_spec = {}
		_start_network_battle(spec)
		return
	if net.is_guest() and idle and not _following and _should_follow_host():
		_follow_host()
		return
	if exploring:
		if _refresh_pending and idle:
			_refresh_pending = false
			shell._refresh_current_room()
		_room_signature = _current_room_signature()

## Battling flag, location and stars, for everyone's roster, minimap and
## floor selector (NetSession only sends it when it changes).
func _report_status() -> void:
	var state = shell.runtime.session.state if shell.runtime != null and shell.runtime.session != null else null
	if state == null:
		return
	net.set_local_status({
		"battling": shell.current_battle != null,
		"where": {"floor": int(state.progression.get("floor_index", 0)), "lobby": bool(state.progression.get("in_tower_lobby", false)), "room": String(state.current_room_id)},
		"stars": CampaignProgressionService.total_earned_stars(state),
	})

func _in_game() -> bool:
	return shell.runtime != null and shell.runtime.session != null and shell.runtime.session.state != null and (is_instance_valid(shell.current_room) or shell.current_battle != null)

## What a remote world edit must change for this room to be rebuilt.
func _current_room_signature() -> int:
	var state = shell.runtime.session.state
	var room = shell.current_room
	if state == null or not is_instance_valid(room) or room.room == null:
		return 0
	var progression: Dictionary = state.progression
	return MultiplayerWorldSync.fingerprint([
		state.room_state.get(String(room.room.id), {}),
		progression.get("boss_door_unlocked", false),
		progression.get("eggery_door_unlocked", false),
		progression.get("eggery_taken_slots", []),
		progression.get("eggery_picks_remaining", 0),
	])

func _on_world_changed(_from_remote: bool) -> void:
	if not _in_game():
		return
	shell._refresh_source_hud()
	var room = shell.current_room
	if is_instance_valid(room) and room.room != null:
		room.update_campaign_progression(shell.runtime.session.state.progression)
		if _current_room_signature() != _room_signature:
			_refresh_pending = true

# --- Guest: follow the host -----------------------------------------------------------------

## Follow mode: always stand in the host's room. Co-op: only move when the
## host changes floor (or enters/leaves the lobby); rooms are free to roam.
func _should_follow_host() -> bool:
	if net.host_room_id.is_empty() or net.is_versus():
		return false
	if net.is_follow():
		return shell.current_room.room.id != net.host_room_id
	return not _coop_floor.is_empty() and _host_floor() != _coop_floor

## The floor in the (host-owned) world progression the guest has applied.
func _host_floor() -> Array:
	var progression: Dictionary = shell.runtime.session.state.progression
	return [int(progression.get("floor_index", 0)), bool(progression.get("in_tower_lobby", false)), String(progression.get("tower_mode", ""))]

func _follow_host() -> void:
	_following = true
	shell._room_transition_active = true
	shell.current_room.set_controls_enabled(false)
	var curtain: ColorRect = shell._ensure_room_transition_curtain()
	curtain.visible = true
	curtain.color = Color(0.0, 0.0, 0.0, 0.0)
	var fade_out := create_tween()
	fade_out.tween_property(curtain, "color", Color.BLACK, 0.4)
	await fade_out.finished
	var state = shell.runtime.session.state
	if state != null and net.is_guest():
		if not net.is_follow():
			toast("%s took everyone to %s." % [net.player_name(1), "the lobby" if bool(state.progression.get("in_tower_lobby", false)) else "Floor %d" % (int(state.progression.get("floor_index", 0)) + 1)])
		_move_to_host(state)
		shell._show_room_from_state()
	if is_instance_valid(shell.current_room):
		shell.current_room.set_controls_enabled(false)
	await get_tree().create_timer(0.1).timeout
	var fade_in := create_tween()
	fade_in.tween_property(curtain, "color", Color(0.0, 0.0, 0.0, 0.0), 0.4)
	await fade_in.finished
	curtain.visible = false
	shell._room_transition_active = false
	if is_instance_valid(shell.current_room) and shell.interaction_dialog == null:
		shell.current_room.set_controls_enabled(true)
	_following = false

## Put the guest where the host stands. In co-op the host's checkpoint is
## adopted too, so a lost battle returns to this floor rather than an old one.
func _move_to_host(state) -> void:
	state.current_room_id = net.host_room_id
	state.room_state["current_room_id"] = String(net.host_room_id)
	var location: Dictionary = net.host_location.duplicate(true)
	var safe: Dictionary = location.get("safe", {})
	location.erase("safe")
	if StringName(location.get("room_id", "")) == net.host_room_id:
		state.room_state["current_location"] = location
	if not net.is_follow() and not safe.is_empty():
		state.safe_location = safe.duplicate(true)
	_coop_floor = _host_floor()

## Follow mode: every room a guest is shown is the host's room. Battle
## losses, forfeits and checkpoints would otherwise send them elsewhere.
func place_guest_with_host() -> void:
	var state = shell.runtime.session.state if shell.runtime != null and shell.runtime.session != null else null
	if state == null or not net.is_guest() or not net.is_follow() or net.host_room_id.is_empty() or state.current_room_id == net.host_room_id:
		return
	_move_to_host(state)

## Guests never change the floor; in follow mode they cannot change rooms
## either. The room view re-arms its exits after a refusal.
func allow_room_transition(exit_data: Dictionary) -> bool:
	if not net.is_guest() or net.is_versus():
		return true
	var floor_change := String(exit_data.get("target_route", "")) == "lobby"
	if not net.is_follow() and not floor_change:
		return true
	if is_instance_valid(shell.current_room):
		shell.current_room.release_transition_lock()
	if floor_change:
		_blocked_notice("Only the host (%s) can take everyone to another floor." % net.player_name(1))
	else:
		_blocked_notice("Only the host (%s) can lead the group to another room." % net.player_name(1))
	return false

func allow_interaction(kind: StringName) -> bool:
	if net.is_guest() and not net.is_versus() and kind in [&"floor_picker"]:
		_blocked_notice("Only the host (%s) can choose the floor." % net.player_name(1))
		return false
	if net.is_follow() and net.battle_in_progress() and kind in [&"trainer"]:
		toast("Wait for the current battle to finish.")
		return false
	return true

func _blocked_notice(text: String) -> void:
	var now := Time.get_ticks_msec()
	if now - _blocked_notice_msec >= BLOCKED_NOTICE_COOLDOWN_MSEC:
		_blocked_notice_msec = now
		toast(text)

# --- Battles ----------------------------------------------------------------------------------

## Before a trainer fight: in a duo game with double battles, invite the
## partner; in follow mode, reserve the single shared battle slot. Co-op and
## versus fights are otherwise local and granted immediately.
func request_trainer_battle(label: String) -> Dictionary:
	if not net.is_active():
		return {"ok": true, "key": ""}
	if net.double_battles_enabled() and net.players.size() == 2:
		var partner_id: int = net.other_player_ids()[0]
		if not net.player_battling(partner_id):
			if is_instance_valid(shell.current_room):
				shell.current_room.set_controls_enabled(false)
			toast("Asking %s to fight together…" % net.player_name(partner_id))
			var invite: Dictionary = await net.request_double(_trainer_name(label))
			if int(invite.get("partner", 0)) != 0:
				_held_battle_key = String(invite.key)
				_held_battle_armed = false
				return invite
			if not String(invite.get("message", "")).is_empty():
				toast(String(invite.message) + " You fight alone.")
	var reply: Dictionary = await net.request_battle("trainer", label)
	if reply.get("ok", false):
		_held_battle_key = String(reply.key)
		_held_battle_armed = false
	else:
		toast(String(reply.get("message", "The battle could not start.")))
	return reply

func _trainer_name(encounter_id: String) -> String:
	var encounter := shell.runtime.catalog.get_definition(StringName(encounter_id)) as EncounterDefinition
	if encounter == null:
		return "a trainer"
	return String(TRAINER_DIALOGUE.for_encounter(encounter).get("trainer_name", "a trainer"))

## Hand the reserved battle to the battle scene. With a partner it becomes a
## double battle: their party joins team 0 and the trainer's team doubles.
func share_trainer_battle(battle: Node, slot: Dictionary) -> void:
	var key := String(slot.get("key", ""))
	if key.is_empty():
		return
	var partner := int(slot.get("partner", 0))
	if partner == 0:
		battle.call("share_campaign_battle", key)
		return
	var built := MultiplayerDoubleBattle.build_setup(shell.runtime.prepared_battle_setup, slot.get("team", []), partner)
	shell.runtime.prepared_battle_setup = built.setup
	battle.call("share_campaign_battle", key, {"actor_controllers": built.actor_controllers, "double": true, "double_teams": built.double_teams})
	toast("Fighting together with %s!" % net.player_name(partner))

## The trainer battle never started (preparation failed): free the slot.
func cancel_trainer_battle() -> void:
	if not _held_battle_key.is_empty():
		net.release_battle(_held_battle_key)
		_held_battle_key = ""
		_held_battle_armed = false

func _on_battle_spec(spec: Dictionary) -> void:
	if shell.runtime == null or shell.runtime.session == null or shell.runtime.session.state == null:
		return
	if not net.is_follow() and not _spec_controls_local(spec):
		# Co-op: nobody is pulled out of their own adventure to watch.
		toast("%s are battling in the arena." % " and ".join(_spec_fighters(spec)))
		return
	_pending_spec = spec.duplicate(true)

func _spec_controls_local(spec: Dictionary) -> bool:
	for team in spec.get("controllers", {}):
		if int(spec.controllers[team]) == net.local_peer_id():
			return true
	for actor in spec.get("actor_controllers", {}):
		if int(spec.actor_controllers[actor]) == net.local_peer_id():
			return true
	return false

func _spec_fighters(spec: Dictionary) -> PackedStringArray:
	var fighters := PackedStringArray()
	for team in spec.get("names", {}):
		fighters.append(String(spec.names[team]))
	return fighters

func _on_battle_aborted(battle_key: String, _reason: String) -> void:
	if String(_pending_spec.get("key", "")) == battle_key:
		_pending_spec = {}

func _start_network_battle(spec: Dictionary) -> void:
	var local_fights := _spec_controls_local(spec)
	if bool(spec.get("double", false)) and local_fights:
		toast("Teaming up with %s!" % String(spec.get("names", {}).get(0, "your partner")))
	else:
		toast(("Arena: %s" if String(spec.get("kind", "")) == "pvp" else "Watching %s") % " vs ".join(_spec_fighters(spec)))
	# The battle takes over the screen: close whatever menu or dialogue was open.
	shell._clear_dialog(true)
	shell._room_transition_active = true
	if is_instance_valid(shell.current_room):
		shell.current_room.set_controls_enabled(false)
	var battle: Node = BATTLE_SCENE.instantiate()
	battle.visible = false
	shell.screen_host.add_child(battle)
	shell.current_battle = battle
	battle.audio_controller.music_owner = shell._campaign_audio
	battle.network_battle_finished.connect(_on_network_battle_finished.bind(battle, spec, local_fights), CONNECT_ONE_SHOT)
	battle.call("begin_network_battle", spec)
	shell._campaign_audio.fade_music_to(0.0, 0.5)
	await shell._fade_campaign_screen_out()
	if is_instance_valid(shell.current_room):
		shell.current_room.queue_free()
		shell.current_room = null
	shell.room_hud.visible = false
	if is_instance_valid(battle):
		battle.visible = true
	await shell._finish_campaign_screen_transition()

func _on_network_battle_finished(battle: Node, spec: Dictionary, local_fights: bool) -> void:
	if local_fights:
		net.release_battle(String(spec.get("key", "")))
	while shell._room_transition_active:
		await get_tree().process_frame
	shell._room_transition_active = true
	await shell._fade_campaign_screen_out()
	if is_instance_valid(battle):
		battle.queue_free()
	shell.current_battle = null
	if shell.runtime.session.state != null:
		shell._show_room_from_state()
	await shell._finish_campaign_screen_transition()

# --- Arena -------------------------------------------------------------------------------------

func show_arena_picker() -> void:
	if not net.is_active():
		return
	shell._clear_dialog()
	var picker: Control = ARENA_PICKER.new()
	shell.interaction_dialog = picker
	shell._attach_interaction_dialog()
	picker.configure(net.other_player_ids())
	picker.closed.connect(shell._clear_dialog)
	picker.opponent_chosen.connect(_challenge.bind(picker))
	SourceMenuTransition.enter(picker)

func _challenge(peer_id: int, picker: Control) -> void:
	if net.battle_in_progress():
		picker.set_error("Another arena battle is in progress.")
		return
	picker.set_waiting(peer_id)
	var reply: Dictionary = await net.request_pvp(peer_id, net.provide_pvp_team())
	if not reply.get("ok", false) and is_instance_valid(picker):
		picker.set_error(String(reply.get("message", "The challenge could not start.")))

# --- Shared Minion Keeper ---------------------------------------------------------------------

## The Minion Keeper is always reachable in multiplayer (from the menu panel):
## the shared storage holds everyone's minions, not only this player's.
func open_storage() -> void:
	if net.is_active() and _in_game():
		shell._show_storage_manager()

## True when storage may open now. Otherwise asks the host for the lock and
## reopens the Minion Keeper once it is granted.
func storage_ready() -> bool:
	if not net.shares_world() or _holding_storage:
		return true
	if not _storage_request_active:
		_acquire_storage()
	return false

func _acquire_storage() -> void:
	_storage_request_active = true
	var reply: Dictionary = await net.acquire_storage()
	_storage_request_active = false
	if not reply.get("ok", false):
		toast(String(reply.get("message", "The Minion Keeper is busy.")))
		return
	_holding_storage = true
	if _in_game() and is_instance_valid(shell.current_room) and not shell._room_transition_active:
		shell._show_storage_manager()
	else:
		_holding_storage = false
		net.release_storage()

# --- Title-screen join and host panel ---------------------------------------------------------

func show_join_view() -> void:
	shell._clear_dialog()
	var used: Dictionary = {}
	for slot in range(1, SaveRepository.SLOT_COUNT + 1):
		var loaded: Dictionary = shell.runtime.session.save_repository.load_slot(slot)
		if loaded.get("ok", false):
			used[slot] = String(loaded.get("state", {}).get("character", {}).get("name", "Student"))
	_join_view = JOIN_VIEW.new()
	shell.interaction_dialog = _join_view
	shell._attach_interaction_dialog()
	_join_view.configure(net.load_prefs(), used)
	_join_view.closed.connect(shell._clear_dialog)
	_join_view.join_requested.connect(_on_join_requested)
	SourceMenuTransition.enter(_join_view)

## `team`: {"slot": n} or {"fresh": true, "gender": "male"|"female"} (see NetSession.join).
func _on_join_requested(address: String, port: int, username: String, team: Dictionary) -> void:
	_join_view.set_busy(true)
	_join_view.set_status("Connecting to %s:%d…" % [address, port], false)
	var started: Dictionary = net.join(address, port, username, team)
	if not started.get("ok", false):
		_join_view.set_busy(false)
		_join_view.set_status(String(started.get("message", "Could not connect.")), true)

func _on_join_finished(ok: bool, message: String) -> void:
	if not ok:
		if is_instance_valid(_join_view):
			_join_view.set_busy(false)
			_join_view.set_status(message, true)
		return
	shell._clear_dialog(true)
	var state = shell.runtime.session.state
	var host: String = net.player_name(1)
	if net.is_versus():
		toast(("Back in the race in %s's game!" if net.join_profile_status == "returning" else "The race is on! Climb the tower before the others.") % host)
		shell._enter_loaded_save_with_transition()
		_refresh_hud()
		return
	if state != null:
		_move_to_host(state)
	match net.join_profile_status:
		"returning": toast("Welcome back! Your team in %s's world is here." % host)
		"imported": toast("Your team came along. What it earns here stays in %s's world." % host)
		"fresh_blocked": toast("%s's game does not allow bringing teams: you start with the starters." % host)
		_: toast("You start fresh in %s's world with the starter minions." % host)
	shell._enter_loaded_save_with_transition()
	_refresh_hud()

func show_host_view() -> void:
	shell._clear_dialog()
	var view: Control = HOST_VIEW.new()
	shell.interaction_dialog = view
	shell._attach_interaction_dialog()
	var character: Dictionary = shell.runtime.session.state.character if shell.runtime.session.state != null else {}
	view.configure(net.load_prefs(), String(character.get("name", "")))
	view.closed.connect(shell._close_source_menu.bind(shell._show_campaign_menu))
	view.profiles_requested.connect(show_profiles_view)
	shell._adopt_source_menu_backdrop(view)
	SourceMenuTransition.enter(view)

# --- In-game menu panel -------------------------------------------------------------------------

## Adds the multiplayer panel to the left of the source in-game menu popup.
## It is a child of the popup so it animates in and out with it.
func build_menu_panel(popup: Control) -> void:
	var size := Vector2(214.0, popup.size.y)
	var inner := size.x - 28.0
	var panel := MultiplayerUi.panel(popup, Vector2(-size.x - 14.0, 0.0), size)
	panel.name = "MultiplayerMenuPanel"
	MultiplayerUi.title(panel, "Multiplayer", Vector2(14.0, 12.0), inner, 20)
	if not net.is_active():
		MultiplayerUi.label(panel, "Open this campaign so friends can join from their title screen and play in your world.", Vector2(14.0, 48.0), Vector2(inner, 120.0), 14, MultiplayerUi.MUTED)
		_replays_button(panel, Vector2(14.0, size.y - 94.0), inner)
		MultiplayerUi.button(panel, "Open to friends", Vector2(14.0, size.y - 52.0), Vector2(inner, 34.0), show_host_view, 16).name = "OpenMultiplayerButton"
		return
	MultiplayerUi.label(panel, net.status_text(), Vector2(14.0, 42.0), Vector2(inner, 40.0), 13, MultiplayerUi.GOLD).name = "StatusLabel"
	var roster := RichTextLabel.new()
	roster.name = "Roster"
	roster.bbcode_enabled = true
	roster.position = Vector2(14.0, 78.0)
	roster.size = Vector2(inner, size.y - 78.0 - 158.0)
	# A long roster scrolls instead of running under the buttons.
	roster.scroll_active = true
	roster.mouse_filter = Control.MOUSE_FILTER_PASS
	roster.add_theme_font_override("normal_font", MultiplayerUi.FONT)
	roster.add_theme_font_size_override("normal_font_size", 15)
	roster.add_theme_color_override("default_color", MultiplayerUi.INK)
	roster.text = "\n".join(_roster_lines("#a8b0be"))
	panel.add_child(roster)
	# Four rows of slightly shorter buttons leave the roster room for four names.
	var y := size.y - 152.0
	_replays_button(panel, Vector2(14.0, y), inner, 30.0)
	y += 36.0
	MultiplayerUi.button(panel, "Minion Keeper", Vector2(14.0, y), Vector2(inner, 30.0), open_storage, 16).name = "StorageButton"
	y += 36.0
	if net.is_host():
		MultiplayerUi.button(panel, "Invite & settings", Vector2(14.0, y), Vector2(inner, 30.0), show_host_view, 16).name = "HostSettingsButton"
	else:
		var kept := "%s keeps your run in this race." if net.is_versus() else "%s keeps your team in this world."
		MultiplayerUi.label(panel, kept % net.player_name(1), Vector2(14.0, y), Vector2(inner, 30.0), 13, MultiplayerUi.MUTED)
	y += 36.0
	MultiplayerUi.button(panel, "Close game" if net.is_host() else "Leave game", Vector2(14.0, y), Vector2(inner, 30.0), _leave_from_menu, 16).name = "LeaveButton"

## Battle replays live in this panel too: it is the menu's only side panel.
func _replays_button(panel: Control, at: Vector2, width: float, height: float = 34.0) -> void:
	MultiplayerUi.button(panel, "Battle replays", at, Vector2(width, height), shell._battle_history.show_history.bind(true), 16).name = "BattleReplaysButton"

func _leave_from_menu() -> void:
	if net.is_host():
		net.leave()
		toast("Your game is closed. Friends went back to their title screen.")
		shell._clear_dialog()
		return
	shell._leave_to_title()

## Host: the usernames this world (or race) keeps a team for.
func show_profiles_view() -> void:
	shell._clear_dialog()
	var view: Control = PROFILES_VIEW.new()
	shell.interaction_dialog = view
	shell._attach_interaction_dialog()
	view.configure()
	view.closed.connect(shell._close_source_menu.bind(show_host_view))
	shell._adopt_source_menu_backdrop(view)
	SourceMenuTransition.enter(view)

## The versus host's game switched between its campaign and its race.
func _on_campaign_replaced() -> void:
	await get_tree().process_frame
	if not is_instance_valid(shell.current_room) or shell.current_battle != null or shell.runtime.session.state == null:
		return
	shell._clear_dialog(true)
	toast("The race is on! Your campaign waits for you." if net.host_in_race() else "Back to your own campaign.")
	shell._enter_loaded_save_with_transition()

# --- Questions (arena challenges, double battle invites) ---------------------------------------

func _on_prompt_requested(prompt_id: int, kind: String, from_peer: int, text: String) -> void:
	var view: Control = PROMPT_VIEW.new()
	_prompt_layer.add_child(view)
	_prompt_views[prompt_id] = view
	view.configure(text, "Fight!" if kind == "pvp" else "Join", "Not now", net.PROMPT_SECONDS, net.player_color(from_peer))
	view.answered.connect(func(accepted: bool) -> void:
		_prompt_views.erase(prompt_id)
		net.answer_prompt(prompt_id, accepted)
	)

func _on_prompt_closed(prompt_id: int) -> void:
	var view: Control = _prompt_views.get(prompt_id)
	_prompt_views.erase(prompt_id)
	if is_instance_valid(view):
		view.dismiss()

func _on_disconnected(reason: String) -> void:
	_pending_spec = {}
	_held_battle_key = ""
	_holding_storage = false
	_coop_floor = []
	for prompt_id in _prompt_views.keys():
		_on_prompt_closed(prompt_id)
	_refresh_hud()
	shell._room_transition_active = false
	shell._show_title_screen()
	shell._clear_dialog()
	var view: Control = NOTICE_VIEW.new()
	view.name = "DisconnectNotice"
	shell.interaction_dialog = view
	shell._attach_interaction_dialog()
	view.configure(net.last_disconnect_kind, reason, true)
	view.closed.connect(func() -> void:
		if shell.interaction_dialog == view:
			shell._clear_dialog()
	)
	SourceMenuTransition.enter(view)
