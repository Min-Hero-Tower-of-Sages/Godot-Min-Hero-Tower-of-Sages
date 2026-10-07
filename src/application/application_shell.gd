extends Control

const BATTLE_SCENE: PackedScene = preload("res://scenes/main.tscn")
const ROOM_SCENE: PackedScene = preload("res://scenes/campaign_room_view.tscn")
const FONT: Font = preload("res://content/base/fonts/BurbinCasual.ttf")
const NEW_CAMPAIGN_INTRO := preload("res://src/presentation/source_new_campaign_intro.gd")
const MULTIPLAYER_CONTROLLER := preload("res://src/application/multiplayer_shell_controller.gd")

const TITLE_BACKGROUND := "res://content/base/art/source_symbols/1242_Utilities.SpriteHandler_mainMenu_titleScreen_background.png"
const TITLE_LOGO := "res://content/base/art/source_symbols/353_Utilities.SpriteHandler_mainMenu_titleLogo.png"
const PLAY_BUTTON := "res://content/base/art/source_symbols/579_Utilities.SpriteHandler_mainMenu_playButton.png"
const SLOT_BACKGROUND := "res://content/base/art/source_symbols/501_Utilities.SpriteHandler_mainMenu_saveSlotBackground.png"
const SLOT_FILLED := "res://content/base/art/source_symbols/320_Utilities.SpriteHandler_mainMenu_saveSlotFilled.png"
const CHARACTER_BACKGROUND := "res://content/base/art/source_symbols/1352_Utilities.SpriteHandler_mainMenu_characterCreationBackground.png"
const CHARACTER_MALE_ICON := "res://content/base/art/source_symbols/1585_Utilities.SpriteHandler_mainMenu_characterCreation_maleIcon.png"
const CHARACTER_FEMALE_ICON := "res://content/base/art/source_symbols/893_Utilities.SpriteHandler_mainMenu_characterCreation_femaleIcon.png"
const CHARACTER_MALE_PREVIEW := "res://content/base/art/source_symbols/447_Utilities.SpriteHandler_mainMenu_characterCreation_maleIcon_fullSized.png"
const CHARACTER_FEMALE_PREVIEW := "res://content/base/art/source_symbols/914_Utilities.SpriteHandler_mainMenu_characterCreation_femaleIcon_fullSized.png"
const CHARACTER_GENDER_SELECTED := "res://content/base/art/source_symbols/523_Utilities.SpriteHandler_mainMenu_characterCreation_maleFemaleSelectedIcon.png"
const CHARACTER_OK_BUTTON := "res://content/base/art/source_symbols/618_Utilities.SpriteHandler_mainMenu_characterCreation_okButton.png"
const CHARACTER_CLOSE_BUTTON := "res://content/base/art/source_symbols/838_Utilities.SpriteHandler_mainMenu_saveSlot_deleteButton.png"
const SPEECH_BUBBLE := "res://content/base/art/rooms/menus_speechBubble.png"
const SPEECH_BUBBLE_ARROW := "res://content/base/art/source_symbols/689_Utilities.SpriteHandler_menus_speechBubble_arrow.png"
const SAGE_RESCUE_BUTTON := "res://content/base/art/source_symbols/835_Utilities.SpriteHandler_topDown_rescueButton.png"
const SAGE_GIFT_BUTTON := "res://content/base/art/source_symbols/559_Utilities.SpriteHandler_topDown_giftButton.png"
const SAGE_NOT_TELLING_BUTTON := "res://content/base/art/source_symbols/200_Utilities.SpriteHandler_topDown_notTellingButton.png"
const SAGE_RESCUE_PICTURE := "res://content/base/art/source_symbols/242_Utilities.SpriteHandler_topDown_pictureRescueButton.png"
const SAGE_GIFT_PICTURE := "res://content/base/art/source_symbols/1635_Utilities.SpriteHandler_topDown_pictureGiftButton.png"
const SAGE_NOT_TELLING_PICTURE := "res://content/base/art/source_symbols/676_Utilities.SpriteHandler_topDown_pictureNotTellingButton.png"
const SPEECH_TEXT_WIDTH := 228.0
const SPEECH_TEXT_VIEW_HEIGHT := 43.0
const SPEECH_TEXT_SCROLL_STEP := 21.5
const SPEECH_FONT_SIZE := 17

@onready var screen_host: Control = $ScreenHost

var runtime: Variant
var current_screen: Control
var current_room: Variant
var current_battle: Node
var room_hud: Control
var room_hud_canvas: CanvasLayer
var room_status: Label
var map_button: Button
var party_button: Button
var interaction_dialog: Control
var interaction_dialog_canvas: CanvasLayer
var room_transition_canvas: CanvasLayer
var room_transition_curtain: ColorRect
var _room_transition_active := false
var _settings: CampaignSettingsService
var _hud_map: CampaignMinimapView
var _hud_keys: Label
var _hud_stars: Label
var _hud_sound_toggle: TextureButton
var _hud_music_toggle: TextureButton
var _reward_presenter: BattleRewardPresenter
var _hud_progress: Control
var _hud_star_signature := Vector2i(-1, -1)
var _seal_fusion: Control
var _campaign_audio: BattleAudioController
var _previous_region_music := ""
var _reward_canvas_origin := Vector2.ZERO
var _menu_navigation_active := false
var _menu_backdrop: CanvasLayer
var _retiring_menu_canvases: Array[CanvasLayer] = []
var _pending_titan_rewards: Array[Dictionary] = []
var _titan_sink_started := false
var _source_dialogue_label: Label
var _source_dialogue_scroller: Control
var _source_dialogue_arrow: TextureRect
var _source_dialogue_yes: Callable
var _source_dialogue_no: Callable
var _source_dialogue_choices: Array[TextureButton] = []
var _source_dialogue_bubble_position := Vector2.ZERO
var _source_dialogue_scale := Vector2.ONE
var _source_dialogue_scroll_step := SPEECH_TEXT_SCROLL_STEP
var _source_dialogue_content_height := 0.0
var _source_dialogue_line_index := 0
var _source_dialogue_line_count := 0
var _source_dialogue_is_animating := false
var _source_dialogue_on_complete: Callable
var _active_sage_interaction: Dictionary = {}
var _sage_bonus_choice_pending := false
var _trainer_return_location: Dictionary = {}
var name_entry: LineEdit
var selected_slot := 1
var selected_gender := "male"
var party_swap_selected_party := -1
var party_swap_selected_storage := -1
var party_manager_hint: Label
var _multiplayer: MultiplayerShellController
## Resolved at runtime so this script compiles before autoloads exist.
var net: Node:
	get: return get_node_or_null("/root/NetSession")

func _ready() -> void:
	_settings = CampaignSettingsService.new()
	_settings.settings_changed.connect(_refresh_source_hud)
	runtime = get_node_or_null("/root/CampaignRuntime")
	_create_room_hud()
	_campaign_audio = BattleAudioController.new()
	_campaign_audio.add_to_group("source_menu_audio")
	add_child(_campaign_audio)
	_reward_presenter = BattleRewardPresenter.new()
	room_hud_canvas.add_child(_reward_presenter)
	_seal_fusion = preload("res://src/presentation/source_sage_seal_presenter.gd").new()
	room_hud_canvas.add_child(_seal_fusion)
	_multiplayer = MULTIPLAYER_CONTROLLER.new()
	_multiplayer.name = "Multiplayer"
	_multiplayer.shell = self
	add_child(_multiplayer)
	_show_title_screen()

func show_catalog_menu(menu_id: StringName, context: Dictionary = {}) -> bool:
	return _show_catalog_menu(menu_id, context)

func _show_catalog_menu(menu_id: StringName, context: Dictionary = {}) -> bool:
	if runtime == null or runtime.catalog == null:
		_show_notice("Can't open menu %s: the content catalog is unavailable." % menu_id)
		return false
	var definition := runtime.catalog.get_definition(menu_id) as MenuDefinition
	if definition == null:
		_show_notice("Can't open menu %s: no MenuDefinition with that ID is registered." % menu_id)
		return false
	var errors := definition.validation_errors()
	if not errors.is_empty():
		_show_notice("Can't open menu %s: %s" % [menu_id, " | ".join(errors)])
		return false
	var packed_scene := ResourceLoader.load(definition.scene_path, "PackedScene") as PackedScene
	if packed_scene == null:
		_show_notice("Can't open menu %s: its scene could not be loaded from %s." % [menu_id, definition.scene_path])
		return false
	var instance := packed_scene.instantiate()
	var extension := instance as MenuExtensionScreen
	if extension == null:
		instance.free()
		_show_notice("Can't open menu %s: scene root must extend MenuExtensionScreen (%s)." % [menu_id, definition.scene_path])
		return false
	_clear_game_screen()
	room_hud.visible = false
	extension.name = "CatalogMenu_%s" % String(menu_id).replace(":", "_").replace("/", "_")
	extension.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	extension.route_requested.connect(_on_menu_extension_route_requested)
	screen_host.add_child(extension)
	current_screen = extension
	extension.configure_menu(definition, context.duplicate(true))
	return true

func _on_menu_extension_route_requested(route_id: StringName, payload: Dictionary) -> void:
	match String(route_id):
		"title", "back_to_title":
			_show_title_screen()
		"room", "return_to_room":
			_show_room_from_state()
		_:
			# Unknown built-in routes deliberately fall through to catalog IDs.
			# This keeps the shell extensible without taking over its legacy routes.
			_show_catalog_menu(route_id, payload)

func _show_title_screen() -> void:
	_campaign_audio.play_music("titleTrack", 1.0, 3.0)
	_build_title_screen(false)

func _show_save_slots() -> void:
	_clear_dialog()
	var screen := current_screen
	if screen == null or screen.get_node_or_null("TitleBackdrop") == null:
		_build_title_screen(true)
		screen = current_screen
	var creation_layer := screen.get_node_or_null("CharacterCreationLayer")
	if creation_layer != null:
		_restore_title_after_creation(screen)
		var creation_exit := create_tween()
		creation_exit.tween_property(creation_layer, "modulate:a", 0.0, 0.5)
		creation_exit.finished.connect(creation_layer.queue_free)
		return
	var slots_already_shown := bool(screen.get_meta("title_save_slots_visible", false))
	_reveal_title_save_slots(screen, slots_already_shown)

func _build_title_screen(skip_entrance: bool) -> void:
	var screen := _new_menu_screen()
	var backdrop := Control.new()
	backdrop.name = "TitleBackdrop"
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(backdrop)
	# The original title scene scrolls the complete doorway composition upward:
	# the doors begin below the viewport and settle into the opening as the stone
	# background rises from y=-70 to y=-448.
	var left_door := SourceMenuArt.image(backdrop, "mainMenu_titleScreen_doorLeft", Vector2(164.0, 608.0))
	var right_door := SourceMenuArt.image(backdrop, "mainMenu_titleScreen_doorRight", Vector2(349.0, 608.0))
	var left_glow := SourceMenuArt.image(backdrop, "mainMenu_titleScreen_doorLeft_glow", Vector2(164.0, 230.0))
	var right_glow := SourceMenuArt.image(backdrop, "mainMenu_titleScreen_doorRight_glow", Vector2(349.0, 230.0))
	if left_glow != null:
		left_glow.modulate.a = 0.5
		NEW_CAMPAIGN_INTRO.mask_glow(left_glow, 646.0)
	if right_glow != null:
		right_glow.modulate.a = 0.5
		NEW_CAMPAIGN_INTRO.mask_glow(right_glow, 646.0)
	var background := _texture_rect(TITLE_BACKGROUND)
	if background != null:
		background.name = "TitleStoneBackground"
		background.position = Vector2(-30.0, -70.0)
		backdrop.add_child(background)
	# Keep references alive through the title-scene setup even if a source asset
	# is absent from a partial extraction; the normal build resolves all four.
	if left_door == null or right_door == null:
		push_warning("The recovered title doorway art is incomplete.")

	var dark_band := ColorRect.new()
	dark_band.name = "TitleButtonBand"
	dark_band.position = Vector2(0.0, 194.0)
	dark_band.size = Vector2(700.0, 218.0)
	dark_band.pivot_offset = dark_band.size * 0.5
	dark_band.scale.y = 0.9
	dark_band.color = Color(0.0, 0.0, 0.0, 0.5)
	dark_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(dark_band)
	var logo := _texture_rect(TITLE_LOGO)
	if logo != null:
		logo.name = "TitleLogo"
		logo.position = Vector2(185.0, 0.0)
		screen.add_child(logo)
	var play_button := SourceMenuArt.button(screen, "mainMenu_playButton", Vector2(263.0, 261.0), _show_save_slots)
	if play_button != null:
		play_button.name = "TitlePlayButton"
	var credits_button := SourceMenuArt.button(screen, "mainMenu_creditsButton", Vector2(296.0, 469.0), _show_title_credits)
	if credits_button != null:
		credits_button.name = "TitleCreditsButton"
	var sponsor_button := SourceMenuArt.button(screen, "mainMenu_titleScreen_sponsorLogo", Vector2(27.0, 267.0), func() -> void: _open_title_link("http://sogood.com/"))
	if sponsor_button != null:
		sponsor_button.name = "TitleSponsorButton"
	var tc_games_button := SourceMenuArt.button(screen, "mainMenu_titleScreen_ourLogo", Vector2(472.0, 268.0), func() -> void: _open_title_link("http://www.facebook.com/ToyChestGames"))
	if tc_games_button != null:
		tc_games_button.name = "TitleToyChestButton"
	var host_games_button := SourceMenuArt.button(screen, "mainMenu_hostGamesLogo", Vector2(15.0, 491.0), func() -> void: _open_title_link("http://sogood.com/gamesforsite.php"))
	if host_games_button != null:
		host_games_button.name = "TitleHostGamesButton"
	var music_button := SourceMenuArt.button(screen, "menu_muteMusicButton_on" if _settings.music_enabled else "menu_muteMusicButton_off", Vector2(4.0, 6.0), _toggle_title_music)
	if music_button != null:
		music_button.name = "TitleMusicToggle"
	var sound_button := SourceMenuArt.button(screen, "menu_muteSoundButton_on" if _settings.sound_enabled else "menu_muteSoundButton_off", Vector2(36.0, 5.0), _toggle_title_sound)
	if sound_button != null:
		sound_button.name = "TitleSoundToggle"

	if skip_entrance:
		if background != null:
			background.position.y = -448.0
		if left_door != null:
			left_door.position.y = 230.0
		if right_door != null:
			right_door.position.y = 230.0
		if logo != null:
			logo.modulate.a = 1.0
		if dark_band != null:
			dark_band.modulate.a = 1.0
			dark_band.scale.y = 1.0
		if play_button != null:
			play_button.modulate.a = 0.0
			play_button.position.y = 171.0
			play_button.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for button in [credits_button, sponsor_button, tc_games_button, host_games_button, music_button, sound_button]:
			if button != null:
				button.mouse_filter = Control.MOUSE_FILTER_STOP
				button.modulate.a = 1.0
	else:
		if logo != null:
			logo.position.y = -50.0
			logo.modulate.a = 0.0
		if dark_band != null:
			dark_band.modulate.a = 0.0
		if play_button != null:
			play_button.modulate.a = 0.0
			play_button.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if credits_button != null:
			credits_button.position.y += 50.0
			credits_button.modulate.a = 0.0
		if sponsor_button != null:
			sponsor_button.modulate.a = 0.0
		if tc_games_button != null:
			tc_games_button.modulate.a = 0.0
		if host_games_button != null:
			host_games_button.modulate.a = 0.0
		if music_button != null:
			music_button.modulate.a = 0.0
		if sound_button != null:
			sound_button.modulate.a = 0.0
		var black_cover := ColorRect.new()
		black_cover.name = "TitleOpeningFade"
		black_cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		black_cover.color = Color.BLACK
		black_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
		black_cover.z_index = 500
		screen.add_child(black_cover)
		var cover_tween := create_tween()
		cover_tween.tween_interval(0.5)
		cover_tween.tween_property(black_cover, "modulate:a", 0.0, 1.5)
		cover_tween.tween_callback(black_cover.queue_free)
		for scrolling_art in [background, left_door, right_door]:
			if scrolling_art != null:
				var scroll_tween: Tween = scrolling_art.create_tween().set_trans(Tween.TRANS_LINEAR)
				scroll_tween.tween_interval(0.5)
				scroll_tween.tween_property(scrolling_art, "position:y", -448.0 if scrolling_art == background else 230.0, 8.4)
		var band_tween := create_tween()
		band_tween.tween_interval(2.9)
		band_tween.tween_property(dark_band, "modulate:a", 1.0, 1.0)
		band_tween.parallel().tween_property(dark_band, "scale:y", 1.0, 1.0)
		if play_button != null:
			var play_tween := create_tween()
			play_tween.tween_interval(3.7)
			play_tween.tween_property(play_button, "modulate:a", 1.0, 0.5)
		if logo != null:
			_tween_title_widget(logo, 4.6, 0.8, Vector2(185.0, 0.0))
		if credits_button != null:
			_tween_title_widget(credits_button, 4.6, 0.8, Vector2(296.0, 469.0))
		for button in [sponsor_button, tc_games_button, host_games_button, music_button, sound_button]:
			if button != null:
				_tween_title_widget(button, 4.6, 0.8, button.position)
		_activate_title_controls_later(screen)

func _tween_title_widget(widget: Control, delay: float, duration: float, target_position: Vector2) -> void:
	var tween := create_tween()
	tween.tween_interval(delay)
	tween.tween_property(widget, "modulate:a", 1.0, duration)
	if not widget.position.is_equal_approx(target_position):
		tween.parallel().tween_property(widget, "position", target_position, duration)

func _activate_title_controls_later(screen: Control) -> void:
	await get_tree().create_timer(4.2).timeout
	if not is_instance_valid(screen) or current_screen != screen:
		return
	var play_button := screen.get_node_or_null("TitlePlayButton") as Control
	if play_button != null:
		play_button.mouse_filter = Control.MOUSE_FILTER_STOP
	await get_tree().create_timer(1.2).timeout
	if not is_instance_valid(screen) or current_screen != screen:
		return
	for node_name in ["TitleCreditsButton", "TitleSponsorButton", "TitleToyChestButton", "TitleHostGamesButton", "TitleMusicToggle", "TitleSoundToggle"]:
		var button := screen.get_node_or_null(node_name) as Control
		if button != null:
			button.mouse_filter = Control.MOUSE_FILTER_STOP

func _reveal_title_save_slots(screen: Control, immediate: bool) -> void:
	if screen == null:
		return
	var existing_slots := screen.get_node_or_null("TitleSaveSlots") as Control
	if existing_slots != null:
		for child in existing_slots.get_children():
			existing_slots.remove_child(child)
			child.queue_free()
	else:
		existing_slots = Control.new()
		existing_slots.name = "TitleSaveSlots"
		existing_slots.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		existing_slots.mouse_filter = Control.MOUSE_FILTER_IGNORE
		screen.add_child(existing_slots)
	var title_play := screen.get_node_or_null("TitlePlayButton") as Control
	if title_play != null:
		title_play.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if immediate:
			title_play.position.y = 171.0
			title_play.modulate.a = 0.0
		else:
			var play_exit := create_tween()
			play_exit.tween_property(title_play, "position:y", 171.0, 0.7)
			play_exit.parallel().tween_property(title_play, "modulate:a", 0.0, 0.7)
	for slot in range(1, SaveRepository.SLOT_COUNT + 1):
		var loaded: Dictionary = runtime.session.save_repository.load_slot(slot) if runtime != null and runtime.session != null else {"ok": false}
		var is_used := bool(loaded.get("ok", false))
		var target := Vector2(230.0, 188.0 + float(slot - 1) * 67.0)
		var card := _create_title_save_card(existing_slots, slot, is_used, loaded, target)
		if immediate:
			card.position = target
			card.modulate.a = 1.0
		else:
			card.position = Vector2(230.0, 334.0)
			card.modulate.a = 0.0
			var slot_tween := create_tween()
			slot_tween.tween_interval(0.3 * float(slot - 1))
			slot_tween.tween_property(card, "position", target, 0.6)
			slot_tween.parallel().tween_property(card, "modulate:a", 1.0, 0.6)
			_activate_save_card_later(card, 0.6 + 0.3 * float(slot - 1))
		if immediate:
			_activate_save_card_later(card, 0.0)
	# Below the save cards (they end at y 398) and above Credits (y 469),
	# skinned with the save card's own stone art so it reads as part of the list.
	var join_target := Vector2(240.0, 412.0)
	var join := _title_card_button(existing_slots, "Join a friend's game", join_target, Vector2(229.0, 42.0))
	join.name = "JoinMultiplayerButton"
	join.pressed.connect(_multiplayer.show_join_view)
	if not immediate:
		# Slides up after the last card, like the cards themselves.
		join.position = join_target + Vector2(0.0, 30.0)
		join.modulate.a = 0.0
		join.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var join_tween := create_tween()
		join_tween.tween_interval(0.3 * float(SaveRepository.SLOT_COUNT))
		join_tween.tween_property(join, "position", join_target, 0.6)
		join_tween.parallel().tween_property(join, "modulate:a", 1.0, 0.6)
		join_tween.tween_callback(func() -> void: join.mouse_filter = Control.MOUSE_FILTER_STOP)
	screen.set_meta("title_save_slots_visible", true)

## A button drawn with the save card art (nine-sliced), in the cards' ink.
func _title_card_button(parent: Control, text: String, at: Vector2, button_size: Vector2) -> Button:
	var button := Button.new()
	button.text = text
	button.position = at
	button.size = button_size
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_override("font", FONT)
	button.add_theme_font_size_override("font_size", 19)
	var ink := Color8(69, 71, 116)
	for state in ["font_color", "font_focus_color", "font_hover_color", "font_pressed_color"]:
		button.add_theme_color_override(state, ink)
	button.add_theme_color_override("font_hover_color", Color8(96, 98, 158))
	var art := load(SLOT_FILLED) as Texture2D
	for state in ["normal", "hover", "pressed", "focus"]:
		var skin := StyleBoxTexture.new()
		skin.texture = art
		skin.set_texture_margin_all(14.0)
		if state == "hover":
			skin.modulate_color = Color(1.08, 1.08, 1.12)
		elif state == "pressed":
			skin.modulate_color = Color(0.9, 0.9, 0.96)
		button.add_theme_stylebox_override(state, skin)
	parent.add_child(button)
	preload("res://src/presentation/source_menu_button_audio.gd").bind_button(button)
	return button

func _create_title_save_card(parent: Control, slot: int, is_used: bool, loaded: Dictionary, at: Vector2) -> Control:
	var card := Control.new()
	card.name = "SaveSlot%d" % slot
	card.position = at
	card.size = Vector2(250.0, 60.0)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(card)
	var art_symbol := "mainMenu_saveSlotFilled" if is_used else "mainMenu_saveSlotBackground"
	var background_button := SourceMenuArt.button(card, art_symbol, Vector2.ZERO, _on_save_slot_selected.bind(slot, is_used))
	if background_button != null:
		background_button.name = "SlotButton"
		background_button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not is_used:
		var new_slot := _label(card, "New Slot", Vector2(86.0, 21.0), Vector2(150.0, 30.0), 18, Color8(213, 215, 229))
		new_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		new_slot.add_theme_color_override("font_shadow_color", Color.TRANSPARENT)
		return card
	var state: Dictionary = loaded.get("state", {})
	var character: Dictionary = state.get("character", {})
	var title := _label(card, String(character.get("name", "Student")), Vector2(19.0, 8.0), Vector2(136.0, 28.0), 22, Color8(69, 71, 116))
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.add_theme_color_override("font_shadow_color", Color.TRANSPARENT)
	var party: Array = state.get("party", [])
	var storage: Array = state.get("storage", [])
	var minion_count := party.size() + storage.size()
	var minions := _label(card, "Minions: %d/101" % minion_count, Vector2(19.0, 36.0), Vector2(130.0, 22.0), 17, Color8(69, 71, 116))
	minions.mouse_filter = Control.MOUSE_FILTER_IGNORE
	minions.add_theme_color_override("font_shadow_color", Color.TRANSPARENT)
	var progression: Dictionary = state.get("progression", {})
	var seals := clampi(int(progression.get("sage_seals", 0)), 0, 6)
	var seal_symbols: Array[String] = ["titleScreen_plantSageStone", "titleScreen_fireSageStone", "titleScreen_electricSageStone", "titleScreen_undeadSageStone", "titleScreen_plantWizardSageStone", "titleScreen_undeadWizardSageStone"]
	for seal_index in range(seals):
		var seal := SourceMenuArt.image(card, seal_symbols[seal_index], Vector2(156.0 + 5.0 * seal_index, 10.0))
		if seal != null:
			seal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var star_icon := SourceMenuArt.image(card, "mainMenu_saveSlot_starIcon", Vector2(155.0, 33.0))
	if star_icon != null:
		star_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var star_total := 0
	for rating in progression.get("encounter_star_ratings", {}).values():
		star_total += clampi(int(rating), 0, 3)
	var stars := _label(card, str(star_total), Vector2(185.0, 33.0), Vector2(55.0, 24.0), 20, Color8(69, 71, 116))
	stars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stars.add_theme_color_override("font_shadow_color", Color.TRANSPARENT)
	var delete_button := SourceMenuArt.button(card, "mainMenu_saveSlot_deleteButton", Vector2(211.0, 9.0), _confirm_delete_save.bind(slot))
	if delete_button != null:
		delete_button.name = "DeleteSaveButton"
		delete_button.mouse_filter = Control.MOUSE_FILTER_IGNORE
		delete_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return card

func _activate_save_card_later(card: Control, delay: float) -> void:
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
	if is_instance_valid(card):
		var slot_button := card.get_node_or_null("SlotButton") as TextureButton
		if slot_button != null:
			slot_button.mouse_filter = Control.MOUSE_FILTER_STOP
		var delete_button := card.get_node_or_null("DeleteSaveButton") as TextureButton
		if delete_button != null:
			delete_button.mouse_filter = Control.MOUSE_FILTER_STOP

func _show_title_credits() -> void:
	if current_screen == null or current_screen.get_node_or_null("TitleCredits") != null:
		return
	var screen := current_screen
	for node_name in ["TitleCreditsButton", "TitleSponsorButton", "TitleToyChestButton", "TitleHostGamesButton", "TitleMusicToggle", "TitleSoundToggle"]:
		var item := screen.get_node_or_null(node_name) as Control
		if item != null:
			item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel := Control.new()
	panel.name = "TitleCredits"
	panel.position = Vector2(16.0, -34.0)
	panel.size = Vector2(700.0, 525.0)
	panel.modulate.a = 0.0
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	screen.add_child(panel)
	var credits_background := SourceMenuArt.image(panel, "mainMenu_credits_background", Vector2.ZERO)
	if credits_background != null:
		credits_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var return_button := SourceMenuArt.button(panel, "mainMenu_credits_returnButton", Vector2(281.0, 436.0), _close_title_credits)
	if return_button != null:
		return_button.name = "CreditsReturnButton"
	var enter := create_tween()
	enter.set_parallel(true)
	enter.tween_property(panel, "modulate:a", 1.0, 0.7)
	enter.tween_property(panel, "position:y", 16.0, 0.7)
	var credits := screen.get_node_or_null("TitleCreditsButton") as Control
	if credits != null:
		var move_credits := create_tween()
		move_credits.tween_property(credits, "position:y", 549.0, 0.5)
	for node_name in ["TitleHostGamesButton"]:
		var item := screen.get_node_or_null(node_name) as Control
		if item != null:
			var hide := create_tween()
			hide.set_parallel(true)
			hide.tween_property(item, "modulate:a", 0.0, 0.5)
			hide.tween_property(item, "position:y", item.position.y + 50.0, 0.5)
	if return_button != null:
		return_button.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_activate_title_return_later(return_button, 0.7)

func _activate_title_return_later(button: Control, delay: float) -> void:
	await get_tree().create_timer(delay).timeout
	if is_instance_valid(button):
		button.mouse_filter = Control.MOUSE_FILTER_STOP

func _close_title_credits() -> void:
	if current_screen == null:
		return
	var panel := current_screen.get_node_or_null("TitleCredits") as Control
	if panel != null:
		var exit := create_tween()
		exit.set_parallel(true)
		exit.tween_property(panel, "modulate:a", 0.0, 0.7)
		exit.tween_property(panel, "position:y", -34.0, 0.7)
		exit.finished.connect(panel.queue_free)
	var credits := current_screen.get_node_or_null("TitleCreditsButton") as Control
	if credits != null:
		var bring_credits := create_tween()
		bring_credits.tween_property(credits, "position:y", 469.0, 0.7)
	for node_name in ["TitleHostGamesButton"]:
		var item := current_screen.get_node_or_null(node_name) as Control
		if item != null:
			var restore := create_tween()
			restore.set_parallel(true)
			restore.tween_property(item, "modulate:a", 1.0, 0.5)
			restore.tween_property(item, "position:y", 491.0, 0.5)
	_restore_title_buttons_later(current_screen, 0.7)

func _restore_title_buttons_later(screen: Control, delay: float) -> void:
	await get_tree().create_timer(delay).timeout
	if not is_instance_valid(screen) or current_screen != screen:
		return
	for node_name in ["TitleCreditsButton", "TitleSponsorButton", "TitleToyChestButton", "TitleHostGamesButton", "TitleMusicToggle", "TitleSoundToggle"]:
		var item := screen.get_node_or_null(node_name) as Control
		if item != null:
			item.mouse_filter = Control.MOUSE_FILTER_STOP
	var slots := screen.get_node_or_null("TitleSaveSlots") as Control
	if slots != null:
		for card in slots.get_children():
			if card is Control:
				(card as Control).mouse_filter = Control.MOUSE_FILTER_STOP

func _open_title_link(url: String) -> void:
	var error := OS.shell_open(url)
	if error != OK:
		_show_notice("Could not open link: %s" % url)

func _toggle_title_music() -> void:
	_settings.set_music_enabled(not _settings.music_enabled)
	_refresh_title_toggle_art()

func _toggle_title_sound() -> void:
	_settings.set_sound_enabled(not _settings.sound_enabled)
	_refresh_title_toggle_art()

func _refresh_title_toggle_art() -> void:
	if current_screen == null:
		return
	var music := current_screen.get_node_or_null("TitleMusicToggle") as TextureButton
	if music != null:
		var music_art := SourceMenuArt.texture("menu_muteMusicButton_on" if _settings.music_enabled else "menu_muteMusicButton_off")
		music.texture_normal = music_art
		music.texture_hover = music_art
		music.texture_pressed = music_art
	var sound := current_screen.get_node_or_null("TitleSoundToggle") as TextureButton
	if sound != null:
		var sound_art := SourceMenuArt.texture("menu_muteSoundButton_on" if _settings.sound_enabled else "menu_muteSoundButton_off")
		sound.texture_normal = sound_art
		sound.texture_hover = sound_art
		sound.texture_pressed = sound_art

func _restore_title_after_creation(screen: Control) -> void:
	for node_name in ["TitleLogo", "TitleButtonBand", "TitleCreditsButton", "TitleSponsorButton", "TitleToyChestButton", "TitleHostGamesButton", "TitleMusicToggle", "TitleSoundToggle"]:
		var item := screen.get_node_or_null(node_name) as Control
		if item == null:
			continue
		item.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var restore := create_tween()
		restore.tween_property(item, "modulate:a", 1.0, 0.5)
		if node_name == "TitleHostGamesButton":
			restore.parallel().tween_property(item, "position:y", 491.0, 0.5)
	var band := screen.get_node_or_null("TitleButtonBand") as Control
	if band != null:
		var band_restore := create_tween()
		band_restore.tween_property(band, "scale:y", 1.0, 0.5)
	var slots := screen.get_node_or_null("TitleSaveSlots") as Control
	if slots != null:
		for card in slots.get_children():
			if card is Control:
				var slot_card := card as Control
				slot_card.modulate.a = 0.0
				var slot_button := slot_card.get_node_or_null("SlotButton") as TextureButton
				if slot_button != null:
					slot_button.mouse_filter = Control.MOUSE_FILTER_IGNORE
				var delete_button := slot_card.get_node_or_null("DeleteSaveButton") as TextureButton
				if delete_button != null:
					delete_button.mouse_filter = Control.MOUSE_FILTER_IGNORE
				var card_fade := create_tween()
				card_fade.tween_property(slot_card, "modulate:a", 1.0, 0.5)
				_activate_save_card_later(slot_card, 0.5)
	_restore_title_buttons_later(screen, 0.5)

func _confirm_delete_save(slot: int) -> void:
	_clear_dialog()
	interaction_dialog = Control.new()
	interaction_dialog.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	interaction_dialog.z_index = 1500
	var input_blocker := ColorRect.new()
	input_blocker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	input_blocker.color = Color(0.0, 0.0, 0.0, 0.0)
	input_blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	interaction_dialog.add_child(input_blocker)
	var slot_position := Vector2(230.0, 188.0 + float(slot - 1) * 67.0)
	var popup_position := slot_position + Vector2(70.0, -73.0)
	var background := _texture_rect("res://content/base/art/source_symbols/1076_Utilities.SpriteHandler_conformationBox_background.png")
	if background != null:
		background.position = popup_position
		interaction_dialog.add_child(background)
	var question := _label(interaction_dialog, "Delete your file?", popup_position + Vector2(7.0, 11.0), Vector2(200.0, 28.0), 16, Color8(249, 249, 249))
	question.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var yes := _texture_button(interaction_dialog, "res://content/base/art/source_symbols/388_Utilities.SpriteHandler_conformationBox_yesButton.png", popup_position + Vector2(5.0, 42.0))
	var no := _texture_button(interaction_dialog, "res://content/base/art/source_symbols/706_Utilities.SpriteHandler_conformationBox_noButton.png", popup_position + Vector2(105.0, 42.0))
	if yes != null:
		yes.pressed.connect(_delete_save_slot.bind(slot))
	else:
		_text_button(interaction_dialog, "Yes", popup_position + Vector2(5.0, 42.0), Vector2(90.0, 32.0)).pressed.connect(_delete_save_slot.bind(slot))
	if no != null:
		no.pressed.connect(_clear_dialog)
	else:
		_text_button(interaction_dialog, "No", popup_position + Vector2(105.0, 42.0), Vector2(90.0, 32.0)).pressed.connect(_clear_dialog)
	_attach_interaction_dialog()

func _delete_save_slot(slot: int) -> void:
	var result: Dictionary = runtime.delete_campaign_save(slot) if runtime != null else {"ok": false, "message": "Campaign runtime is unavailable"}
	if not result.get("ok", false):
		_show_notice("Could not delete slot %d: %s" % [slot, result.get("message", "unknown save error")])
		return
	_show_save_slots()

func _on_save_slot_selected(slot: int, is_used: bool) -> void:
	if _room_transition_active:
		return
	selected_slot = slot
	if is_used:
		var result: Dictionary = runtime.load_campaign(slot) if runtime != null else {"ok": false, "message": "Campaign runtime is unavailable"}
		if not result.get("ok", false):
			_show_notice("Unable to load slot %d: %s" % [slot, result.get("message", "unknown save error")])
			return
		_enter_loaded_save_with_transition()
		return
	_show_character_creation()

func _enter_loaded_save_with_transition() -> void:
	_room_transition_active = true
	_campaign_audio.fade_music_to(0.0, 0.8)
	var curtain := _ensure_room_transition_curtain()
	curtain.visible = true
	curtain.color = Color(0.0, 0.0, 0.0, 0.0)
	var fade_out := create_tween()
	fade_out.tween_property(curtain, "color", Color.BLACK, 0.8)
	await fade_out.finished
	_show_room_from_state()
	if is_instance_valid(current_room):
		current_room.set_controls_enabled(false)
	await get_tree().create_timer(0.2).timeout
	var fade_in := create_tween()
	fade_in.tween_property(curtain, "color", Color(0.0, 0.0, 0.0, 0.0), 0.5)
	await fade_in.finished
	if is_instance_valid(curtain):
		curtain.visible = false
	if is_instance_valid(current_room):
		current_room.set_controls_enabled(true)
	_room_transition_active = false

func _show_character_creation() -> void:
	var screen: Control
	var has_title_backdrop := current_screen != null and current_screen.get_node_or_null("TitleBackdrop") != null
	if has_title_backdrop:
		screen = Control.new()
		screen.name = "CharacterCreationLayer"
		screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		screen.mouse_filter = Control.MOUSE_FILTER_STOP
		screen.modulate.a = 0.0
		current_screen.add_child(screen)
		_animate_title_for_creation(current_screen)
	else:
		screen = _new_menu_screen()
		_add_title_background(screen)
		screen.modulate.a = 0.0
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.0, 0.0, 0.0, 0.3)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(shade)
	var creation_background := _texture_rect(CHARACTER_BACKGROUND)
	if creation_background != null:
		creation_background.position = Vector2(100.0, 130.0)
		screen.add_child(creation_background)
	var panel_origin := Vector2(100.0, 130.0)
	# The selection art is an outline behind the character icon, not an overlay.
	# Adding it after the icon painted over the blue male artwork with white.
	var gender_marker := _texture_rect(CHARACTER_GENDER_SELECTED)
	if gender_marker != null:
		gender_marker.name = "SelectedGenderMarker"
		gender_marker.position = panel_origin + Vector2(143.0, 128.0)
		screen.add_child(gender_marker)
	var male := _texture_button(screen, CHARACTER_MALE_ICON, panel_origin + Vector2(143.0, 128.0))
	var female := _texture_button(screen, CHARACTER_FEMALE_ICON, panel_origin + Vector2(188.0, 128.0))
	if male != null:
		male.pressed.connect(_set_gender.bind("male"))
	if female != null:
		female.pressed.connect(_set_gender.bind("female"))
	var preview := _texture_rect(CHARACTER_MALE_PREVIEW)
	if preview != null:
		preview.name = "CharacterPreview"
		preview.position = panel_origin + Vector2(306.0, 29.0)
		screen.add_child(preview)
	var name_box := LineEdit.new()
	name_box.position = panel_origin + Vector2(145.0, 81.0)
	name_box.size = Vector2(150.0, 37.0)
	name_box.max_length = 10
	name_box.text = "Ryder"
	name_box.add_theme_font_override("font", FONT)
	name_box.add_theme_font_size_override("font_size", 26)
	name_box.add_theme_color_override("font_color", Color8(16, 16, 24))
	name_box.add_theme_stylebox_override("normal", _line_edit_style())
	name_box.add_theme_stylebox_override("focus", _line_edit_style())
	name_box.text_changed.connect(_sanitize_character_name)
	name_entry = name_box
	screen.add_child(name_box)
	name_box.grab_focus()
	name_box.caret_column = name_box.text.length()
	var ok := _texture_button(screen, CHARACTER_OK_BUTTON, panel_origin + Vector2(118.0, 179.0))
	if ok != null:
		ok.pressed.connect(_create_campaign)
	else:
		_text_button(screen, "OK", panel_origin + Vector2(118.0, 179.0), Vector2(100.0, 44.0)).pressed.connect(_create_campaign)
	var close := _texture_button(screen, CHARACTER_CLOSE_BUTTON, panel_origin + Vector2(450.0, 13.0))
	if close != null:
		close.pressed.connect(_show_save_slots)
	selected_gender = "male"
	var entrance := create_tween()
	entrance.tween_interval(0.5)
	entrance.tween_property(screen, "modulate:a", 1.0, 0.9)

func _animate_title_for_creation(screen: Control) -> void:
	for node_name in ["TitleLogo", "TitlePlayButton", "TitleCreditsButton", "TitleSponsorButton", "TitleToyChestButton", "TitleHostGamesButton", "TitleMusicToggle", "TitleSoundToggle"]:
		var item := screen.get_node_or_null(node_name) as Control
		if item == null:
			continue
		item.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var fade := create_tween()
		fade.tween_property(item, "modulate:a", 0.0, 0.5)
		if node_name == "TitleHostGamesButton":
			fade.parallel().tween_property(item, "position:y", 541.0, 0.5)
	var band := screen.get_node_or_null("TitleButtonBand") as Control
	if band != null:
		var expand := create_tween()
		expand.tween_property(band, "scale:y", 1.4, 1.2)
	var slots := screen.get_node_or_null("TitleSaveSlots") as Control
	if slots != null:
		for card in slots.get_children():
			if card is Control:
				(card as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
				var fade_card := create_tween()
				fade_card.tween_property(card, "modulate:a", 0.0, 0.5)

func _set_gender(gender: String) -> void:
	if name_entry != null:
		if selected_gender == "male" and name_entry.text == "Ryder":
			name_entry.text = "Vala" if gender == "female" else "Ryder"
		elif selected_gender == "female" and name_entry.text == "Vala":
			name_entry.text = "Ryder" if gender == "male" else "Vala"
	selected_gender = gender
	if current_screen == null:
		return
	var preview := current_screen.find_child("CharacterPreview", true, false) as TextureRect
	var marker := current_screen.find_child("SelectedGenderMarker", true, false) as TextureRect
	if preview == null:
		for child in current_screen.get_children():
			if child is TextureRect and child.position == Vector2(406.0, 159.0):
				preview = child
				break
	if preview != null:
		preview.texture = _load_texture(CHARACTER_FEMALE_PREVIEW if gender == "female" else CHARACTER_MALE_PREVIEW)
	if marker != null:
		marker.position = Vector2(288.0 if gender == "female" else 243.0, 258.0)

func _sanitize_character_name(value: String) -> void:
	if name_entry == null or value.is_empty():
		return
	var allowed := RegEx.new()
	allowed.compile("[^A-Za-z0-9 ]")
	var sanitized := allowed.sub(value, "", true)
	if sanitized == value:
		return
	var old_caret := name_entry.caret_column
	name_entry.text = sanitized
	name_entry.caret_column = mini(old_caret, sanitized.length())

func _create_campaign() -> void:
	if _room_transition_active:
		return
	if runtime == null:
		_show_notice("Campaign runtime is unavailable")
		return
	if runtime.has_save(selected_slot):
		_show_notice("Slot %d already contains a campaign. Choose an empty slot." % selected_slot)
		return
	var character_name := name_entry.text.strip_edges() if name_entry != null else ""
	var result: Dictionary = runtime.start_new_campaign(selected_slot, character_name, StringName(selected_gender))
	if not result.get("ok", false):
		_show_notice("Could not start campaign: %s" % result.get("message", "unknown save error"))
		return
	_start_new_campaign_intro()

func _start_new_campaign_intro() -> void:
	_room_transition_active = true
	var intro := NEW_CAMPAIGN_INTRO.new()
	intro.name = "NewCampaignIntro"
	var backdrop := current_screen.get_node_or_null("TitleBackdrop") as Control
	var background_y := -448.0
	if backdrop != null:
		var stone := backdrop.get_node_or_null("TitleStoneBackground") as Control
		if stone != null:
			background_y = stone.position.y
	current_screen.add_child(intro)
	current_screen.move_child(intro, 0)
	intro.start(_campaign_audio, background_y)
	# Keep the creation panel above the cinematic while it fades away. The
	# intro then owns input, preventing double OK/slot selection during playback.
	for child in current_screen.get_children():
		if child == intro or not child is Control:
			continue
		_disable_title_subtree(child)
		var fade: Tween = child.create_tween()
		fade.tween_property(child, "modulate:a", 0.0, 0.5)
		fade.tween_callback(child.hide)
	intro.completed.connect(_finish_new_campaign_intro, CONNECT_ONE_SHOT)

func _disable_title_subtree(node: Node) -> void:
	if node is Control:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	if node is BaseButton:
		(node as BaseButton).disabled = true
	for child in node.get_children():
		_disable_title_subtree(child)

func _finish_new_campaign_intro() -> void:
	await _fade_campaign_screen_out()
	# start_new_campaign has already committed the save and starter party.
	# Finishing/skipping the intro must never grant them a second time.
	_show_room_from_state()
	await _finish_campaign_screen_transition()

func _show_room_from_state(spawn_id: StringName = &"", spawn_position: Vector2 = Vector2.INF, restore_facing: StringName = &"") -> void:
	if runtime == null or runtime.session == null or runtime.session.state == null:
		_show_title_screen()
		return
	var state = runtime.session.state
	_multiplayer.place_guest_with_host()
	if bool(state.progression.get("in_tower_lobby", false)) and state.current_room_id != &"base:room/main_tower_lobby":
		_show_tower_lobby_screen()
		return
	var room := runtime.catalog.get_definition(state.current_room_id) as RoomDefinition
	if room == null:
		_show_notice("Saved room %s is missing from the loaded content." % state.current_room_id)
		return
	var location: Dictionary = state.room_state.get("current_location", {})
	if StringName(location.get("room_id", "")) != room.id:
		location = state.safe_location if StringName(state.safe_location.get("room_id", "")) == room.id else {}
	if spawn_id.is_empty():
		spawn_id = StringName(location.get("spawn_id", room.spawn_ids[0] if not room.spawn_ids.is_empty() else "start"))
		if spawn_id not in room.spawn_ids and not room.spawn_ids.is_empty():
			spawn_id = room.spawn_ids[0]
	if spawn_position == Vector2.INF:
		spawn_position = _as_vector2(location.get("position", room.spawn_positions.get(String(spawn_id), Vector2.ZERO)), room.spawn_positions.get(String(spawn_id), Vector2.ZERO))
		if restore_facing.is_empty():
			restore_facing = StringName(location.get("facing", ""))
	if current_room == null:
		_clear_game_screen()
		current_room = ROOM_SCENE.instantiate()
		screen_host.add_child(current_room)
		current_room.transition_requested.connect(_on_room_transition_requested)
		current_room.interaction_requested.connect(_on_room_interaction_requested)
	current_battle = null
	current_screen = null
	room_hud.visible = true
	room_status.text = ""
	map_button.visible = false
	party_button.visible = false
	var room_context := {
		"restore_facing": String(restore_facing),
		"progression": state.progression.duplicate(true),
		"room_state": state.room_state.get(String(room.id), {}).duplicate(true),
		"tower_mode": String(CampaignTowerModeService.mode_for_global_floor(int(state.progression.get("floor_index", 0)))),
		"lobby_titan_owned": bool(runtime.session.lobby_titan_status().get("has_titan_1", false)),
	}
	if not current_room.configure(room, spawn_id, spawn_position, state.character, room_context):
		_show_notice("Room %s could not be created." % room.id)
	var room_music = preload("res://src/presentation/source_room_music.gd")
	_previous_region_music = String(state.progression.get("previous_region_music", ""))
	if _previous_region_music.is_empty():
		_previous_region_music = room_music.regional_for_floor(runtime.catalog, runtime.session.campaign, int(state.progression.get("floor_index", 0)))
	var music_profile: Dictionary = room_music.profile(room, _previous_region_music, room.id == &"base:room/level_1_1_entryhallway" and int(state.progression.get("floor_index", 0)) == 0)
	_previous_region_music = String(music_profile.region)
	# Retained by the next normal campaign save, like source m_prevBackgroundMusic.
	state.progression["previous_region_music"] = _previous_region_music
	if not String(music_profile.track).is_empty():
		_campaign_audio.play_music(String(music_profile.track), float(music_profile.volume), float(music_profile.fade_seconds))
	_refresh_source_hud()
	_schedule_context_room_tutorial(current_room, room.id)

func _schedule_context_room_tutorial(return_room: Node, room_id: StringName) -> void:
	var room := runtime.catalog.get_definition(room_id) as RoomDefinition
	var tutorial_id := CampaignProgressionService.room_tutorial_id(runtime.session.state, room)
	if tutorial_id.is_empty():
		return
	await get_tree().create_timer(0.9 if tutorial_id == "key_keepers" else 1.5).timeout
	while is_instance_valid(return_room) and current_room == return_room and return_room.room.id == room_id and (is_instance_valid(interaction_dialog) or _room_transition_active):
		await get_tree().create_timer(0.25).timeout
	if not is_instance_valid(return_room) or current_room != return_room or return_room.room.id != room_id or runtime.session.state == null:
		return
	if CampaignProgressionService.room_tutorial_id(runtime.session.state, room) != tutorial_id:
		return
	var tutorial := preload("res://src/presentation/source_campaign_tutorial_view.gd").new()
	interaction_dialog = tutorial
	_attach_interaction_dialog()
	tutorial.configure(runtime.session, tutorial_id, _campaign_audio)
	tutorial.completed.connect(func() -> void:
		if interaction_dialog == tutorial:
			_clear_dialog()
	)

func _process(_delta: float) -> void:
	if runtime != null and runtime.session != null and runtime.session.state != null and is_instance_valid(current_room) and current_room.room != null and current_room.room.id == runtime.session.state.current_room_id:
		runtime.session.update_exploration_position(current_room.player_position(), StringName(current_room.get_meta("spawn_id", "")), current_room.player_facing())
	if is_instance_valid(_reward_presenter) and _reward_presenter.visible:
		_reward_presenter.position = get_viewport().get_canvas_transform().origin - _reward_canvas_origin
	if room_hud != null and room_hud.visible and runtime != null and runtime.session != null and runtime.session.state != null:
		if _hud_keys != null:
			var progression: Dictionary = runtime.session.state.progression
			var floor_keys := int(progression.get("floor_keys", 0))
			var eggery_keys := int(progression.get("eggery_keys", 0))
			_hud_keys.text = "x%d" % (floor_keys + eggery_keys if eggery_keys > 0 else floor_keys)
		if _hud_stars != null:
			var state: CampaignState = runtime.session.state
			var floor_index := int(state.progression.get("floor_index", 0))
			var ratings: Dictionary = state.progression.get("encounter_star_ratings", {})
			var signature := Vector2i(floor_index, hash(ratings))
			if signature != _hud_star_signature:
				_hud_star_signature = signature
				_hud_stars.text = "x%d" % CampaignTowerModeService.floor_star_count(state, runtime.catalog, runtime.session.campaign, CampaignTowerModeService.source_floor_index(floor_index), CampaignTowerModeService.mode_for_global_floor(floor_index))
		if is_instance_valid(_hud_progress):
			var state: CampaignState = runtime.session.state
			var has_talents := false
			for owned in state.party:
				var definition := runtime.catalog.get_definition(owned.definition_id) as MinionDefinition
				has_talents = has_talents or CampaignProgressionService.available_talent_points(owned, definition) > 0
			var movement_enabled: bool = _settings.tips_enabled and is_instance_valid(current_room) and current_room._controls_enabled and interaction_dialog == null and not _room_transition_active
			_hud_progress.sync(state.progression, has_talents, not state.owned_gems.is_empty() and not bool(state.progression.get("gem_tutorial_seen", false)), _hud_progress.has_affordable_star_upgrade(state), movement_enabled)

func _refresh_source_hud() -> void:
	if room_hud == null or _settings == null:
		return
	if _hud_music_toggle != null:
		_hud_music_toggle.texture_normal = SourceMenuArt.texture("menu_muteMusicButton_on" if _settings.music_enabled else "menu_muteMusicButton_off")
	if _hud_sound_toggle != null:
		_hud_sound_toggle.texture_normal = SourceMenuArt.texture("menu_muteSoundButton_on" if _settings.sound_enabled else "menu_muteSoundButton_off")
	if runtime == null or runtime.session == null or runtime.session.state == null or runtime.session.campaign == null:
		_remove_source_hud_map()
		return
	if runtime.session.state.current_room_id == &"base:room/main_tower_lobby" or bool(runtime.session.state.progression.get("in_tower_lobby", false)):
		_remove_source_hud_map()
		return # Source lobby has no floor minimap, even if the last floor unlocked one.
	if bool(runtime.session.state.progression.get("map_unlocked", false)):
		if not is_instance_valid(_hud_map):
			_hud_map = CampaignMinimapView.new()
			room_hud.add_child(_hud_map)
			_hud_map.open_requested.connect(_show_floor_map)
		_hud_map.configure(runtime.catalog, runtime.session.state, runtime.session.campaign, true)
		_hud_map.position = Vector2(9, 404)
	else:
		_remove_source_hud_map()

func _remove_source_hud_map() -> void:
	if is_instance_valid(_hud_map):
		_hud_map.get_parent().remove_child(_hud_map)
		_hud_map.queue_free()
	_hud_map = null

func _on_room_transition_requested(exit_data: Dictionary) -> void:
	if runtime == null or runtime.session == null:
		return
	if _room_transition_active:
		return
	if not _multiplayer.allow_room_transition(exit_data):
		return
	_room_transition_active = true
	if current_room != null and is_instance_valid(current_room):
		current_room.set_controls_enabled(false)
	var curtain := _ensure_room_transition_curtain()
	curtain.visible = true
	curtain.color = Color(0.0, 0.0, 0.0, 0.0)
	var fade_out := create_tween()
	fade_out.tween_property(curtain, "color", Color.BLACK, 0.5)
	await fade_out.finished
	_complete_room_transition(exit_data)
	if bool(exit_data.get("source_teleport", false)) and _campaign_audio != null:
		_campaign_audio.play_sound("tower_teleport", 1.0)
	# The destination room is instantiated while the curtain is fully opaque.
	# Keep its movement and trigger areas locked until the fade has cleared so a
	# spawn overlapping a portal cannot start a second transition underneath it.
	if current_room != null and is_instance_valid(current_room):
		current_room.set_controls_enabled(false)
	await get_tree().create_timer(0.1).timeout
	var fade_in := create_tween()
	fade_in.tween_property(curtain, "color", Color(0.0, 0.0, 0.0, 0.0), 0.5)
	await fade_in.finished
	if is_instance_valid(curtain):
		curtain.visible = false
	if current_room != null and is_instance_valid(current_room):
		current_room.set_controls_enabled(true)
	_room_transition_active = false

func _ensure_room_transition_curtain() -> ColorRect:
	if room_transition_curtain != null and is_instance_valid(room_transition_curtain):
		return room_transition_curtain
	room_transition_canvas = CanvasLayer.new()
	room_transition_canvas.name = "RoomTransitionCanvas"
	room_transition_canvas.layer = 20
	add_child(room_transition_canvas)
	room_transition_curtain = ColorRect.new()
	room_transition_curtain.name = "RoomTransitionCurtain"
	room_transition_curtain.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	room_transition_curtain.color = Color(0.0, 0.0, 0.0, 0.0)
	room_transition_curtain.mouse_filter = Control.MOUSE_FILTER_STOP
	room_transition_curtain.visible = false
	room_transition_canvas.add_child(room_transition_curtain)
	return room_transition_curtain

func _complete_room_transition(exit_data: Dictionary) -> void:
	if String(exit_data.get("target_route", "")) == "lobby":
		var lobby_result: Dictionary = runtime.enter_tower_lobby(current_room != null and String(current_room.room.id).contains("eggery"))
		if not lobby_result.get("ok", false):
			room_status.text = "Lobby unavailable: %s" % lobby_result.get("message", "unknown error")
			return
		_show_room_from_state()
		return
	var result: Dictionary = runtime.session.enter_room(
		StringName(exit_data.get("target_room_id", "")),
		int(exit_data.get("transition_id", -1)),
	)
	if not result.get("ok", false):
		room_status.text = "Transition unavailable: %s" % result.get("message", "unknown error")
		return
	_show_room_from_state(StringName(result.get("spawn_id", "")), _as_vector2(result.get("position", Vector2.ZERO), Vector2.ZERO))

func _on_room_interaction_requested(interaction: Dictionary) -> void:
	if _room_transition_active or runtime == null or runtime.session == null or current_room == null:
		return
	var interaction_kind := StringName(interaction.get("kind", ""))
	if interaction_kind == &"pvp_arena":
		_multiplayer.show_arena_picker()
		return
	if not _multiplayer.allow_interaction(interaction_kind):
		return
	if interaction_kind == &"eggery_exit_blocked":
		_show_player_dialogue("You still need to choose an egg!")
		return
	if interaction_kind == &"floor_picker":
		_show_floor_picker()
		return
	if interaction_kind in [&"gem_shop", &"gem_combiner", &"minion_storage", &"titan_guard", &"titan_reward"]:
		var message := String(interaction.get("text", interaction.get("locked_text", "")))
		var after := Callable()
		if interaction_kind == &"gem_shop":
			after = _show_gem_merchant.bind(&"shop")
		elif interaction_kind == &"gem_combiner":
			if int(runtime.session.state.progression.get("sage_seals", 0)) > 1:
				after = _show_gem_merchant.bind(&"combine")
			else:
				message = String(interaction.get("locked_text", ""))
		elif interaction_kind == &"minion_storage":
			# Shared storage may hold other players' minions: always open in multiplayer.
			if runtime.session.state.party.size() + runtime.session.state.storage.size() > 5 or net.is_active():
				after = _show_storage_manager
			else:
				message = String(interaction.get("locked_text", ""))
		elif interaction_kind in [&"titan_guard", &"titan_reward"]:
			var status: Dictionary = runtime.session.lobby_titan_status()
			if interaction_kind == &"titan_guard":
				message = String(status.get("guard_message", interaction.get("locked_text", "")))
			else:
				message = String(status.get("message", ""))
				if status.get("can_claim_titans", false):
					after = _claim_lobby_titan
		_show_source_dialogue(interaction, String(interaction.get("speaker", "")), message, after)
		return
	if interaction_kind in [&"claim_room_chest", &"claim_room_gem_chest"]:
		var chest_result: Dictionary = runtime.session.claim_room_gem_chest(interaction) if interaction_kind == &"claim_room_gem_chest" else runtime.session.claim_room_chest(interaction)
		if not chest_result.get("ok", false):
			room_status.text = "Can't open chest: %s" % chest_result.get("message", "unknown error")
			return
		if StringName(chest_result.get("kind", "")) == &"chest_already_claimed":
			_refresh_current_room()
			return
		var chest_kind := String(interaction.get("chest_kind", chest_result.get("chest_kind", "gold")))
		room_status.text = String(chest_result.get("message", "")) if chest_kind == "gem" else "You found %d coins." % int(chest_result.get("currency", 0))
		# Source chests fade away while the pickup animation plays; claiming one
		# does not freeze the player or rebuild the room.
		current_room.animate_source_chest_open(int(interaction.get("source_object_index", -1)), chest_kind)
		return
	var interaction_id := StringName(interaction.get("id", ""))
	var checkpoint_position: Variant = current_room.player_position()
	var checkpoint_spawn_id := StringName(current_room.get_meta("spawn_id", ""))
	var result: Dictionary = runtime.session.interact(interaction_id, checkpoint_position, checkpoint_spawn_id)
	if not result.get("ok", false):
		room_status.text = "Can't interact: %s" % result.get("message", "unknown error")
		return
	if StringName(result.get("kind", "")) == &"trainer":
		_show_trainer_dialog(interaction, StringName(result.get("encounter_id", "")), String(result.get("dialog_text", "")), String(result.get("trainer_name", "Trainer")))
	elif StringName(result.get("kind", "")) == &"heal_party":
		room_status.text = ""
		current_room.play_source_healstone(interaction_id)
		_refresh_source_hud()
	elif StringName(result.get("kind", "")) == &"door_locked":
		_show_player_dialogue(String(result.get("message", "")))
	elif StringName(result.get("kind", "")) in [&"map_granted", &"map_hint", &"grand_sage"]:
		if StringName(result.get("kind", "")) != &"grand_sage":
			_campaign_audio.fade_music_to(0.5, 0.5)
		if StringName(result.get("kind", "")) == &"grand_sage":
			_active_sage_interaction = interaction.duplicate(true)
			var sage_message := String(result.get("message", ""))
			var sage_name := String(interaction.get("trainer_name", "Grand Sage"))
			if bool(result.get("first_visit", false)):
				_show_grand_sage_dialog(interaction, sage_message)
			else:
				_show_source_dialogue(interaction, sage_name, sage_message)
		else:
			_show_source_dialogue(interaction, String(interaction.get("trainer_name", "Qui-tel Trainer")), String(result.get("message", "")), Callable(self, "_finish_source_map_dialogue").bind(StringName(result.get("kind", "")) == &"map_granted"))
	elif StringName(result.get("kind", "")) == &"door_unlocked":
		room_status.text = ""
		current_room.update_campaign_progression(runtime.session.state.progression)
		current_room.animate_source_door_unlock(StringName(result.get("door", "boss")))
		_refresh_source_hud()
	elif StringName(result.get("kind", "")) == &"egg_pick":
		var egg_slot := int(interaction.get("source_zone_id", -1))
		_show_egg_reveal(result, egg_slot)
	elif StringName(result.get("kind", "")) == &"door_already_open":
		room_status.text = ""

func _finish_source_map_dialogue(newly_granted: bool) -> void:
	if not is_instance_valid(current_room) or runtime.session.state == null:
		return
	current_room.update_campaign_progression(runtime.session.state.progression)
	_refresh_source_hud()
	if newly_granted:
		_campaign_audio.play_sound("tower_gettingMap", 1.0)
	_campaign_audio.fade_music_to(1.0, 0.5)

func _show_player_dialogue(message: String, on_complete: Callable = Callable()) -> void:
	var actor_screen: Vector2 = current_room.player_screen_position() if is_instance_valid(current_room) else Vector2(226, 334)
	var bubble_position := actor_screen + Vector2(45, -30)
	var bubble_texture := _load_texture(SPEECH_BUBBLE)
	if bubble_texture != null and bubble_position.x + bubble_texture.get_width() > 700:
		bubble_position.x = actor_screen.x - 225
	_show_source_dialogue({"dialogue_layout": {"position": bubble_position, "scale": Vector2.ONE}}, "Inner Monologue", message, on_complete)

func _refresh_current_room() -> void:
	if current_room == null or runtime == null or runtime.session == null or runtime.session.state == null:
		return
	var restore_spawn := StringName(current_room.get_meta("spawn_id", "start"))
	var restore_position: Vector2 = current_room.player_position()
	_show_room_from_state(restore_spawn, restore_position)

func _show_trainer_dialog(interaction: Dictionary, encounter_id: StringName, dialog_text: String = "", trainer_name: String = "Trainer") -> void:
	_campaign_audio.fade_music_to(0.5, 0.5)
	var message := dialog_text if not dialog_text.is_empty() else String(interaction.get("first_visit_text", "A trainer challenges you."))
	var player_position: Vector2 = current_room.player_position() if current_room != null else Vector2.ZERO
	var begin_battle := Callable(self, "_begin_trainer_battle").bind(encounter_id, player_position)
	var completed: Dictionary = runtime.session.state.progression.get("completed_encounters", {})
	var resolved := CampaignTowerModeService.resolve_encounter(runtime.catalog, runtime.catalog.get_definition(encounter_id) as EncounterDefinition, int(runtime.session.state.progression.get("floor_index", 0)))
	var actual_encounter_id: StringName = resolved.encounter.id if bool(resolved.get("ok", false)) else encounter_id
	var layout := interaction.duplicate(true)
	if bool(completed.get(String(actual_encounter_id), false)):
		# Source rematches are optional; advancing the text must not start combat.
		layout["on_yes"] = begin_battle
		layout["on_no"] = func() -> void:
			_clear_dialog()
			_campaign_audio.fade_music_to(1.0, 0.5)
		_show_source_dialogue(layout, trainer_name, message)
		var stars := int(runtime.session.state.progression.get("encounter_star_ratings", {}).get(String(actual_encounter_id), 0))
		if stars > 0 and is_instance_valid(interaction_dialog):
			var rating := _label(interaction_dialog, "Stars: %d/3" % stars, _source_dialogue_bubble_position + Vector2(10, 66) * _source_dialogue_scale, Vector2(228, 16) * _source_dialogue_scale, maxi(1, roundi(10 * _source_dialogue_scale.y)), Color.hex(0xf1e34aff))
			rating.name = "TrainerStars"
			rating.mouse_filter = Control.MOUSE_FILTER_IGNORE
	else:
		_show_source_dialogue(layout, trainer_name, message, begin_battle)

func _show_grand_sage_dialog(interaction: Dictionary, message: String) -> void:
	_show_source_dialogue(interaction, String(interaction.get("trainer_name", "Grand Sage")), message, Callable(self, "_show_grand_sage_bonus_picker"))

func _show_source_dialogue(interaction: Dictionary, speaker: String, message: String, on_complete: Callable = Callable()) -> void:
	_clear_dialog()
	interaction_dialog = Control.new()
	interaction_dialog.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	interaction_dialog.z_index = 1500
	var advance_catcher := Button.new()
	advance_catcher.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	advance_catcher.focus_mode = Control.FOCUS_NONE
	advance_catcher.flat = true
	advance_catcher.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	advance_catcher.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	advance_catcher.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	advance_catcher.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	advance_catcher.pressed.connect(_advance_source_dialogue)
	interaction_dialog.add_child(advance_catcher)
	var layout: Dictionary = interaction.get("dialogue_layout", current_room.dialogue_layout_for_zone(int(interaction.get("source_zone_id", 0))) if current_room != null else {"position": Vector2(226.0, 420.0), "scale": Vector2.ONE})
	var bubble_scale := _as_vector2(layout.get("scale", Vector2.ONE), Vector2.ONE).abs()
	var bubble_texture := _load_texture(SPEECH_BUBBLE)
	if bubble_texture == null:
		_clear_dialog()
		_show_notice(message)
		return
	var bubble_size := bubble_texture.get_size() * bubble_scale
	var bubble_position := _as_vector2(layout.get("position", Vector2(226.0, 420.0)), Vector2(226.0, 420.0))
	var viewport_size := get_viewport_rect().size
	bubble_position.x = clampf(bubble_position.x, 8.0, maxf(8.0, viewport_size.x - bubble_size.x - 8.0))
	bubble_position.y = clampf(bubble_position.y, 8.0, maxf(8.0, viewport_size.y - bubble_size.y - 8.0))
	_source_dialogue_bubble_position = bubble_position
	_source_dialogue_yes = interaction.get("on_yes", Callable())
	_source_dialogue_no = interaction.get("on_no", Callable())
	var bubble := TextureRect.new()
	bubble.texture = bubble_texture
	bubble.position = bubble_position
	bubble.size = bubble_size
	bubble.stretch_mode = TextureRect.STRETCH_SCALE
	bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	interaction_dialog.add_child(bubble)
	var scaled_font_size := maxi(12, roundi(float(SPEECH_FONT_SIZE) * minf(bubble_scale.x, bubble_scale.y)))
	var speaker_label := _label(interaction_dialog, speaker, bubble_position + Vector2(-55.0, 4.0) * bubble_scale, Vector2(SPEECH_TEXT_WIDTH, 18.0) * bubble_scale, 11 * maxi(1, roundi(minf(bubble_scale.x, bubble_scale.y))), Color.hex(0x819bc1ff))
	speaker_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	speaker_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	speaker_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_source_dialogue_scale = bubble_scale
	# Hold input until the wrapped layout has been measured in-tree. The clip
	# window still displays the first lines immediately while the text control
	# retains ample height, so no content is truncated during layout.
	_source_dialogue_is_animating = true
	_source_dialogue_on_complete = on_complete
	_source_dialogue_scroller = Control.new()
	_source_dialogue_scroller.position = bubble_position + Vector2(10.0, 27.0) * bubble_scale
	_source_dialogue_scroller.size = Vector2(SPEECH_TEXT_WIDTH, SPEECH_TEXT_VIEW_HEIGHT) * bubble_scale
	_source_dialogue_scroller.clip_contents = true
	_source_dialogue_scroller.mouse_filter = Control.MOUSE_FILTER_IGNORE
	interaction_dialog.add_child(_source_dialogue_scroller)
	# Flash TextField's internal baseline padding is not Label padding. Start
	# Godot's first complete line at the mask origin, not at Flash's -7 offset.
	# Limit settled frames to two lines so no third-line fragments leak below.
	_source_dialogue_line_index = 0
	_source_dialogue_line_count = 0
	_source_dialogue_label = _label(_source_dialogue_scroller, message, Vector2.ZERO, Vector2(SPEECH_TEXT_WIDTH * bubble_scale.x, 4096.0), scaled_font_size, Color.hex(0xd6e0f0ff))
	_source_dialogue_label.custom_maximum_size = Vector2(SPEECH_TEXT_WIDTH * bubble_scale.x, 4096.0)
	_source_dialogue_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_source_dialogue_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_source_dialogue_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_source_dialogue_label.add_theme_constant_override("line_spacing", roundi(-2.0 * bubble_scale.y))
	_source_dialogue_label.max_lines_visible = 2
	var arrow := _texture_rect(SPEECH_BUBBLE_ARROW)
	if arrow != null:
		arrow.position = bubble_position + Vector2(230.0, 71.0) * bubble_scale
		arrow.scale = bubble_scale
		_source_dialogue_arrow = arrow
		interaction_dialog.add_child(arrow)
	else:
		_source_dialogue_arrow = null
	_update_source_dialogue_arrow()
	_attach_interaction_dialog()
	_measure_source_dialogue_after_layout(scaled_font_size)

func _advance_source_dialogue() -> void:
	if _source_dialogue_label == null or _source_dialogue_is_animating:
		return
	_source_dialogue_is_animating = true
	if _source_dialogue_can_scroll():
		_source_dialogue_label.max_lines_visible = 3
		var next_y := _source_dialogue_label.position.y - _source_dialogue_scroll_step
		var scroll_tween := create_tween()
		scroll_tween.tween_property(_source_dialogue_label, "position:y", next_y, 0.25)
		scroll_tween.tween_interval(0.1)
		scroll_tween.tween_callback(_finish_source_dialogue_scroll)
		return
	if _source_dialogue_yes.is_valid() or _source_dialogue_no.is_valid():
		_source_dialogue_is_animating = false
		_update_source_dialogue_arrow()
		return
	var finished := _source_dialogue_on_complete
	var dialogue_to_close := interaction_dialog
	var close_tween := create_tween()
	close_tween.tween_property(dialogue_to_close, "modulate:a", 0.0, 0.2)
	close_tween.tween_callback(_finish_source_dialogue_close.bind(dialogue_to_close, finished))

func _source_dialogue_can_scroll() -> bool:
	if _source_dialogue_label == null or _source_dialogue_scroller == null or _source_dialogue_content_height <= 0.0:
		return false
	# Advance exactly one wrapped line until the final two-line window. Pixel
	# bottom thresholds cannot reliably express this across Flash/Godot metrics.
	return _source_dialogue_line_index + 2 < _source_dialogue_line_count

func _measure_source_dialogue_after_layout(font_size: int) -> void:
	await get_tree().process_frame
	if _source_dialogue_label == null or not is_instance_valid(_source_dialogue_label):
		return
	var line_count := maxi(1, _source_dialogue_label.get_line_count())
	_source_dialogue_line_count = line_count
	var rendered_line_height := FONT.get_height(font_size) + float(_source_dialogue_label.get_theme_constant("line_spacing"))
	# Godot's font ascent/descent differs from Flash's masked TextField. Two
	# complete glyph boxes plus their shared leading and shadow must fit; the
	# hard-coded 43px window clipped the bottom of g/y/p on its second line.
	var glyph_window_height := ceilf(2.0 * FONT.get_height(font_size) + float(_source_dialogue_label.get_theme_constant("line_spacing")) + float(_source_dialogue_label.get_theme_constant("shadow_offset_y")))
	_source_dialogue_scroller.size.y = maxf(SPEECH_TEXT_VIEW_HEIGHT * _source_dialogue_scale.y, glyph_window_height)
	# Translate during the tween, then reset to a whole-line window using
	# lines_skipped. No cumulative subpixel offset remains after Space.
	_source_dialogue_scroll_step = maxf(1.0, rendered_line_height)
	_source_dialogue_content_height = rendered_line_height + _source_dialogue_scroll_step * float(maxi(0, line_count - 1))
	_source_dialogue_is_animating = false
	_update_source_dialogue_arrow()

func _update_source_dialogue_arrow() -> void:
	if _source_dialogue_arrow != null and is_instance_valid(_source_dialogue_arrow):
		_source_dialogue_arrow.visible = _source_dialogue_can_scroll()
	if _source_dialogue_label == null or _source_dialogue_is_animating or _source_dialogue_can_scroll() or not _source_dialogue_choices.is_empty():
		return
	if not _source_dialogue_yes.is_valid() and not _source_dialogue_no.is_valid():
		return
	for option in [{"symbol": "menus_speechBubble_yesButton", "y": 74.0, "action": _source_dialogue_yes}, {"symbol": "menus_speechBubble_noButton", "y": 101.0, "action": _source_dialogue_no}]:
		var action: Callable = option.action
		if not action.is_valid():
			continue
		var button := SourceMenuArt.button(interaction_dialog, option.symbol, _source_dialogue_bubble_position + Vector2(202, option.y) * _source_dialogue_scale, Callable(self, "_choose_source_dialogue_option").bind(action))
		if button != null:
			button.scale = _source_dialogue_scale
			button.focus_mode = Control.FOCUS_NONE
			_source_dialogue_choices.append(button)

func _choose_source_dialogue_option(action: Callable) -> void:
	if _source_dialogue_is_animating or not is_instance_valid(interaction_dialog):
		return
	_source_dialogue_is_animating = true
	var closing := interaction_dialog
	var tween := create_tween()
	tween.tween_property(closing, "modulate:a", 0.0, 0.2)
	tween.tween_callback(_finish_source_dialogue_close.bind(closing, action))

func _finish_source_dialogue_scroll() -> void:
	if not is_instance_valid(_source_dialogue_label):
		return
	_source_dialogue_line_index += 1
	_source_dialogue_label.lines_skipped = _source_dialogue_line_index
	_source_dialogue_label.position.y = 0.0
	_source_dialogue_label.max_lines_visible = 2
	_source_dialogue_is_animating = false
	_update_source_dialogue_arrow()

func _finish_source_dialogue_close(dialogue_to_close: Control, finished: Callable) -> void:
	if interaction_dialog == dialogue_to_close:
		_clear_dialog()
	if finished.is_valid():
		finished.call()

func _unhandled_key_input(event: InputEvent) -> void:
	if is_instance_valid(_seal_fusion) and _seal_fusion.active:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_M, KEY_ESCAPE] and current_room != null:
		if _menu_navigation_active:
			get_viewport().set_input_as_handled()
			return
		if _source_dialogue_label != null or _room_transition_active:
			return
		if interaction_dialog != null:
			_close_source_menu(_clear_dialog)
		else:
			_show_campaign_menu()
		get_viewport().set_input_as_handled()
		return
	if _source_dialogue_label == null or not event is InputEventKey or not event.pressed or event.echo:
		return
	if not event.is_action_pressed("interact") and not event.is_action_pressed("ui_accept") and event.keycode not in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER, KEY_E] and event.physical_keycode != KEY_E:
		return
	_advance_source_dialogue()
	get_viewport().set_input_as_handled()

func _show_grand_sage_bonus_picker() -> void:
	_clear_dialog()
	interaction_dialog = Control.new()
	interaction_dialog.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	interaction_dialog.z_index = 1500
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.0, 0.0, 0.0, 0.0)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	interaction_dialog.add_child(shade)
	var layout: Dictionary = current_room.dialogue_layout_for_zone(int(_active_sage_interaction.get("source_zone_id", 0))) if current_room != null else {"position": Vector2(186.0, 150.0), "scale": Vector2.ONE}
	var bubble_scale := _as_vector2(layout.get("scale", Vector2.ONE), Vector2.ONE).abs()
	var bubble_position := _as_vector2(layout.get("position", Vector2(186.0, 150.0)), Vector2(186.0, 150.0))
	var viewport_size := get_viewport_rect().size
	var bubble_texture := _load_texture(SPEECH_BUBBLE)
	if bubble_texture == null:
		_clear_dialog()
		_show_notice("Now first things first. How did you get your minions?")
		return
	var bubble_size := bubble_texture.get_size() * bubble_scale
	# The original menu pins the speech bubble near the top edge so the three
	# button-and-picture pairs have room to enter beneath it.
	bubble_position.y = minf(bubble_position.y, 150.0)
	bubble_position.x = clampf(bubble_position.x, 8.0, maxf(8.0, viewport_size.x - bubble_size.x - 8.0))
	bubble_position.y = clampf(bubble_position.y, 8.0, maxf(8.0, viewport_size.y - bubble_size.y - 8.0))
	var bubble := TextureRect.new()
	bubble.texture = bubble_texture
	bubble.position = bubble_position
	bubble.size = bubble_texture.get_size()
	bubble.scale = bubble_scale
	bubble.stretch_mode = TextureRect.STRETCH_SCALE
	bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bubble.modulate.a = 0.0
	interaction_dialog.add_child(bubble)
	var speaker := _label(interaction_dialog, "Grand Sage", bubble_position + Vector2(-55.0, 4.0) * bubble_scale, Vector2(SPEECH_TEXT_WIDTH, 18.0) * bubble_scale, 11 * maxi(1, roundi(minf(bubble_scale.x, bubble_scale.y))), Color.hex(0x819bc1ff))
	speaker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	speaker.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	speaker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	speaker.modulate.a = 0.0
	var prompt := _label(interaction_dialog, "Now first things first.  How did you get your minions?", bubble_position + Vector2(10.0, 22.0) * bubble_scale, Vector2(SPEECH_TEXT_WIDTH, 50.0) * bubble_scale, maxi(12, roundi(17.0 * minf(bubble_scale.x, bubble_scale.y))), Color.hex(0xd6e0f0ff))
	prompt.custom_maximum_size = Vector2(SPEECH_TEXT_WIDTH, 50.0) * bubble_scale
	prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	prompt.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	prompt.add_theme_constant_override("line_spacing", -2)
	prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	prompt.modulate.a = 0.0
	var picker_buttons: Array[TextureButton] = []
	var options := [
		{"stat": &"attack", "button": SAGE_RESCUE_BUTTON, "picture": SAGE_RESCUE_PICTURE},
		{"stat": &"health", "button": SAGE_GIFT_BUTTON, "picture": SAGE_GIFT_PICTURE},
		{"stat": &"speed", "button": SAGE_NOT_TELLING_BUTTON, "picture": SAGE_NOT_TELLING_PICTURE},
	]
	for index in range(options.size()):
		var option: Dictionary = options[index]
		var button_x := 100.0 + float(index) * 180.0
		var stat := StringName(option.stat)
		for asset_path in [String(option.button), String(option.picture)]:
			var button := _texture_button(interaction_dialog, asset_path, Vector2(button_x, bubble_position.y + (105.0 if asset_path == String(option.button) else 168.0)))
			if button == null:
				continue
			button.focus_mode = Control.FOCUS_NONE
			button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			button.modulate.a = 0.0
			button.pressed.connect(_begin_grand_sage_bonus_selection.bind(stat))
			picker_buttons.append(button)
	_attach_interaction_dialog()
	var enter_tween := create_tween().set_parallel(true)
	enter_tween.tween_property(shade, "color:a", 0.65, 0.5).set_delay(1.5)
	enter_tween.tween_property(bubble, "modulate:a", 1.0, 0.5).set_delay(0.5)
	enter_tween.tween_property(speaker, "modulate:a", 1.0, 0.5).set_delay(0.5)
	enter_tween.tween_property(prompt, "modulate:a", 1.0, 0.5).set_delay(0.5)
	for button in picker_buttons:
		enter_tween.tween_property(button, "modulate:a", 1.0, 0.5).set_delay(2.1)

func _begin_grand_sage_bonus_selection(stat_bonus: StringName) -> void:
	if _sage_bonus_choice_pending:
		return
	_sage_bonus_choice_pending = true
	if interaction_dialog == null or not is_instance_valid(interaction_dialog):
		_choose_grand_sage_bonus(stat_bonus)
		return
	var shade := interaction_dialog.get_child(0) as ColorRect
	var exit_tween := create_tween().set_parallel(true)
	if shade != null:
		exit_tween.tween_property(shade, "color:a", 0.0, 0.5).set_delay(0.8)
	var sage_bubble: TextureRect
	for child in interaction_dialog.get_children():
		if child is TextureRect and (child as TextureRect).texture == _load_texture(SPEECH_BUBBLE):
			sage_bubble = child as TextureRect
			break
	if sage_bubble != null:
		exit_tween.tween_property(sage_bubble, "modulate:a", 0.0, 0.5).set_delay(1.2)
	for child in interaction_dialog.get_children():
		if child is Label:
			exit_tween.tween_property(child, "modulate:a", 0.0, 0.5).set_delay(1.2)
		if child is TextureButton:
			var button := child as TextureButton
			button.disabled = true
			exit_tween.tween_property(button, "modulate:a", 0.0, 0.5)
	exit_tween.chain().tween_callback(_choose_grand_sage_bonus.bind(stat_bonus))

func _choose_grand_sage_bonus(stat_bonus: StringName) -> void:
	var checkpoint_position: Variant = current_room.player_position() if current_room != null else null
	var checkpoint_spawn_id := StringName(current_room.get_meta("spawn_id", "")) if current_room != null else &""
	var result: Dictionary = runtime.session.choose_grand_sage_bonus(stat_bonus, checkpoint_position, checkpoint_spawn_id) if runtime != null and runtime.session != null else {"ok": false, "message": "Campaign is unavailable."}
	_clear_dialog()
	if not result.get("ok", false):
		room_status.text = "Could not choose a Sage's gift: %s" % result.get("message", "unknown error")
		return
	_refresh_current_room()
	var response := "A heart of gold! I'm excited to see you progress through the tower. Go now and see if you can get the first Sage Seal."
	match stat_bonus:
		&"health": response = "What a fine gift! Go now and see if you can get the first Sage Seal."
		&"speed": response = "It doesn't matter then; we'll know how good a keeper you are soon enough. Go now and see if you can get the first Sage Seal."
	_show_source_dialogue(_active_sage_interaction, String(_active_sage_interaction.get("trainer_name", "Grand Sage")), response)

func _begin_trainer_battle(encounter_id: StringName, player_position: Vector2) -> void:
	if _room_transition_active:
		return
	_clear_dialog()
	var battle_slot: Dictionary = await _multiplayer.request_trainer_battle(String(encounter_id))
	if not battle_slot.get("ok", false) or _room_transition_active:
		_multiplayer.cancel_trainer_battle()
		if is_instance_valid(current_room):
			current_room.set_controls_enabled(interaction_dialog == null)
		return
	_trainer_return_location.clear()
	var trainer_return_location: Dictionary = {}
	if runtime != null and runtime.session != null and runtime.session.state != null and current_room != null:
		trainer_return_location = {
			"room_id": String(runtime.session.state.current_room_id),
			"spawn_id": String(current_room.get_meta("spawn_id", "start")),
			"position": player_position,
			"facing": String(current_room.player_facing()),
			"encounter_id": String(encounter_id),
			"first_visit": not bool(runtime.session.state.progression.get("completed_encounters", {}).get(String(encounter_id), false)),
		}
	var prepared: Dictionary = runtime.prepare_trainer_battle(encounter_id, player_position)
	if not prepared.get("ok", false):
		_multiplayer.cancel_trainer_battle()
		room_status.text = "Battle could not start: %s" % prepared.get("message", "unknown error")
		return
	room_status.text = ""
	_trainer_return_location = trainer_return_location
	_trainer_return_location["interaction_encounter_id"] = String(encounter_id)
	_trainer_return_location["encounter_id"] = String(runtime.session.state.pending_battle.get("encounter_id", encounter_id))
	_trainer_return_location["first_visit"] = not bool(runtime.session.state.progression.get("completed_encounters", {}).get(_trainer_return_location["encounter_id"], false))
	_room_transition_active = true
	if is_instance_valid(current_room):
		current_room.set_controls_enabled(false)
	# ScreenController starts the hidden destination before fading the old
	# screen. Spawn animations therefore continue underneath the curtain.
	current_battle = BATTLE_SCENE.instantiate()
	current_battle.visible = false
	screen_host.add_child(current_battle)
	current_battle.audio_controller.music_owner = _campaign_audio
	current_battle.campaign_return_requested.connect(_on_campaign_return_requested)
	current_battle.campaign_forfeit_return_requested.connect(_on_campaign_forfeit_return_requested)
	current_battle.campaign_defeat_return_requested.connect(_on_campaign_defeat_return_requested)
	_multiplayer.share_trainer_battle(current_battle, battle_slot)
	current_battle.call("begin_campaign_battle")
	_campaign_audio.fade_music_to(0.0, 0.5)
	await _fade_campaign_screen_out()
	if current_room != null:
		current_room.queue_free()
		current_room = null
	room_hud.visible = false
	current_battle.visible = true
	await _finish_campaign_screen_transition()

func _fade_campaign_screen_out() -> void:
	var curtain := _ensure_room_transition_curtain()
	curtain.visible = true
	curtain.color = Color(0.0, 0.0, 0.0, 0.0)
	var fade := create_tween()
	fade.tween_property(curtain, "color", Color.BLACK, 0.5)
	await fade.finished

func _finish_campaign_screen_transition() -> void:
	# ScreenController.SetSceneTo: switch at opaque, hold 0.2s, reveal 0.5s.
	if is_instance_valid(current_room):
		current_room.set_controls_enabled(false)
	await get_tree().create_timer(0.2).timeout
	var curtain := _ensure_room_transition_curtain()
	var fade := create_tween()
	fade.tween_property(curtain, "color", Color(0.0, 0.0, 0.0, 0.0), 0.5)
	await fade.finished
	curtain.visible = false
	_room_transition_active = false
	if is_instance_valid(current_room) and not is_instance_valid(interaction_dialog) and not _seal_fusion.active:
		current_room.set_controls_enabled(true)

func _on_campaign_return_requested() -> void:
	if _room_transition_active:
		return
	if not _complete_defeat_return_before_transition(Callable(self, "_on_campaign_return_requested")):
		return
	_room_transition_active = true
	var settlement: Dictionary = current_battle.campaign_settlement.duplicate(true) if is_instance_valid(current_battle) else {}
	if runtime != null:
		runtime.campaign_return_pending = false
	var return_location := _trainer_return_location.duplicate(true)
	_trainer_return_location.clear()
	await _fade_campaign_screen_out()
	await _restore_campaign_victory_room(settlement, return_location)
	await _finish_campaign_screen_transition()

func _restore_campaign_victory_room(settlement: Dictionary, return_location: Dictionary) -> void:
	if runtime != null and runtime.session != null and runtime.session.state != null and StringName(return_location.get("room_id", "")) == runtime.session.state.current_room_id:
		_show_room_from_state(
			StringName(return_location.get("spawn_id", "start")),
			_as_vector2(return_location.get("position", Vector2.INF), Vector2.INF),
			StringName(return_location.get("facing", "")),
		)
	else:
		_show_room_from_state()
	# MainChar.FinishActivate plays pickup feedback back in exploration, not
	# over the victory card. Let the room camera settle before anchoring icons.
	if bool(return_location.get("first_visit", false)) and is_instance_valid(current_room):
		current_room.set_controls_enabled(false)
	await get_tree().process_frame
	if bool(return_location.get("first_visit", false)) and is_instance_valid(current_room):
		var encounter_id := StringName(return_location.get("encounter_id", ""))
		var encounter := runtime.catalog.get_definition(encounter_id) as EncounterDefinition
		var dialogue: Dictionary = preload("res://src/application/source_trainer_dialogue.gd").for_encounter(encounter)
		var after_win := String(dialogue.get("after_win_text", ""))
		if not after_win.is_empty():
			for interaction in current_room.room.interactions:
				if StringName(interaction.get("encounter_id", "")) == StringName(return_location.get("interaction_encounter_id", encounter_id)):
					var return_interaction: Dictionary = interaction.duplicate(true)
					if not return_interaction.has("trainer_name"):
						return_interaction["trainer_name"] = dialogue.get("trainer_name", "Trainer")
					var show_dialogue := Callable(self, "_show_return_trainer_dialogue").bind(return_interaction, after_win, settlement, current_room, runtime.session.state.current_room_id)
					var trainer_type := String(encounter.source_trainer_type)
					var seal_family := int(trainer_type.trim_prefix("TrainerType.TRAINER_GYM_")) if trainer_type.begins_with("TrainerType.TRAINER_GYM_") else 0
					if seal_family > 0 and int(settlement.get("first_clear_rewards", {}).get("sage_seals", 0)) > 0:
						current_room.set_controls_enabled(false)
						if _seal_fusion.play(seal_family, _campaign_audio, show_dialogue):
							return
					show_dialogue.call()
					return
	_present_return_rewards(settlement)

func _show_return_trainer_dialogue(interaction: Dictionary, message: String, settlement: Dictionary, return_room: Node, room_id: StringName) -> void:
	if not is_instance_valid(return_room) or current_room != return_room or return_room.room.id != room_id:
		return
	_show_source_dialogue(interaction, String(interaction.get("trainer_name", "Trainer")), message, Callable(self, "_present_return_rewards").bind(settlement))

func _present_return_rewards(settlement: Dictionary) -> void:
	if is_instance_valid(current_room):
		current_room.set_controls_enabled(not _room_transition_active)
	if is_instance_valid(current_room) and not settlement.get("first_clear_rewards", {}).is_empty():
		_reward_canvas_origin = get_viewport().get_canvas_transform().origin
		_reward_presenter.position = Vector2.ZERO
		_reward_presenter.start(settlement, current_room.player_screen_position(), int(runtime.session.state.progression.get("floor_index", 0)), _campaign_audio, int(runtime.session.state.progression.get("sage_seals", 0)))
	if is_instance_valid(current_room) and int(runtime.session.state.progression.get("floor_keys", 0)) == 3 and not bool(runtime.session.state.progression.get("boss_room_tutorial_seen", false)):
		_schedule_boss_room_tutorial(current_room, runtime.session.state.current_room_id)

func _schedule_boss_room_tutorial(return_room: Node, room_id: StringName) -> void:
	await get_tree().create_timer(2.8).timeout
	while is_instance_valid(return_room) and current_room == return_room and return_room.room.id == room_id and (is_instance_valid(interaction_dialog) or _room_transition_active):
		await get_tree().create_timer(0.25).timeout
	if not is_instance_valid(return_room) or current_room != return_room or return_room.room.id != room_id or runtime.session.state == null:
		return
	if bool(runtime.session.state.progression.get("boss_room_tutorial_seen", false)) or int(runtime.session.state.progression.get("floor_keys", 0)) != 3:
		return
	var tutorial := preload("res://src/presentation/source_campaign_tutorial_view.gd").new()
	interaction_dialog = tutorial
	_attach_interaction_dialog()
	tutorial.configure(runtime.session, "boss_room", _campaign_audio)
	tutorial.completed.connect(func() -> void:
		if interaction_dialog == tutorial:
			_clear_dialog()
	)

func _on_campaign_forfeit_return_requested() -> void:
	if _room_transition_active:
		return
	_room_transition_active = true
	if runtime != null:
		runtime.campaign_return_pending = false
	# Forfeiting follows the source game's death/checkpoint return. Settlement
	# has already healed the party and moved the campaign to its safe location.
	_trainer_return_location.clear()
	await _fade_campaign_screen_out()
	_show_room_from_state()
	await _finish_campaign_screen_transition()

func _on_campaign_defeat_return_requested() -> void:
	if _room_transition_active:
		return
	if not _complete_defeat_return_before_transition(Callable(self, "_on_campaign_defeat_return_requested")):
		return
	_room_transition_active = true
	if runtime != null:
		runtime.campaign_return_pending = false
	_trainer_return_location.clear()
	# LoseScreen.GotoTopDownScreen_part2 invokes the ordinary ScreenController
	# transition after its 3s blackout. Keep that old screen until the shared
	# fade reaches black, then reveal the healed checkpoint after the .2s hold.
	await _fade_campaign_screen_out()
	_show_room_from_state()
	await _finish_campaign_screen_transition()

func _complete_defeat_return_before_transition(retry: Callable) -> bool:
	if runtime == null: return true
	var returned: Dictionary = runtime.complete_defeat_return()
	if returned.ok: return true
	# Retain the old battle and committed loss/XP if persistence fails. Closing
	# this notice retries only the recovery transaction, not battle settlement.
	_show_notice("Could not save the checkpoint return: %s. Press OK to retry." % returned.get("message", "unknown save error"))
	var buttons := interaction_dialog.find_children("", "Button", true, false)
	if not buttons.is_empty(): buttons[0].pressed.connect(retry, CONNECT_DEFERRED)
	return false

func _create_room_hud() -> void:
	room_hud_canvas = CanvasLayer.new()
	room_hud_canvas.name = "CampaignHudCanvas"
	room_hud_canvas.layer = 5
	add_child(room_hud_canvas)
	room_hud = Control.new()
	room_hud.name = "CampaignRoomHud"
	room_hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	room_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	room_hud.visible = false
	room_hud_canvas.add_child(room_hud)
	party_button = _text_button(room_hud, "Party", Vector2(402.0, 9.0), Vector2(68.0, 34.0))
	party_button.visible = false
	party_button.pressed.connect(_show_party_manager)
	var gems := _text_button(room_hud, "Gems", Vector2(328.0, 9.0), Vector2(68.0, 34.0))
	gems.visible = false
	gems.pressed.connect(_show_gem_inventory)
	map_button = _text_button(room_hud, "Map", Vector2(478.0, 9.0), Vector2(64.0, 34.0))
	map_button.visible = false
	map_button.pressed.connect(_show_floor_map)
	var save := _text_button(room_hud, "Save", Vector2(548.0, 9.0), Vector2(66.0, 34.0))
	save.visible = false
	save.pressed.connect(_save_campaign)
	var title := _text_button(room_hud, "Title", Vector2(618.0, 9.0), Vector2(70.0, 34.0))
	title.visible = false
	title.pressed.connect(_leave_to_title)
	room_status = _label(room_hud, "", Vector2(14.0, 370.0), Vector2(520.0, 24.0), 14, Color8(255, 232, 152))
	_hud_progress = preload("res://src/presentation/source_campaign_progress_hud.gd").new()
	room_hud.add_child(_hud_progress)
	var menu_button := SourceMenuArt.button(room_hud, "menus_gameplayMenuTab", Vector2(596, 491), _show_campaign_menu)
	if menu_button != null:
		menu_button.name = "CampaignMenuButton"
	SourceMenuArt.image(room_hud, "hud_starsAndKeysBackground", Vector2(388, 488))
	_hud_keys = _label(room_hud, "x0", Vector2(382, 489), Vector2(150, 32), 25, Color8(229, 232, 232))
	_hud_stars = _label(room_hud, "x0", Vector2(462, 489), Vector2(150, 32), 25, Color8(229, 232, 232))
	_hud_keys.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud_stars.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud_music_toggle = SourceMenuArt.button(room_hud, "menu_muteMusicButton_on", Vector2(4, 6), func() -> void: _settings.set_music_enabled(not _settings.music_enabled))
	_hud_sound_toggle = SourceMenuArt.button(room_hud, "menu_muteSoundButton_on", Vector2(36, 5), func() -> void: _settings.set_sound_enabled(not _settings.sound_enabled))

func _show_campaign_menu() -> void:
	if _room_transition_active or (is_instance_valid(_seal_fusion) and _seal_fusion.active):
		return
	if runtime == null or runtime.session == null or current_room == null:
		return
	_clear_dialog()
	interaction_dialog = Control.new()
	interaction_dialog.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0, 0, 0, 0.3)
	interaction_dialog.add_child(shade)
	var panel := Control.new()
	panel.position = Vector2(483, 177)
	interaction_dialog.add_child(panel)
	var background := SourceMenuArt.image(panel, "menus_topDownMenuPopUp_background", Vector2.ZERO)
	panel.size = background.size
	var actions: Array[Callable] = [_show_party_manager, _show_minion_pedia, _show_you_menu, _save_from_menu, _show_settings_menu, _leave_to_title]
	var symbols := ["minions", "minionDex", "you", "save", "settings", "mainMenu"]
	for index in symbols.size():
		SourceMenuArt.button(panel, "menus_topDownMenuPopUp_%s" % symbols[index], Vector2(17, 19 + 39 * index), actions[index])
	SourceMenuArt.button(panel, "menus_topDownMenuPopUp_resume", Vector2(17, 269), _close_source_menu.bind(_clear_dialog))
	_multiplayer.build_menu_panel(panel)
	if _settings.tips_enabled:
		if _hud_progress.has_affordable_star_upgrade(runtime.session.state):
			SourceMenuArt.image(panel, "tutorial_newStars_side", Vector2(-42, 90))
		for owned in runtime.session.state.party:
			var definition := runtime.catalog.get_definition(owned.definition_id) as MinionDefinition
			if CampaignProgressionService.available_talent_points(owned, definition) > 0:
				SourceMenuArt.image(panel, "tutorial_newTalentPointsPopup_side", Vector2(-90, 13))
				break
	_attach_interaction_dialog()
	panel.pivot_offset = panel.size * 0.5
	interaction_dialog.set_meta("source_transition_visuals", panel)
	_adopt_source_menu_backdrop(interaction_dialog)
	SourceMenuTransition.enter(interaction_dialog, true)

func _save_from_menu() -> void:
	if runtime == null or runtime.session == null:
		return
	_clear_dialog()
	var view := preload("res://src/presentation/campaign_save_menu_view.gd").new()
	interaction_dialog = view
	view.cancelled.connect(_close_source_menu.bind(_show_campaign_menu))
	view.saved.connect(func(return_to_lobby: bool) -> void:
		_close_source_menu(func() -> void:
			_clear_dialog()
			if return_to_lobby:
				_show_room_from_state()
		, true)
	)
	_attach_interaction_dialog()
	view.configure(runtime.session)
	_adopt_source_menu_backdrop(view)
	SourceMenuTransition.enter(view, true)

func _show_settings_menu() -> void:
	_clear_dialog()
	var view := CampaignSettingsView.new()
	interaction_dialog = view
	view.closed.connect(_close_source_menu.bind(_show_campaign_menu))
	_attach_interaction_dialog()
	view.configure(_settings)
	_adopt_source_menu_backdrop(view)
	SourceMenuTransition.enter(view)

func _show_you_menu() -> void:
	if runtime == null or runtime.session == null:
		return
	_clear_dialog()
	var view := CampaignYouMenuView.new()
	interaction_dialog = view
	view.closed.connect(_close_source_menu.bind(_show_campaign_menu))
	_attach_interaction_dialog()
	view.configure(runtime.session)
	_adopt_source_menu_backdrop(view)
	SourceMenuTransition.enter(view)

func _show_minion_pedia() -> void:
	_clear_dialog()
	var view := CampaignMinionPediaView.new()
	interaction_dialog = view
	view.closed.connect(_close_source_menu.bind(_show_campaign_menu))
	_attach_interaction_dialog()
	view.configure(runtime.catalog, runtime.session.state)
	_adopt_source_menu_backdrop(view)
	SourceMenuTransition.enter(view)

func _show_gem_inventory(member_id: StringName = &"", socket: int = 0) -> void:
	if runtime == null or runtime.session == null or runtime.session.state == null:
		return
	var return_to_storage := interaction_dialog is CampaignStorageMenuView
	var return_to_party := interaction_dialog is CampaignPartyMenuView
	var previous_view := interaction_dialog as Control if return_to_storage or return_to_party else null
	var previous_tab := int(previous_view.get("_tab")) if return_to_party else 2
	var previous_box := int(previous_view.get("_box_page")) if return_to_storage else 0
	if previous_view != null:
		# Keep the originating details screen below the source socket-selection
		# overlay. Detach it before freeing its old CanvasLayer.
		previous_view.reparent(self, false)
	_clear_dialog()
	var gem_view := CampaignGemMenuView.new()
	interaction_dialog = gem_view
	gem_view.z_index = 1500
	var return_route := Callable(self, "_restore_gem_storage_details").bind(member_id, previous_box) if return_to_storage else Callable(self, "_restore_gem_party_details").bind(member_id, previous_tab) if return_to_party else Callable(self, "_show_campaign_menu")
	gem_view.closed.connect(_close_source_menu.bind(return_route))
	gem_view.exit_requested.connect(_close_source_menu.bind(_clear_dialog))
	_attach_interaction_dialog()
	if previous_view != null:
		gem_view.set_backdrop(previous_view)
	gem_view.configure(runtime.session, member_id, socket)
	_adopt_source_menu_backdrop(gem_view)
	SourceMenuTransition.enter(gem_view, true)

func _restore_gem_party_details(member_id: StringName, tab: int) -> void:
	_show_party_manager()
	var view := interaction_dialog as CampaignPartyMenuView
	if view == null:
		return
	for index in runtime.session.state.party.size():
		if runtime.session.state.party[index].instance_id == member_id:
			view._selected = index
			view._showing_details = true
			view._tab = tab
			view._render()
			SourceMenuTransition.enter(view, true)
			return

func _restore_gem_storage_details(member_id: StringName, box: int) -> void:
	_show_storage_manager()
	var view := interaction_dialog as CampaignStorageMenuView
	if view != null:
		view._box_page = box
		view._selected_id = member_id
		view._detail_tab = 2
		view._render()
		SourceMenuTransition.enter(view, true)

func _show_gem_merchant(mode: StringName = &"shop") -> void:
	if runtime == null or runtime.session == null or runtime.session.state == null:
		return
	_clear_dialog()
	var view := CampaignGemMerchantView.new()
	interaction_dialog = view
	view.closed.connect(_close_source_menu.bind(_clear_dialog))
	_attach_interaction_dialog()
	view.configure_merchant(runtime.session, mode, _campaign_audio)
	SourceMenuTransition.enter(view)

func _show_floor_map() -> void:
	if runtime == null or runtime.session == null or runtime.session.state == null or runtime.session.campaign == null:
		return
	_clear_dialog()
	var map_view := CampaignMinimapView.new()
	interaction_dialog = map_view
	map_view.z_index = 1500
	map_view.closed.connect(_clear_dialog)
	_attach_interaction_dialog()
	map_view.configure(runtime.catalog, runtime.session.state, runtime.session.campaign)

func _show_tower_lobby_screen() -> void:
	var result: Dictionary = runtime.enter_tower_lobby()
	if not result.get("ok", false):
		_show_notice(String(result.get("message", "Lobby unavailable")))
		return
	_show_room_from_state()

func _show_floor_picker() -> void:
	_clear_dialog()
	var view := CampaignFloorSelectView.new()
	interaction_dialog = view
	view.closed.connect(_clear_dialog)
	view.floor_selected.connect(_select_tower_floor)
	view.mode_selected.connect(_select_tower_mode)
	_attach_interaction_dialog()
	view.configure(runtime.session, _campaign_audio)

func _show_legacy_floor_picker() -> void:
	if runtime == null or runtime.session == null or runtime.session.state == null or runtime.session.campaign == null:
		_show_title_screen()
		return
	var state = runtime.session.state
	var screen := _new_menu_screen()
	_add_title_background(screen)
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.02, 0.035, 0.07, 0.72)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(shade)
	var heading := _label(screen, "Tower Lobby", Vector2(190.0, 55.0), Vector2(320.0, 48.0), 30, Color8(255, 216, 102))
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var current_index := int(state.progression.get("floor_index", 0))
	var intro := _label(screen, "Choose an unlocked floor. Your party will rest before you enter.", Vector2(102.0, 108.0), Vector2(496.0, 38.0), 16, Color8(247, 243, 222))
	intro.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var panel := PanelContainer.new()
	panel.position = Vector2(118.0, 157.0)
	panel.size = Vector2(464.0, 280.0)
	screen.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.custom_minimum_size.x = 420.0
	rows.add_theme_constant_override("separation", 7)
	scroll.add_child(rows)
	var unlocked: Array = state.progression.get("unlocked_floor_indices", [0]).duplicate()
	unlocked.sort()
	for floor_index_variant in unlocked:
		var floor_index := int(floor_index_variant)
		var floor_data: Dictionary = {}
		for configured_floor in runtime.session.campaign.floors:
			if int(configured_floor.get("floor_index", -1)) == floor_index:
				floor_data = configured_floor
				break
		var floor_number := floor_index + 1
		var room_label := ""
		var room_ids: Array = floor_data.get("room_ids", [])
		if not room_ids.is_empty():
			var first_room := runtime.catalog.get_definition(StringName(floor_data.get("start_room_id", room_ids[0]))) as RoomDefinition
			if first_room != null:
				room_label = " — %s" % String(first_room.display_name).trim_prefix("Floor %d — " % floor_number)
		var suffix := "  •  current floor" if floor_index == current_index else ""
		if floor_data.is_empty():
			suffix += "  •  not ported yet"
		var floor_button := _text_button(rows, "Floor %d%s%s" % [floor_number, room_label, suffix], Vector2.ZERO, Vector2(416.0, 44.0))
		floor_button.disabled = floor_data.is_empty()
		if not floor_data.is_empty():
			floor_button.pressed.connect(_select_tower_floor.bind(floor_index))
	if unlocked.is_empty():
		var empty_label := _label(rows, "No floors have been unlocked.", Vector2.ZERO, Vector2(416.0, 38.0), 16, Color8(42, 41, 40))
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Functional services until the source lobby/NPC layout replaces this floor
	# selection screen; keep merchants out of the in-battle and room HUD menus.
	_text_button(screen, "Gem shop", Vector2(118, 455), Vector2(145, 38)).pressed.connect(_show_gem_merchant.bind(&"shop"))
	_text_button(screen, "Combine gems", Vector2(275, 455), Vector2(150, 38)).pressed.connect(_show_gem_merchant.bind(&"combine"))
	_text_button(screen, "Storage", Vector2(437, 455), Vector2(145, 38)).pressed.connect(_show_storage_manager)

func _select_tower_floor(floor_index: int) -> void:
	if runtime == null:
		return
	var result: Dictionary = runtime.select_tower_floor(floor_index)
	if not result.get("ok", false):
		_show_notice("Could not enter Floor %d: %s" % [floor_index + 1, result.get("message", "unknown error")])
		return
	# Room views are reused, so loading a floor does not clear overlays through
	# _clear_game_screen. Retire the selector before reconfiguring the room.
	# Disconnect immediately: queue_free alone leaves it callable this frame.
	var picker := interaction_dialog as CampaignFloorSelectView
	if is_instance_valid(picker):
		picker.floor_selected.disconnect(_select_tower_floor)
		picker.hide()
	_clear_dialog()
	_show_room_from_state(StringName(result.get("spawn_id", "")), _as_vector2(result.get("position", Vector2.ZERO), Vector2.ZERO))

func _select_tower_mode(mode: StringName) -> void:
	var result: Dictionary = runtime.session.select_tower_mode(mode)
	if not result.get("ok", false):
		room_status.text = String(result.get("message", "Tower mode unavailable"))
		return
	_show_floor_picker()

func _show_party_manager() -> void:
	if runtime == null or runtime.session == null or runtime.session.state == null:
		return
	_clear_dialog()
	var view := CampaignPartyMenuView.new()
	interaction_dialog = view
	view.closed.connect(_close_source_menu.bind(_show_campaign_menu))
	view.storage_requested.connect(_show_storage_manager)
	view.gems_requested.connect(_show_gem_inventory)
	view.talents_requested.connect(_show_campaign_talents)
	_attach_interaction_dialog()
	view.configure(runtime.session, Callable(self, "_build_party_menu_row"))
	_adopt_source_menu_backdrop(view)
	SourceMenuTransition.enter(view, true)

func _build_party_menu_row(parent: Control, owned: OwnedMinionState, on_pressed: Callable) -> void:
	var definition := runtime.catalog.get_definition(owned.definition_id) as MinionDefinition
	var presentation := runtime.catalog.get_definition(definition.presentation_id) as MinionPresentationDefinition if definition != null else null
	_build_source_party_row(parent, Vector2.ZERO, owned, definition, presentation, on_pressed)

func _show_campaign_talents(member_id: StringName) -> void:
	var owned: OwnedMinionState
	for member in runtime.session.state.party:
		if member.instance_id == member_id:
			owned = member
			break
	if owned == null:
		return
	_clear_dialog()
	var view := BattleProgressionPresenter.new()
	interaction_dialog = view
	view.sequence_finished.connect(_show_party_manager)
	view.campaign_close_requested.connect(_clear_dialog)
	_attach_interaction_dialog()
	view.show_campaign_talents(owned, runtime.catalog, Callable(runtime, "save_campaign"))
	_adopt_source_menu_backdrop(view)

func _show_storage_manager() -> void:
	if runtime == null or runtime.session == null or runtime.session.state == null:
		return
	if not _multiplayer.storage_ready():
		return
	_clear_dialog()
	var view := CampaignStorageMenuView.new()
	interaction_dialog = view
	view.closed.connect(_close_source_menu.bind(_clear_dialog))
	view.gems_requested.connect(_show_gem_inventory)
	_attach_interaction_dialog()
	view.configure(runtime.session, Callable(self, "_build_party_menu_row"))
	_adopt_source_menu_backdrop(view)
	SourceMenuTransition.enter(view)

func _show_legacy_storage_manager() -> void:
	if runtime == null or runtime.session == null or runtime.session.state == null:
		return
	_clear_dialog()
	party_swap_selected_party = -1
	party_swap_selected_storage = -1
	var state = runtime.session.state
	interaction_dialog = Control.new()
	interaction_dialog.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	interaction_dialog.z_index = 1500
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.0, 0.0, 0.0, 0.62)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	interaction_dialog.add_child(shade)
	var panel := PanelContainer.new()
	panel.position = Vector2(47.0, 38.0)
	panel.size = Vector2(606.0, 448.0)
	interaction_dialog.add_child(panel)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 8)
	panel.add_child(rows)
	var heading := _label(rows, "Party & storage   •   %d/5 party members   •   %d stored" % [state.party.size(), state.storage.size()], Vector2.ZERO, Vector2(572.0, 34.0), 18, Color8(42, 41, 40))
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	party_manager_hint = _label(rows, "Select one party member and one stored minion to swap their places.", Vector2.ZERO, Vector2(572.0, 32.0), 14, Color8(85, 77, 58))
	party_manager_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 12)
	rows.add_child(columns)
	var party_column := VBoxContainer.new()
	party_column.custom_minimum_size = Vector2(278.0, 320.0)
	party_column.add_theme_constant_override("separation", 5)
	columns.add_child(party_column)
	_label(party_column, "Active party", Vector2.ZERO, Vector2(270.0, 26.0), 16, Color8(42, 41, 40))
	var party_scroll := ScrollContainer.new()
	party_scroll.custom_minimum_size = Vector2(278.0, 285.0)
	party_column.add_child(party_scroll)
	var party_entries := VBoxContainer.new()
	party_entries.custom_minimum_size.x = 260.0
	party_entries.add_theme_constant_override("separation", 5)
	party_scroll.add_child(party_entries)
	_build_roster_entries(party_entries, state.party, true)
	var storage_column := VBoxContainer.new()
	storage_column.custom_minimum_size = Vector2(278.0, 320.0)
	storage_column.add_theme_constant_override("separation", 5)
	columns.add_child(storage_column)
	_label(storage_column, "Storage", Vector2.ZERO, Vector2(270.0, 26.0), 16, Color8(42, 41, 40))
	var storage_scroll := ScrollContainer.new()
	storage_scroll.custom_minimum_size = Vector2(278.0, 285.0)
	storage_column.add_child(storage_scroll)
	var storage_entries := VBoxContainer.new()
	storage_entries.custom_minimum_size.x = 260.0
	storage_entries.add_theme_constant_override("separation", 5)
	storage_scroll.add_child(storage_entries)
	if state.storage.is_empty():
		_label(storage_entries, "No stored minions yet. Eggs chosen with a full party are kept here.", Vector2.ZERO, Vector2(252.0, 64.0), 14, Color8(89, 84, 72))
	else:
		_build_roster_entries(storage_entries, state.storage, false)
	_text_button(rows, "Close party", Vector2.ZERO, Vector2(140.0, 34.0)).pressed.connect(_clear_dialog)
	_attach_interaction_dialog()

func _show_egg_reveal(result: Dictionary, egg_slot: int, ask_party: bool = false) -> void:
	var definition := result.get("definition") as MinionDefinition
	var owned := result.get("minion") as OwnedMinionState
	if definition == null or owned == null:
		_show_notice("An egg hatched, but its minion data could not be loaded.")
		return
	var actor_screen := Vector2(226, 334)
	if is_instance_valid(current_room):
		actor_screen = current_room.get_viewport().get_canvas_transform() * current_room.to_global(current_room.player_position())
	# MainChar.BringInCharChatBoxWithText positions its own speech bubble,
	# not a room NPC bubble. The details card appears beside it immediately.
	var bubble_position := actor_screen + Vector2(45, -30)
	var bubble_texture := _load_texture(SPEECH_BUBBLE)
	if bubble_texture != null and bubble_position.x + bubble_texture.get_width() > 700:
		bubble_position.x = actor_screen.x - 225
	var interaction := {"dialogue_layout": {"position": bubble_position, "scale": Vector2.ONE}}
	var message: String
	var on_complete := Callable()
	if ask_party:
		message = "Would you like to add %s to your party?" % definition.display_name
		interaction["on_yes"] = Callable(self, "_show_egg_party_picker").bind(owned.instance_id, definition.display_name, egg_slot)
		interaction["on_no"] = Callable(self, "_finish_egg_reveal").bind(egg_slot, owned.instance_id)
	elif egg_slot >= 0 and int(result.get("remaining", 0)) > 0:
		message = "This egg contains a %s. Would you like to keep it?" % definition.display_name
		interaction["on_yes"] = Callable(self, "_accept_egg_preview").bind(result, egg_slot)
		interaction["on_no"] = Callable(self, "_discard_egg_pick").bind(owned.instance_id, egg_slot, definition.display_name)
	else:
		# Preserve the original displayed wording, including its spelling.
		message = "You've recieved a %s." % definition.display_name
		on_complete = Callable(self, "_accept_egg_preview").bind(result, egg_slot)
	_show_source_dialogue(interaction, "Inner Monologue", message, on_complete)
	if not is_instance_valid(interaction_dialog):
		return
	var presentation := runtime.catalog.get_definition(definition.presentation_id) as MinionPresentationDefinition
	var details := CampaignEggeryPresenter.new()
	details.name = "HatcheryMinionDetails"
	interaction_dialog.add_child(details)
	details.present(result, presentation, actor_screen, get_viewport_rect().size)

func _accept_egg_preview(result: Dictionary, egg_slot: int) -> void:
	var owned := result.get("minion") as OwnedMinionState
	if owned == null:
		return
	if runtime.session.state.party.size() >= 5 and StringName(result.get("destination", "")) != &"party":
		# BaseEggery.AddMinion waits .25s between the closing keep prompt
		# and the second, add-to-party question.
		var receiving_room: Node = current_room
		if is_instance_valid(receiving_room):
			receiving_room.set_controls_enabled(false)
		await get_tree().create_timer(0.25).timeout
		if not is_instance_valid(receiving_room) or current_room != receiving_room:
			return
		_show_egg_reveal(result, egg_slot, true)
	else:
		_finish_egg_reveal(egg_slot, owned.instance_id)

func _show_egg_party_picker(egg_instance_id: StringName, egg_name: String, egg_slot: int) -> void:
	if runtime == null or runtime.session == null or runtime.session.state == null:
		return
	_clear_dialog()
	interaction_dialog = Control.new()
	interaction_dialog.set_meta("egg_party_picker", true)
	interaction_dialog.set_meta("egg_minion_name", egg_name)
	interaction_dialog.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	interaction_dialog.z_index = 1500
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.0, 0.0, 0.0, 0.65)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	interaction_dialog.add_child(shade)
	_add_source_art(interaction_dialog, "802_Utilities.SpriteHandler_menus_backgroundMedium.png", Vector2(168.0, 57.0), Vector2(359.0, 415.0))
	_add_source_art(interaction_dialog, "1141_Utilities.SpriteHandler_tutorial_choosingAMinionBar.png", Vector2(523.0, 103.0), Vector2(69.0, 362.0))
	var heading := _label(interaction_dialog, "Choose a minion to swap", Vector2(587.0, 220.0), Vector2(90.0, 86.0), 20, Color8(250, 250, 250))
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_add_source_texture_button(interaction_dialog, "666_Utilities.SpriteHandler_menus_exitButton.png", Vector2(464.0, 35.0), Callable(self, "_finish_egg_reveal").bind(egg_slot, egg_instance_id))
	var party: Array = runtime.session.state.party
	for index in mini(5, party.size()):
		var member := party[index] as OwnedMinionState
		if member == null:
			continue
		var definition := runtime.catalog.get_definition(member.definition_id) as MinionDefinition
		var member_name := member.nickname if not member.nickname.is_empty() else definition.display_name if definition != null else String(member.definition_id)
		var member_presentation := runtime.catalog.get_definition(definition.presentation_id) as MinionPresentationDefinition if definition != null else null
		_build_source_party_row(interaction_dialog, Vector2(186.0, 77.0 + 75.0 * index), member, definition, member_presentation, Callable(self, "_swap_egg_into_party").bind(index, egg_instance_id, egg_name, member_name, egg_slot))
	_attach_interaction_dialog()
	interaction_dialog.modulate.a = 0.0
	var entrance := create_tween()
	entrance.tween_interval(0.1)
	entrance.tween_property(interaction_dialog, "modulate:a", 1.0, 0.5)

func _build_source_party_row(parent: Control, at: Vector2, owned: OwnedMinionState, definition: MinionDefinition, presentation: MinionPresentationDefinition, on_pressed: Callable) -> void:
	var row := Control.new()
	row.name = "SourceMinionOverview"
	row.position = at
	row.size = Vector2(323.0, 76.0)
	parent.add_child(row)
	_add_source_art(row, "651_Utilities.SpriteHandler_menus_minionInfo_background.png", Vector2.ZERO, row.size)
	_add_source_art(row, "1659_Utilities.SpriteHandler_menus_minionIcon_background.png", Vector2(5.0, 5.0), Vector2.ZERO)
	if presentation != null and not presentation.legacy_sprite_name.is_empty():
		var sprite_path := "res://content/base/art/battle/minions/%s.png" % String(presentation.legacy_sprite_name)
		if not ResourceLoader.exists(sprite_path):
			sprite_path = "res://content/base/art/battle/%s.png" % String(presentation.legacy_sprite_name)
		var sprite := _load_texture(sprite_path)
		if sprite != null:
			var mask_texture := SourceMenuArt.texture("menus_minionIcon_mask")
			if mask_texture != null:
				var mask := Sprite2D.new()
				mask.name = "SourceMinionIconMask"
				mask.texture = mask_texture
				mask.centered = false
				mask.position = Vector2(8, 8)
				mask.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
				row.add_child(mask)
				var icon := Sprite2D.new()
				icon.name = "SourceMinionIcon"
				icon.texture = sprite
				icon.centered = false
				icon.position = Vector2(presentation.icon_offset) - mask.position
				mask.add_child(icon)
	var display_name := owned.nickname if not owned.nickname.is_empty() else definition.display_name if definition != null else String(owned.definition_id)
	var name_label := _label(row, display_name, Vector2(72.0, -1.0), Vector2(180.0, 32.0), 18, Color.hex(0xebebebff))
	name_label.name = "SourceMinionName"
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var stats := CampaignProgressionService.owned_display_stats(owned, definition, runtime.session.catalog, runtime.session.state) if definition != null else {"health": 1, "energy": 0}
	var max_health := maxi(1, int(stats.get("health", 1)))
	var max_energy := maxi(0, int(stats.get("energy", 0)))
	var health := max_health if owned.persistent_health < 0 else clampi(owned.persistent_health, 0, max_health)
	var energy := max_energy if owned.persistent_energy < 0 else clampi(owned.persistent_energy, 0, max_energy)
	_add_source_bar(row, "1481_Utilities.SpriteHandler_menus_minionInfo_healthBar_full.png", Vector2(72.0, 29.0), float(health) / float(max_health))
	_add_source_bar(row, "1293_Utilities.SpriteHandler_menus_minionInfo_energyBar_full.png", Vector2(72.0, 42.0), float(energy) / float(max_energy) if max_energy > 0 else 0.0)
	var gem_count := mini(4, definition.gem_slots) if definition != null else 0
	for gem_index in gem_count:
		var has_gem := gem_index < owned.equipment_ids.size() and not String(owned.equipment_ids[gem_index]).is_empty()
		var gem_asset := "1171_Utilities.SpriteHandler_menus_minionInfo_filledGemSlot.png" if has_gem else "1341_Utilities.SpriteHandler_menus_minionInfo_emptyGemSlot.png"
		_add_source_art(row, gem_asset, Vector2(72.0 + gem_index * 20.0, 53.0), Vector2.ZERO)
	var bonus_x := 76.0 + gem_count * 20.0
	_add_source_art(row, _egg_stat_bonus_asset(_egg_stat_bonus_index(owned.stat_bonus)), Vector2(bonus_x, 55.0), Vector2.ZERO)
	var lv_label := _label(row, "lv", Vector2(285, 55) if owned.level > 9 else Vector2(286, 56), Vector2(50.0, 16.0), 10, Color.hex(0xebebebff))
	lv_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var level_at := Vector2(298.0, 42.0) if owned.level < 10 else Vector2(295.0, 48.0)
	var level_label := _label(row, str(owned.level), level_at, Vector2(50, 32), 22, Color.hex(0xebebebff))
	if owned.level > 9:
		level_label.scale = Vector2.ONE * 0.75
	level_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for text_label in [name_label, lv_label, level_label]:
		text_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		text_label.position.y += 2.0 # Flash TextField's inset, not a vertically centered box.
		text_label.add_theme_constant_override("shadow_offset_x", 0)
		text_label.add_theme_constant_override("shadow_offset_y", 0)
	if definition != null and CampaignProgressionService.available_talent_points(owned, definition) > 0:
		var talent_hint := preload("res://src/presentation/source_tutorial_popup.gd").new()
		talent_hint.position = Vector2(-105, 13)
		row.add_child(talent_hint)
		talent_hint.configure("tutorial_newTalentPointsPopup_side")
	var select := Button.new()
	select.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	select.flat = true
	select.focus_mode = Control.FOCUS_NONE
	select.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	select.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	select.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	select.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	select.pressed.connect(on_pressed)
	row.add_child(select)

func _add_source_bar(parent: Control, asset: String, at: Vector2, ratio: float) -> void:
	var symbol := asset.get_slice("_Utilities.SpriteHandler_", 1).trim_suffix(".png")
	SourceMenuArt.bar(parent, symbol, at, ratio, symbol.replace("_full", "_cap"))

func _add_source_art(parent: Control, asset: String, at: Vector2, art_size: Vector2) -> TextureRect:
	var texture := _load_texture("res://content/base/art/source_symbols/%s" % asset)
	if texture == null:
		return null
	var art := TextureRect.new()
	art.texture = texture
	art.position = at
	art.size = texture.get_size() if art_size == Vector2.ZERO else art_size
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_SCALE
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(art)
	return art

func _add_source_texture_button(parent: Control, asset: String, at: Vector2, action: Callable) -> void:
	var texture := _load_texture("res://content/base/art/source_symbols/%s" % asset)
	if texture == null:
		return
	var button := TextureButton.new()
	button.texture_normal = texture
	button.texture_hover = texture
	button.texture_pressed = texture
	button.position = at
	button.size = texture.get_size()
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(action)
	parent.add_child(button)

func _add_source_choice(text: String, at: Vector2, button_size: Vector2, action: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.position = at
	button.size = button_size
	button.custom_minimum_size = button_size
	button.flat = true
	button.add_theme_font_override("font", FONT)
	button.add_theme_font_size_override("font_size", 17)
	button.add_theme_color_override("font_color", Color8(247, 243, 222))
	button.add_theme_color_override("font_hover_color", Color8(255, 230, 134))
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color8(37, 45, 67, 222)
	normal.border_color = Color8(185, 161, 110)
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(4)
	button.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color8(66, 76, 103, 238)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	button.pressed.connect(action)
	interaction_dialog.add_child(button)

func _egg_stat_bonus_index(stat_bonus: StringName) -> int:
	match stat_bonus:
		&"health": return 0
		&"energy": return 1
		&"attack": return 2
		&"healing": return 3
		&"speed": return 4
		_: return 0

func _egg_stat_bonus_asset(bonus_index: int) -> String:
	var sprite_ids: Array[int] = [294, 295, 296, 297, 299]
	var index := clampi(bonus_index, 0, sprite_ids.size() - 1)
	return "%d_Utilities.SpriteHandler_hud_statBonus_%d.png" % [sprite_ids[index], index]

func _swap_egg_into_party(party_index: int, egg_instance_id: StringName, egg_name: String, outgoing_name: String, egg_slot: int) -> void:
	var completed: Dictionary
	if egg_slot >= 0:
		# Egg candidates are previews, not storage entries. Accept and replace
		# in one save-before-commit operation, preserving the outgoing minion.
		completed = runtime.session.finish_egg_selection(egg_instance_id, party_index)
	else:
		# Lobby Titans have already been granted into the owned collection.
		var storage_index := -1
		for index in runtime.session.state.storage.size():
			if runtime.session.state.storage[index].instance_id == egg_instance_id:
				storage_index = index
				break
		if storage_index < 0:
			_show_notice("The received minion is no longer in storage.")
			return
		completed = runtime.session.swap_party_with_storage(party_index, storage_index)
	if not completed.get("ok", false):
		_show_notice("Could not add %s to your party: %s" % [egg_name, completed.get("message", "unknown error")])
		return
	await _show_egg_storage_notice(outgoing_name, egg_slot)

func _finish_egg_reveal(egg_slot: int, accepted_instance_id: StringName = &"") -> void:
	var from_party_picker := is_instance_valid(interaction_dialog) and bool(interaction_dialog.get_meta("egg_party_picker", false))
	var received_name := String(interaction_dialog.get_meta("egg_minion_name", "Minion")) if from_party_picker else "Minion"
	if egg_slot >= 0:
		var completed: Dictionary = runtime.session.finish_egg_selection(accepted_instance_id)
		if not completed.get("ok", false):
			_show_notice("Could not finish this hatchery selection: %s" % completed.get("message", "unknown error"))
			return
	if from_party_picker:
		await _show_egg_storage_notice(received_name, egg_slot)
		return
	_clear_dialog()
	if egg_slot >= 0:
		await _sink_accepted_eggery_and_refresh(egg_slot)
	else:
		await _sink_egg_and_refresh(egg_slot)
	if egg_slot < 0:
		_show_next_titan_reward()

func _show_egg_storage_notice(display_name: String, egg_slot: int) -> void:
	if is_instance_valid(interaction_dialog):
		var closing := interaction_dialog
		closing.mouse_filter = Control.MOUSE_FILTER_STOP
		for child in closing.find_children("*", "BaseButton", true, false):
			(child as BaseButton).disabled = true
		var exit_tween := create_tween()
		exit_tween.tween_property(closing, "modulate:a", 0.0, 0.5)
		await exit_tween.finished
		if interaction_dialog != closing:
			return
	_clear_dialog()
	var actor_screen: Vector2 = current_room.player_screen_position() if is_instance_valid(current_room) else Vector2(226, 334)
	var bubble_position := actor_screen + Vector2(45, -30)
	var bubble_texture := _load_texture(SPEECH_BUBBLE)
	if bubble_texture != null and bubble_position.x + bubble_texture.get_width() > 700:
		bubble_position.x = actor_screen.x - 225
	_show_source_dialogue({"dialogue_layout": {"position": bubble_position, "scale": Vector2.ONE}}, "Inner Monologue", "%s has been sent to storage" % display_name, Callable(self, "_finish_egg_storage_notice").bind(egg_slot))

func _finish_egg_storage_notice(egg_slot: int) -> void:
	room_status.text = ""
	if egg_slot >= 0:
		await _sink_accepted_eggery_and_refresh(egg_slot)
	else:
		await _sink_egg_and_refresh(egg_slot)
		_show_next_titan_reward()

func _sink_accepted_eggery_and_refresh(accepted_slot: int) -> void:
	if current_room == null or not is_instance_valid(current_room) or not current_room.has_method("sink_egg"):
		_refresh_current_room()
		return
	current_room.update_campaign_progression(runtime.session.state.progression)
	_refresh_source_hud()
	current_room.set_controls_enabled(true)
	var sinking_tweens: Array[Tween] = []
	var slots: Array[int] = [accepted_slot]
	slots.append_array(CampaignEggeryPresenter.accepted_egg_slots(accepted_slot))
	for slot in slots:
		var sinking: Tween = current_room.sink_egg(slot)
		if sinking != null:
			sinking_tweens.append(sinking)
	if not sinking_tweens.is_empty():
		await sinking_tweens[0].finished
	# Source eggs animate within the existing room. Rebuilding it here could
	# close a newly opened egg dialogue or restart another egg's sinking tween.

func _claim_lobby_titan() -> void:
	var result: Dictionary = runtime.session.claim_lobby_titan()
	if not result.get("ok", false):
		_show_notice(String(result.get("message", "Titan reward unavailable")))
		return
	_pending_titan_rewards.assign(result.get("rewards", []))
	_titan_sink_started = false
	_show_next_titan_reward()

func _show_next_titan_reward() -> void:
	if _pending_titan_rewards.is_empty():
		return
	_show_egg_reveal(_pending_titan_rewards.pop_front(), -1)

func _discard_egg_pick(instance_id: StringName, egg_slot: int, minion_name: String) -> void:
	var result: Dictionary = runtime.session.discard_latest_egg_minion(instance_id)
	if not result.get("ok", false):
		_show_notice("Could not decline %s: %s" % [minion_name, result.get("message", "unknown error")])
		return
	_clear_dialog()
	room_status.text = ""
	await _sink_egg_and_refresh(egg_slot)

func _sink_egg_and_refresh(egg_slot: int) -> void:
	if egg_slot < 0:
		if is_instance_valid(current_room) and not _titan_sink_started:
			current_room.sink_egg(CampaignRoomView.LOBBY_TITAN_SLOT)
			_titan_sink_started = true
		return
	if current_room != null and is_instance_valid(current_room) and current_room.has_method("sink_egg"):
		current_room.update_campaign_progression(runtime.session.state.progression)
		_refresh_source_hud()
		current_room.set_controls_enabled(true)
		var sinking: Tween = current_room.sink_egg(egg_slot)
		if sinking != null:
			await sinking.finished
		# Do not reload the room when an old egg finishes sinking.

func _build_roster_entries(parent: Control, members: Array, is_party: bool) -> void:
	for index in members.size():
		var owned := members[index] as OwnedMinionState
		if owned == null:
			continue
		var definition := runtime.catalog.get_definition(owned.definition_id) as MinionDefinition
		var display_name := owned.nickname if not owned.nickname.is_empty() else definition.display_name if definition != null else String(owned.definition_id)
		var button := _text_button(parent, "%d. %s   Lv. %d" % [index + 1, display_name, owned.level], Vector2.ZERO, Vector2(258.0, 40.0))
		button.custom_minimum_size = Vector2(258.0, 40.0)
		button.pressed.connect(_select_party_manager_entry.bind(is_party, index))

func _select_party_manager_entry(is_party: bool, index: int) -> void:
	if is_party:
		party_swap_selected_party = index
	else:
		party_swap_selected_storage = index
	if party_swap_selected_party < 0 or party_swap_selected_storage < 0:
		var side := "party" if is_party else "storage"
		party_manager_hint.text = "Selected %s member %d. Now select a minion from the other side." % [side, index + 1]
		return
	var result: Dictionary = runtime.session.swap_party_with_storage(party_swap_selected_party, party_swap_selected_storage)
	if not result.get("ok", false):
		party_manager_hint.text = "Swap failed: %s" % result.get("message", "unknown error")
		party_swap_selected_party = -1
		party_swap_selected_storage = -1
		return
	room_status.text = "Party and storage updated."
	_show_party_manager()

func _save_campaign() -> void:
	var result: Dictionary = runtime.save_campaign() if runtime != null else {"ok": false, "message": "Campaign runtime is unavailable"}
	room_status.text = "Saved." if result.get("ok", false) else "Save failed: %s" % result.get("message", "unknown error")

func _leave_to_title() -> void:
	if runtime != null and runtime.session != null and runtime.session.state != null:
		var result: Dictionary = runtime.save_campaign()
		if not result.get("ok", false):
			room_status.text = "Save failed: %s" % result.get("message", "unknown error")
			return
	net.leave()
	_show_title_screen()

func _show_notice(message: String) -> void:
	_clear_dialog()
	interaction_dialog = Control.new()
	interaction_dialog.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	interaction_dialog.z_index = 1500
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.0, 0.0, 0.0, 0.5)
	interaction_dialog.add_child(shade)
	var panel := PanelContainer.new()
	panel.position = Vector2(120.0, 206.0)
	panel.size = Vector2(460.0, 112.0)
	interaction_dialog.add_child(panel)
	var rows := VBoxContainer.new()
	rows.alignment = BoxContainer.ALIGNMENT_CENTER
	rows.add_theme_constant_override("separation", 8)
	panel.add_child(rows)
	var text := _label(rows, message, Vector2.ZERO, Vector2(430.0, 54.0), 16, Color8(42, 41, 40))
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_text_button(rows, "OK", Vector2.ZERO, Vector2(120.0, 36.0)).pressed.connect(_clear_dialog)
	_attach_interaction_dialog()

func _attach_interaction_dialog() -> void:
	interaction_dialog_canvas = CanvasLayer.new()
	interaction_dialog_canvas.name = "InteractionDialogCanvas"
	interaction_dialog_canvas.layer = 10
	add_child(interaction_dialog_canvas)
	interaction_dialog_canvas.add_child(interaction_dialog)
	if current_room != null and is_instance_valid(current_room):
		current_room.set_controls_enabled(false)

func _adopt_source_menu_backdrop(view: Control) -> void:
	preload("res://src/presentation/source_menu_button_audio.gd").bind_tree(view)
	if not is_instance_valid(_menu_backdrop):
		_menu_backdrop = preload("res://src/presentation/source_campaign_menu_backdrop.gd").new()
		add_child(_menu_backdrop)
	_menu_backdrop.open_menu(view)

func _close_source_menu(route: Callable, to_exploration: bool = false) -> void:
	if _menu_navigation_active or not is_instance_valid(interaction_dialog):
		return
	if not to_exploration and route != Callable(self, "_clear_dialog") and bool(interaction_dialog.get_meta("source_shared_menu_backdrop", false)):
		# Source starts the next popup's entrance alongside the old popup's exit.
		# The route's _clear_dialog retains only the outgoing visual canvas.
		if route.is_valid():
			route.call()
		return
	_menu_navigation_active = true
	var closing := interaction_dialog
	if (to_exploration or route == Callable(self, "_clear_dialog")) and is_instance_valid(_menu_backdrop):
		_menu_backdrop.close_menu()
	var tween := SourceMenuTransition.exit(closing)
	tween.tween_callback(func() -> void:
		_menu_navigation_active = false
		if interaction_dialog == closing and route.is_valid():
			closing.set_meta("source_menu_exit_complete", true)
			route.call()
	)

func _retire_source_menu_canvas() -> bool:
	if not is_instance_valid(interaction_dialog_canvas) or not is_instance_valid(interaction_dialog):
		return false
	if interaction_dialog.get_parent() != interaction_dialog_canvas or interaction_dialog is BattleProgressionPresenter:
		return false # Socket selection explicitly retains its details backdrop.
	if not bool(interaction_dialog.get_meta("source_shared_menu_backdrop", false)) or bool(interaction_dialog.get_meta("source_menu_exit_complete", false)):
		return false
	var retiring := interaction_dialog_canvas
	_retiring_menu_canvases.append(retiring)
	_disable_retiring_menu_input(interaction_dialog)
	var fade := SourceMenuTransition.exit(interaction_dialog)
	fade.tween_callback(func() -> void:
		_retiring_menu_canvases.erase(retiring)
		if is_instance_valid(retiring):
			retiring.queue_free()
	)
	return true

func _disable_retiring_menu_input(node: Node) -> void:
	node.set_process_input(false)
	node.set_process_unhandled_input(false)
	node.set_process_unhandled_key_input(false)
	node.set_process(false)
	if node is Control:
		node.release_focus()
		node.focus_mode = Control.FOCUS_NONE
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if node is BaseButton:
		node.disabled = true
	if node is BattleMoveTooltip or (node is Control and node.name.to_lower().contains("tooltip")):
		node.hide()
	for child in node.get_children():
		_disable_retiring_menu_input(child)

func _clear_dialog(immediate: bool = false) -> void:
	if is_instance_valid(_menu_backdrop):
		_menu_backdrop.request_close_menu()
	_menu_navigation_active = false
	var retained := not immediate and _retire_source_menu_canvas()
	if retained:
		pass # The old canvas releases itself after its .5s exit and .1s cleanup.
	elif interaction_dialog_canvas != null and is_instance_valid(interaction_dialog_canvas):
		interaction_dialog_canvas.queue_free()
	elif interaction_dialog != null and is_instance_valid(interaction_dialog):
		interaction_dialog.queue_free()
	interaction_dialog_canvas = null
	interaction_dialog = null
	_source_dialogue_label = null
	_source_dialogue_scroller = null
	_source_dialogue_arrow = null
	_source_dialogue_yes = Callable()
	_source_dialogue_no = Callable()
	_source_dialogue_choices.clear()
	_source_dialogue_scale = Vector2.ONE
	_source_dialogue_scroll_step = SPEECH_TEXT_SCROLL_STEP
	_source_dialogue_content_height = 0.0
	_source_dialogue_is_animating = false
	_source_dialogue_on_complete = Callable()
	_sage_bonus_choice_pending = false
	if current_room != null and is_instance_valid(current_room):
		if runtime != null and runtime.session != null and runtime.session.state != null:
			current_room.update_campaign_progression(runtime.session.state.progression)
		current_room.set_controls_enabled(not _room_transition_active)

func _new_menu_screen() -> Control:
	_clear_game_screen()
	room_hud.visible = false
	var screen := Control.new()
	screen.name = "CurrentMenu"
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen_host.add_child(screen)
	current_screen = screen
	return screen

func _clear_game_screen() -> void:
	if is_instance_valid(_menu_backdrop):
		_menu_backdrop.reset()
	_pending_titan_rewards.clear()
	if is_instance_valid(_seal_fusion):
		_seal_fusion.cancel()
	if is_instance_valid(_reward_presenter):
		_reward_presenter.cancel()
	_clear_dialog(true)
	for retiring in _retiring_menu_canvases:
		if is_instance_valid(retiring):
			retiring.queue_free()
	_retiring_menu_canvases.clear()
	for child in screen_host.get_children():
		child.queue_free()
	current_screen = null
	current_room = null
	current_battle = null

func _add_title_background(parent: Control) -> void:
	var background := _texture_rect(TITLE_BACKGROUND)
	if background != null:
		background.position = Vector2(-30.0, -70.0)
		parent.add_child(background)

func _texture_rect(path: String) -> TextureRect:
	var texture := _load_texture(path)
	if texture == null:
		return null
	var rect := TextureRect.new()
	rect.texture = texture
	rect.size = texture.get_size()
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect

func _texture_button(parent: Control, path: String, at: Vector2) -> TextureButton:
	var texture := _load_texture(path)
	if texture == null:
		return null
	var button := TextureButton.new()
	button.texture_normal = texture
	button.texture_hover = texture
	button.texture_pressed = texture
	button.position = at
	button.size = texture.get_size()
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	parent.add_child(button)
	preload("res://src/presentation/source_menu_button_audio.gd").bind_button(button)
	return button

func _load_texture(path: String) -> Texture2D:
	return load(path) as Texture2D if ResourceLoader.exists(path) else null

func _text_button(parent: Control, text: String, at: Vector2, button_size: Vector2) -> Button:
	var button := Button.new()
	button.text = text
	button.position = at
	button.size = button_size
	button.custom_minimum_size = button_size
	button.add_theme_font_override("font", FONT)
	button.add_theme_font_size_override("font_size", 18)
	button.add_theme_color_override("font_color", Color8(247, 243, 222))
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color8(72, 77, 105)
	normal.border_color = Color8(200, 172, 94)
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(7)
	button.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color8(96, 96, 129)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	parent.add_child(button)
	preload("res://src/presentation/source_menu_button_audio.gd").bind_button(button)
	return button

func _label(parent: Control, text: String, at: Vector2, label_size: Vector2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.position = at
	label.size = label_size
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	parent.add_child(label)
	return label

func _line_edit_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color8(220, 220, 220)
	style.border_color = Color.BLACK
	style.set_border_width_all(1)
	style.content_margin_left = 2.0
	style.content_margin_right = 2.0
	return style

func _slot_title(slot: int) -> String:
	if runtime == null or runtime.session == null:
		return "Slot %d — Saved game" % slot
	var loaded: Dictionary = runtime.session.save_repository.load_slot(slot)
	if not loaded.get("ok", false):
		return "Slot %d — Saved game" % slot
	var character: Dictionary = loaded.state.get("character", {})
	var name := String(character.get("name", "Student"))
	var floor_index := int(loaded.state.get("progression", {}).get("floor_index", 0))
	var room_id := StringName(loaded.state.get("current_room_id", ""))
	var room := runtime.catalog.get_definition(room_id) as RoomDefinition if runtime.catalog != null else null
	if room != null:
		floor_index = int(room.minimap_metadata.get("floor_index", floor_index))
	return "%s — Floor %d" % [name, floor_index + 1]

func _as_vector2(value: Variant, fallback: Vector2) -> Vector2:
	if value is Vector2:
		return value
	if value is Array and value.size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	if value is Dictionary:
		return Vector2(float(value.get("x", fallback.x)), float(value.get("y", fallback.y)))
	if value is String:
		var serialized: String = String(value).trim_prefix("Vector2(").trim_suffix(")").trim_prefix("(").trim_suffix(")")
		var components: PackedStringArray = serialized.split(",")
		if components.size() >= 2 and components[0].strip_edges().is_valid_float() and components[1].strip_edges().is_valid_float():
			return Vector2(float(components[0]), float(components[1]))
	return fallback
