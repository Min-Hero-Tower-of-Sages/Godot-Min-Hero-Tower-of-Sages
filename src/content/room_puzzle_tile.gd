class_name RoomPuzzleTile
extends RefCounted

const PREFIX := "puzzle_"
const LABELS := {"ice": "Ice slide", "slow": "Slow ground", "arrow": "Force direction", "jump": "Jump pad", "pit": "Gap"}
const ART_DIRECTORY := "res://content/base/art/rooms/"
const TEXTURES := {
	"ice": preload(ART_DIRECTORY + "puzzle_ice.svg"),
	"slow": preload(ART_DIRECTORY + "puzzle_slow.svg"),
	"arrow": preload(ART_DIRECTORY + "puzzle_arrow.svg"),
	"jump": preload(ART_DIRECTORY + "puzzle_jump.svg"),
	"pit": preload(ART_DIRECTORY + "puzzle_pit.svg"),
}

static func kind(sprite: String) -> String:
	var value := sprite.trim_prefix(PREFIX)
	return value if sprite.begins_with(PREFIX) and LABELS.has(value) else ""

static func contact(attributes: Dictionary) -> Dictionary:
	var angle := deg_to_rad(float(attributes.get("rotation", 0)))
	var scale := Vector2(float(attributes.get("xScale", 1)), float(attributes.get("yScale", 1)))
	var origin := Vector2(float(attributes.get("xPos", 0)), float(attributes.get("yPos", 0)))
	return {
		"kind": kind(String(attributes.get("spriteName", ""))),
		"transform": Transform2D(angle, scale, 0.0, origin),
		"direction": Vector2.RIGHT.rotated(angle).round() * signf(scale.x),
	}

static func contains(tile: Dictionary, point: Vector2) -> bool:
	var transform: Transform2D = tile.transform
	return Rect2(Vector2.ZERO, Vector2(64, 64)).has_point(transform.affine_inverse() * point)
