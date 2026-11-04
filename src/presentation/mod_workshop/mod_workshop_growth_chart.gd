class_name ModWorkshopGrowthChart
extends Control

## The five battle stats of a minion from level 1 to 60, using the game's own
## level formula (LegacyMinionStats.raw_stats). `stats` is the live record
## dictionary, so spin boxes only need to call queue_redraw(). Hovering shows
## the exact values at that level; `evolution_level` draws a marker line.

const KEYS := ModWorkshopStatBars.KEYS
const COLORS := ModWorkshopStatBars.COLORS
const MAX_LEVEL := 60
const LEFT := 30.0
const BOTTOM := 18.0
const LEGEND := 18.0

var stats: Dictionary = {}
var evolution_level := 0
var _hover_level := 0

func _init() -> void:
	custom_minimum_size = Vector2(260, 168)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_PASS
	mouse_exited.connect(func() -> void:
		_hover_level = 0
		queue_redraw())

## Stats at one level, as whole numbers like the in-game summary screen.
static func stats_at(base: Dictionary, level: int) -> Dictionary:
	var definition := MinionDefinition.new()
	definition.base_health = int(base.get("health", 0))
	definition.base_energy = int(base.get("energy", 0))
	definition.base_attack = int(base.get("attack", 0))
	definition.base_healing = int(base.get("healing", 0))
	definition.base_speed = int(base.get("speed", 0))
	var raw := LegacyMinionStats.raw_stats(definition, level)
	var result: Dictionary = {}
	for key in raw: result[key] = int(raw[key])
	return result

func _plot() -> Rect2:
	return Rect2(LEFT, LEGEND, maxf(40.0, size.x - LEFT - 6.0), maxf(40.0, size.y - LEGEND - BOTTOM))

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var plot := _plot()
		var level := clampi(roundi(1.0 + (event.position.x - plot.position.x) / plot.size.x * (MAX_LEVEL - 1)), 1, MAX_LEVEL)
		if level != _hover_level:
			_hover_level = level
			queue_redraw()

func _draw() -> void:
	var font := ModWorkshopForm.FONT
	var plot := _plot()
	var top := stats_at(stats, MAX_LEVEL)
	var cap := 50.0
	for key in KEYS: cap = maxf(cap, float(top.get(key, 0)))
	# Multiples of 40 keep all four guide labels whole numbers.
	cap = ceilf(cap / 40.0) * 40.0
	draw_rect(plot, Color8(19, 21, 23))
	# Horizontal guides every quarter of the scale.
	for step in 5:
		var value := cap * step / 4.0
		var y := plot.end.y - plot.size.y * step / 4.0
		draw_line(Vector2(plot.position.x, y), Vector2(plot.end.x, y), Color8(48, 52, 59), 1.0)
		draw_string(font, Vector2(0, y + 4), str(int(value)), HORIZONTAL_ALIGNMENT_RIGHT, LEFT - 4, 10, ModWorkshopForm.MUTED)
	for level in [1, 15, 30, 45, 60]:
		var x := _x(plot, level)
		draw_string(font, Vector2(x - 14, size.y - 4), "Lv%d" % level, HORIZONTAL_ALIGNMENT_CENTER, 28, 10, ModWorkshopForm.MUTED)
	if evolution_level > 1 and evolution_level <= MAX_LEVEL:
		var ex := _x(plot, evolution_level)
		draw_dashed_line(Vector2(ex, plot.position.y), Vector2(ex, plot.end.y), ModWorkshopForm.GOLD, 1.0, 4.0)
		draw_string(font, Vector2(ex + 3, plot.position.y + 10), "evolves", HORIZONTAL_ALIGNMENT_LEFT, 60, 10, ModWorkshopForm.GOLD)
	# One polyline per stat; every third level is plenty at this size.
	var series: Array = []
	for _key in KEYS: series.append(PackedVector2Array())
	for level in range(1, MAX_LEVEL + 1, 3) + [MAX_LEVEL]:
		var values := stats_at(stats, level)
		for index in KEYS.size():
			series[index].append(Vector2(_x(plot, level), plot.end.y - plot.size.y * clampf(float(values[KEYS[index]]) / cap, 0.0, 1.0)))
	for index in KEYS.size(): draw_polyline(series[index], COLORS[index], 2.0, true)
	# Legend across the top, or the hovered level's exact values.
	var shown := _hover_level if _hover_level > 0 else MAX_LEVEL
	var at := stats_at(stats, shown)
	var x_cursor := LEFT
	draw_string(font, Vector2(x_cursor, 12), "Lv %d" % shown, HORIZONTAL_ALIGNMENT_LEFT, 40, 11, ModWorkshopForm.GOLD)
	x_cursor += 38
	var slot := maxf(36.0, (size.x - x_cursor) / KEYS.size())
	for index in KEYS.size():
		draw_rect(Rect2(x_cursor, 5, 7, 7), COLORS[index])
		draw_string(font, Vector2(x_cursor + 10, 12), "%s %d" % [String(KEYS[index]).left(3).capitalize(), at[KEYS[index]]], HORIZONTAL_ALIGNMENT_LEFT, slot - 10, 11, ModWorkshopForm.INK)
		x_cursor += slot
	if _hover_level > 0:
		var hx := _x(plot, _hover_level)
		draw_line(Vector2(hx, plot.position.y), Vector2(hx, plot.end.y), Color(1, 1, 1, 0.5), 1.0)

func _x(plot: Rect2, level: int) -> float:
	return plot.position.x + plot.size.x * float(level - 1) / float(MAX_LEVEL - 1)
