extends Control
signal battle_entry_animation_started
signal battle_entry_animation_finished
signal campaign_return_requested
signal campaign_defeat_return_requested
signal campaign_forfeit_return_requested
## Spectated or arena battle finished; the shell returns everyone to the room.
signal network_battle_finished
signal _network_command_arrived

const RecoveredCatalog = preload("res://content/imported/recovered-20260911/catalog.tres")
const VFX_CATALOG_SCRIPT = preload("res://src/presentation/battle_vfx_catalog.gd")
const AUDIO_CONTROLLER_SCRIPT = preload("res://src/presentation/battle_audio_controller.gd")
const COMBATANT_VIEW_SCRIPT = preload("res://src/presentation/battle_combatant_view.gd")
const BATTLE_DEMO_PACK = preload("res://content/base/packs/battle_demo.tres")
const CAMPAIGN_SLICE_PACK = preload("res://content/base/packs/campaign_slice.tres")
const DEFAULT_ICON = preload("res://content/base/art/battle/moveIcon_claw.png")
const MISS_TEXTURE = preload("res://content/base/art/battle/visualMove_moveMissed.png")
const MOVE_IMPACT_TEXTURE = preload("res://content/base/art/battle/visual_moves/936_Utilities_SpriteHandler_mv_yellowAndOrangeImpact.png")
const RESURRECTION_TOMBSTONE_TEXTURE = preload("res://content/base/art/battle/modStone_tombstone.png")
const SHIELD_STONE_TEXTURE = preload("res://content/base/art/battle/modStone_shieldStone.png")
const SHIELD_COUNTER_TEXTURE = preload("res://content/base/art/battle/modStone_shieldStoneCounterIcon.png")
const RESURRECTION_STONE_TEXTURE = preload("res://content/base/art/battle/modStone_resurection.png")
const MOVE_TIMER_STONE_TEXTURE = preload("res://content/base/art/battle/modStone_extraMoveStone.png")
const MOVE_TIMER_BUFF_PANEL_TEXTURE = preload("res://content/base/art/battle/modStone_extraMoveYourBuffBackground.png")
const EXTRA_MINION_STONE_TEXTURE = preload("res://content/base/art/battle/modStone_extraMinionOnDeathStone.png")
const EXTRA_MINION_CRYSTAL_TEXTURE = preload("res://content/base/art/battle/modStone_extraMinionCrystal.png")
const MOVE_TIMER_DEFAULT_ICON = preload("res://content/base/art/battle/moveIcon_agility.png")
const MOVE_TIMER_DEFAULT_BUFF_ICON = preload("res://content/base/art/battle/moveIcon_agileInspiration.png")
const VICTORY_BACKGROUND_TEXTURE = preload("res://content/base/art/battle/battleScreenVictoryBackground.png")
const VICTORY_STAR_TEXTURE = preload("res://content/base/art/battle/battleScreenVictoryStar.png")
const VICTORY_MALE_BUST_TEXTURE = preload("res://content/base/art/source_symbols/744_Utilities.SpriteHandler_menus_maleBust_icon.png")
const VICTORY_FEMALE_BUST_TEXTURE = preload("res://content/base/art/source_symbols/238_Utilities.SpriteHandler_menus_femaleBust_icon.png")
const VISUAL_SAME_AS_CLASS_ID := 188
const BURBIN_FONT = preload("res://content/base/fonts/BurbinCasual.ttf")
const MOVE_TOOLTIP_SCRIPT = preload("res://src/presentation/battle_move_tooltip.gd")
const PROGRESSION_PRESENTER_SCRIPT = preload("res://src/presentation/battle_progression_presenter.gd")
const PresentationState = preload("res://src/presentation/battle_presentation_state.gd")
const DESPERATION_MOVE_ID := &"base:move/desperation/tier1"
const PLAYER_SHOWCASE_ROSTER: Array[StringName] = [
	&"base:minion/raptor_1", &"base:minion/fire_frog_1", &"base:minion/healinghorse_1",
	&"base:minion/icetree_1", &"base:minion/griffen_1",
]
const PLAYER_SHOWCASE_EXTRA_MOVES := [
	[&"base:move/blow_by/tier4"],
	[&"base:move/blaze/tier1"],
	[&"base:move/swift_mend/tier1"],
	[&"base:move/ice_barrier/tier1"],
	[&"base:move/flurry/tier1"],
]
# Keep the practice rival to twelve active source moves across five minions,
# matching the player showcase; Mirror Skin remains as its source passive.
const SHOWCASE_ENEMY_MOVE_IDS := {
	&"base:minion/grasssnake_3": [&"base:move/poison_tooth/tier1", &"base:move/grassblade/tier5", &"base:move/mirror_skin/tier2"],
	&"base:minion/grassgorilla_2": [&"base:move/pound/tier1", &"base:move/drain/tier2", &"base:move/tree_slam/tier5"],
}
const SOURCE_ENCOUNTER_ID := &"base:encounter/demo_hard_floor1_room1"
const SHOWCASE_ENEMY_LEVEL_OFFSET := -7
const DEFAULT_MOVE_PROJECTILE_SECONDS := 0.42
const MOVE_PROJECTILE_FADE_SECONDS := 0.18
const BATTLE_ENTRY_ANIMATION_SECONDS := 1.9
## CheckForWinLose schedules CalculateNewMinionStats after 1s for replacements;
## the minion's fade-in is done then, while teleport particle tails may remain.
const BATTLE_REPLACEMENT_HANDOFF_SECONDS := 1.0
const TARGET_ORBIT_X := [0.0, 0.72, 1.0, 0.72, 0.0, -0.72, -1.0, -0.72]
const TARGET_ORBIT_Y := [-1.0, -0.72, 0.0, 0.72, 1.0, 0.72, 0.0, -0.72]
const SOURCE_GROUND_DAMAGE_INDEX_BY_FAMILY := {
	"fade_through_target": 0,
	"burn_at_target": 1,
	"fall_onto_target": 2,
	"fall_from_top": 2,
	"orbit_into_target": 3,
	"rotate_into_target": 3,
}

static func source_ground_damage_index_for_family(family: String) -> int:
	return int(SOURCE_GROUND_DAMAGE_INDEX_BY_FAMILY.get(family, -1))

@onready var event_text: Label = %EventText
@onready var turn_title: Label = %TurnTitle
@onready var move_panel: Control = %MovePanel
@onready var move_buttons: Control = %MoveButtons
@onready var energy_fill: TextureProgressBar = %EnergyFill
@onready var out_of_energy_tip: TextureRect = %OutOfEnergyTip
@onready var cooldown_tip: PanelContainer = %CooldownTip
@onready var cancel_target: Button = %CancelTarget
@onready var forfeit_button: TextureButton = %Forfeit
@onready var forfeit_confirmation: Control = %ForfeitConfirmation
@onready var forfeit_yes: TextureButton = %Yes
@onready var forfeit_no: TextureButton = %No
@onready var combatant_layer: Control = %CombatantLayer
@onready var arena_floor: Control = $Island
@onready var battle_grey_layer: ColorRect = %BattleGreyLayer
@onready var current_turn_indicator: TextureRect = %CurrentMinionTurn
@onready var start_overlay: Control = %StartOverlay
@onready var start_button: Button = %StartBattle
@onready var result_overlay: Control = %ResultOverlay
@onready var result_title: Label = %ResultTitle
@onready var restart_button: Button = %RestartBattle
@onready var move_vfx_layer: Control = %MoveVfxLayer

var battle_modifier_layer: Control
var controller := BattleController.new()
var vfx_catalog: BattleVfxCatalog = VFX_CATALOG_SCRIPT.new()
var audio_controller: BattleAudioController = AUDIO_CONTROLLER_SCRIPT.new()
var catalog: ContentCatalog
var source_encounter: EncounterDefinition
var combatant_views: Dictionary = {}
var _original_player_ids: Dictionary = {}
var _retired_player_views: Dictionary = {}
var resurrection_tombstones: Dictionary = {}
var active_battle_modifiers: Dictionary = {}
var _shield_bob_tweens: Array[Tween] = []
var _pending_extra_minion_animation_ids: Array[StringName] = []
var _move_timer_icon_tween: Tween
var _modifier_visual_completion_usec := 0
var _move_selector_tweens: Array[Tween] = []
var _move_selector_exit_deadline_usec := 0
var _move_selector_exiting := false
var _turn_indicator_tween: Tween
var _turn_indicator_fade_deadline_usec := 0
var _battle_grey_tween: Tween
var _battle_music_start_tween: Tween
var _victory_presentation_tweens: Array[Tween] = []
var _victory_popup_tween: Tween
var victory_popup: Control
var victory_background: TextureRect
var victory_player_icon: TextureRect
var victory_stars: Array[TextureRect] = []
var _defeat_presentation_tweens: Array[Tween] = []
var defeat_transition_layer: Control
var defeat_black: ColorRect
var defeat_message: Label
var _earthquake_tween: Tween
var _earthquake_base_positions: Array[float] = []
var presenter := BattlePresenter.new()
var pending_move: Dictionary = {}
var selected_targets: Array[StringName] = []
var _last_move_visual_duration_seconds := 0.0
var busy := false
var move_tooltip: BattleMoveTooltip
## Your minion's stats, opened by clicking its health bar (never the enemy's).
var stats_panel: BattleStatsPanel
## The decision the move selector was opened for, and whose moves it shows
## (empty while closed by a click on empty ground).
var _selector_decision: Dictionary = {}
var _selector_minion_id: StringName = &""
## Last pointer position seen by _input (viewport coordinates).
var _mouse_point := Vector2(-1.0, -1.0)
var _stats_signature := 0
var campaign_mode := false
var campaign_settlement: Dictionary = {}
var campaign_progression_presenter: BattleProgressionPresenter
var _campaign_defeat_transition_pending := false
var _campaign_victory_return_pending := false
var _battle_result_presented := false
var _move_selection_hint: TextureRect
var _move_hint_tween: Tween
## Multiplayer lockstep. Every machine runs the same engine from the same
## setup/rules/seed; only human commands travel. Roles: "" offline,
## &"battler" (campaign fight others watch or join), &"spectator", &"pvp",
## &"ally" (the partner in a duo double battle, controlling only its own
## minions, listed in net_spec.actor_controllers).
var net_role: StringName = &""
var net_spec: Dictionary = {}
var _local_teams: Array = [0]
## Extra spec fields the battler publishes (double battle partner, names).
var _net_extras: Dictionary = {}
## Engine teams with more than five minions (double battle): those sides use
## the denser ten-place layout with smaller minions.
var _double_teams: Array = []
var _ai_teams: Array = [1]
## 1 when the local player controls engine team 1: views are mirrored so the
## local team always stands on the left, while the engine stays untouched.
var _team_flip := 0
var _net_command_queue: Array[Dictionary] = []
var _net_aborted := false
var _net_snapshot_reply: Dictionary = {}

## Battle history: every fight records itself as a BattleReplay and is saved
## to the history when it ends (or, unfinished, when the scene closes).
var _recording: Dictionary = {}
var _recording_saved := false
var _turns_played := 0
## Replay playback (net_role &"replay"): the recorded human commands are fed
## back in order; AI turns are recomputed by the engine as they were live.
var replay_data: Dictionary = {}
var settings_service: CampaignSettingsService
var _audio_controls: Control
var _music_toggle: TextureButton
var _sound_toggle: TextureButton
var _replay_cursor := 0
var _replay_hud: Control
var _replay_finished := false
const REPLAY_HUD_SCRIPT := preload("res://src/presentation/battle_replay_hud.gd")
## The "choosing a move" beat before each recorded turn plays.
const REPLAY_TURN_BEAT_SECONDS := 0.45
## Battle clock. Presentation deadlines use it instead of the system clock so
## a replay played at 2x/4x (or paused at 0x) scales every wait together.
## Live battles never change speed, so it is then exactly the system clock.
var _clock_speed := 1.0
var _clock_base_real := 0
var _clock_base_virtual := 0

func _ready() -> void:
	preload("res://src/presentation/source_menu_button_audio.gd").bind_tree(self)
	_create_audio_toggles()
	# Hovered (passing clicks on) so its cursor shape is the one shown.
	mouse_filter = Control.MOUSE_FILTER_PASS
	battle_modifier_layer = Control.new()
	battle_modifier_layer.name = "BattleModifierLayer"
	battle_modifier_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	battle_modifier_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	battle_modifier_layer.z_index = 1
	add_child(battle_modifier_layer)
	add_child(presenter)
	add_child(audio_controller)
	campaign_progression_presenter = PROGRESSION_PRESENTER_SCRIPT.new() as BattleProgressionPresenter
	add_child(campaign_progression_presenter)
	campaign_progression_presenter.sequence_finished.connect(_on_campaign_progression_sequence_finished)
	move_tooltip = MOVE_TOOLTIP_SCRIPT.new() as BattleMoveTooltip
	add_child(move_tooltip)
	move_tooltip.z_index = 1100
	stats_panel = BattleStatsPanel.new()
	stats_panel.name = "StatsPanel"
	stats_panel.z_index = 1100
	add_child(stats_panel)
	_create_victory_popup()
	_create_defeat_transition()
	presenter.seconds_per_event = 0.10
	start_button.pressed.connect(_start_battle)
	restart_button.pressed.connect(_on_restart_pressed)
	forfeit_button.pressed.connect(_forfeit)
	forfeit_yes.pressed.connect(_confirm_forfeit)
	forfeit_no.pressed.connect(_cancel_forfeit)
	cancel_target.pressed.connect(_cancel_targeting)
	move_panel.visible = false
	cancel_target.visible = false
	battle_grey_layer.modulate.a = 0.0
	current_turn_indicator.modulate.a = 0.0
	current_turn_indicator.texture = preload("res://content/base/art/battle/battleScreenCurrMinionsTurn.png")
	current_turn_indicator.visible = false
	var cooldown_style := StyleBoxFlat.new()
	cooldown_style.bg_color = Color8(225, 29, 34)
	cooldown_style.border_color = Color8(245, 121, 121)
	cooldown_style.set_border_width_all(3)
	cooldown_style.set_corner_radius_all(10)
	cooldown_style.content_margin_left = 8
	cooldown_style.content_margin_right = 8
	cooldown_style.content_margin_top = 3
	cooldown_style.content_margin_bottom = 3
	cooldown_tip.add_theme_stylebox_override("panel", cooldown_style)
	var cooldown_text := cooldown_tip.get_node("CooldownText") as Label
	cooldown_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cooldown_text.add_theme_font_override("font", BURBIN_FONT)
	cooldown_text.add_theme_font_size_override("font_size", 11)
	cooldown_text.add_theme_color_override("font_color", Color.WHITE)
	cooldown_text.add_theme_color_override("font_shadow_color", Color.BLACK)
	cooldown_text.add_theme_constant_override("shadow_offset_x", 2)
	cooldown_text.add_theme_constant_override("shadow_offset_y", 2)
	cooldown_tip.size = Vector2(220, 40)
	var confirmation_question := forfeit_confirmation.get_node("Question") as Label
	confirmation_question.add_theme_font_override("font", BURBIN_FONT)
	confirmation_question.add_theme_font_size_override("font_size", 16)
	confirmation_question.add_theme_color_override("font_color", Color8(249, 249, 249))
	_set_forfeit_enabled(false)

func begin_campaign_battle() -> void:
	var runtime: Variant = get_node_or_null("/root/CampaignRuntime")
	if runtime == null or not runtime.active_campaign_battle or runtime.prepared_battle_setup.is_empty():
		_show_fatal("There is no prepared campaign encounter to start")
		return
	campaign_mode = true
	start_overlay.visible = false
	await _start_battle()

## Start a battle published by another player (spectating, or an arena fight).
func begin_network_battle(spec: Dictionary) -> void:
	var net: Node = get_node_or_null("/root/NetSession")
	net_spec = spec.duplicate(true)
	_double_teams = spec.get("double_teams", [])
	_local_teams.clear()
	var controllers: Dictionary = spec.get("controllers", {})
	for team in controllers:
		if net != null and int(controllers[team]) == net.local_peer_id():
			_local_teams.append(int(team))
	net_role = &"pvp" if not _local_teams.is_empty() else &"spectator"
	var actor_controllers: Dictionary = spec.get("actor_controllers", {})
	if _local_teams.is_empty() and net != null and actor_controllers.values().any(func(peer: Variant) -> bool: return int(peer) == net.local_peer_id()):
		net_role = &"ally"
		_local_teams = [0]
	_team_flip = 1 if _local_teams == [1] else 0
	campaign_mode = false
	start_overlay.visible = false
	forfeit_button.visible = net_role in [&"pvp", &"ally"]
	_connect_network_battle(net)
	await _start_battle()

## Watch a recorded battle (see BattleReplay). Leaves with network_battle_finished.
func begin_replay(replay: Dictionary) -> void:
	replay_data = replay
	net_role = &"replay"
	net_spec = {
		"key": "",
		"seed": int(replay.seed),
		"setup": replay.setup,
		"rules": replay.rules,
		"encounter_id": String(replay.get("encounter_id", "")),
		"names": replay.get("names", {}),
	}
	_double_teams = replay.get("double_teams", [])
	_local_teams = []
	# Show the recorder's side on the left, as they saw it.
	_team_flip = 1 if int(replay.get("pov", 0)) == 1 else 0
	campaign_mode = false
	start_overlay.visible = false
	forfeit_button.visible = false
	_replay_hud = REPLAY_HUD_SCRIPT.new()
	_replay_hud.name = "ReplayHud"
	_replay_hud.z_index = 1200
	add_child(_replay_hud)
	_replay_hud.configure(replay)
	_replay_hud.speed_changed.connect(set_playback_speed)
	_replay_hud.restart_requested.connect(_restart_replay)
	_replay_hud.exit_requested.connect(_exit_replay)
	# The replay bar takes the top of the screen; the turn banner sits below it.
	(event_text.get_parent() as Control).position.y += 44.0
	set_playback_speed(1.0)
	var campaign_runtime: Variant = get_node_or_null("/root/CampaignRuntime")
	var content_version := String(campaign_runtime.catalog.content_version) if campaign_runtime != null and campaign_runtime.catalog != null else ""
	if String(replay.get("content", content_version)) != content_version:
		_replay_hud.show_notice("Recorded on another version of the game: it may play out differently.")
	await _start_battle()

func _restart_replay() -> void:
	_replay_hud.hide_end()
	set_playback_speed(_replay_hud.current_speed())
	await _start_battle()

func _exit_replay() -> void:
	set_playback_speed(1.0)
	busy = true
	network_battle_finished.emit()

## The next recorded human command, after a short "choosing" beat.
func _next_replay_command(decision: Dictionary) -> BattleCommand:
	await get_tree().create_timer(REPLAY_TURN_BEAT_SECONDS).timeout
	if not is_inside_tree() or _replay_finished:
		return null
	var commands: Array = replay_data.get("commands", [])
	if _replay_cursor >= commands.size():
		_end_replay("The recording stops here.", "This battle was not finished.")
		return null
	var entry: Dictionary = commands[_replay_cursor]
	if int(entry.get("r", -1)) != int(decision.revision):
		_end_replay("The recording stops here.", "This replay no longer matches the game.")
		return null
	var check := int(entry.get("c", 0))
	if check != 0 and BattleReplay.state_check(controller.engine.snapshot()) != check:
		_replay_hud.show_notice("This replay plays out differently on this version of the game.")
	_replay_cursor += 1
	return BattleReplay.to_command(entry)

func _end_replay(headline: String, detail: String) -> void:
	if _replay_finished:
		return
	_replay_finished = true
	busy = true
	move_panel.visible = false
	_hide_current_turn_indicator()
	event_text.get_parent().visible = false
	audio_controller.fade_music_to(0.0, 1.5)
	_replay_hud.show_end(headline, detail)

## Campaign battler: publish this fight so other players spectate (or, with
## `extras` naming actor_controllers, help fight) it.
func share_campaign_battle(battle_key: String, extras: Dictionary = {}) -> void:
	net_spec = {"key": battle_key}
	_net_extras = extras.duplicate(true)
	_double_teams = extras.get("double_teams", [])

func _connect_network_battle(net: Node) -> void:
	if net == null or net.battle_command_received.is_connected(_on_network_battle_command):
		return
	net.battle_command_received.connect(_on_network_battle_command)
	net.battle_aborted.connect(_on_network_battle_aborted)
	net.battle_snapshot_received.connect(_on_network_battle_snapshot)
	# Commands that arrived during the screen fade, before this scene listened.
	_net_command_queue.append_array(net.buffered_battle_commands(String(net_spec.get("key", ""))))

func _net() -> Node:
	var net: Node = get_node_or_null("/root/NetSession")
	return net if net != null and net.is_active() else null

func _on_network_battle_command(battle_key: String, command: Dictionary) -> void:
	if battle_key != String(net_spec.get("key", "")):
		return
	_net_command_queue.append(command)
	_network_command_arrived.emit()

func _on_network_battle_aborted(battle_key: String, reason: String) -> void:
	if battle_key != String(net_spec.get("key", "")) or _net_aborted:
		return
	_net_aborted = true
	_network_command_arrived.emit()
	if net_role == &"battler":
		return # A campaign battle simply continues against its AI trainer.
	busy = true
	move_panel.visible = false
	move_tooltip.hide()
	forfeit_confirmation.visible = false
	_set_forfeit_enabled(false)
	_clear_target_states()
	_hide_current_turn_indicator()
	event_text.get_parent().visible = false
	audio_controller.fade_music_to(0.0, 1.5)
	_show_battle_ended_card(reason)
	await get_tree().create_timer(3.0).timeout
	network_battle_finished.emit()

## The other side of a shared battle is gone: a slate card like the
## multiplayer panels, instead of a line in the turn banner.
func _show_battle_ended_card(reason: String) -> void:
	var layer := Control.new()
	layer.name = "BattleEndedCard"
	layer.z_index = 1200
	add_child(layer)
	var card_size := Vector2(360.0, 112.0)
	var panel := MultiplayerUi.modal(layer, card_size)
	(layer.get_child(0) as ColorRect).color = Color(0.0, 0.0, 0.0, 0.35)
	var stripe := ColorRect.new()
	stripe.color = MultiplayerUi.ERROR
	stripe.position = Vector2(4.0, 4.0)
	stripe.size = Vector2(6.0, card_size.y - 8.0)
	panel.add_child(stripe)
	var caption := MultiplayerUi.title(panel, "Battle ended", Vector2(24.0, 12.0), card_size.x - 40.0, 20)
	caption.add_theme_color_override("font_color", MultiplayerUi.ERROR)
	MultiplayerUi.label(panel, reason, Vector2(24.0, 44.0), Vector2(card_size.x - 40.0, 24.0), 17, MultiplayerUi.INK)
	MultiplayerUi.label(panel, "Taking you back to your game…", Vector2(24.0, 74.0), Vector2(card_size.x - 40.0, 20.0), 13, MultiplayerUi.MUTED)
	panel.pivot_offset = card_size * 0.5
	panel.scale = Vector2(0.85, 0.85)
	panel.modulate.a = 0.0
	var reveal := create_tween().set_parallel(true)
	reveal.tween_property(panel, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	reveal.tween_property(panel, "modulate:a", 1.0, 0.2)

func _on_network_battle_snapshot(battle_key: String, revision: int, snapshot: Dictionary) -> void:
	if battle_key == String(net_spec.get("key", "")):
		_net_snapshot_reply = {"revision": revision, "snapshot": snapshot}
		_network_command_arrived.emit()

## Wait for the remote owner of `decision` to choose. Verifies both machines
## agree on the pre-command state and re-syncs from the sender if they drift.
func _await_network_turn(decision: Dictionary) -> BattleCommand:
	var revision := int(decision.revision)
	while not _net_aborted:
		for index in _net_command_queue.size():
			var queued: Dictionary = _net_command_queue[index]
			if int(queued.get("revision", -1)) != revision:
				continue
			_net_command_queue.remove_at(index)
			var expected := int(queued.get("check", 0))
			var net := _net()
			if net != null and expected != 0 and MultiplayerWorldSync.fingerprint(controller.engine.snapshot()) != expected:
				push_warning("Multiplayer battle drift at revision %d; restoring sender state" % revision)
				_net_snapshot_reply.clear()
				net.request_battle_snapshot(String(net_spec.key), revision, int(queued.get("sender", 0)))
				var deadline := Time.get_ticks_msec() + 5000
				while _net_snapshot_reply.is_empty() and Time.get_ticks_msec() < deadline and not _net_aborted:
					await get_tree().create_timer(0.1).timeout
				if not _net_snapshot_reply.is_empty():
					controller.engine.restore(_net_snapshot_reply.snapshot)
					_sync_from_engine()
			var targets: Array[StringName] = []
			for raw_id in queued.get("targets", []):
				targets.append(StringName(raw_id))
			var kind := BattleCommand.Kind.FORFEIT if String(queued.get("kind", "")) == "forfeit" else BattleCommand.Kind.USE_MOVE
			return BattleCommand.new(StringName(queued.actor), kind, StringName(queued.get("move", "")), targets, revision)
		# Commands are applied strictly in revision order; drop anything older.
		_net_command_queue = _net_command_queue.filter(func(entry: Dictionary) -> bool: return int(entry.get("revision", -1)) >= revision)
		await _network_command_arrived
	return null

## Submit a locally chosen command, record it, and stream it to every other player.
func _submit_local_command(command: BattleCommand) -> BattleResponse:
	var net := _net()
	var shared := net != null and not net_role.is_empty()
	var pre_snapshot: Dictionary = controller.engine.snapshot() if shared or not _recording.is_empty() else {}
	var response := controller.submit(command)
	if response.accepted and not _recording.is_empty():
		BattleReplay.record_command(_recording, command, pre_snapshot)
	if response.accepted and shared:
		var targets: Array = []
		for target_id in command.target_ids:
			targets.append(String(target_id))
		net.send_battle_command(String(net_spec.key), {
			"revision": command.expected_revision,
			"actor": String(command.actor_id),
			"kind": "forfeit" if command.kind == BattleCommand.Kind.FORFEIT else "move",
			"move": String(command.move_id),
			"targets": targets,
		}, pre_snapshot)
	return response

## Whose turn this is: the actor's own controller in a double battle,
## otherwise whoever controls its team.
func _is_local_decision(decision: Dictionary) -> bool:
	var owners: Dictionary = net_spec.get("actor_controllers", {})
	var actor := String(decision.get("actor_id", ""))
	if owners.has(actor):
		var net := _net()
		return net != null and int(owners[actor]) == net.local_peer_id()
	return int(decision.team) in _local_teams and net_role != &"ally"

func _decision_owner_name(decision: Dictionary) -> String:
	var owners: Dictionary = net_spec.get("actor_controllers", {})
	var actor := String(decision.get("actor_id", ""))
	var net := _net()
	if net != null:
		if owners.has(actor):
			return net.player_name(int(owners[actor]))
		if net_role == &"ally" and int(decision.team) == 0:
			return net.player_name(int(net_spec.get("controllers", {}).get(0, 1)))
	return _network_player_name(int(decision.team))

func _display_team(engine_team: int) -> int:
	return engine_team ^ _team_flip if engine_team in [0, 1] else engine_team

func _network_player_name(team: int) -> String:
	var names: Dictionary = net_spec.get("names", {})
	return String(names.get(team, "Team %d" % (team + 1)))

func _process(_delta: float) -> void:
	if move_tooltip != null and move_tooltip.visible:
		move_tooltip.follow_mouse(get_global_mouse_position(), size)
	_update_target_cursor()
	_refresh_stats_panel()

func _exit_tree() -> void:
	_cancel_battle_music_start()
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	if net_role == &"replay":
		Engine.time_scale = 1.0
	# Left before the end (disconnect, quit): keep what was played.
	if not _recording_saved and not (_recording.get("commands", []) as Array).is_empty():
		_save_recording()

func _now_usec() -> int:
	if _clock_base_real == 0:
		return Time.get_ticks_usec()
	return _clock_base_virtual + int(float(Time.get_ticks_usec() - _clock_base_real) * _clock_speed)

## Replay speed: 0 pauses, 1/2/4 play. Timers and tweens follow Engine.time_scale;
## absolute presentation deadlines follow the rebased battle clock.
func set_playback_speed(speed: float) -> void:
	var now := _now_usec()
	_clock_base_virtual = now
	_clock_base_real = Time.get_ticks_usec()
	_clock_speed = speed
	Engine.time_scale = speed

func _cancel_battle_music_start() -> void:
	if _battle_music_start_tween != null and _battle_music_start_tween.is_running():
		_battle_music_start_tween.kill()
	_battle_music_start_tween = null

func _update_target_cursor() -> void:
	var cursor_shape := Input.CURSOR_ARROW
	var mouse_point := _mouse_point
	if _inspectable_view_at(mouse_point) != null:
		cursor_shape = Input.CURSOR_POINTING_HAND
	else:
		# One of your minions whose moves a click would open.
		var minion := _selector_click_target(mouse_point).get("minion") as BattleCombatantView
		if minion != null and _selector_would_open(minion):
			cursor_shape = Input.CURSOR_POINTING_HAND
	if not busy and not pending_move.is_empty() and not forfeit_confirmation.visible:
		var mouse_position := _mouse_point
		var pointer_over_cancel := cancel_target.visible and cancel_target.get_global_rect().has_point(mouse_position)
		if not pointer_over_cancel:
			for raw_id in pending_move.get("target_ids", []):
				var target_view := combatant_views.get(String(raw_id)) as BattleCombatantView
				if target_view != null and target_view.targetable and target_view.contains_canvas_point(mouse_position):
					cursor_shape = Input.CURSOR_POINTING_HAND
					break
	Input.set_default_cursor_shape(cursor_shape)
	# The battle root is the hovered Control (see _ready): the GUI shows its
	# cursor, instead of the arrow of whatever screen hosts the battle.
	var shown := int(cursor_shape) as Control.CursorShape
	if mouse_default_cursor_shape != shown:
		mouse_default_cursor_shape = shown
		# Godot re-reads the shape only on the next mouse event otherwise.
		get_viewport().update_mouse_cursor_state()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		# Before the GUI handles this motion, so it shows the new shape at once.
		_mouse_point = event.position
		_update_target_cursor()
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if is_instance_valid(_audio_controls) and _audio_controls.get_global_rect().has_point(event.position):
			return # Leave corner audio controls to the GUI, not target picking.
		if stats_panel.visible and stats_panel.get_global_rect().has_point(event.position):
			return # The panel's own Details button takes it.
		if _handle_stats_click(event.position) or _handle_selector_click(event.position):
			get_viewport().set_input_as_handled()
			return
	if busy or forfeit_confirmation.visible or pending_move.is_empty():
		return
	if not event is InputEventMouseButton or not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
		return
	if cancel_target.visible and cancel_target.get_global_rect().has_point(event.position):
		return
	var legal_views: Array[BattleCombatantView] = []
	for raw_id in pending_move.get("target_ids", []):
		var target_id := StringName(raw_id)
		var view := combatant_views.get(String(target_id)) as BattleCombatantView
		if view != null and view.targetable:
			legal_views.append(view)
	legal_views.sort_custom(func(left: BattleCombatantView, right: BattleCombatantView) -> bool: return left.position.y > right.position.y)
	for view in legal_views:
		if view.contains_canvas_point(event.position):
			_on_combatant_clicked(view.instance_id)
			get_viewport().set_input_as_handled()
			return
	if not selected_targets.is_empty():
		selected_targets.clear()
		for raw_id in pending_move.get("target_ids", []):
			_set_view_targetable(StringName(raw_id), true)

func _start_battle() -> void:
	busy = true
	stats_panel.close()
	restart_button.disabled = false
	if campaign_progression_presenter != null:
		campaign_progression_presenter.cancel_sequence()
	_campaign_defeat_transition_pending = false
	_campaign_victory_return_pending = false
	_battle_result_presented = false
	_reset_move_selector_animation()
	_reset_victory_presentation()
	_reset_defeat_presentation()
	if _battle_grey_tween != null and _battle_grey_tween.is_running():
		_battle_grey_tween.kill()
	battle_grey_layer.visible = false
	battle_grey_layer.modulate.a = 0.0
	_cancel_battle_music_start()
	if not campaign_mode or not is_instance_valid(audio_controller.music_owner):
		audio_controller.stop_music()
	start_overlay.visible = false
	result_overlay.visible = false
	event_text.get_parent().visible = false
	cancel_target.visible = false
	move_panel.visible = false
	move_tooltip.hide()
	forfeit_confirmation.visible = false
	_set_forfeit_enabled(false)
	_clear_target_states()
	pending_move.clear()
	selected_targets.clear()
	presenter.visual_state.clear()
	_clear_combatant_views()
	_pending_extra_minion_animation_ids.clear()
	_turns_played = 0
	_replay_cursor = 0
	_replay_finished = false
	var campaign_runtime: Variant = get_node_or_null("/root/CampaignRuntime")
	catalog = campaign_runtime.catalog if (campaign_mode or not net_role.is_empty()) and campaign_runtime != null else RecoveredCatalog
	for required_pack in [BATTLE_DEMO_PACK, CAMPAIGN_SLICE_PACK]:
		var already_loaded := false
		for pack in catalog.packs:
			if pack != null and pack.id == required_pack.id:
				already_loaded = true
				break
		if not already_loaded:
			catalog.packs.append(required_pack)
	var catalog_errors := catalog.ensure_index()
	if not catalog_errors.is_empty():
		_show_startup_fatal("Content error: %s" % ", ".join(catalog_errors))
		return
	if net_role in [&"spectator", &"pvp", &"ally", &"replay"]:
		await _start_network_battle()
		return
	if campaign_mode and campaign_runtime != null and campaign_runtime.session != null and campaign_runtime.session.state != null:
		var pending_context: Dictionary = campaign_runtime.session.state.pending_battle
		source_encounter = catalog.get_definition(StringName(pending_context.get("encounter_id", ""))) as EncounterDefinition
	else:
		source_encounter = catalog.get_definition(SOURCE_ENCOUNTER_ID) as EncounterDefinition
	if source_encounter == null:
		_show_startup_fatal("The source-backed trainer encounter is missing")
		return
	var rules := RuleSetDefinition.new()
	rules.id = &"base:rules/playable_battle"
	rules.display_name = "Recovered five-minion battle"
	rules.party_size = 5
	rules.configuration = {
		"ai_teams": [1],
		"ai_difficulty": {"trainer_type": "normal", "floor_rate": 0.5},
	}
	if campaign_mode:
		rules.display_name = "Campaign trainer battle"
		rules.configuration["refill_on_activation"] = true
		rules.configuration["ai_difficulty"] = {
			"trainer_type": String(source_encounter.source_trainer_type),
			"floor_rate": 0.5,
			"floor_index": source_encounter.source_floor_index,
		}
	var trainer_modifier_configuration: Dictionary = source_encounter.battle_modifier_configuration.duplicate(true)
	if not trainer_modifier_configuration.is_empty():
		rules.configuration["battle_modifiers"] = trainer_modifier_configuration
	controller = BattleController.new()
	campaign_settlement.clear()
	var setup: Dictionary = campaign_runtime.prepared_battle_setup.duplicate(true) if campaign_mode and campaign_runtime != null else _build_battle_setup()
	var battle_seed := 20260911
	if campaign_mode and campaign_runtime != null and campaign_runtime.session.state != null:
		battle_seed += int(campaign_runtime.session.state.battle_sequence)
	# Spectators and replays rebuild this exact battle from its wire form; start
	# from that form too so every engine sees identical Variant types.
	setup = bytes_to_var(var_to_bytes(setup))
	rules.configuration = bytes_to_var(var_to_bytes(rules.configuration))
	var net := _net()
	if campaign_mode and net != null and not String(net_spec.get("key", "")).is_empty():
		net_role = &"battler"
		_connect_network_battle(net)
		net_spec.merge({
			"kind": "trainer",
			"seed": battle_seed,
			"setup": setup,
			"rules": {"id": String(rules.id), "display_name": rules.display_name, "party_size": rules.party_size, "configuration": rules.configuration},
			"controllers": {0: net.local_peer_id()},
			"names": {0: net.local_name, 1: _trainer_display_name()},
			"encounter_id": String(source_encounter.id),
		}, true)
		net_spec.merge(_net_extras, true)
		net.publish_battle_spec(net_spec)
	_ai_teams = rules.configuration.get("ai_teams", [1])
	var response := controller.start(setup, catalog, rules, BattleRng.new(battle_seed))
	if not response.accepted:
		_show_startup_fatal("Battle could not start: %s" % response.message)
		return
	if campaign_mode:
		_begin_campaign_recording(setup, rules, battle_seed)
	await _present_battle_entry(response, rules)

func _trainer_display_name() -> String:
	var dialogue: Dictionary = preload("res://src/application/source_trainer_dialogue.gd").for_encounter(source_encounter)
	return String(dialogue.get("trainer_name", "Trainer"))

## Spectator/arena start: everything comes from the published spec.
# --- Minion stats -----------------------------------------------------------------------------

## Your minions (the left side: your team, your side of a double battle,
## the recorder's side of a replay) show their stats. An enemy shows only its
## name and types, and only once you have faced that species before (it is
## in your Minion-pedia). A spectator inspects nobody.
func _inspectable_view_at(canvas_point: Vector2) -> BattleCombatantView:
	if net_role == &"spectator" or _battle_result_presented or forfeit_confirmation.visible:
		return null
	var hovered := get_viewport().gui_get_hovered_control()
	if hovered is BaseButton or (hovered != null and move_panel.is_ancestor_of(hovered)):
		return null
	for view in combatant_views.values():
		var candidate := view as BattleCombatantView
		if candidate == null or candidate.state_cache.is_empty() or not candidate.health_bar_contains_canvas_point(canvas_point):
			continue
		if candidate.team == 0 or _faced_before(candidate.minion_definition):
			return candidate
	return null

func _faced_before(definition: MinionDefinition) -> bool:
	if definition == null or net_role == &"replay":
		return false
	var runtime: Variant = get_node_or_null("/root/CampaignRuntime")
	var state = runtime.session.state if runtime != null and runtime.session != null else null
	if state == null:
		return false
	var id := String(definition.id)
	if id not in state.progression.get("seen_minion_ids", []):
		return false
	# Added to the pedia at the start of this very fight: not faced before.
	return not (campaign_mode and id in state.pending_battle.get("first_seen_minion_ids", []))

## A click on an inspectable health bar opens (or closes) its panel; any other
## click closes it and carries on as usual. True when the click was used.
func _handle_stats_click(canvas_point: Vector2) -> bool:
	var view := _inspectable_view_at(canvas_point)
	if view == null:
		if stats_panel.visible:
			stats_panel.close()
		return false
	if stats_panel.visible and stats_panel.instance_id == view.instance_id:
		stats_panel.close()
		return true
	move_tooltip.hide()
	if view.team == 0:
		stats_panel.show_own(view, catalog)
	else:
		stats_panel.show_enemy(view, catalog)
	_stats_signature = hash(view.state_cache)
	return true

## Follow the minion as the turn is animated (health, stages...).
func _refresh_stats_panel() -> void:
	if stats_panel == null or not stats_panel.visible:
		return
	var view := combatant_views.get(String(stats_panel.instance_id)) as BattleCombatantView
	if view == null or not is_instance_valid(view):
		stats_panel.close()
		return
	var signature := hash(view.state_cache)
	if signature != _stats_signature:
		_stats_signature = signature
		stats_panel.refresh(view)

func _start_network_battle() -> void:
	var encounter_id := String(net_spec.get("encounter_id", ""))
	source_encounter = catalog.get_definition(StringName(encounter_id)) as EncounterDefinition if not encounter_id.is_empty() else null
	var rules := BattleReplay.make_rules(net_spec.get("rules", {}))
	_ai_teams = rules.configuration.get("ai_teams", [1])
	controller = BattleController.new()
	campaign_settlement.clear()
	var setup: Dictionary = (net_spec.get("setup", {}) as Dictionary).duplicate(true)
	var response := controller.start(setup, catalog, rules, BattleRng.new(int(net_spec.get("seed", 0))))
	if not response.accepted:
		_show_startup_fatal(("This replay could not start: %s" if net_role == &"replay" else "Shared battle could not start: %s") % response.message)
		await get_tree().create_timer(2.0).timeout
		network_battle_finished.emit()
		return
	if net_role != &"replay":
		_begin_network_recording()
	await _present_battle_entry(response, rules)

# --- Battle history ------------------------------------------------------------------------

func _begin_campaign_recording(setup: Dictionary, rules: RuleSetDefinition, battle_seed: int) -> void:
	var campaign_runtime: Variant = get_node_or_null("/root/CampaignRuntime")
	var state = campaign_runtime.session.state if campaign_runtime != null and campaign_runtime.session != null else null
	var net := _net()
	var own_name := "You"
	if net != null:
		own_name = String(net.local_name)
	elif state != null:
		own_name = String(state.character.get("name", "You"))
	var double := bool(_net_extras.get("double", false))
	if double and net != null:
		for peer_id in (_net_extras.get("actor_controllers", {}) as Dictionary).values():
			own_name += " & " + String(net.player_name(int(peer_id)))
			break
	var extras := {"content": String(catalog.content_version), "encounter_id": String(source_encounter.id), "double_teams": _double_teams, "role": "fighter"}
	if state != null and not bool(state.progression.get("in_tower_lobby", false)):
		extras["floor"] = int(state.progression.get("floor_index", 0))
	var rule_data := {"id": String(rules.id), "display_name": rules.display_name, "party_size": rules.party_size, "configuration": rules.configuration}
	_start_recording(BattleReplay.create("double" if double else "trainer", battle_seed, setup, rule_data, {0: own_name, 1: _trainer_display_name()}, 0, extras))

## Arena fights, double battle partners and watched battles, from the published spec.
func _begin_network_recording() -> void:
	var names: Dictionary = (net_spec.get("names", {}) as Dictionary).duplicate(true)
	var net := _net()
	if net_role == &"ally" and net != null:
		names[0] = "%s & %s" % [String(names.get(0, "Partner")), String(net.local_name)]
	var kind := "double" if bool(net_spec.get("double", false)) else String(net_spec.get("kind", "pvp"))
	var extras := {"content": String(catalog.content_version), "encounter_id": String(net_spec.get("encounter_id", "")), "double_teams": _double_teams, "role": "watcher" if net_role == &"spectator" else "fighter"}
	var pov := 1 if _local_teams == [1] else 0
	_start_recording(BattleReplay.create(kind, int(net_spec.get("seed", 0)), net_spec.get("setup", {}), net_spec.get("rules", {}), names, pov, extras))

func _start_recording(replay: Dictionary) -> void:
	_recording = replay
	_recording_saved = false

func _finish_recording(result: BattleResult) -> void:
	if _recording.is_empty() or _recording_saved:
		return
	BattleReplay.record_result(_recording, result, _turns_played)
	_save_recording()

func _save_recording() -> void:
	_recording_saved = true
	BattleHistoryRepository.new().add(_recording)

func _present_battle_entry(response: BattleResponse, rules: RuleSetDefinition) -> void:
	active_battle_modifiers = (rules.configuration.get("battle_modifiers", {}) as Dictionary).duplicate(true)
	_original_player_ids.clear()
	for initial_state in controller.engine.snapshot().state.combatants:
		if int(initial_state.team) == 0:
			_original_player_ids[String(initial_state.instance_id)] = true
	# BattleScreen.PlayStartingAnimation starts the track after one second.
	# Keep the outgoing exploration fade intact until this source handoff.
	_battle_music_start_tween = create_tween()
	_battle_music_start_tween.tween_interval(1.0)
	_battle_music_start_tween.tween_callback(audio_controller.play_battle_music)
	var entry_started_usec := _now_usec()
	_sync_from_engine()
	_stagger_entry_teleports()
	_sync_battle_modifier_visuals(active_battle_modifiers)
	var entry_events: Array[BattleEvent] = []
	var initial_shields: Array[BattleEvent] = []
	for event in response.events:
		if event.kind == &"battle_mod_shields_assigned": initial_shields.append(event)
		else: entry_events.append(event)
	if not initial_shields.is_empty():
		for view in combatant_views.values():
			(view as BattleCombatantView).defer_battle_mod_shield_entry()
	battle_entry_animation_started.emit()
	await _present(entry_events)
	await _wait_until_usec(entry_started_usec + int(BATTLE_ENTRY_ANIMATION_SECONDS * 1000000.0))
	battle_entry_animation_finished.emit()
	await _run_campaign_intro_tutorial(entry_started_usec)
	# StartRound assigns shields after teleport/tutorial playback, not during
	# StartActivate. Keep engine targeting intact while deferring presentation.
	if not initial_shields.is_empty():
		await _present(initial_shields)
	busy = false
	await _continue_battle()

## BattleScreenVisualController.PlayIntroAnimation: the minions teleport in
## one by one, opponent then player for each slot, the first after 1 s and
## then every 0.2 s. The views are built hidden behind the room's fade-out, so
## starting all teleports at once left only their tails visible.
func _stagger_entry_teleports() -> void:
	for view in combatant_views.values():
		var minion := view as BattleCombatantView
		if minion == null or not minion.visible:
			continue
		var state := _combatant_state(minion.instance_id)
		var order := int(state.get("slot_index", minion.slot_index)) * 2 + (0 if int(state.get("team", 0)) == 1 else 1)
		minion.hold_for_entry()
		get_tree().create_timer(1.0 + float(order) * 0.2).timeout.connect(func() -> void:
			if is_instance_valid(minion) and minion.is_inside_tree():
				minion.play_extra_minion_spawn_animation()
		)

func _run_campaign_intro_tutorial(entry_started_usec: int) -> void:
	if not campaign_mode:
		return
	var runtime: Variant = get_node_or_null("/root/CampaignRuntime")
	if runtime == null or runtime.session == null or runtime.session.state == null:
		return
	var tutorial_id := _campaign_intro_tutorial_id(runtime.session)
	if tutorial_id.is_empty():
		await _wait_until_usec(entry_started_usec + 3200000)
		return
	await _wait_until_usec(entry_started_usec + 3500000)
	var tutorial := preload("res://src/presentation/source_campaign_tutorial_view.gd").new()
	tutorial.name = "CampaignIntroTutorial"
	add_child(tutorial)
	tutorial.configure(runtime.session, tutorial_id, audio_controller)
	await tutorial.completed
	# IntroTutFinished waits .9s from OK; the tutorial's exit uses the first .5s.
	await get_tree().create_timer(0.4).timeout

func _campaign_intro_tutorial_id(session) -> String:
	var progression: Dictionary = session.state.progression
	if not bool(progression.get("battle_basics_tutorial_seen", false)):
		return "battle_basics"
	if int(progression.get("floor_index", 0)) == 1 and not bool(progression.get("focus_targets_tutorial_seen", false)):
		var room := catalog.get_definition(session.state.current_room_id) as RoomDefinition
		if room != null:
			for interaction in room.interactions:
				if StringName(interaction.get("encounter_id", "")) == source_encounter.id and int(interaction.get("trainer_room_id", -1)) == 1:
					return "focus_targets"
	for pair in [["shield", "shield_modifier"], ["move_timer", "move_timer_modifier"], ["extra_minions", "extra_minions_modifier"], ["resurrection", "resurrection_modifier"]]:
		var config: Dictionary = active_battle_modifiers.get(pair[0], {})
		if not config.is_empty() and not bool(progression.get(String(pair[1]) + "_tutorial_seen", false)):
			return String(pair[1])
	return ""

func _decision_tutorial_id(session, decision: Dictionary) -> String:
	var progression: Dictionary = session.state.progression
	var keys := int(progression.get("floor_keys", 0))
	if keys == 1 and not bool(progression.get("energy_tutorial_seen", false)):
		return "energy"
	var actor: Dictionary = _combatant_state(StringName(decision.actor_id))
	if keys == 2 and StringName(actor.get("definition_id", "")) == &"base:minion/fire_pig_1" and not bool(progression.get("type_effectiveness_tutorial_seen", false)):
		return "type_effectiveness"
	return ""

func _run_decision_tutorial(decision: Dictionary) -> void:
	if not campaign_mode:
		return
	var runtime: Variant = get_node_or_null("/root/CampaignRuntime")
	if runtime == null or runtime.session == null or runtime.session.state == null:
		return
	var tutorial_id := _decision_tutorial_id(runtime.session, decision)
	if tutorial_id.is_empty():
		return
	busy = true
	_set_forfeit_enabled(false)
	move_tooltip.hide()
	await get_tree().create_timer(0.8).timeout
	var tutorial := preload("res://src/presentation/source_campaign_tutorial_view.gd").new()
	tutorial.name = "CampaignDecisionTutorial"
	add_child(tutorial)
	tutorial.configure(runtime.session, tutorial_id, audio_controller)
	await tutorial.completed
	busy = false
	_set_forfeit_enabled(true)

func _build_battle_setup() -> Dictionary:
	var combatants: Array[Dictionary] = []
	for slot_index in PLAYER_SHOWCASE_ROSTER.size():
		var definition := catalog.get_definition(PLAYER_SHOWCASE_ROSTER[slot_index]) as MinionDefinition
		if definition == null:
			continue
		var player_moves: Array[StringName] = []
		for move_id in definition.initial_move_ids:
			player_moves.append(move_id)
		for move_id in PLAYER_SHOWCASE_EXTRA_MOVES[slot_index]:
			if not player_moves.has(move_id):
				player_moves.append(move_id)
		combatants.append(_make_combatant(definition, StringName("player-%d" % (slot_index + 1)), 0, slot_index, 25, player_moves))
	for entry in source_encounter.team_entries:
		var slot_index := int(entry.get("slot_index", 0))
		var definition := catalog.get_definition(StringName(entry.get("definition_id", ""))) as MinionDefinition
		if definition == null:
			continue
		var enemy_moves: Array[StringName] = []
		var source_move_ids: Array = entry.get("move_ids", [])
		var preferred_move_ids: Array = SHOWCASE_ENEMY_MOVE_IDS.get(definition.id, [])
		for move_id in preferred_move_ids:
			var preferred_id := StringName(move_id)
			if source_move_ids.has(preferred_id):
				enemy_moves.append(preferred_id)
		if enemy_moves.is_empty():
			for move_id in source_move_ids:
				enemy_moves.append(StringName(move_id))
				if enemy_moves.size() >= 3:
					break
		# The source encounter is a hard-mode roster. Scale only this practice copy
		# down seven levels and trim to representative authored moves so its derived
		# stats and move count are comparable to the varied test party. The recovered
		# EncounterDefinition remains unchanged.
		var source_level := int(entry.get("level", 25))
		var practice_level := maxi(1, source_level + SHOWCASE_ENEMY_LEVEL_OFFSET)
		combatants.append(_make_combatant(definition, StringName("enemy-%d" % (slot_index + 1)), 1, slot_index, practice_level, enemy_moves))
	return {"battle_id": "source-hard-floor1-room1-five-v-five", "tie_first_team": 0, "combatants": combatants}

func _make_combatant(definition: MinionDefinition, instance_id: StringName, team: int, slot_index: int, level: int, moves: Array[StringName]) -> Dictionary:
	var stats := LegacyMinionStats.current_stats(definition, level)
	return {
		"instance_id": instance_id, "definition_id": definition.id, "team": team, "slot_index": slot_index,
		"level": level, "type_ids": definition.type_ids, "move_ids": moves,
		"base_max_health": stats.health, "max_health": stats.health, "health": stats.health,
		"base_max_energy": stats.energy, "max_energy": stats.energy, "energy": stats.energy,
		"attack": stats.attack, "healing": stats.healing, "speed": stats.speed,
		"max_attack_stat": LegacyMinionStats.max_attack_stat(definition),
		"max_healing_stat": LegacyMinionStats.max_healing_stat(definition),
	}

func _continue_battle() -> void:
	if busy:
		return
	var result = controller.engine.get_result()
	if not result.is_empty():
		_show_result(result)
		return
	var decision := controller.engine.get_decision()
	if decision.is_empty():
		return
	_update_current_turn_indicator(StringName(decision.actor_id))
	if int(decision.team) in _ai_teams:
		_set_forfeit_enabled(false)
		busy = true
		_animate_move_selector_out()
		_clear_target_states()
		event_text.text = "%s is choosing a move…" % _combatant_label(StringName(decision.actor_id))
		await get_tree().create_timer(0.1).timeout
		var ai_response := controller.submit_ai_turn()
		await _handle_response(ai_response)
		return
	if net_role == &"replay":
		_set_forfeit_enabled(false)
		busy = true
		_clear_target_states()
		var recorded := await _next_replay_command(decision)
		if recorded == null:
			return
		var replayed := controller.submit(recorded)
		if not replayed.accepted:
			_end_replay("The recording stops here.", "This replay no longer matches the game.")
			return
		await _handle_response(replayed)
		return
	if not _is_local_decision(decision):
		_set_forfeit_enabled(false)
		busy = true
		_animate_move_selector_out()
		_clear_target_states()
		event_text.get_parent().visible = true
		event_text.text = "%s is choosing a move…" % _decision_owner_name(decision)
		var remote_command := await _await_network_turn(decision)
		if remote_command == null:
			return
		event_text.get_parent().visible = false
		var pre_snapshot: Dictionary = controller.engine.snapshot() if not _recording.is_empty() else {}
		var remote_response := controller.submit(remote_command)
		if remote_response.accepted and not _recording.is_empty():
			BattleReplay.record_command(_recording, remote_command, pre_snapshot)
		await _handle_response(remote_response)
		return
	_set_forfeit_enabled(true)
	_build_move_buttons(decision)
	await _run_decision_tutorial(decision)

## The move selector, for the acting minion (`shown_id` empty) or, as in the
## source's BattleScreenVisualController.reportClick, for another of your
## minions you clicked: its moves are shown greyed out and cannot be chosen
## (MoveSelectorForPlayer.BringIn(false) desaturates the whole selector).
func _build_move_buttons(decision: Dictionary, shown_id: StringName = &"") -> void:
	_reset_move_selector_animation()
	move_tooltip.hide()
	_clear_buttons(move_buttons)
	var actor_id := StringName(decision.actor_id) if shown_id.is_empty() else shown_id
	var interactive := actor_id == StringName(decision.actor_id)
	_selector_decision = decision
	_selector_minion_id = actor_id
	_position_move_panel(actor_id)
	move_panel.visible = true
	move_panel.modulate = Color(1.0, 1.0, 1.0, 1.0) if interactive else Color(0.58, 0.58, 0.62, 1.0)
	var focus_ids: Array[StringName] = [actor_id]
	_focus_combatants(focus_ids)
	var actor_state := _combatant_state(actor_id)
	turn_title.text = "%d/%d" % [int(actor_state.get("energy", 0)), int(actor_state.get("max_energy", 0))]
	turn_title.add_theme_font_override("font", BURBIN_FONT)
	energy_fill.max_value = maxf(1.0, float(actor_state.get("max_energy", 1)))
	energy_fill.value = float(actor_state.get("energy", 0))
	var has_other_legal_move: bool = not interactive or decision.legal_moves.any(func(legal_move: Dictionary): return StringName(legal_move.move_id) != DESPERATION_MOVE_ID)
	var is_energy_limited := _is_energy_limited_fallback(actor_state)
	out_of_energy_tip.visible = not has_other_legal_move and is_energy_limited
	cooldown_tip.visible = not has_other_legal_move and not is_energy_limited
	var legal_by_id: Dictionary = {}
	for legal_move in decision.legal_moves if interactive else []:
		legal_by_id[StringName(legal_move.move_id)] = legal_move
	var displayed_move_ids: Array[StringName] = []
	for move_id in actor_state.get("move_ids", []):
		var learned_move := catalog.get_definition(StringName(move_id)) as MoveDefinition
		if learned_move != null and not learned_move.is_passive and not learned_move.is_global_passive:
			displayed_move_ids.append(learned_move.id)
	if not has_other_legal_move:
		displayed_move_ids.append(DESPERATION_MOVE_ID)
	var move_slot := 0
	var source_x := [-37.0, 41.0, 117.0, -37.0, 41.0, 117.0, -37.0, 41.0, 117.0, -37.0, 41.0, 117.0]
	var source_y := [-21.0, -45.0, -21.0, 49.0, 73.0, 49.0, -91.0, -115.0, -91.0, -161.0, -185.0, -161.0]
	for move_id in displayed_move_ids:
		var move := catalog.get_definition(move_id) as MoveDefinition
		if move == null:
			continue
		var legal_move: Dictionary = legal_by_id.get(move_id, {})
		var can_use := not legal_move.is_empty()
		if not interactive:
			# Greyed like the source's SetIsTheMoveActive: affordable and ready.
			var preview_cooldowns: Dictionary = actor_state.get("cooldowns", {})
			can_use = int(actor_state.get("energy", 0)) >= move.energy_cost and int(preview_cooldowns.get(move.id, preview_cooldowns.get(String(move.id), 0))) <= 0
		var button := Button.new()
		button.set_meta("move_id", move.id)
		button.set_meta("usable", can_use)
		var is_desperation := move.id == DESPERATION_MOVE_ID
		var current_move_slot := move_slot
		var final_button_position := Vector2(-135.0, -60.0) if is_desperation else Vector2(source_x[mini(move_slot, 11)], source_y[mini(move_slot, 11)])
		button.position = final_button_position
		button.set_meta("selector_final_position", final_button_position)
		button.set_meta("selector_ordinary_move", not is_desperation)
		button.size = Vector2(54.0, 52.0)
		button.pivot_offset = button.size * 0.5
		button.icon = _move_icon(move)
		button.expand_icon = true
		button.modulate.a = 1.0 if can_use else 0.3
		for state_name in [&"normal", &"hover", &"pressed", &"focus", &"disabled"]:
			button.add_theme_stylebox_override(state_name, StyleBoxEmpty.new())
		button.mouse_entered.connect(_show_move_tooltip.bind(move))
		button.mouse_exited.connect(_hide_move_tooltip)
		if can_use and interactive:
			button.pressed.connect(_choose_move.bind(legal_move.duplicate(true)))
			button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		move_buttons.add_child(button)
		var name_bubble := Label.new()
		name_bubble.name = "MoveNameBubble"
		name_bubble.text = move.display_name
		# VisualMoveButtonObject: BurbinCasual 10 in a 17px black bubble, as wide
		# as the name plus 10 once the name is over 60px, otherwise 70.
		var name_text_width := BURBIN_FONT.get_string_size(move.display_name, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 10).x
		var name_bubble_width := name_text_width + 10.0 if name_text_width > 60.0 else 70.0
		var bubble_x := -21.0 - (name_bubble_width - 70.0) if current_move_slot % 3 == 0 else (-11.0 - (name_bubble_width - 70.0) * 0.5 if current_move_slot % 3 == 1 else -1.0)
		var bubble_y := 49.0 if current_move_slot in [3, 4, 5] else -19.0
		name_bubble.position = Vector2(bubble_x, bubble_y)
		name_bubble.size = Vector2(name_bubble_width, 17.0)
		name_bubble.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_bubble.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_bubble.add_theme_font_override("font", BURBIN_FONT)
		name_bubble.add_theme_font_size_override("font_size", 10)
		name_bubble.add_theme_color_override("font_color", Color8(235, 235, 235))
		name_bubble.add_theme_stylebox_override("normal", _move_name_bubble_style())
		name_bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(name_bubble)
		var name_arrow := ColorRect.new()
		name_arrow.name = "MoveNameArrow"
		name_arrow.color = Color.BLACK
		name_arrow.size = Vector2(7.0, 7.0)
		name_arrow.position = Vector2(25.0, 44.0 if current_move_slot in [3, 4, 5] else -8.0)
		name_arrow.rotation_degrees = 45.0
		name_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(name_arrow)
		# Behind the bubble, as VisualMoveButtonObject adds it first.
		button.move_child(name_arrow, name_bubble.get_index())
		var cooldowns: Dictionary = actor_state.get("cooldowns", {})
		var turns_left := int(cooldowns.get(move.id, cooldowns.get(String(move.id), 0)))
		if turns_left > 0:
			var overlay := Panel.new()
			overlay.name = "CooldownOverlay"
			overlay.size = button.size
			overlay.scale.y = clampf(1.0 - float(turns_left) / float(move.cooldown_turns + 1), 0.08, 1.0)
			overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var overlay_style := StyleBoxFlat.new()
			overlay_style.bg_color = Color.WHITE
			overlay_style.set_corner_radius_all(6)
			overlay.add_theme_stylebox_override("panel", overlay_style)
			button.add_child(overlay)
		if move.id != DESPERATION_MOVE_ID:
			move_slot += 1
	event_text.text = "Your turn — choose a move"
	_animate_move_selector_in()
	if interactive:
		_show_move_selection_hint()

## While you choose a move (BattleScreenVisualController.reportClick): a click
## on one of your minions opens its selector (only the acting one can choose),
## a click on empty ground closes the selector and its grey layer. True when
## the click was used.
func _handle_selector_click(canvas_point: Vector2) -> bool:
	var target := _selector_click_target(canvas_point)
	if target.is_empty():
		return false
	var clicked := target.get("minion") as BattleCombatantView
	if clicked != null:
		if _selector_would_open(clicked):
			_build_move_buttons(controller.engine.get_decision(), clicked.instance_id)
		return true
	if _selector_minion_id.is_empty():
		return false
	_selector_minion_id = &""
	move_tooltip.hide()
	_animate_move_selector_out()
	_fade_battle_grey_out()
	return true

## What a click at `canvas_point` would hit while you choose a move: {} when
## the selector logic does not take it, {"minion": view} on one of your living
## minions, {"ground": true} elsewhere.
func _selector_click_target(canvas_point: Vector2) -> Dictionary:
	if busy or not pending_move.is_empty() or forfeit_confirmation.visible or _selector_decision.is_empty():
		return {}
	var decision := controller.engine.get_decision()
	if decision.is_empty() or int(decision.revision) != int(_selector_decision.revision) or not _is_local_decision(decision):
		return {}
	var hovered := get_viewport().gui_get_hovered_control()
	if hovered is BaseButton or (hovered != null and move_panel.is_ancestor_of(hovered) and hovered.mouse_filter != Control.MOUSE_FILTER_IGNORE):
		return {}
	# MoveSelectorForPlayer's collision background: drawRect(-60, -70, 240, 220)
	# around the selector. A click there neither closes it nor picks a minion.
	var selector_area := move_panel.get_global_transform_with_canvas() * Rect2(-60.0, -70.0, 240.0, 220.0)
	if move_panel.visible and not _move_selector_exiting and selector_area.has_point(canvas_point):
		return {}
	var candidates: Array = combatant_views.values()
	candidates.sort_custom(func(left: BattleCombatantView, right: BattleCombatantView) -> bool: return left.position.y > right.position.y)
	for view in candidates:
		var candidate := view as BattleCombatantView
		if candidate.team == 0 and not bool(candidate.state_cache.get("defeated", false)) and int(candidate.state_cache.get("health", 1)) > 0 and candidate.contains_canvas_point(canvas_point):
			return {"minion": candidate}
	return {"ground": true}

func _selector_would_open(view: BattleCombatantView) -> bool:
	return view.instance_id != _selector_minion_id or not move_panel.visible or _move_selector_exiting

func _show_move_selection_hint() -> void:
	if not campaign_mode:
		return
	var runtime: Variant = get_node_or_null("/root/CampaignRuntime")
	if runtime == null or runtime.session == null or bool(runtime.session.state.progression.get("move_select_tutorial_seen", false)):
		return
	if not is_instance_valid(_move_selection_hint):
		_move_selection_hint = SourceMenuArt.image(self, "tutorial_chooseAMove", Vector2(306, 33))
		_move_selection_hint.z_index = 1100
	if is_instance_valid(_move_hint_tween):
		_move_hint_tween.kill()
	_move_selection_hint.visible = true
	_move_selection_hint.modulate.a = 0.0
	_move_hint_tween = create_tween()
	_move_hint_tween.tween_property(_move_selection_hint, "modulate:a", 1.0, 0.5).set_delay(0.5)

func _hide_move_selection_hint(immediate: bool = false) -> void:
	if not is_instance_valid(_move_selection_hint):
		return
	if is_instance_valid(_move_hint_tween):
		_move_hint_tween.kill()
	if immediate:
		_move_selection_hint.visible = false
		return
	_move_hint_tween = create_tween()
	_move_hint_tween.tween_property(_move_selection_hint, "modulate:a", 0.0, 0.5)
	_move_hint_tween.tween_callback(func() -> void: _move_selection_hint.visible = false)

func _animate_move_selector_in() -> void:
	var index := 0
	for child in move_buttons.get_children():
		var button := child as Button
		if button == null or not bool(button.get_meta("selector_ordinary_move", false)):
			continue
		button.position = Vector2(-142.0, 69.0)
		# A move sliding in under a still mouse must not pop its tooltip; the
		# button takes the mouse once it has arrived.
		button.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var name_bubble := button.get_node_or_null("MoveNameBubble") as Label
		var name_arrow := button.get_node_or_null("MoveNameArrow") as ColorRect
		if name_bubble != null:
			name_bubble.modulate.a = 0.0
		if name_arrow != null:
			name_arrow.modulate.a = 0.0
		# Owned by the button: it can never call back into a freed button.
		var movement := button.create_tween()
		movement.tween_property(button, "position", button.get_meta("selector_final_position"), 0.3 + float(index) * 0.1).set_delay(float(index) * 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		movement.tween_property(button, "mouse_filter", Control.MOUSE_FILTER_STOP, 0.0)
		_move_selector_tweens.append(movement)
		var label_delay := 0.3 + float(index) * 0.2
		if name_bubble != null:
			var bubble_tween := create_tween()
			bubble_tween.tween_property(name_bubble, "modulate:a", 1.0, 0.2).set_delay(label_delay)
			_move_selector_tweens.append(bubble_tween)
		if name_arrow != null:
			var arrow_tween := create_tween()
			arrow_tween.tween_property(name_arrow, "modulate:a", 1.0, 0.2).set_delay(label_delay)
			_move_selector_tweens.append(arrow_tween)
		index += 1

func _animate_move_selector_out() -> void:
	_hide_move_selection_hint()
	if not move_panel.visible or _move_selector_exiting:
		return
	for tween in _move_selector_tweens:
		if tween != null and tween.is_running():
			tween.kill()
	_move_selector_tweens.clear()
	_move_selector_exiting = true
	var ordinary_buttons: Array[Button] = []
	for child in move_buttons.get_children():
		var button := child as Button
		if button == null or not bool(button.get_meta("selector_ordinary_move", false)):
			continue
		ordinary_buttons.append(button)
		button.disabled = true
	var move_count := ordinary_buttons.size()
	for index in move_count:
		var button := ordinary_buttons[index]
		var movement := create_tween()
		movement.tween_property(button, "position", Vector2(-142.0, 69.0), 0.3 + float(index) * 0.1).set_delay(float(index) * 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		_move_selector_tweens.append(movement)
		var name_bubble := button.get_node_or_null("MoveNameBubble") as Label
		var name_arrow := button.get_node_or_null("MoveNameArrow") as ColorRect
		if name_bubble != null:
			var bubble_tween := create_tween()
			bubble_tween.tween_property(name_bubble, "modulate:a", 0.0, 0.2)
			_move_selector_tweens.append(bubble_tween)
		if name_arrow != null:
			var arrow_tween := create_tween()
			arrow_tween.tween_property(name_arrow, "modulate:a", 0.0, 0.2)
			_move_selector_tweens.append(arrow_tween)
	var fade_delay := 1.0 if move_count > 5 else maxf(0.0, float(move_count - 1) * 0.2)
	var panel_tween := create_tween()
	panel_tween.tween_property(move_panel, "modulate:a", 0.0, 0.3).set_delay(fade_delay)
	panel_tween.tween_callback(func() -> void:
		move_panel.visible = false
		move_panel.modulate.a = 1.0
		_move_selector_exiting = false
		_move_selector_exit_deadline_usec = 0
	)
	_move_selector_tweens.append(panel_tween)
	_move_selector_exit_deadline_usec = _now_usec() + int((fade_delay + 0.3) * 1000000.0)

func _reset_move_selector_animation() -> void:
	_hide_move_selection_hint(true)
	for tween in _move_selector_tweens:
		if tween != null and tween.is_running():
			tween.kill()
	_move_selector_tweens.clear()
	_move_selector_exit_deadline_usec = 0
	_move_selector_exiting = false

func _is_energy_limited_fallback(actor_state: Dictionary) -> bool:
	var energy := int(actor_state.get("energy", 0))
	for move_id in actor_state.get("move_ids", []):
		var move := catalog.get_definition(StringName(move_id)) as MoveDefinition
		if move != null and move.available and not move.is_passive and not move.is_global_passive and energy >= move.energy_cost:
			return false
	return true

func _show_move_tooltip(move: MoveDefinition) -> void:
	if not busy and not _move_selector_exiting:
		move_tooltip.show_move(move)
		move_tooltip.follow_mouse(get_global_mouse_position(), size)

func _hide_move_tooltip() -> void:
	move_tooltip.hide()

func _position_move_panel(actor_id: StringName) -> void:
	var view := combatant_views.get(String(actor_id)) as BattleCombatantView
	if view == null:
		return
	move_panel.position = view.position + Vector2(117.0, -114.0)

func _move_name_bubble_style() -> StyleBoxFlat:
	# drawRoundRect(..., 17, 20): solid black, 10px corner radius, no padding.
	var style := StyleBoxFlat.new()
	style.bg_color = Color.BLACK
	style.set_corner_radius_all(10)
	style.set_content_margin_all(0.0)
	return style

func _choose_move(legal_move: Dictionary) -> void:
	if busy or _move_selector_exiting or forfeit_confirmation.visible:
		return
	if campaign_mode:
		var runtime: Variant = get_node_or_null("/root/CampaignRuntime")
		if runtime != null and runtime.session != null and not bool(runtime.session.state.progression.get("move_select_tutorial_seen", false)):
			var acknowledged: Dictionary = runtime.session.acknowledge_source_tutorial("move_select")
			if not acknowledged.ok:
				event_text.get_parent().visible = true
				event_text.text = "Could not save move guidance. Choose the move again to retry."
				return
	move_tooltip.hide()
	pending_move = legal_move
	selected_targets.clear()
	_animate_move_selector_out()
	var move := catalog.get_definition(StringName(legal_move.move_id)) as MoveDefinition
	if move == null:
		pending_move.clear()
		return
	var legal_ids: Array[StringName] = []
	for raw_id in legal_move.target_ids:
		legal_ids.append(StringName(raw_id))
	if move.target_mode != MoveDefinition.TargetMode.CHOSEN or move.target_side == MoveDefinition.TargetSide.SELF or move.target_count >= legal_ids.size():
		selected_targets.assign(legal_ids)
		_submit_pending_move()
		return
	for view in combatant_views.values():
		var combatant_view := view as BattleCombatantView
		var legal := legal_ids.has(combatant_view.instance_id)
		combatant_view.set_target_state(legal, false)
	_focus_combatants(legal_ids)
	_set_forfeit_enabled(false)
	var actor_view := combatant_views.get(String(controller.engine.get_decision().actor_id)) as BattleCombatantView
	if actor_view != null and actor_view.minion_sprite != null and actor_view.minion_sprite.texture != null:
		cancel_target.position = actor_view.position + Vector2(-28.0, -85.0 - actor_view.minion_sprite.texture.get_height())
		cancel_target.visible = true

func _on_combatant_clicked(target_id: StringName) -> void:
	if busy or pending_move.is_empty():
		return
	var legal_ids: Array = pending_move.get("target_ids", [])
	if not legal_ids.has(target_id) and not legal_ids.has(String(target_id)):
		return
	var move := catalog.get_definition(StringName(pending_move.move_id)) as MoveDefinition
	var required_count := mini(move.target_count, legal_ids.size())
	if selected_targets.has(target_id):
		selected_targets.erase(target_id)
	elif selected_targets.size() < required_count:
		selected_targets.append(target_id)
	for view in combatant_views.values():
		var combatant_view := view as BattleCombatantView
		combatant_view.set_target_state(legal_ids.has(combatant_view.instance_id) or legal_ids.has(String(combatant_view.instance_id)), selected_targets.has(combatant_view.instance_id))
	if selected_targets.size() == required_count:
		_submit_pending_move()

func _set_view_targetable(target_id: StringName, targetable: bool) -> void:
	var view := combatant_views.get(String(target_id)) as BattleCombatantView
	if view != null:
		view.set_target_state(targetable, selected_targets.has(target_id))

func _clear_target_states() -> void:
	_fade_battle_grey_out()
	for view in combatant_views.values():
		var combatant_view := view as BattleCombatantView
		combatant_view.z_index = int(combatant_view.position.y)
		combatant_view.set_target_state(false, false)

func _focus_combatants(ids: Array[StringName]) -> void:
	if _battle_grey_tween != null and _battle_grey_tween.is_running():
		_battle_grey_tween.kill()
	if not battle_grey_layer.visible:
		battle_grey_layer.modulate.a = 0.0
		battle_grey_layer.visible = true
	_battle_grey_tween = create_tween()
	_battle_grey_tween.tween_property(battle_grey_layer, "modulate:a", 1.0, 0.5)
	for view in combatant_views.values():
		var combatant_view := view as BattleCombatantView
		combatant_view.z_index = 700 if ids.has(combatant_view.instance_id) else int(combatant_view.position.y)

func _fade_battle_grey_out() -> void:
	if not battle_grey_layer.visible:
		return
	if _battle_grey_tween != null and _battle_grey_tween.is_running():
		_battle_grey_tween.kill()
	_battle_grey_tween = create_tween()
	var fade_tween := _battle_grey_tween
	fade_tween.tween_property(battle_grey_layer, "modulate:a", 0.0, 0.5)
	fade_tween.tween_callback(func() -> void:
		if _battle_grey_tween == fade_tween:
			battle_grey_layer.visible = false
	)

func _submit_pending_move() -> void:
	if busy or pending_move.is_empty():
		return
	_animate_move_selector_out()
	busy = true
	move_tooltip.hide()
	_set_forfeit_enabled(false)
	cancel_target.visible = false
	_clear_target_states()
	var decision := controller.engine.get_decision()
	var command := BattleCommand.new(StringName(decision.actor_id), BattleCommand.Kind.USE_MOVE, StringName(pending_move.move_id), selected_targets, int(decision.revision))
	pending_move.clear()
	selected_targets.clear()
	await _handle_response(_submit_local_command(command))

func _forfeit() -> void:
	if busy or forfeit_button.disabled:
		return
	move_tooltip.hide()
	forfeit_confirmation.visible = true
	_set_forfeit_enabled(false)

func _cancel_forfeit() -> void:
	forfeit_confirmation.visible = false
	_set_forfeit_enabled(true)

func _set_forfeit_enabled(enabled: bool) -> void:
	forfeit_button.disabled = not enabled
	forfeit_button.modulate.a = 1.0 if enabled else 0.3

func _confirm_forfeit() -> void:
	if busy or not forfeit_confirmation.visible:
		return
	busy = true
	forfeit_confirmation.visible = false
	_animate_move_selector_out()
	var decision := controller.engine.get_decision()
	var command := BattleCommand.new(StringName(decision.actor_id), BattleCommand.Kind.FORFEIT, &"", [], int(decision.revision))
	await _handle_response(_submit_local_command(command))

func _handle_response(response: BattleResponse) -> void:
	if not response.accepted:
		event_text.text = "Command rejected: %s" % response.message
		busy = false
		await _continue_battle()
		return
	_turns_played += 1
	if _replay_hud != null:
		_replay_hud.set_turn(_turns_played)
	var last_skipped_turn: BattleEvent = null
	for event in response.events:
		if event.kind in [&"turn_skipped", &"frozen_turn_skipped", &"stunned_turn_skipped", &"exhausted_turn_skipped"]:
			last_skipped_turn = event
	await _present(response.events)
	var play_extra_minion_entry := not _pending_extra_minion_animation_ids.is_empty()
	if last_skipped_turn != null:
		_set_event_text(last_skipped_turn)
	_sync_from_engine()
	if play_extra_minion_entry:
		await _wait_until_usec(_now_usec() + int(BATTLE_REPLACEMENT_HANDOFF_SECONDS * 1000000.0))
	busy = false
	await _continue_battle()

func _present(events: Array[BattleEvent]) -> void:
	var source_queue := preload("res://src/presentation/source_battle_event_queue.gd").build(events)
	var presentation_events: Array[BattleEvent] = source_queue.events
	var deferred_resources: Dictionary = source_queue.resource_events
	# The engine can have queued the next actor while the previous action's
	# animation / impact events are still being presented. Fade the old marker
	# away and hold the handoff until its source 0.3-second fade has finished.
	_hide_current_turn_indicator()
	_modifier_visual_completion_usec = 0
	var impact_deadlines_usec: Dictionary = {}
	var active_move_impact_deadline_usec := 0
	var move_visual_completion_deadline_usec := 0
	var visual_completion_deadline_usec := 0
	var periodic_phase_started := false
	var resurrection_phase_started := false
	var replacement_phase_started := false
	var timer_cast_ready_usec := 0
	var missed_move_visuals_queued := false
	var queued_callouts: Dictionary = {}
	var queued_stat_callouts: Array = []
	var queued_redirection_ids: Array = []
	var redirection_presented := false
	for event_index in presentation_events.size():
		var event := presentation_events[event_index]
		if (event.kind == &"cost_paid" and not deferred_resources.has(event)) or event.kind in [&"move_used", &"decision_requested", &"charge_started", &"charge_progressed", &"charge_released", &"frozen_turn_skipped", &"stunned_turn_skipped", &"exhausted_turn_skipped", &"round_started", &"battle_completed"]:
			# Automatic charged actions may share a response with the prior
			# attack. Source RunQueuedMoves finishes before the next cast/cost,
			# decision prompt, status-skip feedback or completed-battle handoff.
			await _wait_until_usec(maxi(move_visual_completion_deadline_usec, maxi(visual_completion_deadline_usec, _modifier_visual_completion_usec)))
		if event.kind == &"move_used":
			queued_callouts = event.values.get("visual_callouts", {})
			queued_stat_callouts = event.values.get("stat_callouts", [])
			queued_redirection_ids = event.values.get("redirection_callouts", [])
			redirection_presented = false
		var callout_already_played := _callout_was_queued(event, queued_callouts, queued_stat_callouts, queued_redirection_ids)
		if replacement_phase_started and event.kind != &"battle_mod_extra_spawned":
			await _wait_until_usec(_modifier_visual_completion_usec)
			replacement_phase_started = false
		if not replacement_phase_started and event.kind == &"battle_mod_extra_spawned":
			# CheckForWinLose replaces dead slots after the previous attack. Group
			# sibling replacements, then complete their entry before auto-actions.
			await _wait_until_usec(maxi(move_visual_completion_deadline_usec, visual_completion_deadline_usec))
			replacement_phase_started = true
		if not resurrection_phase_started and event.kind in [&"battle_mod_resurrection_progressed", &"battle_mod_resurrected"]:
			# CheckForWinLose handles all tombstones together after the attack,
			# not at the HP contact frame or staggered per defeated minion.
			await _wait_until_usec(maxi(move_visual_completion_deadline_usec, visual_completion_deadline_usec))
			resurrection_phase_started = true
		if event.kind == &"battle_mod_timer_triggered":
			# GetAPlayersMove is reached only after the previous source move's
			# queue finishes. Do not start the stone over its fading impact tail.
			var previous_finish_usec := maxi(move_visual_completion_deadline_usec, visual_completion_deadline_usec)
			previous_finish_usec = maxi(previous_finish_usec, _modifier_visual_completion_usec)
			await _wait_until_usec(previous_finish_usec)
		if event.kind == &"move_used" and timer_cast_ready_usec > 0:
			# The stone enlarges/spins before its AI casts, after exactly .7s.
			await _wait_until_usec(timer_cast_ready_usec)
			timer_cast_ready_usec = 0
		if periodic_phase_started and event.kind not in [&"periodic_tick", &"periodic_expired", &"periodic_health_applied"]:
			# A response can also contain an automatic charged turn or a new
			# round. Finish the grouped tick phase before presenting either.
			var periodic_wait_usec := visual_completion_deadline_usec - _now_usec()
			if periodic_wait_usec > 0:
				await get_tree().create_timer(float(periodic_wait_usec) / 1000000.0).timeout
			periodic_phase_started = false
		if not periodic_phase_started and event.kind in [&"periodic_tick", &"periodic_expired", &"periodic_health_applied"]:
			# BattleScreen.RunTickMoves starts all DOT/HOT visuals and health
			# transitions together, AFTER the final attack's queue has finished.
			# Per-target impact waits here staggered the whole round and allowed
			# the first DOT to overlap the final actor's attack.
			var attack_finish_usec := maxi(move_visual_completion_deadline_usec, visual_completion_deadline_usec)
			attack_finish_usec = maxi(attack_finish_usec, _modifier_visual_completion_usec)
			var attack_wait_usec := attack_finish_usec - _now_usec()
			if attack_wait_usec > 0:
				await get_tree().create_timer(float(attack_wait_usec) / 1000000.0).timeout
			periodic_phase_started = true
			impact_deadlines_usec.clear()
			active_move_impact_deadline_usec = 0
			visual_completion_deadline_usec = _visual_deadline_after(visual_completion_deadline_usec, 0.5)
		if event.kind == &"missed":
			visual_completion_deadline_usec = _visual_deadline_after(visual_completion_deadline_usec, 0.4 if missed_move_visuals_queued else 0.8)
		if event.kind == &"reflected_damage" and not callout_already_played:
			visual_completion_deadline_usec = _visual_deadline_after(visual_completion_deadline_usec, 0.9)
		if event.kind == &"turn_skipped":
			visual_completion_deadline_usec = _visual_deadline_after(visual_completion_deadline_usec, 0.8)
		if event.kind in [&"charge_started", &"frozen", &"frozen_turn_skipped", &"stunned", &"stunned_turn_skipped", &"exhausted_turn_skipped", &"stat_stage_changed"] and not callout_already_played:
			visual_completion_deadline_usec = _visual_deadline_after(visual_completion_deadline_usec, 0.9)
		var is_move_impact_event := deferred_resources.has(event) or event.kind in [&"damage", &"healed", &"shield_set", &"redirected_damage", &"reflected_damage", &"self_damage", &"periodic_applied", &"periodic_refreshed", &"frozen", &"stunned", &"stat_stage_changed", &"buffs_debuffs_cleared"]
		if is_move_impact_event:
			# Apply normal move effects at the source queue's m_moveTime-.1
			# boundary, independently of physical/sound contact callbacks.
			# Full VFX lifetime still gates the next actor below.
			var hit_deadline_usec := int(impact_deadlines_usec.get(String(event.target_id), active_move_impact_deadline_usec))
			var remaining_usec := hit_deadline_usec - _now_usec()
			if remaining_usec > 0:
				await get_tree().create_timer(float(remaining_usec) / 1000000.0).timeout
			if not redirection_presented:
				for redirector_id in queued_redirection_ids:
					var redirector_view := combatant_views.get(String(redirector_id)) as BattleCombatantView
					if redirector_view != null:
						redirector_view.show_redirection_feedback()
				redirection_presented = true
		_set_event_text(event)
		if event.kind == &"move_used":
			resurrection_phase_started = false
			missed_move_visuals_queued = not bool(event.values.get("hit", true)) and not event.values.get("target_ids", []).is_empty()
			impact_deadlines_usec.clear()
			active_move_impact_deadline_usec = 0
			_last_move_visual_duration_seconds = 0.0
		var should_present_immediately := event.kind in [&"move_used", &"periodic_tick", &"periodic_health_applied", &"periodic_expired", &"battle_mod_shields_assigned", &"battle_mod_shield_removed", &"battle_mod_resurrection_progressed", &"battle_mod_resurrected", &"battle_mod_extra_spawned"] or is_move_impact_event
		if should_present_immediately:
			presenter.play([event], true)
		else:
			await presenter.play([event], false)
		var visual_targets: Array[StringName] = []
		if event.kind == &"move_used":
			for target_id in event.values.get("target_ids", []):
				visual_targets.append(StringName(target_id))
		if event.kind in [&"periodic_tick", &"periodic_applied", &"periodic_refreshed"]:
			_last_move_visual_duration_seconds = 0.0
		var move_impact_delays: Dictionary = {}
		if event.kind == &"move_used":
			move_impact_delays = await _animate_queued_move(event, visual_targets)
		elif event.kind != &"missed" or not missed_move_visuals_queued:
			move_impact_delays = _animate_event(event, visual_targets, callout_already_played)
		if event.kind == &"move_used":
			for target_id in move_impact_delays:
				var impact_delay := float(move_impact_delays[target_id])
				var scheduled_impact_usec := _now_usec() + int(impact_delay * 1000000.0)
				impact_deadlines_usec[String(target_id)] = scheduled_impact_usec
				active_move_impact_deadline_usec = maxi(active_move_impact_deadline_usec, scheduled_impact_usec)
			if event.kind == &"move_used" and _last_move_visual_duration_seconds > 0.0:
				move_visual_completion_deadline_usec = maxi(
					move_visual_completion_deadline_usec,
					_now_usec() + int(_last_move_visual_duration_seconds * 1000000.0),
				)
			# BaseMoveSystem queues ApplyEffects(.2), then an unconditional
			# .4s tail. This is not conditional on HP/shield actually changing.
			visual_completion_deadline_usec = maxi(visual_completion_deadline_usec, maxi(_now_usec(), active_move_impact_deadline_usec) + 600000)
		elif event.kind in [&"periodic_tick", &"periodic_applied", &"periodic_refreshed"]:
			# Gate the next actor on the complete authored animation, not its
			# contact point. Tick health itself starts immediately, as in source.
			visual_completion_deadline_usec = _visual_deadline_after(visual_completion_deadline_usec, _last_move_visual_duration_seconds + (0.5 if event.kind == &"periodic_tick" else 0.0))
		var event_view := combatant_views.get(String(event.target_id)) as BattleCombatantView
		var previous_health_fill_x := event_view._health_visual_target_x if event_view != null else 0.0
		var previous_shield_fill_x := event_view._shield_visual_target_x if event_view != null else 0.0
		_apply_event_values(event)
		if event.kind == &"battle_mod_timer_triggered":
			timer_cast_ready_usec = _now_usec() + 700000
		if event_view != null and (not is_equal_approx(previous_health_fill_x, event_view._health_visual_target_x) or not is_equal_approx(previous_shield_fill_x, event_view._shield_visual_target_x)):
			# Health/shield tweens start at event application. Wait for their actual
			# completion deadline instead of adding another 0.6s after all effects.
			# Unchanged net-zero periodic events do not start a bar tween.
			visual_completion_deadline_usec = _visual_deadline_after(visual_completion_deadline_usec, 0.6)
		if event.kind == &"defeated":
			visual_completion_deadline_usec = _visual_deadline_after(visual_completion_deadline_usec, 1.7)
		if (event.kind != &"missed" or not missed_move_visuals_queued) and not callout_already_played:
			_play_event_audio(event)
	visual_completion_deadline_usec = maxi(visual_completion_deadline_usec, move_visual_completion_deadline_usec)
	visual_completion_deadline_usec = maxi(visual_completion_deadline_usec, _modifier_visual_completion_usec)
	visual_completion_deadline_usec = maxi(visual_completion_deadline_usec, _move_selector_exit_deadline_usec)
	visual_completion_deadline_usec = maxi(visual_completion_deadline_usec, _turn_indicator_fade_deadline_usec)
	await _wait_until_usec(visual_completion_deadline_usec)
	_modifier_visual_completion_usec = 0
	if _now_usec() >= _move_selector_exit_deadline_usec:
		_move_selector_exit_deadline_usec = 0
	if _now_usec() >= _turn_indicator_fade_deadline_usec:
		_turn_indicator_fade_deadline_usec = 0

func _visual_deadline_after(current_deadline_usec: int, duration_seconds: float) -> int:
	return maxi(current_deadline_usec, _now_usec() + int(duration_seconds * 1000000.0))

func _wait_until_usec(deadline_usec: int) -> void:
	# SceneTreeTimer can consume the creating frame's delta after a slow import
	# or shader frame. Recheck the absolute deadline before releasing the actor.
	while deadline_usec > _now_usec():
		await get_tree().create_timer(float(deadline_usec - _now_usec()) / 1000000.0).timeout

func _play_event_audio(event: BattleEvent) -> void:
	match event.kind:
		&"missed": audio_controller.play_sound("battle_whoosh_sword_swipe", 0.5)
		&"charge_started": audio_controller.play_sound("battle_charging", 0.4)
		&"exhausted_turn_skipped": audio_controller.play_sound("battle_exhausted", 0.9)
		&"frozen", &"frozen_turn_skipped": audio_controller.play_sound("battle_whoosh_wind", 1.0)
		&"stunned", &"stunned_turn_skipped": audio_controller.play_sound("battle_spark", 1.0)
		&"stat_stage_changed":
			audio_controller.play_sound("battle_buff" if int(event.values.get("amount", 0)) >= 0 else "battle_debuff", 0.5 if int(event.values.get("amount", 0)) >= 0 else 0.4)

func _callout_was_queued(event: BattleEvent, queued: Dictionary, stat_callouts: Array = [], redirection_ids: Array = []) -> bool:
	if event.kind == &"redirected_damage":
		return String(event.target_id) in redirection_ids
	if event.kind == &"stat_stage_changed":
		for callout in stat_callouts:
			if String(callout.target_id) == String(event.target_id) and String(callout.stat_type_id) == String(event.values.get("stat_type_id", "")) and int(callout.amount) == int(event.values.get("amount", 0)): return true
	if event.kind in [&"stunned", &"frozen"]:
		return String(event.kind) in queued.get(String(event.target_id), [])
	if event.kind == &"reflected_damage":
		return "reflection" in queued.get(String(event.actor_id), [])
	return false

func _animate_event(event: BattleEvent, visual_targets: Array[StringName] = [], callout_already_played: bool = false) -> Dictionary:
	if event.kind == &"missed":
		_animate_miss(event)
		return {}
	if event.kind == &"periodic_tick":
		return {String(event.target_id): _animate_periodic_tick(event)}
	if event.kind in [&"periodic_applied", &"periodic_refreshed"]:
		var periodic_move := catalog.get_definition(StringName(event.values.get("move_id", ""))) as MoveDefinition
		if periodic_move != null and _resolved_visual_id(periodic_move) == _resolved_dot_visual_id(periodic_move):
			return {}
		return {String(event.target_id): _animate_periodic_application(event)}
	if event.kind == &"move_used":
		var impact_delays: Dictionary = {}
		var move := catalog.get_definition(StringName(event.values.get("move_id", ""))) as MoveDefinition
		var visual_family := String(vfx_catalog.profile_for(_resolved_visual_id(move)).get("family", "")) if move != null else ""
		if visual_family == "screen_shake":
			# A quake is one shared field visual, but each affected minion must
			# retain its ApplyEffects deadline rather than receiving instant HP.
			var effect_delay := _animate_move_visual(event, visual_targets[0] if not visual_targets.is_empty() else &"")
			impact_delays[""] = effect_delay
			for target_id in visual_targets:
				impact_delays[String(target_id)] = effect_delay
		elif visual_targets.is_empty():
			impact_delays[""] = _animate_move_visual(event, &"")
		else:
			for target_id in visual_targets:
				impact_delays[String(target_id)] = _animate_move_visual(event, target_id)
		return impact_delays
	var target_view := combatant_views.get(String(event.target_id)) as BattleCombatantView
	if target_view == null:
		return {}
	var status_badge: Texture2D
	var status_label_text := ""
	match event.kind:
		&"charge_started": status_badge = BattleCombatantView.CHARGING_BADGE
		&"frozen", &"frozen_turn_skipped": status_badge = BattleCombatantView.FROZEN_BADGE
		&"stunned", &"stunned_turn_skipped": status_badge = BattleCombatantView.STUNNED_BADGE
		&"exhausted_turn_skipped": status_badge = BattleCombatantView.EXHAUSTED_BADGE
		&"stat_stage_changed":
			var stage_amount := int(event.values.get("amount", 0))
			if stage_amount == 0:
				return {}
			status_badge = BattleCombatantView.STAT_INCREASE_BADGE if stage_amount > 0 else BattleCombatantView.STAT_DECREASE_BADGE
			var stat_name := String(event.values.get("stat_type_id", "")).get_slice("/", 1)
			status_label_text = stat_name.capitalize() if not stat_name.is_empty() else "Health"
	if status_badge != null:
		if not callout_already_played:
			target_view.show_status_badge(status_badge, status_label_text)
		return {}
	if event.kind == &"reflected_damage" and not callout_already_played:
		target_view.show_reflected_damage_feedback()
	if event.kind in [&"damage", &"healed", &"missed", &"shield_set", &"redirected_damage", &"reflected_damage", &"self_damage"]:
		if event.kind in [&"damage", &"healed"]:
			if event.kind != &"healed" or bool(event.values.get("feedback_has_healing", true)):
				target_view.show_impact_feedback(float(event.values.get("effectiveness", 1.0)), bool(event.values.get("critical", false)))
		elif event.kind == &"redirected_damage" and not callout_already_played:
			target_view.show_redirection_feedback()
	return {}

func _animate_queued_move(event: BattleEvent, targets: Array[StringName]) -> Dictionary:
	var delays := await _animate_attack_queue(event, targets)
	var stat_callouts: Array = event.values.get("stat_callouts", [])
	if stat_callouts.is_empty(): return delays
	var remaining_wait := 0.0
	for delay in delays.values(): remaining_wait = maxf(remaining_wait, float(delay))
	var cleanup_deadline := _now_usec() + roundi(_last_move_visual_duration_seconds * 1000000.0)
	await _wait_until_usec(_now_usec() + roundi(remaining_wait * 1000000.0))
	for callout in stat_callouts:
		await _wait_until_usec(_now_usec() + roundi(float(callout.lead_seconds) * 1000000.0))
		var recipient := combatant_views.get(String(callout.target_id)) as BattleCombatantView
		if recipient != null:
			var positive := int(callout.amount) > 0
			var stat_name := String(callout.stat_type_id).get_slice("/", 1).capitalize()
			recipient.show_status_badge(BattleCombatantView.STAT_INCREASE_BADGE if positive else BattleCombatantView.STAT_DECREASE_BADGE, stat_name)
			audio_controller.play_sound("battle_buff" if positive else "battle_debuff", 0.5 if positive else 0.4)
		cleanup_deadline = maxi(cleanup_deadline, _now_usec() + 800000)
		await _wait_until_usec(_now_usec() + 300000)
	_last_move_visual_duration_seconds = maxf(0.0, float(cleanup_deadline - _now_usec()) / 1000000.0)
	return {"": 0.0}

func _animate_attack_queue(event: BattleEvent, targets: Array[StringName]) -> Dictionary:
	var move := catalog.get_definition(StringName(event.values.get("move_id", ""))) as MoveDefinition if catalog != null else null
	if move == null:
		return _animate_event(event, targets)
	var visual_targets: Array[StringName] = []
	var seen_teams: Dictionary = {}
	for target_id in targets:
		var view := combatant_views.get(String(target_id)) as BattleCombatantView
		if not move.hit_each_target and view != null:
			if seen_teams.has(view.team):
				continue
			seen_teams[view.team] = true
		visual_targets.append(target_id)
	if not bool(event.values.get("hit", true)) and not visual_targets.is_empty():
		return await _animate_queued_miss(event, move, visual_targets)
	if not event.values.get("visual_callouts", {}).is_empty():
		return await _animate_status_queued_move(event, move, visual_targets)
	var family := String(vfx_catalog.profile_for(_resolved_visual_id(move)).get("family", ""))
	if not move.visuals_have_buffer or visual_targets.is_empty() or family == "screen_shake":
		_play_move_actor_lunge(event.actor_id)
		await _wait_until_usec(_now_usec() + 100000)
		var delays := _animate_event(event, visual_targets)
		# ApplyEffects is one queue operation, after the final visual wait.
		var final_delay := 0.0
		for delay in delays.values():
			final_delay = maxf(final_delay, float(delay))
		delays[""] = final_delay
		for target_id in targets:
			delays[String(target_id)] = final_delay
		return delays
	# Each buffered visual has its own .1s actor lead and m_moveTime-.1
	# barrier. ApplyEffects follows the whole sequence, not each target.
	var final_cleanup_deadline := 0
	for target_id in visual_targets:
		_play_move_actor_lunge(event.actor_id)
		await _wait_until_usec(_now_usec() + 100000)
		_last_move_visual_duration_seconds = 0.0
		var cast_time := _now_usec()
		var effect_delay := _animate_move_visual(event, target_id)
		final_cleanup_deadline = maxi(final_cleanup_deadline, cast_time + roundi(_last_move_visual_duration_seconds * 1000000.0))
		await _wait_until_usec(cast_time + roundi(effect_delay * 1000000.0))
	_last_move_visual_duration_seconds = maxf(0.0, float(final_cleanup_deadline - _now_usec()) / 1000000.0)
	var delays := {"": 0.0}
	for target_id in targets:
		delays[String(target_id)] = 0.0
	return delays

func _animate_status_queued_move(event: BattleEvent, move: MoveDefinition, targets: Array[StringName]) -> Dictionary:
	var cleanup_deadline := 0
	var last_effect_wait := 0.0
	if not move.visuals_have_buffer:
		_play_move_actor_lunge(event.actor_id)
		await _wait_until_usec(_now_usec() + 100000)
	for target_id in targets:
		if move.visuals_have_buffer:
			_play_move_actor_lunge(event.actor_id)
			await _wait_until_usec(_now_usec() + 100000)
		var cast_time := _now_usec()
		_last_move_visual_duration_seconds = 0.0
		last_effect_wait = _animate_move_visual(event, target_id)
		cleanup_deadline = maxi(cleanup_deadline, cast_time + roundi(_last_move_visual_duration_seconds * 1000000.0))
		if move.visuals_have_buffer:
			await _wait_until_usec(cast_time + roundi(last_effect_wait * 1000000.0))
		var target := combatant_views.get(String(target_id)) as BattleCombatantView
		for kind in event.values.visual_callouts.get(String(target_id), []):
			if target != null:
				if kind == "reflection":
					target.show_reflected_damage_feedback()
				else:
					target.show_status_badge(BattleCombatantView.STUNNED_BADGE if kind == "stunned" else BattleCombatantView.FROZEN_BADGE)
					audio_controller.play_sound("battle_spark" if kind == "stunned" else "battle_whoosh_wind", 1.0)
			last_effect_wait = 0.8
			cleanup_deadline = maxi(cleanup_deadline, _now_usec() + 800000)
			await _wait_until_usec(_now_usec() + 800000)
	# The unbuffered source queue adds a final wait using the last visual,
	# even when that visual is a status callout already queued above.
	if not move.visuals_have_buffer:
		await _wait_until_usec(_now_usec() + roundi(last_effect_wait * 1000000.0))
	_last_move_visual_duration_seconds = maxf(0.0, float(cleanup_deadline - _now_usec()) / 1000000.0)
	return {"": 0.0}

func _animate_queued_miss(event: BattleEvent, move: MoveDefinition, targets: Array[StringName]) -> Dictionary:
	var actor := combatant_views.get(String(event.actor_id)) as BattleCombatantView
	var final_cleanup_deadline := 0
	if not move.visuals_have_buffer:
		_play_move_actor_lunge(event.actor_id)
		await _wait_until_usec(_now_usec() + 100000)
	for target_id in targets:
		if move.visuals_have_buffer:
			_play_move_actor_lunge(event.actor_id)
			await _wait_until_usec(_now_usec() + 100000)
		var cast_time := _now_usec()
		var target := combatant_views.get(String(target_id)) as BattleCombatantView
		var effect_delay := 0.8 # VisualMoveMiss.m_moveTime-.1
		var duration := 0.8 # Miss artwork cleans up before its .9s move time.
		if target != null and actor != null and target.team == actor.team:
			# Source allies still receive their ordinary visual on a failed roll.
			var ally_event := BattleEvent.new(event.sequence, &"move_used", event.actor_id, target_id, {"move_id": String(move.id), "hit": true})
			_last_move_visual_duration_seconds = 0.0
			effect_delay = _animate_move_visual(ally_event, target_id)
			duration = _last_move_visual_duration_seconds
		else:
			_animate_miss(BattleEvent.new(0, &"missed", event.actor_id, target_id))
			audio_controller.play_sound("battle_whoosh_sword_swipe", 0.5)
		final_cleanup_deadline = maxi(final_cleanup_deadline, cast_time + roundi(duration * 1000000.0))
		if move.visuals_have_buffer:
			await _wait_until_usec(cast_time + roundi(effect_delay * 1000000.0))
	if not move.visuals_have_buffer:
		await _wait_until_usec(final_cleanup_deadline)
	_last_move_visual_duration_seconds = maxf(0.0, float(final_cleanup_deadline - _now_usec()) / 1000000.0)
	return {"": 0.0}

func _play_move_actor_lunge(actor_id: StringName) -> void:
	var actor := combatant_views.get(String(actor_id)) as BattleCombatantView
	# Timer stones have no ordinary minion view, as in MoveCurrentMinion.
	if actor != null and actor.visible:
		actor.play_source_move_lunge()

func _animate_miss(event: BattleEvent) -> void:
	var target_view := combatant_views.get(String(event.target_id)) as BattleCombatantView
	if target_view == null:
		var source_view := combatant_views.get(String(event.actor_id)) as BattleCombatantView
		if source_view == null:
			return
		target_view = _first_living_opponent(source_view.team)
	if target_view == null:
		return
	var effect := Sprite2D.new()
	effect.texture = MISS_TEXTURE
	effect.position = move_vfx_layer.get_global_transform().affine_inverse() * target_view.global_position + Vector2(-MISS_TEXTURE.get_width() * 0.5, -target_view.minion_sprite.texture.get_height() - 50.0)
	effect.centered = false
	effect.modulate.a = 0.0
	move_vfx_layer.add_child(effect)
	var fade := create_tween()
	fade.tween_property(effect, "modulate:a", 1.0, 0.2)
	fade.tween_interval(0.4)
	fade.tween_property(effect, "modulate:a", 0.0, 0.2)
	fade.tween_callback(effect.queue_free)
	create_tween().tween_property(effect, "position:y", effect.position.y - 50.0, 0.8)

func _animate_periodic_tick(event: BattleEvent) -> float:
	var move := catalog.get_definition(StringName(event.values.get("move_id", ""))) as MoveDefinition
	var target_view := combatant_views.get(String(event.target_id)) as BattleCombatantView
	if move == null or target_view == null:
		return 0.0
	var visual_id := _resolved_dot_visual_id(move)
	var effectiveness := float(event.values.get("effectiveness", 1.0))
	target_view.show_impact_feedback(effectiveness, false)
	return _animate_visual_instance(visual_id, target_view, combatant_views.get(String(event.actor_id)) as BattleCombatantView)

func _animate_periodic_application(event: BattleEvent) -> float:
	var move := catalog.get_definition(StringName(event.values.get("move_id", ""))) as MoveDefinition
	var target_view := combatant_views.get(String(event.target_id)) as BattleCombatantView
	if move == null or target_view == null:
		return 0.0
	var visual_id := _resolved_dot_visual_id(move)
	return _animate_visual_instance(visual_id, target_view, combatant_views.get(String(event.actor_id)) as BattleCombatantView)

func _animate_poison_tick(texture: Texture2D, target_view: BattleCombatantView) -> void:
	var layer_inverse: Transform2D = move_vfx_layer.get_global_transform().affine_inverse()
	var origin: Vector2 = layer_inverse * target_view.global_position + Vector2(0.0, -target_view.minion_sprite.texture.get_height() * 0.5)
	for index in 3:
		var effect := Sprite2D.new()
		effect.texture = texture
		effect.position = origin + Vector2((index - 1) * 20.0, 0.0)
		effect.modulate.a = 0.0
		move_vfx_layer.add_child(effect)
		var delay := float(index) * 0.3
		var tween := create_tween().set_parallel(true)
		tween.tween_property(effect, "position:y", effect.position.y - 130.0, 1.6).set_delay(delay)
		tween.tween_property(effect, "scale", Vector2.ONE * 1.5, 1.6).set_delay(delay)
		tween.tween_property(effect, "modulate:a", 1.0, 0.2).set_delay(delay)
		tween.tween_property(effect, "modulate:a", 0.0, 0.2).set_delay(delay + 1.4)
		tween.chain().tween_callback(effect.queue_free)

func _animate_move_visual(event: BattleEvent, target_id: StringName) -> float:
	if not bool(event.values.get("hit", true)):
		return 0.0
	var move_id := StringName(event.values.get("move_id", ""))
	var move := catalog.get_definition(move_id) as MoveDefinition if catalog != null else null
	if move == null:
		return 0.0
	var visual_id := _resolved_visual_id(move)
	var source_view := combatant_views.get(String(event.actor_id)) as BattleCombatantView
	var target_view := combatant_views.get(String(target_id)) as BattleCombatantView
	if target_view == null and source_view != null:
		target_view = _first_living_opponent(source_view.team)
	var physical_contact := _animate_visual_instance(visual_id, target_view, source_view)
	if preload("res://src/presentation/source_visual_move_timing.gd").move_time(vfx_catalog.profile_for(visual_id)) >= 0.0 and _last_move_visual_duration_seconds > 0.0:
		# BaseMoveSystem queues ApplyEffects after PlayMove's m_moveTime-.1
		# barrier, not at the first object's physical/sound impact callback.
		return maxf(0.0, _last_move_visual_duration_seconds - 0.1)
	return physical_contact

func _animate_visual_instance(visual_id: int, target_view: BattleCombatantView, source_view: BattleCombatantView = null) -> float:
	# CreateMove/PlayMove is shared by direct casts and RunTickMoves. Keep one
	# dispatcher so periodic effects do not silently fall back to generic fades.
	var profile := vfx_catalog.profile_for(visual_id)
	var family := String(profile.get("family", ""))
	if family == "screen_shake":
		audio_controller.play_visual(visual_id, audio_controller.prepare_visual_profile(visual_id))
		_animate_source_screen_shake(profile)
		return 0.0
	if family == "test_white_flash":
		audio_controller.play_visual(visual_id, audio_controller.prepare_visual_profile(visual_id))
		return _animate_source_test_white_flash(profile)
	var texture := vfx_catalog.texture_for(visual_id)
	if texture == null:
		return 0.0
	if target_view == null:
		return 0.0
	# One shared sampled profile per target's CreateMove/PlayMove instance.
	profile = audio_controller.prepare_visual_profile(visual_id)
	audio_controller.play_visual(visual_id, profile)
	var ground_damage_index := source_ground_damage_index_for_family(family)
	if ground_damage_index >= 0:
		target_view.bring_in_ground_damage(ground_damage_index)
	var previous_objects := move_vfx_layer.get_children()
	var contact := -1.0
	match family:
		"rise_out_of_target":
			contact = _animate_rise_out_of_target(texture, target_view, profile)
		"orbit_into_target":
			contact = _animate_orbit_into_target(texture, target_view, profile)
		"rotate_into_target":
			contact = _animate_rotate_at_target(texture, target_view, profile)
		"fall_onto_target":
			contact = _animate_fall_onto_target(texture, target_view, profile)
		"fall_from_top":
			contact = _animate_fall_from_top(texture, target_view, profile)
		"burn_at_target":
			_animate_burn_at_target(texture, target_view, profile)
			_last_move_visual_duration_seconds = 1.2
			contact = 0.5
		"fade_through_target":
			contact = _animate_fade_through_target(texture, target_view, profile)
	if contact >= 0.0:
		var source_duration := preload("res://src/presentation/source_visual_move_timing.gd").move_time(profile)
		_last_move_visual_duration_seconds = source_duration
		var objects: Array[Node] = []
		for child in move_vfx_layer.get_children():
			if not previous_objects.has(child):
				objects.append(child)
		_cleanup_visual_instance_at(_now_usec() + roundi(source_duration * 1000000.0), objects)
		return contact
	# Native families above anchor to the attacked minion, not the caster.
	# The move-timer BMod is intentionally absent from combatant_views and
	# must still play those visuals/sounds. Only this projectile fallback needs
	# a visible origin; it is not a substitute sprite for the hidden timer.
	if source_view == null:
		return 0.0
	var effect_size := Vector2(128.0, 128.0)
	var layer_inverse: Transform2D = move_vfx_layer.get_global_transform().affine_inverse()
	var start_position: Vector2 = layer_inverse * source_view.minion_sprite.global_position - effect_size * 0.5
	var end_position: Vector2 = layer_inverse * target_view.minion_sprite.global_position - effect_size * 0.5
	var effect_sprite := TextureRect.new()
	effect_sprite.texture = texture
	effect_sprite.position = start_position
	effect_sprite.size = effect_size
	effect_sprite.pivot_offset = effect_size * 0.5
	effect_sprite.scale = Vector2(0.65, 0.65)
	effect_sprite.modulate = Color(1.0, 1.0, 1.0, 0.0)
	effect_sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	effect_sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	effect_sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	effect_sprite.z_index = 0
	move_vfx_layer.add_child(effect_sprite)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(effect_sprite, "position", end_position, DEFAULT_MOVE_PROJECTILE_SECONDS)
	tween.tween_property(effect_sprite, "scale", Vector2(1.15, 1.15), DEFAULT_MOVE_PROJECTILE_SECONDS)
	tween.tween_property(effect_sprite, "modulate:a", 0.92, 0.08)
	tween.chain().tween_property(effect_sprite, "modulate:a", 0.0, MOVE_PROJECTILE_FADE_SECONDS)
	tween.chain().tween_callback(effect_sprite.queue_free)
	_last_move_visual_duration_seconds = DEFAULT_MOVE_PROJECTILE_SECONDS + MOVE_PROJECTILE_FADE_SECONDS
	return DEFAULT_MOVE_PROJECTILE_SECONDS

func _cleanup_visual_instance_at(deadline_usec: int, objects: Array[Node]) -> void:
	await _wait_until_usec(deadline_usec)
	for object in objects:
		if is_instance_valid(object) and not object.is_queued_for_deletion():
			object.queue_free()

func _animate_source_test_white_flash(profile: Dictionary) -> float:
	var flash := ColorRect.new()
	flash.name = "SourceTestVisualWhiteFlash"
	flash.color = Color.WHITE
	flash.modulate.a = 0.0
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.z_index = 1500
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(flash)
	var fade_in := maxf(0.0, float(profile.get("flash_in_time", 0.2)))
	var fade_out := maxf(0.0, float(profile.get("flash_out_time", 0.2)))
	var duration := float(profile.get("duration", fade_in + fade_out))
	var tween := create_tween()
	tween.tween_property(flash, "modulate:a", 1.0, fade_in)
	tween.tween_property(flash, "modulate:a", 0.0, fade_out)
	tween.tween_callback(flash.queue_free)
	_last_move_visual_duration_seconds = maxf(_last_move_visual_duration_seconds, duration)
	return 0.0

func _animate_source_screen_shake(profile: Dictionary) -> void:
	var intensity := maxf(0.0, float(profile.get("intensity", 0.05)))
	var shake_count := maxi(1, int(profile.get("shake_count", 5)))
	var shake_distance := float(profile.get("shake_distance", 10.0))
	var shaken_objects: Array[Control] = [arena_floor, combatant_layer, battle_modifier_layer]
	if _earthquake_tween != null and _earthquake_tween.is_running():
		_earthquake_tween.kill()
		if _earthquake_base_positions.size() == shaken_objects.size():
			for index in shaken_objects.size():
				shaken_objects[index].position.x = _earthquake_base_positions[index]
	var start_positions: Array[float] = []
	for shaken_object in shaken_objects:
		start_positions.append(shaken_object.position.x)
	_earthquake_base_positions = start_positions.duplicate()
	_earthquake_tween = create_tween()
	for shake_index in shake_count:
		var shake_duration := 0.05 + intensity * (float(shake_index) * 0.5)
		# chain().set_parallel(true) re-enabled parallel mode for the *same*
		# step: all opposing position tweens ran together and cancelled out.
		# One serial offset tween moves all layers together, then returns them.
		_earthquake_tween.tween_method(_apply_screen_shake_offset.bind(start_positions), 0.0, shake_distance, shake_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_earthquake_tween.tween_method(_apply_screen_shake_offset.bind(start_positions), shake_distance, 0.0, shake_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	var source_move_time := (0.05 + intensity * (float(shake_count) * 0.5)) * float(shake_count) + 0.15
	_last_move_visual_duration_seconds = maxf(_last_move_visual_duration_seconds, source_move_time)

func _apply_screen_shake_offset(offset: float, origins: Array[float]) -> void:
	var layers: Array[Control] = [arena_floor, combatant_layer, battle_modifier_layer]
	for index in layers.size():
		layers[index].position.x = origins[index] + offset

func _animate_fade_through_target(texture: Texture2D, target_view: BattleCombatantView, profile: Dictionary) -> float:
	var layer_inverse: Transform2D = move_vfx_layer.get_global_transform().affine_inverse()
	var target_position: Vector2 = layer_inverse * target_view.global_position
	var object_count := clampi(int(profile.get("count", 3)), 1, 12)
	var spacing_delay := maxf(0.0, float(profile.get("delay", 0.07)))
	var movement_speed := maxf(0.2, float(profile.get("movement_speed", 0.8)))
	var final_hang := maxf(0.0, float(profile.get("final_hang_time", 0.1)))
	var master_scale := maxf(0.05, absf(float(profile.get("master_scale", 1.0))))
	var moving_right := target_view.team == 1
	var sprite_width := float(texture.get_width()) * master_scale
	var sprite_height := float(texture.get_height()) * master_scale
	var start_x_offset := float(profile.get("start_x_offset", 0.0))
	var start_x := target_position.x - sprite_width - start_x_offset if moving_right else target_position.x + sprite_width + start_x_offset
	var start_y := target_position.y - sprite_height + float(profile.get("extra_distance", 0.0))
	for index in object_count:
		var effect := Sprite2D.new()
		effect.texture = texture
		effect.centered = false
		effect.position = Vector2(start_x, start_y)
		effect.scale = Vector2(master_scale if moving_right else -master_scale, master_scale)
		effect.modulate = Color(1.0, 1.0, 1.0, 0.0)
		effect.z_index = 2
		move_vfx_layer.add_child(effect)
		var delay := float(index) * spacing_delay
		var travel := create_tween()
		travel.tween_property(effect, "position:x", target_position.x, movement_speed).set_delay(delay)
		var fade := create_tween()
		fade.tween_property(effect, "modulate:a", maxf(0.0, 1.0 - float(index) * 0.3), 0.2).set_delay(delay)
		fade.tween_interval(maxf(0.0, movement_speed - 0.2) + final_hang)
		fade.tween_property(effect, "modulate:a", 0.0, 0.2)
		fade.tween_callback(effect.queue_free)
	_last_move_visual_duration_seconds = float(object_count - 1) * spacing_delay + movement_speed + final_hang + 0.2
	return movement_speed

func _animate_rise_out_of_target(texture: Texture2D, target_view: BattleCombatantView, profile: Dictionary) -> float:
	var layer_inverse: Transform2D = move_vfx_layer.get_global_transform().affine_inverse()
	var target_position: Vector2 = layer_inverse * target_view.global_position
	var target_height := float(target_view.minion_sprite.texture.get_height())
	var count := clampi(int(profile.get("count", 1)), 1, 12)
	var spacing_delay := maxf(0.0, float(profile.get("delay", 0.1)))
	var rise_speed := maxf(0.05, float(profile.get("rise_speed", 1.6)))
	var final_hang := maxf(0.0, float(profile.get("final_hang_time", 0.5)))
	var rise_distance := float(profile.get("rise_distance", 100.0))
	var y_offset := float(profile.get("y_offset", 0.0))
	var x_offset := float(profile.get("x_offset", 0.0))
	var extra_spacing := float(profile.get("extra_x_spacing", 0.0))
	var master_scale := float(profile.get("master_scale", 1.0))
	var finish_scale := master_scale * float(profile.get("finish_scale", 1.3))
	var no_rise := bool(profile.get("no_rise", false))
	var impact_time := final_hang + rise_speed + count * spacing_delay + 0.15
	var play_impact := bool(profile.get("impact_minion", false))
	var sequence_duration := float(count - 1) * spacing_delay + rise_speed + final_hang + 0.4
	if play_impact:
		sequence_duration = maxf(sequence_duration, final_hang + rise_speed + count * spacing_delay + 0.25)
	_last_move_visual_duration_seconds = maxf(_last_move_visual_duration_seconds, sequence_duration)
	for index in count:
		var effect := Sprite2D.new()
		effect.texture = texture
		effect.centered = true
		effect.position = Vector2(
			target_position.x - x_offset + (texture.get_width() * 0.5 + extra_spacing if index % 2 == 1 else 0.0),
			target_position.y - texture.get_height() * 0.5 + y_offset - target_height * 0.5,
		)
		var start_scale := master_scale * float(profile.get("start_scale", 1.0))
		effect.scale = Vector2.ONE * start_scale
		effect.modulate.a = 0.0
		effect.z_index = 2
		move_vfx_layer.add_child(effect)
		var tween := create_tween()
		tween.tween_interval(float(index) * spacing_delay)
		tween.tween_property(effect, "modulate:a", 1.0, 0.2)
		tween.set_parallel(true)
		if not no_rise:
			tween.tween_property(effect, "position:y", effect.position.y - rise_distance, rise_speed)
		tween.tween_property(effect, "scale", Vector2.ONE * finish_scale, rise_speed)
		tween.chain().tween_interval(final_hang)
		tween.tween_property(effect, "modulate:a", 0.0, 0.2)
		tween.tween_callback(effect.queue_free)
		var shake_count := int(profile.get("shake_count", 0))
		if shake_count > 0:
			_animate_visual_shake(effect, float(index) * spacing_delay + 0.2, shake_count)
		if play_impact:
			_animate_target_impact(target_position, target_height, impact_time - 0.5 + float(index) * spacing_delay)
	if bool(profile.get("flash_on_finish", false)):
		var flash_delay := maxf(0.0, impact_time - 0.3)
		var flash_timer := create_tween()
		flash_timer.tween_interval(flash_delay)
		flash_timer.tween_callback(_flash_battle_screen)
	return maxf(0.0, impact_time - 0.4) if play_impact else impact_time

func _animate_target_impact(target_position: Vector2, target_height: float, delay: float) -> void:
	var impact := Sprite2D.new()
	impact.texture = MOVE_IMPACT_TEXTURE
	impact.centered = true
	impact.position = target_position + Vector2(0.0, -target_height * 0.5)
	impact.scale = Vector2.ONE * 0.7
	impact.modulate.a = 0.0
	impact.z_index = 3
	move_vfx_layer.add_child(impact)
	var fade := create_tween()
	fade.tween_interval(maxf(0.0, delay))
	fade.tween_property(impact, "modulate:a", 0.7, 0.1)
	fade.tween_interval(0.1)
	fade.tween_property(impact, "modulate:a", 0.0, 0.2)
	fade.tween_callback(impact.queue_free)
	var drift := create_tween()
	drift.tween_interval(maxf(0.0, delay))
	drift.tween_property(impact, "position:y", impact.position.y - 5.0, 0.6)

func _animate_source_fall_impact(target_position: Vector2, target_height: float, delay: float, impact_scale: float = 0.7, object_index: int = 0) -> void:
	var impact := Sprite2D.new()
	impact.texture = MOVE_IMPACT_TEXTURE
	impact.centered = true
	impact.scale = Vector2.ONE * impact_scale
	var impact_extent_scale := absf(impact_scale)
	impact.position = target_position + Vector2(
		(float(MOVE_IMPACT_TEXTURE.get_width()) * impact_extent_scale * 0.25 if object_index % 2 == 1 else 0.0),
		-float(MOVE_IMPACT_TEXTURE.get_height()) * impact_extent_scale * 0.5 - target_height * 0.5,
	)
	impact.modulate.a = 0.0
	impact.z_index = 3
	move_vfx_layer.add_child(impact)
	var fade := create_tween()
	fade.tween_interval(maxf(0.0, delay))
	fade.tween_property(impact, "modulate:a", 0.7, 0.1)
	fade.tween_interval(0.2)
	fade.tween_property(impact, "modulate:a", 0.0, 0.3)
	fade.tween_callback(impact.queue_free)
	var drift := create_tween()
	drift.tween_interval(maxf(0.0, delay))
	drift.tween_property(impact, "position:y", impact.position.y - 5.0, 0.6)

func _animate_visual_shake(effect: Sprite2D, delay: float, shake_count: int) -> void:
	var tween := create_tween()
	tween.tween_interval(delay)
	tween.tween_property(effect, "rotation_degrees", -5.0, 0.1)
	for _index in shake_count:
		tween.tween_property(effect, "rotation_degrees", 10.0, 0.2)
		tween.tween_property(effect, "rotation_degrees", -10.0, 0.2)
	tween.tween_property(effect, "rotation_degrees", 5.0, 0.1)
	tween.tween_property(effect, "rotation_degrees", 0.0, 0.1)

func _flash_battle_screen() -> void:
	var flash := ColorRect.new()
	flash.color = Color(1.0, 1.0, 1.0, 0.0)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash.z_index = 1200
	move_vfx_layer.add_child(flash)
	var tween := create_tween()
	tween.tween_property(flash, "color:a", 0.45, 0.05)
	tween.tween_property(flash, "color:a", 0.0, 0.12)
	tween.tween_callback(flash.queue_free)

func _animate_orbit_into_target(texture: Texture2D, target_view: BattleCombatantView, profile: Dictionary) -> float:
	var layer_inverse: Transform2D = move_vfx_layer.get_global_transform().affine_inverse()
	var target_position: Vector2 = layer_inverse * target_view.global_position
	var target_height := float(target_view.minion_sprite.texture.get_height())
	var count := clampi(int(profile.get("count", 8)), 1, TARGET_ORBIT_X.size())
	var distance := float(profile.get("move_distance", 80.0))
	var spacing_delay := maxf(0.0, float(profile.get("delay", 0.1)))
	var enter_together := bool(profile.get("all_enter_at_same_time", false))
	var movement_speed := maxf(0.05, float(profile.get("movement_speed", 0.7)))
	var hang_time := maxf(0.0, float(profile.get("hang_time", 0.5)))
	var final_hang := maxf(0.0, float(profile.get("final_hang_time", 0.3)))
	var master_scale := float(profile.get("master_scale", 1.0))
	var y_offset := float(profile.get("y_offset", 0.0))
	var x_offset := float(profile.get("x_offset", 0.0))
	var extra_spacing := float(profile.get("extra_x_spacing", 0.0))
	var center := target_position + Vector2(x_offset - texture.get_width() * 0.5, y_offset - texture.get_height() * 0.5 - target_height * 0.5)
	var impact_time := 0.2 + hang_time + movement_speed
	var last_entry_delay := 0.0 if enter_together else float(count - 1) * spacing_delay
	var movement_finish := last_entry_delay + 0.2 + hang_time + movement_speed
	var fade_finish := last_entry_delay + hang_time + maxf(0.0, movement_speed - 0.2) + final_hang + 0.2
	_last_move_visual_duration_seconds = maxf(_last_move_visual_duration_seconds, maxf(movement_finish, fade_finish))
	for index in count:
		var effect := Sprite2D.new()
		effect.texture = texture
		effect.centered = false
		var ring_offset := Vector2(TARGET_ORBIT_X[index], TARGET_ORBIT_Y[index]) * distance
		if index % 2 == 1:
			ring_offset.x += extra_spacing
		effect.position = center + ring_offset
		effect.scale = Vector2.ONE * master_scale
		effect.modulate.a = 0.0
		effect.z_index = 2
		move_vfx_layer.add_child(effect)
		var entry_delay := float(index) * spacing_delay if not enter_together else 0.0
		var movement := create_tween()
		movement.tween_interval(entry_delay)
		movement.tween_property(effect, "modulate:a", 1.0, 0.2)
		movement.tween_interval(hang_time)
		movement.tween_property(effect, "position", center, movement_speed)
		var fade := create_tween()
		fade.tween_interval(entry_delay + maxf(0.0, movement_speed - 0.2) + final_hang + hang_time)
		fade.tween_property(effect, "modulate:a", 0.0, 0.2)
		fade.tween_callback(effect.queue_free)
	return impact_time

func _animate_rotate_at_target(texture: Texture2D, target_view: BattleCombatantView, profile: Dictionary) -> float:
	var layer_inverse: Transform2D = move_vfx_layer.get_global_transform().affine_inverse()
	var target_position: Vector2 = layer_inverse * target_view.global_position
	var direction := 1.0 if target_view.team == 1 else -1.0
	var impact_speed := maxf(0.05, float(profile.get("impact_speed", 0.4)))
	var object_count := clampi(int(profile.get("count", 1)), 1, 8)
	var delay_between := maxf(0.0, float(profile.get("delay", 0.06)))
	var scale_step := float(profile.get("scale_step", 0.2))
	var master_scale := maxf(0.05, absf(float(profile.get("master_scale", 1.0))))
	var extra_distance := float(profile.get("extra_distance", 0.0))
	var display_impact := bool(profile.get("impact_visible", true))
	var target_height := float(target_view.minion_sprite.texture.get_height()) * absf(target_view.minion_sprite.scale.y)
	var last_delay := float(object_count - 1) * delay_between
	var last_impact_finish := impact_speed
	if display_impact:
		last_impact_finish = maxf(0.0, impact_speed - 0.2) + last_delay + 0.6
	var last_effect_finish := maxf(impact_speed + last_delay + 0.3, impact_speed + 2.0 * last_delay)
	_last_move_visual_duration_seconds = maxf(_last_move_visual_duration_seconds, maxf(last_impact_finish, last_effect_finish))
	for index in object_count:
		var effect_sprite := Sprite2D.new()
		effect_sprite.texture = texture
		effect_sprite.centered = false
		effect_sprite.scale = Vector2(direction * master_scale, master_scale)
		# The source rotates the sprite before using its displayed width and
		# height for placement. At +/-90 degrees those dimensions are swapped.
		var rotated_width := float(texture.get_height()) * master_scale
		var rotated_height := float(texture.get_width()) * master_scale
		effect_sprite.position = target_position + Vector2((-rotated_width / 1.5 - extra_distance) * direction, -rotated_height - 50.0)
		effect_sprite.rotation_degrees = -90.0 * direction
		effect_sprite.modulate.a = maxf(0.0, 1.0 - 0.25 * float(index))
		effect_sprite.z_index = 2
		move_vfx_layer.add_child(effect_sprite)
		var delay := float(index) * delay_between
		var tween := create_tween().set_parallel(true)
		tween.tween_property(effect_sprite, "position:y", effect_sprite.position.y + 50.0, impact_speed + delay)
		tween.tween_property(effect_sprite, "rotation_degrees", 0.0, impact_speed + delay).set_delay(delay)
		tween.tween_property(effect_sprite, "modulate:a", 0.0, 0.2).set_delay(impact_speed + 0.1 + delay)
		tween.chain().tween_callback(effect_sprite.queue_free)
		if display_impact:
			_animate_source_fall_impact(target_position, target_height, maxf(0.0, impact_speed - 0.2) + delay, 1.0 - float(index) * scale_step, index)
	return impact_speed

func _animate_fall_onto_target(texture: Texture2D, target_view: BattleCombatantView, profile: Dictionary) -> float:
	var layer_inverse: Transform2D = move_vfx_layer.get_global_transform().affine_inverse()
	var target_position: Vector2 = layer_inverse * target_view.global_position
	var direction := 1.0 if target_view.team == 1 else -1.0
	var impact_speed := maxf(0.05, float(profile.get("impact_speed", 0.35)))
	var delay_between := maxf(0.0, float(profile.get("delay", 0.1)))
	var object_count := clampi(int(profile.get("count", 1)), 1, 8)
	var bounces := clampi(int(profile.get("pre_impact_bounces", 0)), 0, 8)
	var up_down_speed := maxf(0.05, float(profile.get("up_down_speed", 0.3)))
	var master_scale := maxf(0.05, absf(float(profile.get("master_scale", 1.0))))
	var extra_distance := float(profile.get("extra_distance", 0.0))
	var display_impact := bool(profile.get("impact_visible", true))
	var hang_time := 0.2 + float(bounces) * up_down_speed * 2.0
	var hit_time := hang_time + impact_speed
	var last_object_delay := float(object_count - 1) * delay_between
	var move_finish_time := hang_time + last_object_delay + impact_speed
	var effect_finish_time := move_finish_time
	if display_impact:
		# The source impact sprite begins 0.2s before contact, then fades in,
		# holds, and fades out while drifting upward for 0.6s total.
		effect_finish_time = maxf(effect_finish_time, hang_time + maxf(0.0, impact_speed - 0.2) + last_object_delay + 0.6)
	_last_move_visual_duration_seconds = maxf(_last_move_visual_duration_seconds, effect_finish_time)
	var target_height := float(target_view.minion_sprite.texture.get_height()) * absf(target_view.minion_sprite.scale.y)
	var sprite_width := float(texture.get_width()) * master_scale
	var sprite_height := float(texture.get_height()) * master_scale
	for index in object_count:
		var effect_sprite := Sprite2D.new()
		effect_sprite.texture = texture
		effect_sprite.centered = false
		effect_sprite.scale = Vector2(direction * master_scale, master_scale)
		effect_sprite.position = target_position + Vector2(-sprite_width * 0.5 * direction + (sprite_width * 0.5 if index % 2 == 1 else 0.0), -sprite_height - 100.0)
		effect_sprite.modulate.a = 0.0
		effect_sprite.z_index = 2
		move_vfx_layer.add_child(effect_sprite)
		var delay := float(index) * delay_between
		var arrival_time := hang_time + impact_speed + delay
		var destination_y := target_position.y - sprite_height + extra_distance
		var motion := create_tween()
		motion.tween_property(effect_sprite, "modulate:a", 1.0, 0.2)
		for _bounce_index in bounces:
			motion.tween_property(effect_sprite, "position:y", effect_sprite.position.y - 10.0, up_down_speed)
			motion.tween_property(effect_sprite, "position:y", effect_sprite.position.y, up_down_speed)
		motion.tween_interval(delay)
		motion.tween_property(effect_sprite, "position:y", destination_y, impact_speed)
		var fade := create_tween()
		fade.tween_interval(maxf(0.0, arrival_time - 0.2))
		fade.tween_property(effect_sprite, "modulate:a", 0.0, 0.2)
		fade.tween_callback(effect_sprite.queue_free)
		if display_impact:
			var impact_start_delay := hang_time + maxf(0.0, impact_speed - 0.2) + delay
			_animate_source_fall_impact(target_position, target_height, impact_start_delay, 0.7, index)
	return hit_time

func _animate_fall_from_top(texture: Texture2D, target_view: BattleCombatantView, profile: Dictionary) -> float:
	var layer_inverse: Transform2D = move_vfx_layer.get_global_transform().affine_inverse()
	var target_position: Vector2 = layer_inverse * target_view.global_position
	var impact_speed := maxf(0.05, float(profile.get("impact_speed", 0.75)))
	var delay_between := maxf(0.0, float(profile.get("delay", 0.1)))
	var object_count := clampi(int(profile.get("count", 3)), 1, 8)
	var random_start_limit := maxf(0.0, float(profile.get("random_start_time", 0.0)))
	var random_start := float(profile.random_start_in_game) if profile.has("random_start_in_game") else randf_range(0.0, random_start_limit)
	var scale_step := float(profile.get("scale_step", 0.2))
	var master_scale := maxf(0.05, absf(float(profile.get("master_scale", 1.0))))
	var extra_distance := float(profile.get("extra_distance", 0.0))
	var display_impacts := bool(profile.get("impact_visible", true))
	var target_height := float(target_view.minion_sprite.texture.get_height()) * absf(target_view.minion_sprite.scale.y)
	var last_stagger := float(object_count - 1) * delay_between
	var source_move_time := random_start + impact_speed + float(object_count) * delay_between + 0.15
	var impact_finish := random_start + last_stagger + maxf(0.0, impact_speed - 0.2) + 0.6
	var visual_finish := maxf(source_move_time, impact_finish if display_impacts else 0.0)
	_last_move_visual_duration_seconds = maxf(_last_move_visual_duration_seconds, visual_finish)
	for index in object_count:
		var effect_sprite := Sprite2D.new()
		effect_sprite.texture = texture
		effect_sprite.centered = false
		var object_scale := (1.0 - float(index) * scale_step) * master_scale
		var sprite_width := float(texture.get_width()) * absf(object_scale)
		var sprite_height := float(texture.get_height()) * absf(object_scale)
		effect_sprite.scale = Vector2.ONE * object_scale
		effect_sprite.position = Vector2(target_position.x - sprite_width * 0.5 + (sprite_width * 0.5 if index % 2 == 1 else 0.0), -sprite_height - target_position.y)
		effect_sprite.z_index = 2
		move_vfx_layer.add_child(effect_sprite)
		var delay := float(index) * delay_between + random_start
		var destination_y := target_position.y - sprite_height + extra_distance
		var movement := create_tween()
		movement.tween_property(effect_sprite, "position:y", destination_y, impact_speed).set_delay(delay)
		var fade := create_tween()
		fade.tween_interval(delay + maxf(0.0, impact_speed - 0.2))
		fade.tween_property(effect_sprite, "modulate:a", 0.0, 0.2)
		fade.tween_callback(effect_sprite.queue_free)
		if display_impacts:
			_animate_source_fall_impact(target_position, target_height, delay + maxf(0.0, impact_speed - 0.2), 1.0 - float(index) * scale_step, index)
	return random_start + impact_speed

func _animate_burn_at_target(texture: Texture2D, target_view: BattleCombatantView, profile: Dictionary) -> void:
	var layer_inverse: Transform2D = move_vfx_layer.get_global_transform().affine_inverse()
	var target_position: Vector2 = layer_inverse * target_view.global_position
	for index in mini(int(profile.get("count", 3)), 8):
		var effect_sprite := Sprite2D.new()
		effect_sprite.texture = texture
		effect_sprite.centered = false
		var scale_factor := maxf(0.2, 1.0 - index * float(profile.get("scale_step", 0.2)))
		effect_sprite.scale = Vector2.ONE * scale_factor
		effect_sprite.position = target_position + Vector2(-texture.get_width() * scale_factor * 0.5 + (texture.get_width() * scale_factor * 0.25 if index % 2 == 1 else 0.0), -texture.get_height() * scale_factor)
		effect_sprite.modulate.a = 0.0
		effect_sprite.z_index = 2
		move_vfx_layer.add_child(effect_sprite)
		var alpha_tween := create_tween()
		alpha_tween.tween_property(effect_sprite, "modulate:a", 0.7, 0.5)
		alpha_tween.tween_interval(0.2)
		alpha_tween.tween_property(effect_sprite, "modulate:a", 0.0, 0.5)
		alpha_tween.tween_callback(effect_sprite.queue_free)
		var drift := 5.0 + float(index) * 13.0
		if index % 2 == 1:
			drift += texture.get_width() * scale_factor * 0.25
		var x_tween := create_tween()
		var drift_position := effect_sprite.position.x
		for step in 4:
			# ActionScript's relative "x" tween starts from the previous step's
			# endpoint. Accumulate each signed offset instead of snapping between
			# two coordinates around the original position.
			drift_position += drift if (step + index) % 2 == 0 else -drift
			x_tween.tween_property(effect_sprite, "position:x", drift_position, 0.3)

func _apply_event_values(event: BattleEvent) -> void:
	if event.values.has("turn_order"):
		_set_presented_turn_order(event.values.turn_order)
	if event.kind == &"battle_mod_timer_triggered":
		var timer_count := battle_modifier_layer.get_node_or_null("MoveTimerModVisuals/TimerCount") as Label
		if timer_count != null:
			timer_count.text = "0"
		_animate_move_timer_icon()
		return
	if event.kind == &"battle_mod_extra_spawned":
		var spawned_id := StringName(event.target_id)
		var presented_spawn := _present_replacement_spawn(event)
		if presented_spawn:
			_refresh_presented_buff_icons()
		elif not _pending_extra_minion_animation_ids.has(spawned_id):
			_pending_extra_minion_animation_ids.append(spawned_id)
		var team := int(event.values.get("team", -1))
		_set_extra_minion_remaining(team, int(event.values.get("remaining", 0)))
		var replaced_id := StringName(event.values.get("replaced_id", ""))
		if not replaced_id.is_empty():
			_hide_resurrection_tombstone(replaced_id)
		return
	if event.kind == &"battle_mod_shields_assigned":
		var shield_team := _display_team(int(event.values.get("team", -1)))
		var selected: Array = event.values.get("target_ids", [])
		for raw_view in combatant_views.values():
			var shielded_view := raw_view as BattleCombatantView
			if shielded_view.team != shield_team: continue
			_set_presented_battle_mod_shield(shielded_view, String(shielded_view.instance_id) in selected)
		return
	var target_id := StringName(event.target_id)
	var view := combatant_views.get(String(target_id)) as BattleCombatantView
	if event.kind == &"battle_mod_resurrection_progressed":
		var turns_left := maxi(0, int(event.values.get("required", 0)) - int(event.values.get("elapsed", 0)) - 1)
		_show_resurrection_tombstone(target_id, turns_left)
		return
	if event.kind == &"battle_mod_resurrected":
		_hide_resurrection_tombstone(target_id)
		_modifier_visual_completion_usec = maxi(_modifier_visual_completion_usec, _now_usec() + 1000000)
	if view == null:
		return
	var values := PresentationState.apply_event(view.state_cache, event)
	if event.kind == &"defeated":
		values["defeated"] = true
	elif event.kind == &"battle_mod_resurrected":
		values["defeated"] = false
	elif event.kind == &"battle_mod_shield_removed":
		_set_presented_battle_mod_shield(view, false)
		return
	view.update_from_state(values, true)
	if event.kind in [&"frozen", &"stunned"]:
		view.play_source_condition_tint(event.kind)
	elif event.kind in [&"thawed", &"buffs_debuffs_cleared", &"battle_mod_resurrected"]:
		view.play_source_condition_tint(&"clear")
	if event.kind in [&"periodic_applied", &"periodic_refreshed", &"periodic_expired", &"buffs_debuffs_cleared", &"defeated", &"battle_mod_resurrected"] or event.values.has("health"):
		_refresh_presented_buff_icons()

func _refresh_presented_buff_icons() -> void:
	var presented_states: Array = []
	for presented_view in combatant_views.values():
		presented_states.append((presented_view as BattleCombatantView).state_cache)
	_refresh_buff_icons(presented_states)

func _set_presented_battle_mod_shield(view: BattleCombatantView, active: bool) -> void:
	var changed := bool(view.state_cache.get("battle_mod_shield_active", false)) != active
	view.apply_event_values({"battle_mod_shield_active": active})
	if changed:
		# StartRound/CheckForWinLose waits 1s before choosing the next actor;
		# the shield itself rises/fades over .8s during that boundary.
		_modifier_visual_completion_usec = maxi(_modifier_visual_completion_usec, _now_usec() + 1000000)

func _resurrection_turns_for(instance_id: StringName) -> int:
	if controller == null or controller.engine == null:
		return 0
	var snapshot := controller.engine.snapshot()
	var modifier_state: Dictionary = snapshot.get("state", {}).get("modifier_state", {})
	var turns := int(modifier_state.get("resurrection_turns", 0))
	if turns <= 0:
		return 0
	var team := int(modifier_state.get("resurrection_team", -1))
	for state in snapshot.get("state", {}).get("combatants", []):
		if StringName(state.get("instance_id", "")) == instance_id and int(state.get("team", -2)) == team:
			return turns
	return 0

func _show_resurrection_tombstone(instance_id: StringName, turns_left: int) -> void:
	var view := combatant_views.get(String(instance_id)) as BattleCombatantView
	if view == null:
		return
	var marker: Dictionary = resurrection_tombstones.get(String(instance_id), {})
	var root := marker.get("root") as Node2D
	var label := marker.get("label") as Label
	if root == null or not is_instance_valid(root):
		root = Node2D.new()
		root.name = "ResurrectionTombstone_%s" % String(instance_id)
		root.z_index = 0
		root.visible = false
		var sprite := Sprite2D.new()
		sprite.texture = RESURRECTION_TOMBSTONE_TEXTURE
		sprite.centered = false
		root.add_child(sprite)
		label = Label.new()
		label.position = Vector2(16.0, 25.0)
		label.size = Vector2(50.0, 35.0)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.add_theme_font_override("font", BURBIN_FONT)
		label.add_theme_font_size_override("font_size", 28)
		label.add_theme_color_override("font_color", Color8(229, 230, 232))
		root.add_child(label)
		combatant_layer.add_child(root)
		marker = {"root": root, "label": label}
		resurrection_tombstones[String(instance_id)] = marker
	var was_visible := root.visible
	root.position = combatant_layer.get_global_transform().affine_inverse() * view.global_position + Vector2(-RESURRECTION_TOMBSTONE_TEXTURE.get_width() * 0.5, -RESURRECTION_TOMBSTONE_TEXTURE.get_height())
	label.text = str(maxi(0, turns_left))
	# Source count updates do not restart the entrance animation.
	if was_visible:
		return
	var marker_tween := marker.get("tween") as Tween
	if marker_tween != null and marker_tween.is_running():
		marker_tween.kill()
	root.visible = true
	root.modulate.a = 0.0
	_modifier_visual_completion_usec = maxi(_modifier_visual_completion_usec, _now_usec() + 1000000)
	marker_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	marker_tween.tween_property(root, "modulate:a", 1.0, 0.5)
	marker["tween"] = marker_tween
	resurrection_tombstones[String(instance_id)] = marker

func _hide_resurrection_tombstone(instance_id: StringName) -> void:
	var key := String(instance_id)
	var marker: Dictionary = resurrection_tombstones.get(key, {})
	var root := marker.get("root") as Node2D
	if root == null or not is_instance_valid(root):
		return
	var marker_tween := marker.get("tween") as Tween
	if marker_tween != null and marker_tween.is_running():
		marker_tween.kill()
	marker_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	marker_tween.tween_property(root, "modulate:a", 0.0, 0.5)
	marker_tween.tween_callback(func() -> void: root.visible = false)
	marker["tween"] = marker_tween
	resurrection_tombstones[key] = marker

func _sync_battle_modifier_visuals(modifiers: Dictionary) -> void:
	active_battle_modifiers = modifiers.duplicate(true)
	_clear_battle_modifier_visuals()
	var shield: Dictionary = modifiers.get("shield", {}) as Dictionary
	if not shield.is_empty():
		var shield_root := Node2D.new()
		shield_root.name = "ShieldModVisuals"
		shield_root.position = Vector2(304.0, 119.0)
		battle_modifier_layer.add_child(shield_root)
		_create_modifier_sprite(shield_root, "PlayerShieldStone", SHIELD_STONE_TEXTURE, Vector2(-164.0, -116.0))
		_create_modifier_sprite(shield_root, "EnemyShieldStone", SHIELD_STONE_TEXTURE, Vector2(185.0, -112.0))
		var player_count := clampi(int(shield.get("player", 0)), 0, 3)
		var enemy_count := clampi(int(shield.get("enemy", 0)), 0, 3)
		for index in 3:
			var player_icon := _create_modifier_sprite(shield_root, "PlayerShieldCounter%d" % index, SHIELD_COUNTER_TEXTURE, Vector2(-132.0, -97.0 + float(index) * 23.0))
			player_icon.visible = player_count > index
			_animate_modifier_bob(player_icon)
			var enemy_icon := _create_modifier_sprite(shield_root, "EnemyShieldCounter%d" % index, SHIELD_COUNTER_TEXTURE, Vector2(217.0, -93.0 + float(index) * 23.0))
			enemy_icon.visible = enemy_count > index
			_animate_modifier_bob(enemy_icon, 0.1)
		var player_stone := shield_root.get_node("PlayerShieldStone") as Sprite2D
		var enemy_stone := shield_root.get_node("EnemyShieldStone") as Sprite2D
		_animate_modifier_bob(player_stone)
		_animate_modifier_bob(enemy_stone, 0.1)
	var resurrection: Dictionary = modifiers.get("resurrection", {}) as Dictionary
	if int(resurrection.get("turns", 0)) > 0:
		var resurrection_root := Node2D.new()
		resurrection_root.name = "ResurectionModVisuals"
		resurrection_root.position = Vector2(319.0, 123.0)
		battle_modifier_layer.add_child(resurrection_root)
		_create_modifier_sprite(resurrection_root, "ResurrectionStone", RESURRECTION_STONE_TEXTURE, Vector2(36.0, 94.0))
	var move_timer: Dictionary = modifiers.get("move_timer", {}) as Dictionary
	if not move_timer.is_empty():
		_create_move_timer_visuals(move_timer)
	var extra_minions: Dictionary = modifiers.get("extra_minions", {}) as Dictionary
	if not extra_minions.is_empty():
		_create_extra_minions_visuals(extra_minions)
	if controller != null and controller.engine != null:
		_refresh_battle_modifier_counters(controller.engine.snapshot())

func _create_move_timer_visuals(config: Dictionary) -> void:
	var root := Node2D.new()
	root.name = "MoveTimerModVisuals"
	root.position = Vector2(304.0, 82.0)
	battle_modifier_layer.add_child(root)
	_create_modifier_sprite(root, "EnemyTimerStone", MOVE_TIMER_STONE_TEXTURE, Vector2(225.0, -44.0))
	var player_stone := _create_modifier_sprite(root, "PlayerTimerStone", MOVE_TIMER_STONE_TEXTURE, Vector2(-87.0, -40.0))
	player_stone.scale.x = -1.0
	var buff_panel := _create_modifier_sprite(root, "TimerBuffPanel", MOVE_TIMER_BUFF_PANEL_TEXTURE, Vector2(-229.0, 39.0))
	var buff_icon := Sprite2D.new()
	buff_icon.name = "TimerBuffIcon"
	buff_icon.texture = MOVE_TIMER_DEFAULT_BUFF_ICON
	buff_icon.centered = true
	buff_icon.position = Vector2(17.0, -47.0)
	buff_icon.scale = Vector2(0.8, 0.8)
	buff_icon.modulate.a = 0.0
	buff_panel.add_child(buff_icon)
	var buff_text := _create_modifier_label(buff_panel, "TimerBuffText", "+20% speed", Vector2(-21.0, 7.0), Vector2(150.0, 28.0), 13, Color8(237, 240, 245))
	var passive_id := StringName(config.get("buff_move_id", config.get("passive_move_id", "")))
	var passive_move := catalog.get_definition(passive_id) as MoveDefinition if not passive_id.is_empty() else null
	if passive_move != null:
		buff_icon.texture = _move_icon(passive_move)
		var buff_info: Dictionary = _move_timer_buff_info(passive_move)
		buff_text.text = String(buff_info.get("text", passive_move.display_name))
		buff_text.add_theme_color_override("font_color", buff_info.get("color", Color8(237, 240, 245)))
	var timer_move := catalog.get_definition(StringName(config.get("move_id", ""))) as MoveDefinition
	var timer_icon := Sprite2D.new()
	timer_icon.name = "TimerMoveIcon"
	timer_icon.texture = _move_icon(timer_move) if timer_move != null else MOVE_TIMER_DEFAULT_ICON
	timer_icon.centered = true
	timer_icon.position = Vector2(308.0, -12.0)
	timer_icon.scale = Vector2(0.8, 0.8)
	timer_icon.modulate.a = 0.0
	root.add_child(timer_icon)
	_create_modifier_label(root, "TimerCount", "", Vector2(256.0, 40.0), Vector2(150.0, 38.0), 28, Color8(237, 240, 245))
	_fade_modifier_icon(timer_icon, 1.9)
	_fade_modifier_icon(buff_icon, 1.9)

func _move_timer_buff_info(move: MoveDefinition) -> Dictionary:
	var stat_effect: EffectDefinition
	var armor_effect: EffectDefinition
	var critical_effect: EffectDefinition
	var reflect_effect: EffectDefinition
	for effect in move.effects:
		if effect == null:
			continue
		match effect.kind:
			EffectDefinition.Kind.STAT_PERCENT:
				if stat_effect == null: stat_effect = effect
			EffectDefinition.Kind.ARMOR:
				if armor_effect == null: armor_effect = effect
			EffectDefinition.Kind.CRITICAL_CHANCE:
				if critical_effect == null: critical_effect = effect
			EffectDefinition.Kind.REFLECT:
				if reflect_effect == null: reflect_effect = effect
	if (move.is_passive or move.is_global_passive) and stat_effect != null:
		var stat_name := String(stat_effect.stat_type_id).get_slice("/", 1)
		return {"text": "+%d%% %s" % [stat_effect.amount, stat_name], "color": Color8(255, 245, 104)}
	if armor_effect != null and (move.is_passive or move.is_global_passive or armor_effect.amount != 0):
		return {"text": "%+d%% armor" % armor_effect.amount, "color": Color8(255, 245, 104) if armor_effect.amount >= 0 else Color8(229, 125, 255)}
	if critical_effect != null:
		return {"text": "+%d%% crit" % critical_effect.amount, "color": Color8(255, 245, 104)}
	if reflect_effect != null:
		return {"text": "%+d%% reflect" % reflect_effect.amount, "color": Color8(255, 245, 104)}
	return {"text": move.display_name, "color": Color8(235, 234, 235)}

func _create_extra_minions_visuals(config: Dictionary) -> void:
	var root := Node2D.new()
	root.name = "ExtraMinionsModVisuals"
	root.position = Vector2(268.0, 82.0)
	battle_modifier_layer.add_child(root)
	var player_config: Dictionary = config.get("player", {}) as Dictionary
	var enemy_config: Dictionary = config.get("enemy", {}) as Dictionary
	var player_count := _configured_extra_minion_count(player_config)
	var enemy_count := _configured_extra_minion_count(enemy_config)
	var player_stone := _create_modifier_sprite(root, "PlayerExtraMinionStone", EXTRA_MINION_STONE_TEXTURE, Vector2(61.0, -62.0))
	player_stone.scale.x = -1.0
	_create_modifier_sprite(root, "EnemyExtraMinionStone", EXTRA_MINION_STONE_TEXTURE, Vector2(114.0, -62.0))
	var player_count_label := _create_modifier_label(root, "PlayerExtraMinionCount", str(player_count), Vector2(-66.0, -61.0), Vector2(150.0, 32.0), 21, Color8(237, 240, 245))
	player_count_label.visible = player_count > 0
	var player_icon := _create_extra_minion_icon(root, "PlayerExtraMinionIcon", player_config, Vector2(9.0, 27.0))
	player_icon.visible = player_count > 0
	_create_modifier_sprite(root, "PlayerExtraMinionCrystal", EXTRA_MINION_CRYSTAL_TEXTURE, Vector2(-20.0, -3.0))
	var enemy_count_label := _create_modifier_label(root, "EnemyExtraMinionCount", str(enemy_count), Vector2(93.0, -60.0), Vector2(150.0, 32.0), 21, Color8(237, 240, 245))
	enemy_count_label.visible = enemy_count > 0
	var enemy_icon := _create_extra_minion_icon(root, "EnemyExtraMinionIcon", enemy_config, Vector2(167.0, 24.0))
	enemy_icon.visible = enemy_count > 0
	_create_modifier_sprite(root, "EnemyExtraMinionCrystal", EXTRA_MINION_CRYSTAL_TEXTURE, Vector2(139.0, -3.0))

func _configured_extra_minion_count(config: Dictionary) -> int:
	var templates: Array = config.get("templates", []) as Array
	return maxi(0, int(config.get("count", templates.size())))

func _create_extra_minion_icon(parent: Node2D, icon_name: String, team_config: Dictionary, center: Vector2) -> Sprite2D:
	var texture: Texture2D
	var templates: Array = team_config.get("templates", []) as Array
	if not templates.is_empty():
		var template: Dictionary = templates[0] as Dictionary
		var definition := catalog.get_definition(StringName(template.get("definition_id", ""))) as MinionDefinition
		if definition != null:
			texture = _presentation_texture(definition)
	var icon := Sprite2D.new()
	icon.name = icon_name
	icon.texture = texture
	icon.centered = true
	icon.position = center
	if texture != null:
		var icon_scale := 45.0 / maxf(float(texture.get_width()), float(texture.get_height()))
		icon.scale = Vector2(icon_scale, icon_scale)
	icon.modulate.a = 0.8
	parent.add_child(icon)
	return icon

func _create_modifier_label(parent: Node2D, label_name: String, label_text: String, label_position: Vector2, label_size: Vector2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.name = label_name
	label.text = label_text
	label.position = label_position
	label.size = label_size
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", BURBIN_FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

func _fade_modifier_icon(icon: Sprite2D, delay: float) -> void:
	var tween := create_tween()
	tween.tween_property(icon, "modulate:a", 1.0, 1.5).set_delay(delay)

func _animate_move_timer_icon() -> void:
	var icon := battle_modifier_layer.get_node_or_null("MoveTimerModVisuals/TimerMoveIcon") as Sprite2D
	if icon == null:
		return
	if _move_timer_icon_tween != null and _move_timer_icon_tween.is_running():
		_move_timer_icon_tween.kill()
	icon.modulate.a = 1.0
	icon.scale = Vector2(0.8, 0.8)
	icon.rotation_degrees = 0.0
	_move_timer_icon_tween = create_tween()
	_move_timer_icon_tween.tween_property(icon, "scale", Vector2(2.0, 2.0), 0.5)
	_move_timer_icon_tween.tween_property(icon, "rotation_degrees", 720.0, 2.3)
	_move_timer_icon_tween.tween_property(icon, "scale", Vector2(0.8, 0.8), 0.5)
	_modifier_visual_completion_usec = maxi(_modifier_visual_completion_usec, _now_usec() + 3300000)

func _set_extra_minion_remaining(team: int, remaining: int) -> void:
	if team < 0 or team > 1:
		return
	var label_name := "PlayerExtraMinionCount" if team == 0 else "EnemyExtraMinionCount"
	var icon_name := "PlayerExtraMinionIcon" if team == 0 else "EnemyExtraMinionIcon"
	var label := battle_modifier_layer.get_node_or_null("ExtraMinionsModVisuals/%s" % label_name) as Label
	var icon := battle_modifier_layer.get_node_or_null("ExtraMinionsModVisuals/%s" % icon_name) as Sprite2D
	if label != null:
		label.text = str(maxi(0, remaining))
		label.visible = remaining > 0
	if icon != null:
		icon.visible = remaining > 0

func _refresh_battle_modifier_counters(snapshot: Dictionary) -> void:
	var state: Dictionary = snapshot.get("state", {}) as Dictionary
	var modifier_state: Dictionary = state.get("modifier_state", {}) as Dictionary
	var move_timer: Dictionary = active_battle_modifiers.get("move_timer", {}) as Dictionary
	var timer_label := battle_modifier_layer.get_node_or_null("MoveTimerModVisuals/TimerCount") as Label
	if timer_label != null:
		var interval := maxi(0, int(move_timer.get("interval", 0)))
		var timer_counter := maxi(0, int(modifier_state.get("move_timer_counter", 0)))
		timer_label.text = str(maxi(0, interval - timer_counter + 1)) if interval > 0 else "0"
	var extra_config: Dictionary = active_battle_modifiers.get("extra_minions", {}) as Dictionary
	var used: Dictionary = modifier_state.get("extra_minions_used", {}) as Dictionary
	for team in 2:
		var team_key := "player" if team == 0 else "enemy"
		var team_config: Dictionary = extra_config.get(team_key, {}) as Dictionary
		var used_count := int(used.get(team, used.get(str(team), 0)))
		_set_extra_minion_remaining(team, maxi(0, _configured_extra_minion_count(team_config) - used_count))

func _clear_battle_modifier_visuals() -> void:
	for tween in _shield_bob_tweens:
		if tween != null and tween.is_running():
			tween.kill()
	_shield_bob_tweens.clear()
	if _move_timer_icon_tween != null and _move_timer_icon_tween.is_running():
		_move_timer_icon_tween.kill()
	_move_timer_icon_tween = null
	_modifier_visual_completion_usec = 0
	if battle_modifier_layer == null:
		return
	for child in battle_modifier_layer.get_children():
		child.free()

func _create_modifier_sprite(parent: Node2D, sprite_name: String, texture: Texture2D, sprite_position: Vector2) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.name = sprite_name
	sprite.texture = texture
	sprite.centered = false
	sprite.position = sprite_position
	parent.add_child(sprite)
	return sprite

func _animate_modifier_bob(sprite: Sprite2D, start_delay: float = 0.0) -> void:
	var base_y := sprite.position.y
	var tween := create_tween()
	_shield_bob_tweens.append(tween)
	if start_delay > 0.0:
		tween.tween_interval(start_delay)
	tween.set_loops()
	tween.tween_property(sprite, "position:y", base_y + 5.0, 0.8)
	tween.tween_property(sprite, "position:y", base_y - 5.0, 0.9)
	tween.tween_property(sprite, "position:y", base_y + 5.0, 0.8)
	tween.tween_property(sprite, "position:y", base_y - 5.0, 0.9)
	tween.tween_interval(0.1)

func _retire_combatant_view(instance_id: String) -> void:
	var removed_view := combatant_views.get(instance_id) as BattleCombatantView
	if removed_view != null:
		if _original_player_ids.has(instance_id):
			removed_view.visible = false
			_retired_player_views[instance_id] = removed_view
		else:
			removed_view.queue_free()
		combatant_views.erase(instance_id)
	var stale_marker: Dictionary = resurrection_tombstones.get(instance_id, {})
	var stale_tween := stale_marker.get("tween") as Tween
	if stale_tween != null and stale_tween.is_running(): stale_tween.kill()
	var stale_root := stale_marker.get("root") as Node
	if stale_root != null and is_instance_valid(stale_root): stale_root.queue_free()
	resurrection_tombstones.erase(instance_id)

func _create_combatant_view(state: Dictionary) -> BattleCombatantView:
	var definition := catalog.get_definition(StringName(state.definition_id)) as MinionDefinition
	if definition == null:
		_show_fatal("Missing minion definition for %s" % String(state.definition_id))
		return null
	var texture := _presentation_texture(definition)
	if texture == null:
		_show_fatal("Missing battle art for %s" % String(state.definition_id))
		return null
	var view := COMBATANT_VIEW_SCRIPT.new() as BattleCombatantView
	combatant_layer.add_child(view)
	var displayed_state := state
	var dense := int(state.get("team", 0)) in _double_teams
	if _team_flip != 0 or dense:
		displayed_state = state.duplicate()
		displayed_state["team"] = _display_team(int(state.get("team", 0)))
		displayed_state["double_layout"] = dense
	view.setup(displayed_state, definition, texture)
	combatant_views[String(state.instance_id)] = view
	return view

func _present_replacement_spawn(event: BattleEvent) -> bool:
	var state: Dictionary = event.values.get("combatant", {})
	# Older/synthetic events retain the post-response synchronization fallback.
	if state.is_empty(): return false
	var instance_id := String(event.target_id)
	if String(state.get("instance_id", "")) != instance_id: return false
	if combatant_views.has(instance_id): return true
	_retire_combatant_view(String(event.values.get("replaced_id", "")))
	var view := _create_combatant_view(state)
	if view == null: return false
	view.play_extra_minion_spawn_animation()
	_pending_extra_minion_animation_ids.erase(StringName(instance_id))
	_modifier_visual_completion_usec = maxi(_modifier_visual_completion_usec, _now_usec() + int(BATTLE_REPLACEMENT_HANDOFF_SECONDS * 1000000.0))
	return true

func _sync_from_engine() -> void:
	var snapshot := controller.engine.snapshot()
	var states: Array = snapshot.state.combatants
	var active_instance_ids: Dictionary = {}
	for state in states:
		active_instance_ids[String(state.instance_id)] = true
	for existing_id in combatant_views.keys().duplicate():
		if active_instance_ids.has(String(existing_id)):
			continue
		_retire_combatant_view(String(existing_id))
	for state in states:
		var state_id := StringName(state.instance_id)
		var view := combatant_views.get(String(state_id)) as BattleCombatantView
		if view == null:
			view = _create_combatant_view(state)
			if view == null: return
			if _pending_extra_minion_animation_ids.has(state_id):
				view.play_extra_minion_spawn_animation()
				_pending_extra_minion_animation_ids.erase(state_id)
		else:
			view.update_from_state(state, true)
	_set_presented_turn_order(snapshot.state.turn_order)
	_refresh_buff_icons(states)
	_refresh_battle_modifier_counters(snapshot)

func _set_presented_turn_order(ordered_ids: Array) -> void:
	for existing_view in combatant_views.values():
		(existing_view as BattleCombatantView).set_move_order_position(0)
	for rank_index in ordered_ids.size():
		var ordered_view := combatant_views.get(String(ordered_ids[rank_index])) as BattleCombatantView
		if ordered_view != null: ordered_view.set_move_order_position(rank_index + 1)

func _refresh_buff_icons(states: Array) -> void:
	if catalog == null:
		return
	var ordered_states: Array = states.duplicate()
	ordered_states.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		if int(left.team) != int(right.team):
			return int(left.team) < int(right.team)
		return int(left.slot_index) < int(right.slot_index)
	)
	var global_ids_by_team: Dictionary = {}
	var seen_global_ids_by_team: Dictionary = {}
	for state in ordered_states:
		var team := int(state.team)
		if bool(state.get("defeated", false)) or int(state.get("health", 0)) <= 0:
			continue
		if not global_ids_by_team.has(team):
			global_ids_by_team[team] = []
			seen_global_ids_by_team[team] = {}
		for raw_move_id in state.get("move_ids", []):
			var move_id := StringName(raw_move_id)
			var move := catalog.get_definition(move_id) as MoveDefinition
			if move == null or not move.is_global_passive or seen_global_ids_by_team[team].has(move_id):
				continue
			seen_global_ids_by_team[team][move_id] = true
			global_ids_by_team[team].append(move_id)
	for state in ordered_states:
		var view := combatant_views.get(String(state.instance_id)) as BattleCombatantView
		if view == null:
			continue
		if bool(state.get("defeated", false)) or int(state.get("health", 0)) <= 0:
			view.set_buff_icons([])
			continue
		var moves: Array[MoveDefinition] = []
		for move_id in global_ids_by_team.get(int(state.team), []):
			var global_move := catalog.get_definition(StringName(move_id)) as MoveDefinition
			if global_move != null:
				moves.append(global_move)
		for status in state.get("statuses", []):
			if StringName(status.get("kind", "")) != &"periodic":
				continue
			var status_move := catalog.get_definition(StringName(status.get("move_id", ""))) as MoveDefinition
			if status_move != null:
				moves.append(status_move)
		view.set_buff_icons(moves)

func _set_event_text(event: BattleEvent) -> void:
	match event.kind:
		&"battle_started": event_text.text = "Battle started!"
		&"battle_mod_timer_triggered": event_text.text = "Move timer triggered: %s" % _move_name(StringName(event.values.get("move_id", "")))
		&"battle_mod_extra_spawned": event_text.text = "An extra %s minion entered battle" % ("player" if int(event.values.get("team", -1)) == 0 else "opponent")
		&"turn_started": event_text.text = "%s's turn" % _combatant_label(event.actor_id)
		&"move_used": event_text.text = "%s used %s" % [_combatant_label(event.actor_id), _move_name(StringName(event.values.get("move_id", "")))]
		&"damage": event_text.text = "%s took %d damage" % [_combatant_label(event.target_id), int(event.values.get("amount", 0))]
		&"self_damage": event_text.text = "%s took %d recoil damage" % [_combatant_label(event.target_id), int(event.values.get("amount", 0))]
		&"reflected_damage": event_text.text = "%s took %d reflected damage from %s" % [_combatant_label(event.target_id), int(event.values.get("amount", 0)), _combatant_label(event.actor_id)]
		&"redirected_damage": event_text.text = "%s took %d redirected damage" % [_combatant_label(event.target_id), int(event.values.get("amount", 0))]
		&"healed":
			var recovered := int(event.values.get("amount", 0))
			if recovered > 0:
				event_text.text = "%s recovered %d health" % [_combatant_label(event.target_id), recovered]
			else:
				var target_view := combatant_views.get(String(event.target_id)) as BattleCombatantView
				var full_health := target_view != null and int(target_view.state_cache.get("health", 0)) >= int(target_view.state_cache.get("max_health", 1))
				event_text.text = "%s was already at full health" % _combatant_label(event.target_id) if full_health else "%s could not recover any health" % _combatant_label(event.target_id)
		&"periodic_applied", &"periodic_refreshed": event_text.text = "%s was affected by %s" % [_combatant_label(event.target_id), _move_name(StringName(event.values.get("move_id", "")))]
		&"periodic_tick": event_text.text = "%s resolves at end of round" % _move_name(StringName(event.values.get("move_id", "")))
		&"periodic_health_applied":
			var applied := int(event.values.get("applied", 0))
			if applied < 0:
				event_text.text = "%s took %d damage over time" % [_combatant_label(event.target_id), -applied]
			elif applied > 0:
				event_text.text = "%s recovered %d health over time" % [_combatant_label(event.target_id), applied]
			else:
				event_text.text = "Periodic effect resolved"
		&"missed": event_text.text = "The move missed!"
		&"decision_requested": event_text.text = "%s is ready to choose a move" % _combatant_label(event.actor_id)
		&"turn_skipped": event_text.text = "%s had no usable move and skipped its turn" % _combatant_label(event.actor_id)
		&"frozen_turn_skipped": event_text.text = "%s's turn was skipped while frozen" % _combatant_label(event.actor_id)
		&"stunned_turn_skipped": event_text.text = "%s's turn was skipped while stunned" % _combatant_label(event.actor_id)
		&"exhausted_turn_skipped": event_text.text = "%s's turn was skipped due to exhaustion" % _combatant_label(event.actor_id)
		&"defeated": event_text.text = "%s was defeated" % _combatant_label(event.target_id)
		&"battle_completed": event_text.text = "Battle complete"
		_: event_text.text = String(event.kind).replace("_", " ").capitalize()

func _show_result(result) -> void:
	if _battle_result_presented:
		return
	_cancel_battle_music_start()
	_battle_result_presented = true
	if campaign_progression_presenter != null:
		campaign_progression_presenter.cancel_sequence()
	move_panel.visible = false
	move_tooltip.hide()
	forfeit_confirmation.visible = false
	_set_forfeit_enabled(false)
	cancel_target.visible = false
	_clear_target_states()
	_hide_current_turn_indicator()
	stats_panel.close()
	_finish_recording(result)
	if net_role == &"replay":
		_show_replay_result(result)
		return
	if net_role in [&"spectator", &"pvp"]:
		_show_network_result(result)
		return
	if net_role == &"ally":
		_show_ally_result(result)
		return
	if campaign_mode:
		var campaign_runtime: Variant = get_node_or_null("/root/CampaignRuntime")
		if campaign_runtime == null or not campaign_runtime.active_campaign_battle:
			_show_fatal("Campaign battle finished without an active campaign result context")
			return
		campaign_settlement = campaign_runtime.settle_campaign_battle(result)
		if not campaign_settlement.get("ok", false):
			_show_fatal("Campaign result could not be committed: %s" % campaign_settlement.get("message", "unknown save error"))
			return
		restart_button.text = "Return to room"
		restart_button.disabled = true
	else:
		restart_button.text = "Battle again"
		restart_button.disabled = false
		campaign_settlement.clear()
	result_title.text = "Victory!" if result.winning_team == 0 else "Battle forfeited" if result.reason == &"forfeit" else "Battle lost"
	_restore_player_replacement_views()
	if result.reason != &"forfeit":
		_begin_battle_finish_presentation()
	if result.winning_team == 0:
		audio_controller.fade_music_to(0.0, 1.0)
		if campaign_mode:
			# The recovered campaign flow shows the source victory popup, then its
			# progression sequence, and returns to the room instead of leaving a
			# generic pause/result card on screen.
			_campaign_victory_return_pending = true
			result_overlay.visible = false
		else:
			result_overlay.modulate.a = 1.0
			result_overlay.visible = true
		_play_victory_presentation(result)
		_begin_campaign_progression(true)
	elif result.reason == &"forfeit":
		# The source sends a forfeit straight back to exploration after a short
		# music fade. Campaign mode performs that handoff; the standalone battle
		# keeps a result card so the player has a clear way to restart.
		audio_controller.fade_music_to(0.0, 0.5)
		var forfeit_return_tween := create_tween()
		forfeit_return_tween.tween_interval(0.5)
		forfeit_return_tween.tween_callback(func() -> void:
			if campaign_mode:
				campaign_forfeit_return_requested.emit()
			else:
				result_overlay.modulate.a = 1.0
				result_overlay.visible = true
		)
	elif campaign_mode:
		audio_controller.fade_music_to(0.4, 4.0)
		_campaign_defeat_transition_pending = true
		_begin_campaign_progression(false)
	else:
		audio_controller.fade_music_to(0.4, 4.0)
		_play_defeat_presentation()

## Double battle partner: its own minions keep their health and earn XP (the
## partner who started the fight records the win for the shared world).
func _show_ally_result(result) -> void:
	var campaign_runtime: Variant = get_node_or_null("/root/CampaignRuntime")
	var won := int(result.winning_team) == 0
	var detail := ""
	if campaign_runtime != null and campaign_runtime.session != null and campaign_runtime.session.state != null:
		var settled: Dictionary = campaign_runtime.session.apply_ally_battle_result(result, StringName(net_spec.get("encounter_id", "")), MultiplayerDoubleBattle.ALLY_PREFIX)
		if settled.get("ok", false):
			var gained := 0
			for award in (settled.get("experience_awards", {}) as Dictionary).values():
				gained += int(award.get("experience", 0))
			if gained > 0:
				detail = "\nYour team gained %d XP." % gained
		else:
			detail = "\nYour team could not be updated: %s" % settled.get("message", "unknown error")
	result_title.text = ("Victory together!" if won else "Battle forfeited" if result.reason == &"forfeit" else "Defeated together") + detail
	audio_controller.fade_music_to(0.0, 1.5)
	restart_button.visible = false
	result_overlay.modulate.a = 0.0
	result_overlay.visible = true
	var reveal := create_tween()
	reveal.tween_property(result_overlay, "modulate:a", 1.0, 0.4)
	reveal.tween_interval(2.6)
	await reveal.finished
	network_battle_finished.emit()

## Spectators and arena fighters see who won, then everyone returns together.
func _show_network_result(result) -> void:
	var winner := int(result.winning_team)
	var winner_name := _network_player_name(winner)
	if net_role == &"pvp" and winner in _local_teams:
		result_title.text = "You won!"
	else:
		result_title.text = "%s wins!" % winner_name
	if result.reason == &"forfeit":
		result_title.text += "\n(%s forfeited)" % _network_player_name(1 - winner)
	audio_controller.fade_music_to(0.0, 1.5)
	restart_button.visible = false
	result_overlay.modulate.a = 0.0
	result_overlay.visible = true
	var reveal := create_tween()
	reveal.tween_property(result_overlay, "modulate:a", 1.0, 0.4)
	reveal.tween_interval(2.6)
	await reveal.finished
	network_battle_finished.emit()

func _show_replay_result(result) -> void:
	var winner := int(result.winning_team)
	var detail := "after %d turns" % _turns_played
	if result.reason == &"forfeit":
		detail = "%s forfeited · %s" % [BattleReplay.team_name(replay_data, 1 - winner), detail]
	await get_tree().create_timer(0.8).timeout
	_end_replay("%s wins!" % BattleReplay.team_name(replay_data, winner), detail)

func _begin_campaign_progression(battle_won: bool) -> void:
	if not campaign_mode or campaign_progression_presenter == null:
		return
	var campaign_runtime: Variant = get_node_or_null("/root/CampaignRuntime")
	if campaign_runtime == null or campaign_runtime.session == null or campaign_runtime.session.state == null:
		restart_button.disabled = false
		return
	campaign_progression_presenter.begin_sequence(
		campaign_runtime.session.state.party,
		campaign_settlement.get("experience_awards", {}),
		catalog,
		combatant_views,
		battle_won,
		audio_controller,
		Callable(campaign_runtime, "save_campaign"),
		bool(campaign_settlement.get("show_first_defeat_tutorial", false)),
		campaign_runtime.session.state.owned_gems,
		campaign_runtime.session.state.progression.get("star_upgrades", {}),
		campaign_settlement.get("finish_stat_context", {})
	)

func _restore_player_replacement_views() -> void:
	if _retired_player_views.is_empty():
		return
	var retired_slots: Dictionary = {}
	for retired_view in _retired_player_views.values():
		retired_slots[int(retired_view.slot_index)] = true
	for existing_id in combatant_views.keys().duplicate():
		var extra_view := combatant_views[existing_id] as BattleCombatantView
		if extra_view.team == 0 and retired_slots.has(extra_view.slot_index):
			extra_view.queue_free()
			combatant_views.erase(existing_id)
	for original_id in _retired_player_views:
		var original_view := _retired_player_views[original_id] as BattleCombatantView
		original_view.restore_replaced_minion_for_finish()
		combatant_views[original_id] = original_view
	_retired_player_views.clear()
	_pending_extra_minion_animation_ids.clear()

func _begin_battle_finish_presentation() -> void:
	# SetupVisualsForTheWinningScreen is shared by win/loss XP sequences:
	# hide combat interfaces/opponents, then bring owned dead minions back.
	for view in combatant_views.values():
		if view.team == 0:
			view.begin_finish_presentation()
		else:
			var fade := create_tween()
			fade.tween_property(view, "modulate:a", 0.0, 0.3)
	for marker_id in resurrection_tombstones.keys():
		_hide_resurrection_tombstone(StringName(marker_id))

func _on_campaign_progression_sequence_finished() -> void:
	if campaign_mode and _campaign_defeat_transition_pending:
		_campaign_defeat_transition_pending = false
		_play_defeat_presentation()
		return
	if campaign_mode and _campaign_victory_return_pending:
		_campaign_victory_return_pending = false
		# BaseBattleFinishScreen returns as soon as its queue ends. The popup
		# may still be fading during ScreenController's outgoing curtain; waiting
		# for it here added an unsourced pause to short/skipped result sequences.
		campaign_return_requested.emit()
		return
	if campaign_mode and result_overlay.visible:
		restart_button.disabled = false

func _on_restart_pressed() -> void:
	if campaign_mode:
		campaign_return_requested.emit()
		return
	await _start_battle()

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	# Trainer rematch choices use the shell's Yes/No dialogue handler. The
	# standalone result card also supports Space/Enter without mouse focus.
	if result_overlay.visible and restart_button.visible and not restart_button.disabled and event.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]:
		get_viewport().set_input_as_handled()
		_on_restart_pressed()

func _create_audio_toggles() -> void:
	if settings_service == null: settings_service = CampaignSettingsService.new()
	_audio_controls = Control.new()
	_audio_controls.name = "BattleAudioControls"
	_audio_controls.size = Vector2(70, 34)
	_audio_controls.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_audio_controls.z_index = 1400
	add_child(_audio_controls)
	_music_toggle = SourceMenuArt.button(_audio_controls, "menu_muteMusicButton_on", Vector2(4, 6), func() -> void: settings_service.set_music_enabled(not settings_service.music_enabled))
	_sound_toggle = SourceMenuArt.button(_audio_controls, "menu_muteSoundButton_on", Vector2(36, 5), func() -> void: settings_service.set_sound_enabled(not settings_service.sound_enabled))
	settings_service.settings_changed.connect(_refresh_audio_toggles)
	_refresh_audio_toggles()

func _refresh_audio_toggles() -> void:
	_music_toggle.texture_normal = SourceMenuArt.texture("menu_muteMusicButton_on" if settings_service.music_enabled else "menu_muteMusicButton_off")
	_sound_toggle.texture_normal = SourceMenuArt.texture("menu_muteSoundButton_on" if settings_service.sound_enabled else "menu_muteSoundButton_off")

func _create_defeat_transition() -> void:
	defeat_transition_layer = Control.new()
	defeat_transition_layer.name = "SourceDefeatTransition"
	defeat_transition_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	defeat_transition_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	defeat_transition_layer.z_index = 1300
	defeat_transition_layer.visible = false
	add_child(defeat_transition_layer)
	defeat_black = ColorRect.new()
	defeat_black.name = "DefeatBlackout"
	defeat_black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	defeat_black.color = Color.BLACK
	defeat_black.modulate.a = 0.0
	defeat_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	defeat_transition_layer.add_child(defeat_black)
	defeat_message = Label.new()
	defeat_message.name = "DefeatMessage"
	defeat_message.text = "Your minions have collapsed,  you rush to heal them"
	defeat_message.position = Vector2(0.0, 234.0)
	defeat_message.size = Vector2(700.0, 40.0)
	defeat_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	defeat_message.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	defeat_message.add_theme_font_override("font", BURBIN_FONT)
	defeat_message.add_theme_font_size_override("font_size", 18)
	defeat_message.add_theme_color_override("font_color", Color8(229, 230, 232))
	defeat_message.mouse_filter = Control.MOUSE_FILTER_IGNORE
	defeat_message.modulate.a = 0.0
	defeat_message.visible = false
	defeat_transition_layer.add_child(defeat_message)

func _play_defeat_presentation() -> void:
	_reset_defeat_presentation()
	audio_controller.fade_music_to(0.0, 1.5)
	audio_controller.play_sound("battle_lose", 0.5)
	result_overlay.visible = false
	defeat_transition_layer.visible = true
	defeat_black.modulate.a = 0.0
	defeat_message.modulate.a = 0.0
	defeat_message.visible = true
	var black_tween := create_tween()
	black_tween.tween_interval(0.5)
	black_tween.tween_property(defeat_black, "modulate:a", 1.0, 1.0)
	black_tween.tween_interval(1.5)
	if campaign_mode:
		# The loss message remains on the old screen during ScreenController's
		# final .5s fade. The shell removes this scene only at the opaque switch.
		black_tween.tween_callback(func() -> void:
			if defeat_transition_layer.visible:
				campaign_defeat_return_requested.emit()
		)
	else:
		black_tween.tween_callback(func() -> void:
			if defeat_transition_layer.visible:
				defeat_message.visible = false
		)
		black_tween.tween_property(defeat_black, "modulate:a", 0.0, 0.5)
		black_tween.tween_callback(func() -> void:
			defeat_transition_layer.visible = false
			result_overlay.modulate.a = 1.0
			result_overlay.visible = true
		)
	_defeat_presentation_tweens.append(black_tween)
	var text_tween := create_tween()
	text_tween.tween_property(defeat_message, "modulate:a", 1.0, 1.0).set_delay(0.5)
	_defeat_presentation_tweens.append(text_tween)

func _reset_defeat_presentation() -> void:
	for tween in _defeat_presentation_tweens:
		if tween != null and tween.is_running():
			tween.kill()
	_defeat_presentation_tweens.clear()
	if defeat_transition_layer != null:
		defeat_transition_layer.visible = false
	if defeat_black != null:
		defeat_black.modulate.a = 0.0
	if defeat_message != null:
		defeat_message.modulate.a = 0.0
		defeat_message.visible = false

func _create_victory_popup() -> void:
	victory_popup = Control.new()
	victory_popup.name = "SourceVictoryPopup"
	victory_popup.position = Vector2(504.0, 105.0)
	victory_popup.size = VICTORY_BACKGROUND_TEXTURE.get_size()
	victory_popup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	victory_popup.z_index = 1201
	victory_popup.visible = false
	add_child(victory_popup)
	victory_background = TextureRect.new()
	victory_background.name = "VictoryBackground"
	victory_background.texture = VICTORY_BACKGROUND_TEXTURE
	victory_background.position = Vector2.ZERO
	victory_background.size = VICTORY_BACKGROUND_TEXTURE.get_size()
	victory_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	victory_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	victory_background.modulate.a = 0.0
	victory_popup.add_child(victory_background)
	victory_player_icon = TextureRect.new()
	victory_player_icon.name = "VictoryPlayerBust"
	victory_player_icon.position = Vector2(29.0, 112.0)
	victory_player_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	victory_player_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	victory_background.add_child(victory_player_icon)
	for index in 3:
		var star := TextureRect.new()
		star.name = "VictoryStar%d" % (index + 1)
		star.texture = VICTORY_STAR_TEXTURE
		star.position = Vector2(21.0 + float(index) * 60.0, 66.0)
		star.size = VICTORY_STAR_TEXTURE.get_size()
		star.pivot_offset = star.size * 0.5
		star.scale = Vector2.ONE * 0.8
		star.modulate.a = 0.0
		star.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		star.mouse_filter = Control.MOUSE_FILTER_IGNORE
		victory_background.add_child(star)
		victory_stars.append(star)

func _play_victory_presentation(result: BattleResult) -> void:
	_reset_victory_presentation()
	var character_gender := "male"
	if campaign_mode:
		var campaign_runtime: Variant = get_node_or_null("/root/CampaignRuntime")
		if campaign_runtime != null and campaign_runtime.session != null and campaign_runtime.session.state != null:
			character_gender = String(campaign_runtime.session.state.character.get("gender", "male")).to_lower()
	victory_player_icon.texture = VICTORY_FEMALE_BUST_TEXTURE if character_gender == "female" else VICTORY_MALE_BUST_TEXTURE
	victory_player_icon.size = victory_player_icon.texture.get_size()
	victory_popup.visible = true
	victory_popup.modulate.a = 1.0
	victory_background.modulate.a = 0.0
	var background_tween := create_tween()
	_victory_popup_tween = background_tween
	background_tween.tween_property(victory_background, "modulate:a", 1.0, 0.5).set_delay(0.3)
	background_tween.tween_interval(2.1)
	background_tween.tween_property(victory_background, "modulate:a", 0.0, 0.5)
	background_tween.tween_callback(func() -> void:
		victory_popup.visible = false
	)
	_victory_presentation_tweens.append(background_tween)
	var star_count := _source_victory_star_count(result)
	for index in star_count:
		var star := victory_stars[index]
		star.modulate.a = 0.0
		star.scale = Vector2.ONE * 0.8
		var star_tween := create_tween().set_parallel(true)
		var delay := 0.8 + float(index) * 0.5
		star_tween.tween_property(star, "modulate:a", 1.0, 0.4).set_delay(delay)
		star_tween.tween_property(star, "scale", Vector2.ONE, 0.4).set_delay(delay)
		_victory_presentation_tweens.append(star_tween)
	var sound_tween := create_tween()
	sound_tween.tween_interval(0.4)
	sound_tween.tween_callback(func() -> void:
		if victory_popup.visible and result_title.text == "Victory!":
			audio_controller.play_sound("battle_victory", 0.35)
	)
	_victory_presentation_tweens.append(sound_tween)

func _source_victory_star_count(result: BattleResult) -> int:
	var party_slots: Dictionary = {}
	var living_slots: Dictionary = {}
	for participant in result.participants:
		if int(participant.get("team", -1)) != 0:
			continue
		if String(participant.get("instance_id", "")).begins_with("battle-mod-extra-"):
			continue
		var slot := int(participant.get("slot_index", -1))
		if slot < 0:
			continue
		party_slots[slot] = true
		if bool(participant.get("survived", false)):
			living_slots[slot] = true
	var defeated_party_minions := party_slots.size() - living_slots.size()
	if defeated_party_minions <= 1:
		return 3
	if defeated_party_minions == 2:
		return 2
	if defeated_party_minions <= 4:
		return 1
	return 0

func _reset_victory_presentation() -> void:
	for tween in _victory_presentation_tweens:
		if tween != null and tween.is_running():
			tween.kill()
	_victory_presentation_tweens.clear()
	_victory_popup_tween = null
	if victory_popup != null:
		victory_popup.visible = false
		victory_popup.modulate.a = 1.0
	if victory_background != null:
		victory_background.modulate.a = 0.0
	for star in victory_stars:
		star.modulate.a = 0.0
		star.scale = Vector2.ONE * 0.8

func _cancel_targeting() -> void:
	pending_move.clear()
	selected_targets.clear()
	_clear_target_states()
	cancel_target.visible = false
	await _continue_battle()

func _show_startup_fatal(message: String) -> void:
	if campaign_mode:
		var campaign_runtime: Variant = get_node_or_null("/root/CampaignRuntime")
		if campaign_runtime != null:
			var cancelled: Dictionary = campaign_runtime.cancel_unstarted_battle()
			if not cancelled.ok:
				message += "\nCould not clear the pending battle: %s" % String(cancelled.get("message", "unknown save error"))
	_show_fatal(message)

func _show_fatal(message: String) -> void:
	event_text.get_parent().visible = true
	busy = false
	event_text.text = message
	result_title.text = "Unable to start"
	if campaign_mode:
		restart_button.text = "Return to room"
	result_overlay.visible = true

func _clear_buttons(container: Control) -> void:
	for child in container.get_children():
		child.queue_free()

func _clear_combatant_views() -> void:
	_clear_target_states()
	if _earthquake_tween != null and _earthquake_tween.is_running():
		_earthquake_tween.kill()
	if _earthquake_base_positions.size() == 3:
		var shaken_objects: Array[Control] = [arena_floor, combatant_layer, battle_modifier_layer]
		for index in shaken_objects.size():
			shaken_objects[index].position.x = _earthquake_base_positions[index]
	_earthquake_base_positions.clear()
	active_battle_modifiers.clear()
	_clear_battle_modifier_visuals()
	for marker in resurrection_tombstones.values():
		var marker_tween := (marker as Dictionary).get("tween") as Tween
		if marker_tween != null and marker_tween.is_running():
			marker_tween.kill()
		var marker_root := (marker as Dictionary).get("root") as Node
		if marker_root != null and is_instance_valid(marker_root):
			marker_root.queue_free()
	resurrection_tombstones.clear()
	for view in combatant_views.values():
		(view as Node).queue_free()
	for view in _retired_player_views.values():
		(view as Node).queue_free()
	_retired_player_views.clear()
	_original_player_ids.clear()
	combatant_views.clear()
	if _turn_indicator_tween != null and _turn_indicator_tween.is_running():
		_turn_indicator_tween.kill()
	current_turn_indicator.visible = false
	current_turn_indicator.modulate.a = 0.0
	_turn_indicator_fade_deadline_usec = 0

func _update_current_turn_indicator(actor_id: StringName) -> void:
	var view := combatant_views.get(String(actor_id)) as BattleCombatantView
	if view == null:
		_hide_current_turn_indicator()
		return
	current_turn_indicator.position = view.position + Vector2(-52.0, -40.0)
	current_turn_indicator.size = current_turn_indicator.texture.get_size()
	if _turn_indicator_tween != null and _turn_indicator_tween.is_running():
		_turn_indicator_tween.kill()
	if not current_turn_indicator.visible:
		current_turn_indicator.modulate.a = 0.0
	current_turn_indicator.visible = true
	_turn_indicator_tween = create_tween()
	_turn_indicator_tween.tween_property(current_turn_indicator, "modulate:a", 1.0, 0.3)

func _hide_current_turn_indicator() -> void:
	if not current_turn_indicator.visible:
		return
	if _turn_indicator_tween != null and _turn_indicator_tween.is_running():
		_turn_indicator_tween.kill()
	_turn_indicator_tween = create_tween()
	var fade_tween := _turn_indicator_tween
	fade_tween.tween_property(current_turn_indicator, "modulate:a", 0.0, 0.3)
	_turn_indicator_fade_deadline_usec = _now_usec() + 300000
	fade_tween.tween_callback(func() -> void:
		if _turn_indicator_tween == fade_tween:
			current_turn_indicator.visible = false
	)

func _combatant_state(instance_id: StringName) -> Dictionary:
	if controller == null or controller.engine == null:
		return {}
	for state in controller.engine.snapshot().state.combatants:
		if StringName(state.instance_id) == instance_id:
			return state
	return {}

func _first_living_opponent(team: int) -> BattleCombatantView:
	var candidates: Array[BattleCombatantView] = []
	for state in controller.engine.snapshot().state.combatants:
		if _display_team(int(state.team)) == team or bool(state.get("defeated", false)):
			continue
		var view := combatant_views.get(String(state.instance_id)) as BattleCombatantView
		if view != null:
			candidates.append(view)
	candidates.sort_custom(func(left: BattleCombatantView, right: BattleCombatantView) -> bool: return left.slot_index < right.slot_index)
	return candidates[0] if not candidates.is_empty() else null

func _combatant_label(id: StringName) -> String:
	var timer_config: Dictionary = active_battle_modifiers.get("move_timer", {}) as Dictionary
	var timer_actor: Dictionary = timer_config.get("actor", {}) as Dictionary
	var timer_actor_id := StringName(timer_actor.get("instance_id", "battle-mod-timer"))
	if id == timer_actor_id:
		return "Move timer"
	var view := combatant_views.get(String(id)) as BattleCombatantView
	if view == null or view.minion_definition == null:
		return String(id)
	return "%s %d" % [view.minion_definition.display_name, view.slot_index + 1]

func _move_name(id: StringName) -> String:
	var definition := catalog.get_definition(id) if catalog != null else null
	return definition.display_name if definition is MoveDefinition else String(id)

func _move_description(move: MoveDefinition) -> String:
	var effects: Array[String] = []
	for effect in move.effects:
		if effect != null:
			effects.append("%s %d" % [effect.display_name, effect.amount])
	var type_name := String(move.type_id).get_slice("/", 1).capitalize()
	return "%s • %d energy • %s" % [type_name, move.energy_cost, ", ".join(effects)]

func _move_icon(move: MoveDefinition) -> Texture2D:
	var icon_name := String(move.buff_icon_name)
	var path := "res://content/base/art/battle/%s.png" % icon_name
	return load(path) as Texture2D if ResourceLoader.exists(path) else DEFAULT_ICON

func _resolved_visual_id(move: MoveDefinition) -> int:
	return move.legacy_class_id if move.legacy_visual_id == VISUAL_SAME_AS_CLASS_ID else move.legacy_visual_id

func _resolved_dot_visual_id(move: MoveDefinition) -> int:
	return move.legacy_class_id if move.legacy_dot_visual_id == VISUAL_SAME_AS_CLASS_ID else move.legacy_dot_visual_id

func _presentation_texture(minion: MinionDefinition) -> Texture2D:
	var presentation := catalog.get_definition(minion.presentation_id) as MinionPresentationDefinition
	if presentation == null: return null
	var source_path := "res://content/base/art/battle/minions/%s.png" % String(presentation.legacy_sprite_name)
	if ResourceLoader.exists(source_path):
		return load(source_path) as Texture2D
	var legacy_path := "res://content/base/art/battle/%s.png" % String(presentation.legacy_sprite_name)
	return load(legacy_path) as Texture2D if ResourceLoader.exists(legacy_path) else null
