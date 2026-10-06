extends Control

const FONT := preload("res://content/base/fonts/BurbinCasual.ttf")
const POPUP := preload("res://src/presentation/source_tutorial_popup.gd")
const FAMILY_OFFSETS := [Vector2(13, 3), Vector2(21, 1), Vector2(20, -4), Vector2(12, -8), Vector2(18, 6), Vector2(5, 8)]
var _seal_background: TextureRect
var _seal_icon: TextureRect
var _seal_count: Label
var _talent_hint: TextureRect
var _gem_hint: TextureRect
var _star_hint: TextureRect
var _previous_highest := -99
var _drawer_tween: Tween

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_seal_background = SourceMenuArt.image(self, "hud_sealPiecesBackground", Vector2(391, 490))
	if _seal_background != null:
		_seal_icon = SourceMenuArt.image(_seal_background, "sageSeal_1_1", FAMILY_OFFSETS[0])
		_seal_count = Label.new()
		_seal_count.name = "SealPieceCount"
		_seal_count.position = Vector2(-12, -1)
		_seal_count.size = Vector2(150, 32)
		_seal_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_seal_count.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_seal_count.add_theme_font_override("font", FONT)
		_seal_count.add_theme_font_size_override("font_size", 25)
		_seal_count.add_theme_color_override("font_color", Color8(229, 232, 232))
		_seal_background.add_child(_seal_count)
	_talent_hint = _hint("tutorial_newTalentPointsPopup", Vector2(582, 429))
	_gem_hint = _hint("tutorial_firstGemMenuPopup", Vector2(604, 436))
	_star_hint = _hint("tutorial_newStars_top", Vector2(606, 436))

func _hint(symbol: String, at: Vector2) -> TextureRect:
	var popup := POPUP.new()
	popup.position = at
	popup.z_index = 2
	add_child(popup)
	popup.configure(symbol)
	popup.hide()
	return popup

func sync(progression: Dictionary, show_talents: bool, show_gems: bool, show_stars: bool, movement_enabled: bool) -> void:
	_talent_hint.visible = movement_enabled and show_talents
	_gem_hint.visible = movement_enabled and not show_talents and show_gems
	_star_hint.visible = movement_enabled and not show_talents and not show_gems and show_stars
	var highest := 0
	for floor_index in progression.get("unlocked_floor_indices", [0]):
		highest = maxi(highest, int(floor_index) + 1)
	if highest == _previous_highest or _seal_background == null:
		return
	if highest >= 31:
		_slide_drawer(391, 0.0)
	else:
		var family := maxi(1, ceili(float(highest) / 5.0))
		var remainder := highest % 5
		var pieces := 1 if remainder == 2 else 2 if remainder == 3 else 3 if remainder == 0 else 0
		if highest > 20:
			pieces = 3 if remainder == 4 else 4 if remainder == 0 else pieces
		_seal_count.text = "x%d" % pieces
		if _seal_icon != null:
			_seal_icon.texture = SourceMenuArt.texture("sageSeal_%d_1" % family)
			_seal_icon.position = FAMILY_OFFSETS[clampi(family - 1, 0, FAMILY_OFFSETS.size() - 1)]
		if _previous_highest == -99:
			_seal_background.position.x = 391 if remainder == 1 else 300
		elif _previous_highest % 5 == 1 and remainder > 1:
			_slide_drawer(300, 0.5)
		elif remainder == 1:
			_slide_drawer(391, 0.0)
	_previous_highest = highest

func _slide_drawer(target: float, delay: float) -> void:
	if _drawer_tween != null and _drawer_tween.is_running():
		_drawer_tween.kill()
	_drawer_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_drawer_tween.tween_property(_seal_background, "position:x", target, 0.8).set_delay(delay)

static func has_affordable_star_upgrade(state: CampaignState) -> bool:
	var available := CampaignProgressionService.available_stars(state)
	var upgrades: Dictionary = state.progression.get("star_upgrades", {})
	for key in CampaignProgressionService.star_upgrade_keys():
		if available >= CampaignProgressionService.star_upgrade_cost(int(upgrades.get(String(key), 0))):
			return true
	return false
