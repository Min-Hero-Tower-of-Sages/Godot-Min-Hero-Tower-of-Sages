class_name CampaignFloorSelectView
extends Control

signal floor_selected(floor_index: int)
signal mode_selected(mode: StringName)
signal closed

const FONT: Font = preload("res://content/base/fonts/BurbinCasual.ttf")
const SCREEN_SIZE := Vector2(700.0, 525.0)
const FLOOR_COUNT := 31
const MAX_PAGE := 9
const ITEMS_PER_SCROLL := 3
const ROW_SPACING := 94.0
const SCREEN_SCROLL := 93.0 * ITEMS_PER_SCROLL
const CLOUD_X := [20.0, 380.0, -90.0, 300.0]

var _session: Variant
var _root: Control
var _clouds: Array[TextureRect] = []
var _cloud_scales: Array[float] = []
var _floor_rows: Array[Control] = []
var _info_rows: Array[Control] = []
var _page := 0
var _max_page := 0
var _mode: StringName = &"standard"
var _mountains: TextureRect
var _sky: TextureRect
var _stars: TextureRect
var _up_arrow: TextureButton
var _down_arrow: TextureButton
var _page_tween: Tween
var _audio: BattleAudioController
var _insertion_floor := -1
var _compress_insertion := false
var _insertion_active := false
var _tutorial: Control
var _tutorial_closing := false

func configure(session, audio: BattleAudioController = null) -> void:
	_session = session
	_audio = audio
	if _session != null and _session.state != null:
		_mode = CampaignTowerModeService.selected_mode(_session.state)
		_page = _initial_page_for_mode()
		if _mode == &"standard":
			for value in _session.state.progression.get("pending_optional_floor_reveals", []):
				var floor_index := int(value)
				if floor_index in [3, 8, 13, 18] and CampaignTowerModeService.floor_is_unlocked(_session.state, floor_index, &"standard"):
					_insertion_floor = floor_index
					_compress_insertion = true
					_page = [0, 2, 4, 5][[3, 8, 13, 18].find(floor_index)]
					break
	if is_inside_tree():
		_render()

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	focus_mode = Control.FOCUS_ALL
	grab_focus()
	if _session != null:
		_render()

func _process(delta: float) -> void:
	for index in _clouds.size():
		var cloud := _clouds[index]
		cloud.position.x += 0.4 * _cloud_scales[index] * delta * 60.0
		if cloud.position.x > SCREEN_SIZE.x:
			cloud.position.x = -cloud.size.x

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE):
		_request_close()
		get_viewport().set_input_as_handled()

func _render() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_clouds.clear()
	_cloud_scales.clear()
	_floor_rows.clear()
	_info_rows.clear()
	if _session == null or _session.state == null or _session.catalog == null or _session.campaign == null:
		return
	var viewport_size := get_viewport_rect().size
	var scale_factor := minf(viewport_size.x / SCREEN_SIZE.x, viewport_size.y / SCREEN_SIZE.y)
	_root = Control.new()
	_root.position = (viewport_size - SCREEN_SIZE * scale_factor) * 0.5
	_root.size = SCREEN_SIZE
	_root.scale = Vector2.ONE * scale_factor
	add_child(_root)
	var blue := ColorRect.new()
	blue.size = SCREEN_SIZE
	blue.color = Color8(6, 55, 115)
	blue.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(blue)
	var stars := _image(_root, "roomSelect_background_stars", Vector2.ZERO)
	_stars = stars
	if stars != null:
		stars.size = SCREEN_SIZE
		stars.modulate.a = _stars_alpha()
	var sky := _image(_root, "battleScreenBackground_sky", Vector2.ZERO)
	_sky = sky
	if sky != null:
		sky.size = SCREEN_SIZE
		sky.modulate.a = _clouds_alpha()
	_build_clouds()
	var mountains := _image(_root, "roomSelect_background_frontMountains", Vector2(0.0, 119.0 + _page * 0.75 * 93.0))
	_mountains = mountains
	if mountains != null:
		mountains.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_floor_rows()
	var return_button := _button(_root, "roomSelect_returnButton", Vector2(592.0, -2.0), _request_close)
	if return_button != null:
		return_button.tooltip_text = "Return to the tower lobby"
	_build_page_arrows()
	_build_mode_buttons()
	if _insertion_floor >= 0:
		_play_optional_floor_insertion()

func _request_close() -> void:
	if not _insertion_active:
		closed.emit()

func _play_optional_floor_insertion() -> void:
	_insertion_active = true
	_compress_insertion = false
	for tile in _floor_rows:
		_shake_tower_piece(tile)
		var floor_index := int(tile.get_meta("source_floor"))
		if floor_index >= _insertion_floor:
			create_tween().tween_property(tile, "position:y", _row_y(floor_index, 329.0), 1.8).set_delay(1.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	for info in _info_rows:
		var floor_index := int(info.get_meta("source_floor"))
		if floor_index == _insertion_floor:
			info.visible = false
		if floor_index >= _insertion_floor:
			create_tween().tween_property(info, "position:y", _row_y(floor_index, 354.0), 1.8).set_delay(1.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if is_instance_valid(_mountains):
		_shake_tower_piece(_mountains)
	var sequence := create_tween()
	sequence.tween_interval(0.4)
	sequence.tween_callback(func() -> void:
		if is_instance_valid(_audio):
			_audio.play_sound("battle_earthquake2")
	)
	sequence.tween_interval(2.8)
	sequence.tween_callback(_finish_optional_floor_insertion)

func _shake_tower_piece(piece: Control) -> void:
	var origin := piece.position.x
	var shake := create_tween()
	shake.tween_interval(1.0)
	for index in 16:
		shake.tween_property(piece, "position:x", origin - 4.0 if index % 2 == 0 else origin, 0.125).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _finish_optional_floor_insertion() -> void:
	for info in _info_rows:
		if int(info.get_meta("source_floor")) == _insertion_floor:
			info.visible = true
			info.modulate.a = 0.0
			create_tween().tween_property(info, "modulate:a", 1.0, 0.5)
	if bool(_session.state.progression.get("bonus_floor_tutorial_seen", false)):
		_complete_optional_reveal(false)
	else:
		var delay := create_tween()
		delay.tween_interval(1.5)
		delay.tween_callback(_show_bonus_floor_tutorial)

func _show_bonus_floor_tutorial() -> void:
	_tutorial = Control.new()
	_tutorial.name = "BonusFloorTutorial"
	_tutorial.position = Vector2(164, 38)
	_root.add_child(_tutorial)
	var background := _image(_tutorial, "tutorial_backgroundSmall", Vector2(0, 66))
	var title := _label(_tutorial, "Bonus floors have a chance\nto drop rare minions", Vector2(20, 175), Vector2(380, 60), 18, Color.hex(0xf9faf9ff))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_image(_tutorial, "tutorial_bonusRooms", Vector2(132, 236))
	var button := _button(_tutorial, "tutorial_okButton", Vector2(143, 66 + background.size.y - 75), _dismiss_bonus_floor_tutorial)
	button.name = "BonusTutorialOK"
	_tutorial.size = Vector2(background.size.x, 66 + background.size.y)
	# The visible source bounds start at y=66, not at the Sprite origin.
	# Preserve transformAroundCenter's authored .9-scale origin (164,38).
	_tutorial.pivot_offset = Vector2(background.size.x * 0.5, 66 + background.size.y * 0.5)
	_tutorial.position -= _tutorial.pivot_offset * 0.1
	_tutorial.scale = Vector2.ONE * 0.9
	_tutorial.modulate.a = 0.0
	var entrance := create_tween().set_parallel(true)
	entrance.tween_property(_tutorial, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	entrance.tween_property(_tutorial, "modulate:a", 1.0, 0.4)
	if is_instance_valid(_audio):
		_audio.play_sound("battle_whoosh_falling_deepSound")

func _dismiss_bonus_floor_tutorial() -> void:
	if _tutorial_closing:
		return
	if not _complete_optional_reveal(true):
		return
	_tutorial_closing = true
	_insertion_active = true # Guard through the half-second tutorial fade.
	var exit_tween := create_tween()
	exit_tween.tween_property(_tutorial, "modulate:a", 0.0, 0.5)
	exit_tween.tween_callback(func() -> void:
		_tutorial.queue_free()
		_tutorial = null
		_insertion_active = false
	)

func _complete_optional_reveal(tutorial_seen: bool) -> bool:
	var result: Dictionary = _session.complete_optional_floor_reveal(_insertion_floor, tutorial_seen)
	if not result.ok:
		if is_instance_valid(_tutorial):
			if _tutorial.get_node_or_null("SaveError") == null:
				var message := _label(_tutorial, "Could not save. Press OK to retry.", Vector2(20, 310), Vector2(380, 28), 14, Color.hex(0xed5e5eff))
				message.name = "SaveError"
				message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		else:
			_show_bonus_floor_tutorial()
		return false
	_insertion_floor = -1
	_insertion_active = false
	return true

func _build_clouds() -> void:
	for index in CLOUD_X.size():
		var cloud := _image(_root, "battleScreenBackground_clouds", Vector2(CLOUD_X[index], _cloud_y(index)))
		if cloud == null:
			continue
		var scale := 0.7 - index * 0.07
		cloud.scale = Vector2.ONE * scale
		cloud.size = cloud.texture.get_size()
		cloud.modulate.a = 1.0
		cloud.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_clouds.append(cloud)
		_cloud_scales.append(scale)

func _build_floor_rows() -> void:
	var current_floor := int(_session.state.progression.get("floor_index", 0))
	var unlocked_values := CampaignTowerModeService.unlocked_display_indices(_session.state, _mode)
	var highest_unlocked: int = int(unlocked_values.back()) if not unlocked_values.is_empty() else 0
	_max_page = clampi(floori(float(highest_unlocked) / float(ITEMS_PER_SCROLL)), 0, MAX_PAGE)
	_page = clampi(_page, 0, _max_page)
	var star_ratings: Dictionary = _session.state.progression.get("encounter_star_ratings", {})
	for floor_index in FLOOR_COUNT:
		if _optional_floor_hidden(floor_index):
			continue
		var floor_data := _floor_info(floor_index)
		var migrated := CampaignTowerModeService.floor_has_mode_content(_session.catalog, _session.campaign, floor_index, _mode)
		var unlocked := CampaignTowerModeService.floor_is_unlocked(_session.state, floor_index, _mode)
		var tile := Control.new()
		tile.position = Vector2(114.0, _row_y(floor_index, 329.0))
		tile.set_meta("source_floor", floor_index)
		tile.size = Vector2(150.0, 90.0)
		tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_root.add_child(tile)
		_floor_rows.append(tile)
		_build_floor_tile(tile, floor_index, unlocked and migrated)
		_add_player_tags(tile, CampaignTowerModeService.tower_floor_index(floor_index, _mode))
		if not unlocked or not migrated:
			continue
		var info := Control.new()
		info.position = Vector2(312.0, _row_y(floor_index, 354.0))
		info.set_meta("source_floor", floor_index)
		info.size = Vector2(200.0, 55.0)
		_root.add_child(info)
		_info_rows.append(info)
		_build_floor_info(info, floor_index, floor_data, current_floor, star_ratings, unlocked, migrated)

## Multiplayer: names of the other players on this floor, left of its tile.
func _add_player_tags(tile: Control, global_floor: int) -> void:
	var net: Node = get_node_or_null("/root/NetSession")
	if net == null or not net.is_active():
		return
	var names: Array[int] = []
	for peer_id in net.other_player_ids():
		var where: Dictionary = net.player_location(peer_id)
		if not where.is_empty() and not bool(where.get("lobby", false)) and int(where.get("floor", -1)) == global_floor:
			names.append(peer_id)
	for index in mini(names.size(), 3):
		var tag := Label.new()
		tag.text = net.player_name(names[index]) if index < 2 or names.size() == 3 else "+%d more" % (names.size() - 2)
		tag.position = Vector2(-112.0, 18.0 + 20.0 * float(index))
		tag.size = Vector2(106.0, 20.0)
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		tag.clip_text = true
		tag.add_theme_font_override("font", MultiplayerUi.FONT)
		tag.add_theme_font_size_override("font_size", 15)
		tag.add_theme_color_override("font_color", net.player_color(names[index]) if index < 2 or names.size() == 3 else Color.WHITE)
		tag.add_theme_color_override("font_outline_color", Color(0.06, 0.05, 0.1, 0.95))
		tag.add_theme_constant_override("outline_size", 4)
		tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tile.add_child(tag)

func _build_floor_tile(parent: Control, floor_index: int, unlocked: bool) -> void:
	var room_asset := _floor_room_asset(floor_index)
	var room := _image(parent, room_asset, Vector2.ZERO)
	if room == null:
		return
	if floor_index == 30:
		var sage := _image(parent, "roomSelect_grandSageIcon", Vector2(52.0, -26.0))
		if sage != null:
			sage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	elif floor_index % 5 == 4:
		var medal_symbols := ["generalRoom_plantMedallionStatue", "generalRoom_fireMedallionStatue", "generalRoom_electricMedallionStatue", "generalRoom_undeadMedallionStatue", "generalRoom_plantWizardMedallionStatue", "generalRoom_undeadWizardMedallionStatue"]
		var level_number := floori(float(floor_index) / 5.0)
		var sage := _image(parent, medal_symbols[mini(level_number, medal_symbols.size() - 1)], Vector2(80.0, 32.0))
		if sage != null:
			sage.scale = Vector2.ONE * 0.8
	elif floor_index % 5 == 3 and floori(float(floor_index) / 5.0) < 4:
		var rare_symbols := ["roomSelect_grassRares", "roomSelect_fireRares", "roomSelect_electricRares", "roomSelect_undeadRares"]
		var rare := _image(parent, rare_symbols[floori(float(floor_index) / 5.0)], Vector2(26.0, 20.0))
		if rare != null:
			rare.scale = Vector2.ONE * 0.8
	elif unlocked:
		_add_floor_number(parent, floor_index)
	var new_floor := unlocked and _mode == &"standard" and CampaignTowerModeService.floor_star_count(_session.state, _session.catalog, _session.campaign, floor_index, _mode) == 0
	if not unlocked or new_floor:
		var cover := _image(parent, "roomSelect_towerCovered", Vector2(25.0, 8.0))
		if cover != null:
			cover.scale.y = 0.99
		var lock := _image(parent, "roomSelect_towerCoveredLock", Vector2(83.0, 16.0))
		if lock != null:
			lock.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if new_floor:
			if cover != null:
				create_tween().tween_property(cover, "scale:y", 0.0, 0.9).set_delay(2.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			if lock != null:
				create_tween().tween_property(lock, "modulate:a", 0.0, 0.5).set_delay(2.2)
			var sound := create_tween()
			sound.tween_interval(2.0)
			sound.tween_callback(func() -> void:
				if is_instance_valid(_audio):
					_audio.play_sound("tower_doorUnlock")
			)

func _add_floor_number(parent: Control, floor_index: int) -> void:
	var tower_level := floor_index / 5 + 1
	var floor_number := floor_index % 5 + 1
	var chars := "%dz%d" % [tower_level, floor_number]
	var digit_nodes: Array[TextureRect] = []
	for character in chars:
		var digit := _image(parent, "roomSelect_roomFont_%s" % character, Vector2.ZERO)
		if digit == null:
			continue
		digit_nodes.append(digit)
	var text_width := 0.0
	for index in digit_nodes.size():
		text_width += digit_nodes[index].texture.get_width()
		if index > 0:
			text_width += 5.0
	var x := 105.0 - text_width * 0.9 * 0.5
	for index in digit_nodes.size():
		var digit := digit_nodes[index]
		digit.scale = Vector2.ONE * 0.9
		digit.position = Vector2(x, 28.0 + (18.9 if index == 1 else 0.0))
		x += (digit.texture.get_width() + 5.0) * 0.9
		if _mode == &"standard" and CampaignTowerModeService.floor_star_count(_session.state, _session.catalog, _session.campaign, floor_index, _mode) == 0:
			digit.modulate.a = 0.0
			create_tween().tween_property(digit, "modulate:a", 1.0, 0.9).set_delay(3.3)

func _build_floor_info(parent: Control, floor_index: int, floor_data: Dictionary, current_floor: int, ratings: Dictionary, unlocked: bool, migrated: bool) -> void:
	_image(parent, "roomSelect_roomInformationBackground", Vector2.ZERO)
	var global_floor := CampaignTowerModeService.tower_floor_index(floor_index, _mode)
	var max_stars := 18 if _mode == &"hard" else 12
	if floor_index % 5 == 4 or floor_index == 30:
		max_stars = 3
	var stars := CampaignTowerModeService.floor_star_count(_session.state, _session.catalog, _session.campaign, floor_index, _mode) if migrated else 0
	var star_icon := _image(parent, "roomSelect_roomInformationStars", Vector2(24.0, 11.0))
	var star_label := _label(parent, "%d/%d" % [stars, max_stars], Vector2(55.0, 10.0), Vector2(86.0, 32.0), 21, Color8(243, 243, 243))
	if stars == max_stars:
		star_label.add_theme_color_override("font_color", Color8(71, 119, 91))
	var is_current := current_floor == global_floor
	if unlocked and stars == 0:
		var new_icon := _image(parent, "roomSelect_roomInformationNewIcon", Vector2(164.0, 8.0))
		parent.position.x += 50.0
		parent.modulate.a = 0.0
		var reveal := create_tween().set_parallel(true)
		reveal.tween_property(parent, "position:x", 312.0, 1.0).set_delay(0.9).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		reveal.tween_property(parent, "modulate:a", 1.0, 1.0).set_delay(0.9)
		if new_icon != null:
			new_icon.modulate.a = 0.0
			reveal.tween_property(new_icon, "modulate:a", 1.0, 0.5).set_delay(3.3)
			var pulse := create_tween().set_loops()
			pulse.tween_property(new_icon, "position:x", 174.0, 0.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			pulse.tween_property(new_icon, "position:x", 164.0, 0.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if is_current and unlocked:
		var marker := _image(parent, "roomSelect_tempCharIcon", Vector2(176.0, 0.0))
		var gender := String(_session.state.character.get("gender", "male"))
		_image(marker, "roomSelect_femaleIcon" if gender == "female" else "roomSelect_maleIcon", Vector2(13.0, 7.0))
	if unlocked and migrated:
		var go := _button(parent, "roomSelect_roomInformationGoButton", Vector2(124.0, 11.0), Callable(self, "_choose_floor").bind(global_floor))
		if go != null:
			go.tooltip_text = "Enter Floor %d" % (floor_index + 1)
	else:
		var explanation := "Locked" if migrated else "Floor content is not available in this port yet"
		var note := _label(parent, explanation, Vector2(55.0, 34.0), Vector2(175.0, 22.0), 12, Color8(245, 224, 183))
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func _build_page_arrows() -> void:
	var arrow := SourceMenuArt.texture("roomSelect_upArrow")
	if arrow == null:
		return
	_up_arrow = _button(_root, "roomSelect_upArrow", Vector2(543.0, 4.0), Callable(self, "_change_page").bind(1))
	_down_arrow = _button(_root, "roomSelect_upArrow", Vector2(543.0, 504.0), Callable(self, "_change_page").bind(-1))
	if _down_arrow != null:
		_down_arrow.scale.y = -1.0
	_update_arrows()

func _update_arrows() -> void:
	if is_instance_valid(_up_arrow):
		_up_arrow.visible = _page < _max_page
	if is_instance_valid(_down_arrow):
		_down_arrow.visible = _page > 0

func _optional_floor_hidden(floor_index: int) -> bool:
	return floor_index in [3, 8, 13, 18] and not CampaignTowerModeService.floor_is_unlocked(_session.state, floor_index, &"standard")

func _row_y(floor_index: int, base: float) -> float:
	var height_index := floor_index
	for optional_floor in [3, 8, 13, 18]:
		if floor_index >= optional_floor and (_optional_floor_hidden(optional_floor) or _compress_insertion and optional_floor == _insertion_floor):
			height_index -= 1
	return base - height_index * ROW_SPACING + SCREEN_SCROLL * _page

func _build_mode_buttons() -> void:
	if not CampaignTowerModeService.hard_mode_unlocked(_session.state):
		return
	var normal_position := Vector2(610.0, 358.0)
	var hard_position := Vector2(610.0, 424.0)
	if _mode == &"standard":
		_image(_root, "roomSelect_normalModeButton", normal_position)
		var hard := _button(_root, "roomSelect_hardModeButton_off", hard_position, Callable(self, "_select_mode").bind(&"hard"))
		if hard != null:
			hard.texture_hover = SourceMenuArt.texture("roomSelect_hardModeButton")
			hard.texture_pressed = hard.texture_hover
	else:
		_image(_root, "roomSelect_hardModeButton", hard_position)
		var normal := _button(_root, "roomSelect_normalModeButton_off", normal_position, Callable(self, "_select_mode").bind(&"standard"))
		if normal != null:
			normal.texture_hover = SourceMenuArt.texture("roomSelect_normalModeButton")
			normal.texture_pressed = normal.texture_hover

func _select_mode(mode: StringName) -> void:
	if _insertion_active:
		return
	if mode == _mode:
		return
	if mode == &"hard" and not CampaignTowerModeService.hard_mode_unlocked(_session.state):
		return
	_mode = mode
	_page = _initial_page_for_mode()
	mode_selected.emit(mode)

func _initial_page_for_mode() -> int:
	var unlocked := CampaignTowerModeService.unlocked_display_indices(_session.state, _mode)
	return clampi(floori(float(maxi(0, unlocked.size() - 1)) / float(ITEMS_PER_SCROLL)), 0, MAX_PAGE)

func _floor_info(floor_index: int) -> Dictionary:
	for floor_data in _session.campaign.floors:
		if int(floor_data.get("floor_index", -1)) == floor_index:
			return floor_data
	return {}

func _floor_star_count(floor_index: int, floor_data: Dictionary, ratings: Dictionary) -> int:
	var encounter_ids: Dictionary = {}
	for room_id in floor_data.get("room_ids", []):
		var room := _session.catalog.get_definition(StringName(room_id)) as RoomDefinition
		if room == null:
			continue
		for encounter_id in room.encounter_ids:
			encounter_ids[String(encounter_id)] = true
	var total := 0
	for encounter_id in encounter_ids:
		total += clampi(int(ratings.get(encounter_id, 0)), 0, 3)
	return mini(3 if floor_index % 5 == 4 or floor_index == 30 else 12, total)

func _floor_room_asset(floor_index: int) -> String:
	if floor_index > 29:
		return "roomSelect_towerTop"
	if floor_index > 26:
		return "roomSelect_undeadRoom"
	if floor_index > 24:
		return "roomSelect_electricRoom"
	if floor_index > 23:
		return "roomSelect_plantRoom"
	if floor_index > 21:
		return "roomSelect_fireRoom"
	if floor_index > 19:
		return "roomSelect_plantRoom"
	if floor_index > 14:
		return "roomSelect_undeadRoom"
	if floor_index > 9:
		return "roomSelect_electricRoom"
	if floor_index > 4:
		return "roomSelect_fireRoom"
	return "roomSelect_plantRoom"

func _choose_floor(floor_index: int) -> void:
	if _insertion_active:
		return
	var source_floor := CampaignTowerModeService.source_floor_index(floor_index)
	if not CampaignTowerModeService.floor_is_unlocked(_session.state, source_floor, _mode):
		return
	if not CampaignTowerModeService.floor_has_mode_content(_session.catalog, _session.campaign, source_floor, _mode):
		return
	floor_selected.emit(floor_index)

func _change_page(step: int) -> void:
	if _insertion_active:
		return
	_page = clampi(_page + step, 0, _max_page)
	_update_arrows()
	if is_instance_valid(_page_tween):
		_page_tween.kill()
	_page_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	for tile in _floor_rows:
		_page_tween.tween_property(tile, "position:y", _row_y(int(tile.get_meta("source_floor")), 329.0), 1.0)
	for info in _info_rows:
		_page_tween.tween_property(info, "position:y", _row_y(int(info.get_meta("source_floor")), 354.0), 1.0)
	if is_instance_valid(_mountains):
		_page_tween.tween_property(_mountains, "position:y", 119.0 + _page * 0.75 * 93.0, 1.0)
	if is_instance_valid(_sky):
		_page_tween.tween_property(_sky, "modulate:a", _clouds_alpha(), 1.0)
	if is_instance_valid(_stars):
		_page_tween.tween_property(_stars, "modulate:a", _stars_alpha(), 1.0)
	for index in _clouds.size():
		_page_tween.tween_property(_clouds[index], "position:y", _cloud_y(index), 1.0)

func _cloud_y(index: int) -> float:
	return 110.0 - index * 50.0 + _page * 0.75 * 93.0

func _clouds_alpha() -> float:
	return clampf(1.0 - float(_page - 3) / 6.0, 0.0, 1.0)

func _stars_alpha() -> float:
	return clampf(float(_page - 6) / 3.0, 0.0, 1.0)

func _image(parent: Control, symbol: String, at: Vector2) -> TextureRect:
	if parent == null:
		return null
	var texture := SourceMenuArt.texture(symbol)
	if texture == null:
		return null
	var rect := TextureRect.new()
	rect.texture = texture
	rect.position = at
	rect.size = texture.get_size()
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(rect)
	return rect

func _button(parent: Control, symbol: String, at: Vector2, action: Callable) -> TextureButton:
	var texture := SourceMenuArt.texture(symbol)
	if texture == null:
		return null
	var button := TextureButton.new()
	button.texture_normal = texture
	button.texture_hover = texture
	button.texture_pressed = texture
	button.position = at
	button.size = texture.get_size()
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func _label(parent: Control, value: String, at: Vector2, label_size: Vector2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.position = at + Vector2(2, 2)
	label.size = label_size
	label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label
