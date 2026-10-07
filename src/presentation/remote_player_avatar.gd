class_name RemotePlayerAvatar
extends Node2D

## Another player's character in the current room. Position comes from
## NetSession's interpolated presence; this node only draws it.

const NAME_FONT := preload("res://content/base/fonts/BurbinCasual.ttf")

var peer_id := 0
var _gender: StringName = &""
var _sprite: AnimatedSprite2D
var _name_tag: Label

func configure(id: int, display_name: String, gender: StringName, color: Color) -> void:
	peer_id = id
	z_index = 1
	if _sprite == null:
		_sprite = AnimatedSprite2D.new()
		_sprite.centered = false
		add_child(_sprite)
		_name_tag = make_name_tag()
		add_child(_name_tag)
	if gender != _gender:
		_gender = gender
		_sprite.sprite_frames = CampaignRoomView.create_player_frames(gender)
	_name_tag.text = display_name
	_name_tag.add_theme_color_override("font_color", color)

func apply_presence(presence: Dictionary) -> void:
	position = presence.position
	var pose: StringName = presence.pose
	var walking: bool = presence.walking
	var face_left: bool = presence.left
	var animation_name := pose if walking else StringName("idle_%s" % String(pose))
	if _sprite.sprite_frames != null and _sprite.sprite_frames.has_animation(animation_name):
		if _sprite.animation != animation_name or not _sprite.is_playing():
			_sprite.play(animation_name)
	_sprite.flip_h = face_left
	_sprite.position = CampaignRoomView.player_sprite_offset(_gender, pose, walking, face_left)

## Shared with the local player so every name tag looks the same.
static func make_name_tag() -> Label:
	var tag := Label.new()
	tag.name = "NameTag"
	tag.add_theme_font_override("font", NAME_FONT)
	tag.add_theme_font_size_override("font_size", 15)
	tag.add_theme_color_override("font_outline_color", Color(0.08, 0.06, 0.12, 0.95))
	tag.add_theme_constant_override("outline_size", 5)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.size = Vector2(160.0, 22.0)
	# Centered over the 70px-wide character art, just above its head.
	tag.position = Vector2(-45.0, -24.0)
	tag.z_index = 5
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tag
