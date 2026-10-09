class_name SourceCampaignTutorialView
extends Control

signal completed

const FONT := preload("res://content/base/fonts/BurbinCasual.ttf")
const TEXT_COLOR := Color(0.97647, 0.98039, 0.97647)
const MODIFIER_TIPS := {
	"shield_modifier": ["Shield stones make random\nminions invulnerable", "modStone_shieldStone", Vector2(156, 203), 1.0],
	"move_timer_modifier": ["Extra move stones cast moves after so many turns. They can also give you passive buffs.", "modStone_extraMoveStone", Vector2(116, 184), 1.0],
	"extra_minions_modifier": ["Extra minion stones bring in \nextra minions on death.", "modStone_extraMinionOnDeathStone", Vector2(143, 193), 0.8],
	"resurrection_modifier": ["Resurection stones allow minions to be resurected after so many turns.", "undeadRoom_headstones1", Vector2(115, 197), 1.0],
}
var tutorial_id := ""
var page := 0
var _session: Variant
var _audio: BattleAudioController
var _root: Control
var _panel: Control
var _content: Control
var _background: TextureRect
var _button: TextureButton
var _transitioning := false

func configure(session, id: String, audio: BattleAudioController = null) -> void:
	_session = session
	tutorial_id = id
	_audio = audio
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 4000
	var viewport_size := get_viewport_rect().size
	var scale_factor := minf(viewport_size.x / 700.0, viewport_size.y / 525.0)
	_root = Control.new()
	_root.size = Vector2(700, 525)
	_root.position = (viewport_size - _root.size * scale_factor) * 0.5
	_root.scale = Vector2.ONE * scale_factor
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_panel = Control.new()
	_root.add_child(_panel)
	var small := tutorial_id in ["boss_room", "focus_targets", "key_keepers", "reset_talents_first", "reset_talents_second"]
	_background = SourceMenuArt.image(_panel, "tutorial_backgroundSmall" if small else "tutorial_backgroundLarge", Vector2(0, 66 if small else 0))
	_panel.size = _background.position + _background.size
	_panel.pivot_offset = Vector2(_background.size.x * 0.5, _background.position.y + _background.size.y * 0.5)
	_panel.position = Vector2(164, 38) - _panel.pivot_offset * 0.1
	_panel.scale = Vector2.ONE * 0.9
	_panel.modulate.a = 0.0
	_build_page()
	var entrance := create_tween().set_parallel(true)
	entrance.tween_property(_panel, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	entrance.tween_property(_panel, "modulate:a", 1.0, 0.4)
	if is_instance_valid(_audio):
		_audio.play_sound("battle_whoosh_falling_deepSound")

func _input(event: InputEvent) -> void:
	# The source tutorials advance through their buttons, not Space/Escape.
	if visible and event is InputEventKey:
		get_viewport().set_input_as_handled()

func _build_page() -> void:
	if is_instance_valid(_content):
		_panel.remove_child(_content)
		_content.queue_free()
	_content = Control.new()
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_content)
	match tutorial_id:
		"battle_basics":
			match page:
				0:
					_text("Battle Basics", Vector2(20, 97), 380, 28)
					_text("The minions on the left are yours\nthe minions on the right are your opponents", Vector2(30, 136), 353, 15)
					_art("tutorial_yourThierMinionBackground", Vector2(33, 195))
				1:
					_text("Turn order", Vector2(20, 97), 380, 28)
					_text("These boxes show the minion turn order", Vector2(30, 136), 353, 15)
					_art("tutorial_yourMinionBackground", Vector2(67, 169))
					_arrow(Vector2(49, 218), 50)
					_text("Tip: Turn order is based on how much speed a minion has", Vector2(0, 364), _background.size.x, 13)
				2:
					_text("Health Bar", Vector2(20, 97), 380, 28)
					_text("The red bar shows how much health a minion has", Vector2(30, 136), 353, 15)
					_art("tutorial_bigHealthBar", Vector2(114, 165))
					_art("tutorial_yourMinionHealth", Vector2(124, 236))
					var arrow := _arrow(Vector2(345, 227), -50)
					arrow.scale.x = -1.0
					arrow.set_meta("source_exit_x", 50.0)
		"boss_room":
			_text("Find and challenge the Minor Sage to get the\nfirst piece of the Sage Seal of Courage.", Vector2(20, 181), 380, 16)
			_art("tutorial_bossDoor", Vector2(140, 232))
		"focus_targets":
			_text("Battle Tip", Vector2(20, 163), 380, 28)
			_text("Focus targets:  Sometimes it’s best to focus all your attacks on one minion", Vector2(30, 202), 353, 15)
			var focus := _art("tutorial_focusTarget", Vector2(115, 105))
			focus.set_meta("source_exit_y", -50.0)
			create_tween().tween_property(focus, "position:y", 155.0, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		"energy":
			_text("Energy", Vector2(20, 97), 380, 28)
			_text("The blue bar shows how much energy a minion has", Vector2(30, 136), 353, 15)
			# TutorialHandler explicitly leaves its bigEnergyBar sprite invisible.
			_art("tutorial_energyBarBackground", Vector2(94, 181))
			var arrow := _art("tutorial_energyBarArrow", Vector2(130, 241))
			arrow.scale.x = -1.0
			arrow.set_meta("source_exit_x", -50.0)
			create_tween().tween_property(arrow, "position:x", 180.0, 0.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			_text("Tip:  Each move uses energy and if you run out,\nyou won’t be able to use your moves", Vector2(15, 336), _background.size.x - 30, 14)
		"key_keepers":
			_text("To complete this floor you must defeat all three\nstudents for their keys to the Minor Sage's room.", Vector2(20, 175), 380, 14)
			_art("tutorial_keyKeeper1", Vector2(49, 222))
		"tank":
			_text("Battle Tip", Vector2(20, 97), 380, 28)
			_text("Protect your fragile minions with a redirect damage and high health/armor minion", Vector2(30, 136), 353, 15)
			var tank := _art("tutorial_useATank", Vector2(49, 48))
			tank.set_meta("source_exit_y", -50.0)
			create_tween().tween_property(tank, "position:y", 98.0, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		"reset_talents_first", "reset_talents_second":
			_text("Battle Tip", Vector2(20, 163), 380, 28)
			_text("If a fight is giving you a hard time try and choose better moves for the fight by reseting your skill trees", Vector2(30, 202), 353, 13)
			_art("tutorial_resetTalentPointsIcon", Vector2(163, 247))
			_text("Tip: You can access your skill tree\nat any time in the menu", Vector2(0, 306), SourceMenuArt.texture("tutorial_backgroundLarge").get_width(), 14)
		"type_effectiveness":
			_text("Battle Tip", Vector2(20, 115), 380, 28)
			_text("Move choice:  Some moves do more damage to certain types of minions", Vector2(30, 154), 353, 15)
			_text("Example", Vector2(132, 220), 150, 24)
			_text("Fire moves do more damage to plant minions", Vector2(-3, 255), _background.size.x, 15)
			_art("tutorial_superEffectiveMoves", Vector2(52, 279))
		_:
			if MODIFIER_TIPS.has(tutorial_id):
				var tip: Array = MODIFIER_TIPS[tutorial_id]
				_text("Battle Tip", Vector2(20, 97), 380, 28)
				_text(String(tip[0]), Vector2(30, 136), 353, 15)
				_art(String(tip[1]), tip[2]).scale = Vector2.ONE * float(tip[3])
	_button = SourceMenuArt.button(_content, "tutorial_nextButton" if tutorial_id == "battle_basics" and page < 2 else "tutorial_okButton", Vector2(143, _background.position.y + _background.size.y - 75), _advance)
	_button.name = "TutorialAdvance"
	_content.modulate.a = 0.0
	create_tween().tween_property(_content, "modulate:a", 1.0, 0.5)

func _text(value: String, at: Vector2, width: float, font_size: int) -> Label:
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.text = value
	label.position = at + Vector2(2, 2)
	label.size = Vector2(width, 30)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", TEXT_COLOR)
	label.size = Vector2(width, 30)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(label)
	return label

func _art(symbol: String, at: Vector2) -> TextureRect:
	return SourceMenuArt.image(_content, symbol, at)

func _arrow(at: Vector2, distance: float) -> TextureRect:
	var arrow := _art("tutorial_yourMinionArrow", at)
	create_tween().tween_property(arrow, "position:x", at.x + distance, 0.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	return arrow

func _advance() -> void:
	if _transitioning:
		return
	if tutorial_id == "battle_basics" and page < 2:
		_transitioning = true
		var fade := create_tween()
		fade.tween_property(_content, "modulate:a", 0.0, 0.5)
		fade.tween_callback(func() -> void:
			page += 1
			_build_page()
			_transitioning = false
		)
		return
	var result: Dictionary = _session.acknowledge_source_tutorial(tutorial_id)
	if not result.ok:
		if _content.get_node_or_null("TutorialSaveError") == null:
			var error := _text("Could not save. Press OK to retry.", Vector2(20, _button.position.y - 28), 380, 14)
			error.name = "TutorialSaveError"
			error.add_theme_color_override("font_color", Color.hex(0xed5e5eff))
		return
	_transitioning = true
	for child in _content.get_children():
		if child.has_meta("source_exit_x"):
			create_tween().tween_property(child, "position:x", child.position.x + float(child.get_meta("source_exit_x")), 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		if child.has_meta("source_exit_y"):
			create_tween().tween_property(child, "position:y", child.position.y + float(child.get_meta("source_exit_y")), 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	var exit_tween := create_tween()
	exit_tween.tween_property(_panel, "modulate:a", 0.0, 0.5)
	exit_tween.tween_callback(func() -> void:
		completed.emit()
		queue_free()
	)
