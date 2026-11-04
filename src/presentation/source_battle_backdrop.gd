class_name SourceBattleBackdrop
extends RefCounted

## BattleBackground.as advances by .1 degrees at the original 30 FPS. Keep
## that motion independent of rendering FPS and of the battle's RNG/state.
const CLOUD_PHASES := [0.3, 0.6, 0.1, 0.7, 0.9]
const CLOUD_SPEEDS := [1.2, 1.0, 1.0, 1.2, 2.0]
var phase := -55.0
var _clouds: Array[TextureRect] = []
var _distant: Array[Dictionary] = []
var _horizon: Control
var _horizon_origin := Vector2.ZERO
var _glow: TextureRect
var _elapsed := 0.0

func configure(scene: Control) -> void:
	var original := scene.get_node("Clouds") as TextureRect
	var scales := [1.0, 0.8, 0.6, 0.8, 0.6]
	var heights := [-35.0, 5.0, 62.0, -10.0, 30.0]
	for index in CLOUD_PHASES.size():
		var cloud := original if index == 0 else original.duplicate() as TextureRect
		if index > 0:
			cloud.name = "DriftingCloud%d" % index
			scene.add_child(cloud)
			scene.move_child(cloud, scene.get_node("Horizon").get_index())
		cloud.position.y = heights[index]
		cloud.scale = Vector2.ONE * scales[index]
		_clouds.append(cloud)
	_horizon = scene.get_node("Horizon")
	_horizon_origin = _horizon.position
	for data in [
		["battleScreenBackground_smallIsland", "FarIsland", 0.5, 0.8, -1250.0, 0.45, -70.0],
		["battleScreenBackground_city", "DistantCity", 0.3, 0.8, -1180.0, 0.65, -70.0],
		["battleScreenBackground_smallIsland", "NearIsland", 1.1, 0.8, -1250.0, 0.6, -105.0],
		["battleScreenBackground_mountain", "DistantTower", 1.0, 0.5, -1000.0, 0.8, -85.0],
	]:
		var texture := SourceMenuArt.texture(String(data[0]))
		if texture == null: continue
		var layer := TextureRect.new()
		layer.name = String(data[1])
		layer.texture = texture
		layer.size = texture.get_size()
		layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		scene.add_child(layer)
		scene.move_child(layer, scene.get_node("Island").get_index())
		_distant.append({"node": layer, "speed": data[2], "offset": data[3], "start": data[4], "scale": data[5], "height": data[6]})
	var glow_texture := SourceMenuArt.texture("battleScreenBackground_lanternGlow")
	if glow_texture != null:
		_glow = TextureRect.new()
		_glow.name = "LanternGlow"
		_glow.texture = glow_texture
		_glow.size = glow_texture.get_size()
		_glow.position = Vector2(302, 178)
		_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		scene.add_child(_glow)
		scene.move_child(_glow, scene.get_node("Island").get_index() + 1)
	advance(0.0)

func advance(delta: float) -> void:
	phase += maxf(0.0, delta) * 3.0
	_elapsed += maxf(0.0, delta)
	for index in _clouds.size():
		_clouds[index].position.x = 700.0 - fposmod(phase * CLOUD_SPEEDS[index] + 360.0 * CLOUD_PHASES[index], 360.0) * (1200.0 / 360.0)
	for data in _distant:
		var layer := data.node as TextureRect
		var angle := fposmod(phase * float(data.speed) + 360.0 * float(data.offset), 360.0)
		layer.position.x = -float(data.start) - angle * (2000.0 / 360.0)
		var depth := 1.0 + absf((angle - 180.0) / 360.0)
		layer.scale = Vector2.ONE * float(data.scale) * depth
		layer.position.y = float(data.height) + (437.0 - layer.size.y * layer.scale.y) * 0.5
	if is_instance_valid(_horizon): _horizon.position.y = _horizon_origin.y - absf(sin(deg_to_rad(phase))) * 15.0
	if is_instance_valid(_glow): _glow.modulate.a = 0.75 + sin(_elapsed * 1.4) * 0.25
