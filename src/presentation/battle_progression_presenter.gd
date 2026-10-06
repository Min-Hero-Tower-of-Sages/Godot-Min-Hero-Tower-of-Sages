class_name BattleProgressionPresenter
extends Control

const SOURCE_TALENT_STATE := preload("res://src/presentation/shaders/source_talent_state.gdshader")

signal sequence_finished
signal campaign_close_requested
signal _talent_choice_selected(move_id: StringName)

const EXP_BACKGROUND := preload("res://content/base/art/battle/battleScreenMenus_fillBar_background.png")
const EXP_FILL := preload("res://content/base/art/battle/battleScreenMenus_fillBar_expFill.png")
const LEVEL_UP_PANEL := preload("res://content/base/art/battle/battleScreenMenus_levelUp_popUp.png")
const TALENT_POINT_BADGE := preload("res://content/base/art/battle/battleScreenMenus_newSkillPointIndicator.png")
const BURBIN_FONT := preload("res://content/base/fonts/BurbinCasual.ttf")
const SOURCE_TUTORIAL_SMALL_BACKGROUND := preload("res://content/base/art/source_symbols/942_Utilities.SpriteHandler_tutorial_backgroundSmall.png")
const SOURCE_TUTORIAL_DEATH_ICON := preload("res://content/base/art/source_symbols/1353_Utilities.SpriteHandler_tutorial_deathIcon.png")
const SOURCE_TUTORIAL_OK_BUTTON := preload("res://content/base/art/source_symbols/584_Utilities.SpriteHandler_tutorial_okButton.png")
const SOURCE_TALENT_MEDIUM_BACKGROUND := preload("res://content/base/art/source_symbols/802_Utilities.SpriteHandler_menus_backgroundMedium.png")
const SOURCE_TALENT_BACKGROUND := preload("res://content/base/art/source_symbols/1463_Utilities.SpriteHandler_menus_skillTree_background.png")
const SOURCE_TALENT_SPECIALIZATION := preload("res://content/base/art/source_symbols/1644_Utilities.SpriteHandler_menus_skillTree_specializationBackground.png")
const SOURCE_TALENT_TABS_LEFT := preload("res://content/base/art/source_symbols/1235_Utilities.SpriteHandler_menus_skillTree_advancedTabsLeft.png")
const SOURCE_TALENT_TABS_CENTER := preload("res://content/base/art/source_symbols/1637_Utilities.SpriteHandler_menus_skillTree_advancedTabsCentert.png")
const SOURCE_TALENT_POINTS_BUBBLE := preload("res://content/base/art/source_symbols/341_Utilities.SpriteHandler_menus_skillTree_pointsBubble.png")
const SOURCE_TALENT_RETURN := preload("res://content/base/art/source_symbols/393_Utilities.SpriteHandler_menus_returnButton.png")
const SOURCE_TALENT_BUTTON_BACKGROUND := preload("res://content/base/art/source_symbols/917_Utilities.SpriteHandler_menus_skillTree_buttonBackground.png")
const SOURCE_TALENT_RESET := preload("res://content/base/art/source_symbols/853_Utilities.SpriteHandler_menus_skillTree_resetButton.png")
const SOURCE_TALENT_OTHER_TREE := preload("res://content/base/art/source_symbols/952_Utilities.SpriteHandler_menus_skillTree_otherTreeIndicator.png")
const RESET_TALENTS_ACTION := &"ui:talents/reset"
const SOURCE_HEALTH_BACKGROUND := preload("res://content/base/art/battle/minions/battleScreenMenus_healthFillBar_background.png")
const PROGRESSION_SERVICE := preload("res://src/application/campaign_progression_service.gd")

const EXP_BAR_FADE_SECONDS := 0.3
const EXP_BAR_FILL_SECONDS := 0.6
const LEVEL_CARD_SECONDS := 3.0
const LEVEL_CARD_UPDATE_SECONDS := 2.3
const BETWEEN_LEVELS_SECONDS := 0.15

var _sequence_id := 0
var _sequence_active := false
var _bar_nodes: Array[Control] = []
var _popup_nodes: Array[Control] = []
var _active_talent_tooltip: BattleMoveTooltip
var _owned_gems: Array[Dictionary] = []
var _star_upgrades: Dictionary = {}
var _display_stat_state := CampaignState.new()
var _display_stat_catalog: ContentCatalog
var _display_stat_context: Dictionary = {}
var _talent_selected_tree := -1
var _skip_revision := 0
var _campaign_talent_mode := false
var _music_finish_started := false

func _input(event: InputEvent) -> void:
	if not _sequence_active or not event is InputEventKey or not event.pressed or event.echo:
		return
	# BaseBattleFinishScreen delegates input to these screens while they are
	# open. Result-queue shortcuts must never dismiss an unchosen talent/evolution.
	if get_node_or_null("TalentTreeModal") != null or get_node_or_null("ProgressionModal") != null or get_node_or_null("FirstDefeatTutorial") != null:
		return
	if event.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]:
		_skip_revision += 1
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_ESCAPE:
		cancel_sequence()
		get_viewport().set_input_as_handled()
		sequence_finished.emit()

func _process(_delta: float) -> void:
	if is_instance_valid(_active_talent_tooltip) and _active_talent_tooltip.visible:
		_active_talent_tooltip.follow_mouse(get_local_mouse_position(), get_viewport_rect().size)

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 1300
	visible = false

func begin_sequence(party: Array, awards: Dictionary, catalog: ContentCatalog, combatant_views: Dictionary, battle_won: bool, audio_controller: BattleAudioController, save_callback: Callable = Callable(), show_first_defeat_tutorial: bool = false, owned_gems: Array[Dictionary] = [], star_upgrades: Dictionary = {}, finish_stat_context: Dictionary = {}) -> void:
	cancel_sequence()
	_campaign_talent_mode = false
	_owned_gems = owned_gems
	_star_upgrades = star_upgrades
	_display_stat_state.party.assign(party)
	_display_stat_state.owned_gems.assign(owned_gems)
	_display_stat_state.progression["star_upgrades"] = star_upgrades
	_display_stat_catalog = catalog
	_display_stat_context = finish_stat_context.duplicate(true)
	_sequence_id += 1
	_sequence_active = true
	_music_finish_started = false
	visible = true
	if battle_won and audio_controller != null:
		_restore_victory_music(_sequence_id, audio_controller)
	_run_sequence(_sequence_id, party.duplicate(), awards.duplicate(true), catalog, combatant_views, battle_won, audio_controller, save_callback, show_first_defeat_tutorial)

func _restore_victory_music(run_id: int, audio_controller: BattleAudioController) -> void:
	# WinScreen.PlayVictory at 0.4s schedules background music six seconds
	# later. Do not resurrect it after a short/skipped finish sequence returns.
	await get_tree().create_timer(6.4).timeout
	if _is_current(run_id) and not _music_finish_started and is_instance_valid(audio_controller):
		audio_controller.fade_music_to(0.2, 0.5)

func show_campaign_talents(owned: OwnedMinionState, catalog: ContentCatalog, save_callback: Callable) -> void:
	cancel_sequence()
	_campaign_talent_mode = true
	_sequence_id += 1
	_sequence_active = true
	visible = true
	var definition := catalog.get_definition(owned.definition_id) as MinionDefinition
	if definition != null:
		await _present_talent_choice(_sequence_id, owned, definition, catalog, save_callback, false)
	_sequence_active = false
	visible = false
	sequence_finished.emit()

func cancel_sequence() -> void:
	_display_stat_context.clear()
	_sequence_id += 1
	_sequence_active = false
	for node in _bar_nodes + _popup_nodes:
		if is_instance_valid(node):
			node.queue_free()
	_bar_nodes.clear()
	_popup_nodes.clear()
	visible = false

func _run_sequence(run_id: int, party: Array, awards: Dictionary, catalog: ContentCatalog, combatant_views: Dictionary, battle_won: bool, audio_controller: BattleAudioController, save_callback: Callable, show_first_defeat_tutorial: bool) -> void:
	if show_first_defeat_tutorial and CampaignSettingsService.new().tips_enabled:
		await _present_first_defeat_tutorial(run_id)
		if not _is_current(run_id):
			return
	await _delay(1.8 if battle_won else 0.3, run_id)
	if not _is_current(run_id):
		return
	for raw_owned in party:
		if not _is_current(run_id):
			return
		var owned := raw_owned as OwnedMinionState
		if owned == null:
			continue
		var award: Dictionary = awards.get(String(owned.instance_id), {})
		var old_level := int(award.get("old_level", owned.level))
		if award.is_empty() or old_level >= 59:
			continue
		var definition := catalog.get_definition(owned.definition_id) as MinionDefinition
		var view := combatant_views.get(String(owned.instance_id)) as BattleCombatantView
		if definition == null or view == null:
			continue
		await _present_owned_minion(run_id, owned, award, definition, view, catalog, audio_controller, save_callback)
	if not _is_current(run_id):
		return
	_music_finish_started = true
	if audio_controller != null:
		audio_controller.fade_music_to(0.0, 1.5)
	await _delay(1.0, run_id)
	if not _is_current(run_id):
		return
	_clear_nodes()
	_sequence_active = false
	visible = false
	sequence_finished.emit()

func _present_first_defeat_tutorial(run_id: int) -> void:
	var modal := ColorRect.new()
	modal.name = "FirstDefeatTutorial"
	modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.color = Color(0.015, 0.02, 0.035, 0.72)
	modal.mouse_filter = Control.MOUSE_FILTER_STOP
	modal.z_index = 20
	add_child(modal)
	_popup_nodes.append(modal)
	var panel := Control.new()
	panel.name = "Panel"
	panel.position = Vector2(164.0, 104.0)
	panel.size = Vector2(415.0, 351.0)
	panel.pivot_offset = panel.size * 0.5
	panel.scale = Vector2(0.9, 0.9)
	panel.modulate.a = 0.0
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	modal.add_child(panel)
	var background := TextureRect.new()
	background.texture = SOURCE_TUTORIAL_SMALL_BACKGROUND
	background.size = panel.size
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(background)
	var title := _modal_label("Tower Tip", Vector2(20.0, 97.0), Vector2(380.0, 42.0), 28, Color8(249, 240, 217), HORIZONTAL_ALIGNMENT_CENTER)
	title.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	title.modulate.a = 0.0
	panel.add_child(title)
	var message := _modal_label("When you die you still get a small amount of\nexp for fighting", Vector2(30.0, 136.0), Vector2(353.0, 44.0), 15, Color8(249, 240, 217), HORIZONTAL_ALIGNMENT_CENTER)
	message.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.modulate.a = 0.0
	panel.add_child(message)
	var skull := TextureRect.new()
	skull.name = "DeathIcon"
	skull.texture = SOURCE_TUTORIAL_DEATH_ICON
	skull.position = Vector2(168.0, 187.0)
	skull.size = Vector2(74.0, 62.0)
	skull.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	skull.mouse_filter = Control.MOUSE_FILTER_IGNORE
	skull.modulate.a = 0.0
	panel.add_child(skull)
	var tip := _modal_label("Tip: You don’t get any exp for forfeiting a battle", Vector2(0.0, 256.0), Vector2(415.0, 32.0), 15, Color8(249, 240, 217), HORIZONTAL_ALIGNMENT_CENTER)
	tip.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.modulate.a = 0.0
	panel.add_child(tip)
	var continue_button := TextureButton.new()
	continue_button.texture_normal = SOURCE_TUTORIAL_OK_BUTTON
	continue_button.position = Vector2(143.0, 276.0)
	continue_button.size = Vector2(128.0, 50.0)
	continue_button.ignore_texture_size = true
	continue_button.stretch_mode = TextureButton.STRETCH_SCALE
	continue_button.pressed.connect(func() -> void: modal.set_meta("dismissed", true))
	panel.add_child(continue_button)
	var entrance := create_tween().set_parallel(true)
	entrance.tween_property(modal, "modulate:a", 1.0, 0.4)
	entrance.tween_property(panel, "modulate:a", 1.0, 0.4)
	entrance.tween_property(panel, "scale", Vector2.ONE, 0.4)
	for item in [title, message, skull, tip]:
		entrance.tween_property(item, "modulate:a", 1.0, 0.5)
	while _is_current(run_id) and not bool(modal.get_meta("dismissed", false)):
		await get_tree().process_frame
	if not _is_current(run_id):
		return
	await _animate_alpha(modal, 0.0, 0.5, run_id)
	if not _is_current(run_id):
		return
	modal.queue_free()
	_popup_nodes.erase(modal)

func _present_owned_minion(run_id: int, owned: OwnedMinionState, award: Dictionary, definition: MinionDefinition, view: BattleCombatantView, catalog: ContentCatalog, audio_controller: BattleAudioController, save_callback: Callable) -> void:
	var old_experience := int(award.get("old_experience", owned.experience))
	var new_experience := int(award.get("new_experience", owned.experience))
	var old_level := int(award.get("old_level", owned.level))
	var new_level := int(award.get("new_level", owned.level))
	var active_definition := definition
	var evolved_during_sequence := false
	var bar := _create_experience_bar(view, old_experience)
	await _animate_alpha(bar, 1.0, EXP_BAR_FADE_SECONDS, run_id)
	if not _is_current(run_id):
		return
	for level in range(old_level, new_level):
		await _animate_experience(bar, 1000.0, EXP_BAR_FILL_SECONDS, run_id)
		if not _is_current(run_id):
			return
		var popup := _create_level_popup(view, owned, active_definition, level, audio_controller)
		await _present_level_popup(popup, view, owned, active_definition, level, run_id)
		if not _is_current(run_id):
			return
		var reached_level := level + 1
		if is_talent_point_earned_on_level(reached_level):
			await _present_talent_choice(run_id, owned, active_definition, catalog, save_callback, true, view, audio_controller)
		elif not evolved_during_sequence and not active_definition.evolution_id.is_empty() and reached_level >= active_definition.evolution_level:
			evolved_during_sequence = await _present_evolution(run_id, owned, active_definition, view, catalog, audio_controller, save_callback)
			if evolved_during_sequence:
				active_definition = catalog.get_definition(owned.definition_id) as MinionDefinition
				_reposition_experience_bar(bar, view)
		if not _is_current(run_id):
			return
		bar.get_node("Fill").value = 0.0
		await _delay(BETWEEN_LEVELS_SECONDS, run_id)
		if not _is_current(run_id):
			return
	var final_progress := clampf(float(new_experience - new_level * 1000) / 1000.0, 0.0, 1.0) * 1000.0
	await _animate_experience(bar, final_progress, 0.7, run_id)
	if not _is_current(run_id):
		return
	await _animate_alpha(bar, 0.0, 0.5, run_id)
	if is_instance_valid(view):
		view.set_campaign_level_display(new_level)
	bar.queue_free()
	_bar_nodes.erase(bar)

func _present_talent_choice(run_id: int, owned: OwnedMinionState, definition: MinionDefinition, catalog: ContentCatalog, save_callback: Callable, close_when_spent: bool = true, origin_view: BattleCombatantView = null, audio_controller: BattleAudioController = null) -> void:
	var choices := CampaignProgressionService.talent_choices(owned, definition, catalog)
	if choices.is_empty() and close_when_spent:
		return
	_talent_selected_tree = CampaignProgressionService.talent_specialization_index(owned, definition)
	var modal := _create_talent_modal(owned, definition, catalog, choices)
	await _animate_talent_entrance(modal, run_id, origin_view, audio_controller)
	if not _is_current(run_id) or not is_instance_valid(modal):
		return
	while _is_current(run_id):
		var selected_move_id: StringName = await _talent_choice_selected
		if not _is_current(run_id):
			return
		if selected_move_id.is_empty():
			break
		var previous_moves := owned.learned_move_ids.duplicate()
		var previous_nodes := owned.talent_node_ids.duplicate()
		var purchase: Dictionary
		if selected_move_id == RESET_TALENTS_ACTION:
			purchase = CampaignProgressionService.reset_talents(owned, definition)
			_talent_selected_tree = -1
		else:
			purchase = CampaignProgressionService.purchase_talent_choice(owned, definition, catalog, selected_move_id)
			if purchase.ok and StringName(purchase.choice.get("kind", "")) == &"specialization":
				_talent_selected_tree = int(purchase.choice.tree_index)
		if purchase.ok:
			if not _save_progression(save_callback):
				owned.learned_move_ids.assign(previous_moves)
				owned.talent_node_ids.assign(previous_nodes)
				break
			choices = CampaignProgressionService.talent_choices(owned, definition, catalog)
			if choices.is_empty() and close_when_spent:
				break
			remove_child(modal) # Release its name before building the refreshed modal.
			modal.queue_free()
			_popup_nodes.erase(modal)
			modal = _create_talent_modal(owned, definition, catalog, choices)
		else:
			push_error("Could not apply campaign talent choice: %s" % purchase.get("message", purchase.get("code", "unknown error")))
			break
	if _is_current(run_id):
		await _animate_alpha(modal.get_node("TalentTreePanel") as Control, 0.0, 0.5, run_id)
	if is_instance_valid(modal):
		modal.queue_free()
	_popup_nodes.erase(modal)
	_active_talent_tooltip = null

func _animate_talent_entrance(modal: Control, run_id: int, origin_view: BattleCombatantView, audio_controller: BattleAudioController) -> void:
	var panel := modal.get_node("TalentTreePanel") as Control
	var input_guard := Control.new()
	input_guard.name = "TalentEntranceInputGuard"
	input_guard.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	input_guard.mouse_filter = Control.MOUSE_FILTER_STOP
	input_guard.z_index = 100
	modal.add_child(input_guard)
	panel.modulate.a = 0.0
	var tween := create_tween()
	if origin_view == null:
		tween.tween_interval(0.1)
		tween.tween_property(panel, "modulate:a", 1.0, 0.5)
	else:
		# BattleScreenTalentTreeWrapper rises from the minion as a small card,
		# leaves the canvas, then drops into its authored position at (177,30).
		panel.scale = Vector2.ONE * 0.18
		panel.position = origin_view.position + origin_view.minion_sprite.position
		if audio_controller != null:
			audio_controller.play_sound("battle_whoosh")
		tween.tween_property(panel, "modulate:a", 1.0, 0.3)
		tween.tween_property(panel, "position:y", -90.0, 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(panel, "position:y", -420.0, 0.1)
		tween.tween_property(panel, "scale", Vector2.ONE, 0.1)
		if audio_controller != null:
			tween.tween_callback(func() -> void: audio_controller.play_sound("battle_whoosh"))
		tween.tween_property(panel, "position:x", 177.0, 0.1)
		tween.tween_property(panel, "position:y", 30.0, 1.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	while tween.is_running() and _is_current(run_id) and is_instance_valid(modal):
		await get_tree().process_frame
	if not _is_current(run_id) or not is_instance_valid(modal):
		if tween.is_running():
			tween.kill()
		return
	if _is_current(run_id) and is_instance_valid(input_guard):
		input_guard.queue_free()

func _create_talent_modal(owned: OwnedMinionState, definition: MinionDefinition, catalog: ContentCatalog, choices: Array[Dictionary]) -> Control:
	var modal := ColorRect.new()
	modal.name = "TalentTreeModal"
	modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.color = Color(0, 0, 0, 0.65) if _campaign_talent_mode else Color(0.015, 0.02, 0.035, 0.72)
	modal.mouse_filter = Control.MOUSE_FILTER_STOP
	modal.z_index = 20
	add_child(modal)
	_popup_nodes.append(modal)
	var panel := Control.new()
	panel.name = "TalentTreePanel"
	panel.position = Vector2(177.0, 30.0)
	if _campaign_talent_mode:
		var viewport_size := get_viewport_rect().size
		var factor := minf(viewport_size.x / 700.0, viewport_size.y / 525.0)
		panel.position = (viewport_size - Vector2(700, 525) * factor) * 0.5 + CampaignPartyMenuView.SOURCE_SETTLED_PANEL_POSITION * factor
		panel.scale = Vector2.ONE * factor
	panel.size = SOURCE_TALENT_MEDIUM_BACKGROUND.get_size()
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	modal.add_child(panel)
	_add_talent_texture(panel, SOURCE_TALENT_MEDIUM_BACKGROUND, Vector2.ZERO)
	if _campaign_talent_mode:
		var close := SourceMenuArt.button(panel, "menus_exitButton", Vector2(296, -22), func() -> void:
			cancel_sequence()
			campaign_close_requested.emit()
		)
		close.name = "CloseButton"
	_add_talent_texture(panel, SOURCE_TALENT_BACKGROUND, Vector2(17.0, 20.0))
	var talent_tooltip := _create_talent_tooltip(modal)
	var return_button := TextureButton.new()
	return_button.name = "ReturnButton"
	return_button.texture_normal = SOURCE_TALENT_RETURN
	return_button.position = Vector2(2.0, 356.0)
	return_button.ignore_texture_size = true
	return_button.size = SOURCE_TALENT_RETURN.get_size()
	return_button.pressed.connect(func() -> void: _talent_choice_selected.emit(&""))
	panel.add_child(return_button)
	var points := _talent_label("Points: %d" % CampaignProgressionService.available_talent_points(owned, definition), Vector2(64.0, 310.0), Vector2(250.0, 34.0), 20)
	points.name = "TalentPoints"
	panel.add_child(points)
	var specialization_index := CampaignProgressionService.talent_specialization_index(owned, definition)
	if specialization_index < 0 and not definition.specialization_move_ids.is_empty():
		_add_talent_texture(panel, SOURCE_TALENT_SPECIALIZATION, Vector2(24.0, 116.0))
		panel.add_child(_talent_label("Choose a specialization", Vector2(61.0, 69.0), Vector2(250.0, 34.0), 20))
		for tree_index in definition.specialization_move_ids.size():
			var move_id := definition.specialization_move_ids[tree_index]
			var move := catalog.get_definition(move_id) as MoveDefinition
			if move == null:
				continue
			var tree := catalog.get_definition(definition.talent_tree_ids[tree_index]) as TalentTreeDefinition if tree_index < definition.talent_tree_ids.size() else null
			var tree_name := tree.display_name if tree != null else "Specialization %d" % (tree_index + 1)
			panel.add_child(_talent_label(tree_name, Vector2(-49.0 + float(tree_index) * 104.0, 120.0), Vector2(250.0, 28.0), 20))
			var can_buy := choices.any(func(choice: Dictionary) -> bool: return StringName(choice.get("move_id", "")) == move_id)
			_add_talent_choice_button(panel, move, Vector2(77.0 + float(tree_index) * 76.0, 172.0), can_buy, "0/1", talent_tooltip)
	else:
		_add_talent_texture(panel, SOURCE_TALENT_BUTTON_BACKGROUND, Vector2(262.0, 340.0))
		var reset_button := TextureButton.new()
		reset_button.name = "ResetTalentsButton"
		reset_button.texture_normal = SOURCE_TALENT_RESET
		reset_button.position = Vector2(276.0, 361.0)
		reset_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		reset_button.pressed.connect(func() -> void: _talent_choice_selected.emit(RESET_TALENTS_ACTION))
		panel.add_child(reset_button)
		points.position.x = 44.0
		points.size.x = 280.0
		var tree_pages: Array[Control] = []
		var tree_indices: Array[int] = []
		var first_page := -1
		var tabs_background := _add_talent_texture(panel, SOURCE_TALENT_TABS_LEFT, Vector2(19.0, 20.0))
		for tree_index in definition.talent_tree_ids.size():
			var tree := catalog.get_definition(definition.talent_tree_ids[tree_index]) as TalentTreeDefinition
			if tree == null:
				continue
			var page := Control.new()
			page.name = "TalentTree%d" % tree_index
			page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			page.mouse_filter = Control.MOUSE_FILTER_IGNORE
			page.visible = false
			panel.add_child(page)
			tree_pages.append(page)
			tree_indices.append(tree_index)
			var available_nodes: Dictionary = {}
			for choice in choices:
				if int(choice.get("tree_index", -1)) == tree_index:
					available_nodes[StringName(choice.get("node_id", ""))] = true
			# The recovered page places dependency markers behind each dependent node.
			# Draw them first so the node icons sit above the source-style dark squares.
			for node in tree.nodes:
				var prerequisites: Array = node.get("prerequisite_node_ids", [])
				if prerequisites.is_empty():
					continue
				var marker := ColorRect.new()
				marker.name = "Dependency_%s" % String(node.get("id", ""))
				marker.position = Vector2(67.0 + float(node.get("column", 0)) * 107.0, 52.0 + float(node.get("row", 0)) * 63.0)
				marker.size = Vector2(16.0, 16.0)
				marker.color = Color8(15, 15, 15)
				marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
				page.add_child(marker)
			for node in tree.nodes:
				var node_moves: Array = node.get("move_ids", [])
				if node_moves.is_empty():
					continue
				var owned_count := 0
				for move_index in node_moves.size():
					if StringName(node_moves[move_index]) in owned.learned_move_ids:
						owned_count = move_index + 1
				var shown_index := mini(owned_count, node_moves.size() - 1)
				var move := catalog.get_definition(StringName(node_moves[shown_index])) as MoveDefinition
				if move == null:
					continue
				var can_buy := available_nodes.has(StringName(node.get("id", "")))
				var visually_active := CampaignProgressionService.talent_node_looks_active(owned, definition, tree, tree_index, node)
				_add_talent_choice_button(page, move, Vector2(48.0 + float(node.get("column", 0)) * 107.0, 65.0 + float(node.get("row", 0)) * 63.0), can_buy, "%d/%d" % [owned_count, node_moves.size()], talent_tooltip, visually_active)
			if not available_nodes.is_empty() and first_page < 0:
				first_page = tree_pages.size() - 1
		var remembered_page := tree_indices.find(_talent_selected_tree)
		var selected_page := remembered_page if remembered_page >= 0 else maxi(first_page, 0)
		if not tree_pages.is_empty():
			tree_pages[selected_page].visible = true
		_set_talent_tabs_texture(tabs_background, tree_indices[selected_page] if not tree_indices.is_empty() else 0)
		if not tree_indices.is_empty():
			_update_talent_points_label(points, owned, definition, catalog, tree_indices[selected_page])
		for page_index in tree_pages.size():
			var tab_index := page_index
			var actual_tree_index := tree_indices[page_index]
			var tab_tree := catalog.get_definition(definition.talent_tree_ids[actual_tree_index]) as TalentTreeDefinition
			var spent_points := CampaignProgressionService.maximum_talent_points(owned.level) - CampaignProgressionService.available_talent_points(owned, definition)
			if actual_tree_index != specialization_index and spent_points > 10 and CampaignProgressionService.available_talent_points(owned, definition) > 0:
				_add_talent_texture(panel, SOURCE_TALENT_OTHER_TREE, Vector2(10.0 + float(actual_tree_index) * 105.0, 19.0))
			var tab_label := _talent_label(tab_tree.display_name if tab_tree != null else "Tree %d" % (actual_tree_index + 1), Vector2(-51.0 + float(actual_tree_index) * 108.0, 24.0), Vector2(250.0, 32.0), 20)
			tab_label.name = "TreeTabLabel%d" % actual_tree_index
			panel.add_child(tab_label)
			var tab := Button.new()
			tab.name = "TreeTabButton%d" % actual_tree_index
			tab.position = Vector2(23.0 + float(actual_tree_index) * 105.0, 24.0)
			tab.size = Vector2(103.0, 32.0)
			tab.flat = true
			tab.text = ""
			tab.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			tab.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
			tab.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
			tab.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
			tab.pressed.connect(func() -> void:
				for index in tree_pages.size():
					tree_pages[index].visible = index == tab_index
				_set_talent_tabs_texture(tabs_background, actual_tree_index)
				_talent_selected_tree = actual_tree_index
				_update_talent_points_label(points, owned, definition, catalog, actual_tree_index)
				talent_tooltip.visible = false
			)
			panel.add_child(tab)
	return modal

func _update_talent_points_label(label: Label, owned: OwnedMinionState, definition: MinionDefinition, catalog: ContentCatalog, tree_index: int) -> void:
	var available_points := CampaignProgressionService.available_talent_points(owned, definition)
	var spent_points := CampaignProgressionService.maximum_talent_points(owned.level) - available_points
	var specialization_index := CampaignProgressionService.talent_specialization_index(owned, definition)
	if specialization_index >= 0 and tree_index != specialization_index and spent_points < 10:
		var tree := catalog.get_definition(definition.talent_tree_ids[tree_index]) as TalentTreeDefinition
		label.text = "Reset to %s to add points here" % (tree.display_name.to_lower() if tree != null else "this specialization")
		label.add_theme_font_size_override("font_size", 17)
		label.add_theme_color_override("font_color", Color.hex(0xed5e5eff))
	else:
		label.text = "Points: %d" % available_points
		label.add_theme_font_size_override("font_size", 20)
		label.add_theme_color_override("font_color", Color.hex(0xffea00ff))

func _create_talent_tooltip(parent: Control) -> BattleMoveTooltip:
	var tooltip := BattleMoveTooltip.new()
	tooltip.name = "TalentMoveTooltip"
	tooltip.z_index = 60
	parent.add_child(tooltip)
	_active_talent_tooltip = tooltip
	# TalentTreeNode uses BaseMinionMove's same tooltip as battle moves;
	# the brown/gold override was not part of the original interface.
	return tooltip

func _set_talent_tabs_texture(tabs_background: TextureRect, selected_tree_index: int) -> void:
	# The source page uses a centered tab strip for its middle specialization and
	# the left strip flipped for the right specialization.
	if selected_tree_index == 1:
		tabs_background.texture = SOURCE_TALENT_TABS_CENTER
		tabs_background.flip_h = false
	elif selected_tree_index == 2:
		tabs_background.texture = SOURCE_TALENT_TABS_LEFT
		tabs_background.flip_h = true
	else:
		tabs_background.texture = SOURCE_TALENT_TABS_LEFT
		tabs_background.flip_h = false

func _add_talent_texture(parent: Control, texture: Texture2D, at: Vector2) -> TextureRect:
	var sprite := TextureRect.new()
	sprite.texture = texture
	sprite.position = at
	sprite.size = texture.get_size()
	sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(sprite)
	return sprite

func _add_talent_choice_button(parent: Control, move: MoveDefinition, at: Vector2, enabled: bool = true, progress_text: String = "0/1", talent_tooltip: BattleMoveTooltip = null, visually_active: bool = true) -> void:
	var button := TextureButton.new()
	button.texture_normal = _talent_move_icon(move)
	button.set_meta("move_id", move.id)
	button.set_meta("purchasable", enabled)
	button.set_meta("visually_active", visually_active)
	button.position = at
	button.size = Vector2(53.0, 51.0)
	button.ignore_texture_size = true
	button.stretch_mode = TextureButton.STRETCH_SCALE
	button.disabled = false
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if enabled else Control.CURSOR_ARROW
	var state_material := ShaderMaterial.new()
	state_material.shader = SOURCE_TALENT_STATE
	state_material.set_shader_parameter("saturation", 1.0)
	state_material.set_shader_parameter("brightness", 1.0)
	button.material = state_material
	if not visually_active:
		var inactive := create_tween().set_parallel(true)
		inactive.tween_method(func(value: float) -> void: state_material.set_shader_parameter("saturation", value), 1.0, 0.1, 0.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		inactive.tween_method(func(value: float) -> void: state_material.set_shader_parameter("brightness", value), 1.0, 0.5, 0.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if talent_tooltip != null:
		button.mouse_entered.connect(func() -> void: talent_tooltip.show_move(move))
		button.mouse_exited.connect(func() -> void: talent_tooltip.visible = false)
	var selected_move_id := move.id
	if enabled:
		button.pressed.connect(func() -> void: _talent_choice_selected.emit(selected_move_id))
	parent.add_child(button)
	var points_bubble := _add_talent_texture(parent, SOURCE_TALENT_POINTS_BUBBLE, at + Vector2(29.0, 37.0))
	points_bubble.material = state_material
	var points_label := _talent_label(progress_text, at + Vector2(20.0, 37.0), Vector2(50.0, 17.0), 10)
	points_label.add_theme_color_override("font_color", Color.hex(0xe5e5e5ff))
	points_label.scale = Vector2.ONE * 0.95
	points_label.material = state_material
	parent.add_child(points_label)

func _talent_label(value: String, at: Vector2, label_size: Vector2, font_size: int) -> Label:
	var label := _modal_label(value, at + Vector2(2, 2), label_size, font_size, Color.hex(0xffea00ff), HORIZONTAL_ALIGNMENT_CENTER)
	label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	return label

func _talent_move_icon(move: MoveDefinition) -> Texture2D:
	# This metadata is the recovered m_buffIcon field and is also the icon source
	# used by the battle presentation; display-name reconstruction is ambiguous
	# for move families such as Pound, Spike, and Bite.
	if move.buff_icon_name.is_empty():
		return null
	var icon_path := "res://content/base/art/battle/%s.png" % String(move.buff_icon_name)
	return load(icon_path) as Texture2D if ResourceLoader.exists(icon_path) else null

func _present_evolution(run_id: int, owned: OwnedMinionState, old_definition: MinionDefinition, view: BattleCombatantView, catalog: ContentCatalog, audio_controller: BattleAudioController, save_callback: Callable) -> bool:
	var new_definition := catalog.get_definition(old_definition.evolution_id) as MinionDefinition
	if new_definition == null:
		push_error("Missing configured campaign evolution %s" % old_definition.evolution_id)
		return false
	var old_texture := _presentation_texture(old_definition, catalog)
	var new_texture := _presentation_texture(new_definition, catalog)
	if old_texture == null or new_texture == null:
		push_error("Evolution art is missing for %s -> %s" % [old_definition.id, new_definition.id])
		return false
	var modal := preload("res://src/presentation/source_evolution_popup.gd").new()
	add_child(modal)
	modal.configure(old_definition, old_texture, new_texture)
	_popup_nodes.append(modal)
	var panel := modal.get_node("Panel") as Control
	panel.modulate.a = 0.0
	create_tween().tween_property(panel, "modulate:a", 1.0, 0.5)
	var old_sprite := panel.get_node("OldMask/OldSprite") as Sprite2D
	var new_sprite := panel.get_node("NewSprite") as Sprite2D
	var message := panel.get_node("Message") as Label
	var close_button := panel.get_node("CloseButton") as TextureButton
	# Use one timeline for the delays, motion and sounds. Mixing wall-clock
	# delays with frame-time tweens drifted when the engine's frame time changed.
	var movement := create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	movement.tween_property(old_sprite, "position:x", old_sprite.position.x + 173.0, 2.5).set_delay(2.0)
	movement.tween_property(new_sprite, "position:x", new_sprite.position.x + 173.0, 2.5).set_delay(2.0)
	if audio_controller != null:
		movement.tween_callback(func() -> void: audio_controller.play_sound("battle_whoosh_magic2")).set_delay(2.0)
		movement.tween_callback(func() -> void: audio_controller.play_sound("battle_levelUp", 0.2)).set_delay(3.7)
	while movement.is_running():
		if not _is_current(run_id):
			movement.kill()
			return false
		if bool(modal.get_meta("skip_evolution", false)):
			if movement != null and movement.is_running():
				movement.kill()
			await _animate_alpha(modal, 0.0, 0.5, run_id)
			_discard_evolution_popup(modal)
			return false
		await get_tree().process_frame
	if not _is_current(run_id):
		return false
	var before := owned.duplicate_state()
	var evolution := CampaignProgressionService.evolve_owned_minion(owned, catalog, _owned_gems, _star_upgrades, _display_stat_state, _display_stat_context)
	if not evolution.ok:
		push_error("Could not apply campaign evolution: %s" % evolution.get("message", evolution.get("code", "unknown error")))
		_discard_evolution_popup(modal)
		return false
	if not _save_progression(save_callback):
		owned.definition_id = before.definition_id
		owned.nickname = before.nickname
		owned.persistent_health = before.persistent_health
		owned.persistent_energy = before.persistent_energy
		await _animate_alpha(modal, 0.0, 0.5, run_id)
		_discard_evolution_popup(modal)
		return false
	var stats: Dictionary = evolution.stats
	view.apply_campaign_evolution(new_definition, new_texture, int(stats.health), int(stats.energy), owned.persistent_health, owned.persistent_energy)
	message.text = "%s has grown into a %s!" % [old_definition.display_name, new_definition.display_name]
	close_button.visible = false
	await _delay(1.5, run_id)
	if not _is_current(run_id):
		return false
	await _animate_alpha(modal, 0.0, 0.5, run_id)
	if not _is_current(run_id):
		return false
	_discard_evolution_popup(modal)
	return true

func _discard_evolution_popup(modal: Control) -> void:
	if modal.get_parent() == self:
		remove_child(modal)
	modal.queue_free()
	_popup_nodes.erase(modal)

func _reposition_experience_bar(bar: Control, view: BattleCombatantView) -> void:
	var sprite_height := float(view.minion_sprite.texture.get_height())
	var background := bar.get_child(0) as TextureRect
	background.position = view.position + Vector2(-background.size.x * 0.5 - 6.0, -sprite_height - 30.0)
	bar.get_node("Fill").position = view.position + Vector2(-SOURCE_HEALTH_BACKGROUND.get_width() * 0.5 + 4.0, -sprite_height - 27.0)

func _modal_label(text_value: String, label_position: Vector2, label_size: Vector2, font_size: int, color: Color, alignment: HorizontalAlignment) -> Label:
	var label := Label.new()
	label.text = text_value
	label.position = label_position
	label.size = label_size
	label.horizontal_alignment = alignment
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", BURBIN_FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _presentation_texture(definition: MinionDefinition, catalog: ContentCatalog) -> Texture2D:
	var presentation := catalog.get_definition(definition.presentation_id) as MinionPresentationDefinition
	if presentation == null:
		return null
	var source_path := "res://content/base/art/battle/minions/%s.png" % String(presentation.legacy_sprite_name)
	if ResourceLoader.exists(source_path):
		return load(source_path) as Texture2D
	var legacy_path := "res://content/base/art/battle/%s.png" % String(presentation.legacy_sprite_name)
	return load(legacy_path) as Texture2D if ResourceLoader.exists(legacy_path) else null

func _save_progression(save_callback: Callable) -> bool:
	if save_callback.is_null():
		return true
	var result: Variant = save_callback.call()
	if result is Dictionary and not bool(result.get("ok", false)):
		push_error("Could not save campaign progression: %s" % result.get("message", result.get("code", "unknown error")))
		return false
	return true

func _create_experience_bar(view: BattleCombatantView, old_experience: int) -> Control:
	var root := Control.new()
	root.name = "ExperienceBar_%s" % String(view.instance_id)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sprite_height := float(view.minion_sprite.texture.get_height()) if view.minion_sprite != null and view.minion_sprite.texture != null else 0.0
	var background := TextureRect.new()
	background.texture = EXP_BACKGROUND
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.size = EXP_BACKGROUND.get_size()
	background.position = view.position + Vector2(-background.size.x * 0.5 - 6.0, -sprite_height - 30.0)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(background)
	var fill := TextureProgressBar.new()
	fill.name = "Fill"
	fill.texture_progress = EXP_FILL
	fill.min_value = 0.0
	fill.max_value = 1000.0
	fill.value = float(posmod(old_experience, 1000))
	# InterfaceBar translates the fill from negative x toward zero under its
	# fixed mask: the visible overlap starts at the LEFT edge, not the right.
	fill.fill_mode = TextureProgressBar.FILL_LEFT_TO_RIGHT
	fill.size = EXP_FILL.get_size()
	# The source anchors the fill to the health bar frame (77 px), while the
	# decorative experience backdrop is wider (92 px).
	fill.position = view.position + Vector2(-SOURCE_HEALTH_BACKGROUND.get_width() * 0.5 + 4.0, -sprite_height - 27.0)
	fill.add_theme_stylebox_override("background", StyleBoxEmpty.new())
	fill.add_theme_stylebox_override("fill", StyleBoxEmpty.new())
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(fill)
	root.modulate.a = 0.0
	add_child(root)
	_bar_nodes.append(root)
	return root

func _create_level_popup(view: BattleCombatantView, owned: OwnedMinionState, definition: MinionDefinition, level: int, audio_controller: BattleAudioController) -> Control:
	var root := Control.new()
	root.name = "LevelUp_%s_%d" % [String(owned.instance_id), level + 1]
	root.position = view.position + Vector2(40.0, -244.0)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.modulate.a = 0.0
	var panel := TextureRect.new()
	panel.texture = LEVEL_UP_PANEL
	panel.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	panel.size = LEVEL_UP_PANEL.get_size()
	panel.position = Vector2(0.0, -32.0)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(panel)
	var minion_name := owned.nickname if not owned.nickname.is_empty() else definition.display_name
	var name_label := _popup_label(minion_name, Vector2(22.0, 13.0), Vector2(135.0, 24.0), 20, Color8(235, 234, 235), HORIZONTAL_ALIGNMENT_LEFT)
	root.add_child(name_label)
	var level_label := _popup_label("lv.%d" % level, Vector2(33.0, 13.0), Vector2(150.0, 24.0), 20, Color8(235, 234, 235), HORIZONTAL_ALIGNMENT_RIGHT)
	level_label.name = "LevelLabel"
	root.add_child(level_label)
	var current_stats: Dictionary = PROGRESSION_SERVICE.owned_display_stats(owned, definition, _display_stat_catalog, _display_stat_state, level, _display_stat_context)
	var next_stats: Dictionary = PROGRESSION_SERVICE.owned_display_stats(owned, definition, _display_stat_catalog, _display_stat_state, level + 1, _display_stat_context)
	var stat_keys: Array[String] = ["health", "energy", "attack", "healing", "speed"]
	var value_labels: Array[Label] = []
	var delta_labels: Array[Label] = []
	for index in stat_keys.size():
		var stat_key := stat_keys[index]
		var y := 44.0 + float(index) * 29.0
		var value := _popup_label(str(current_stats[stat_key]), Vector2(87.0, y), Vector2(48.0, 27.0), 20, Color8(45, 45, 56), HORIZONTAL_ALIGNMENT_LEFT)
		value.name = "CurrentStat%d" % index
		root.add_child(value)
		value_labels.append(value)
		var delta := _popup_label("+%d" % (int(next_stats[stat_key]) - int(current_stats[stat_key])), Vector2(138.0, y - 2.0), Vector2(50.0, 29.0), 23, Color8(45, 45, 56), HORIZONTAL_ALIGNMENT_CENTER)
		delta.name = "NextStat%d" % index
		root.add_child(delta)
		delta_labels.append(delta)
	var skill_badge := TextureRect.new()
	skill_badge.texture = TALENT_POINT_BADGE
	skill_badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	skill_badge.position = Vector2(186.0, 39.0)
	skill_badge.size = TALENT_POINT_BADGE.get_size()
	skill_badge.visible = is_talent_point_earned_on_level(level + 1)
	skill_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(skill_badge)
	root.set_meta("level_label", level_label)
	root.set_meta("value_labels", value_labels)
	root.set_meta("delta_labels", delta_labels)
	root.set_meta("audio_controller", audio_controller)
	add_child(root)
	_popup_nodes.append(root)
	return root

func _present_level_popup(popup: Control, view: BattleCombatantView, owned: OwnedMinionState, definition: MinionDefinition, level: int, run_id: int) -> void:
	# All stages of a level card are one source queue item. One press skips
	# this whole card, but still applies its stat display before the next choice.
	var step_revision := _skip_revision
	var audio_controller: BattleAudioController = popup.get_meta("audio_controller") if popup.has_meta("audio_controller") else null
	if audio_controller != null:
		audio_controller.play_sound("battle_levelUp", 0.2)
	var fade_in := create_tween()
	fade_in.tween_property(popup, "modulate:a", 1.0, 0.5).set_delay(0.1)
	await _wait_for_tween(fade_in, run_id, step_revision)
	if not _is_current(run_id):
		return
	if step_revision == _skip_revision:
		await _delay(LEVEL_CARD_UPDATE_SECONDS - 0.6, run_id)
	if not _is_current(run_id):
		return
	var current_stats: Dictionary = PROGRESSION_SERVICE.owned_display_stats(owned, definition, _display_stat_catalog, _display_stat_state, level, _display_stat_context)
	var next_stats: Dictionary = PROGRESSION_SERVICE.owned_display_stats(owned, definition, _display_stat_catalog, _display_stat_state, level + 1, _display_stat_context)
	for index in 5:
		var value_labels: Array = popup.get_meta("value_labels")
		var delta_labels: Array = popup.get_meta("delta_labels")
		(value_labels[index] as Label).text = str(next_stats[["health", "energy", "attack", "healing", "speed"][index]])
		var delta_label := delta_labels[index] as Label
		var delta_tween := create_tween()
		delta_tween.tween_property(delta_label, "modulate:a", 0.0, 0.2)
	var level_label := popup.get_meta("level_label") as Label
	level_label.text = "lv.%d" % (level + 1)
	if is_instance_valid(view):
		view.apply_campaign_level_up(current_stats, next_stats)
	if step_revision == _skip_revision:
		await _delay(maxf(0.0, LEVEL_CARD_SECONDS - LEVEL_CARD_UPDATE_SECONDS), run_id)
	if not _is_current(run_id):
		return
	if step_revision == _skip_revision:
		await _animate_alpha(popup, 0.0, 0.3, run_id)
	else:
		popup.modulate.a = 0.0
	if is_instance_valid(popup):
		popup.queue_free()
	_popup_nodes.erase(popup)

func _popup_label(text_value: String, label_position: Vector2, label_size: Vector2, font_size: int, color: Color, alignment: HorizontalAlignment) -> Label:
	var label := Label.new()
	label.text = text_value
	label.position = label_position
	label.size = label_size
	label.horizontal_alignment = alignment
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", BURBIN_FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _animate_experience(bar: Control, target_value: float, duration: float, run_id: int) -> void:
	if not is_instance_valid(bar):
		return
	var fill := bar.get_node("Fill") as TextureProgressBar
	var tween := create_tween()
	tween.tween_property(fill, "value", target_value, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await _wait_for_tween(tween, run_id, _skip_revision)
	if not _is_current(run_id):
		return

func _animate_alpha(node: CanvasItem, target_alpha: float, duration: float, run_id: int) -> void:
	if not is_instance_valid(node):
		return
	var tween := create_tween()
	tween.tween_property(node, "modulate:a", target_alpha, duration)
	await _wait_for_tween(tween, run_id, _skip_revision)
	if not _is_current(run_id):
		return

func _delay(duration: float, run_id: int) -> void:
	if duration <= 0.0:
		return
	var revision := _skip_revision
	var remaining := duration
	while _is_current(run_id) and revision == _skip_revision and remaining > 0.0:
		await get_tree().process_frame
		remaining -= get_process_delta_time()

func _wait_for_tween(tween: Tween, run_id: int, revision: int) -> void:
	while _is_current(run_id) and tween.is_running():
		if revision != _skip_revision:
			# Completing rather than killing the tween preserves its destination
			# and avoids leaving an awaited finished signal suspended forever.
			tween.custom_step(1000.0)
			return
		await get_tree().process_frame
	if not _is_current(run_id) and tween.is_running():
		tween.kill()

func _clear_nodes() -> void:
	for node in _bar_nodes + _popup_nodes:
		if is_instance_valid(node):
			node.queue_free()
	_bar_nodes.clear()
	_popup_nodes.clear()

func _is_current(run_id: int) -> bool:
	return _sequence_active and run_id == _sequence_id and is_inside_tree()

static func is_talent_point_earned_on_level(level: int) -> bool:
	if level == 3:
		return false
	if level == 60:
		return true
	var progress := float(level - 3) / 3.0 if level < 31 else float(level - 30) / 4.0 + 9.0
	return is_equal_approx(progress, roundf(progress))
