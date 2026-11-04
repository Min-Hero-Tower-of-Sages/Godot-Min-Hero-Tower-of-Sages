class_name ModWorkshopStatBars
extends Control

## Five labelled bars for a minion's base stats. `stats` is the live record
## dictionary, so spin boxes only need to call queue_redraw(). `original`
## (optional) marks the unmodified values with a tick, for changes to
## existing minions.

const KEYS := ["health", "energy", "attack", "healing", "speed"]
const COLORS := ModWorkshopForm.STAT_COLORS
const LABEL_WIDTH := 54.0
const VALUE_WIDTH := 30.0

var stats: Dictionary = {}
var original: Dictionary = {}
## Match the height of the spin boxes beside the bars.
var row_height := 19.0:
	set(value):
		row_height = value
		custom_minimum_size.y = row_height * KEYS.size()
		queue_redraw()

func _init() -> void:
	custom_minimum_size = Vector2(150, row_height * KEYS.size())
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	var font := ModWorkshopForm.FONT
	var cap := 60.0
	for key in KEYS:
		cap = maxf(cap, maxf(float(stats.get(key, 0)), float(original.get(key, 0))) * 1.15)
	var bar_x := LABEL_WIDTH
	var bar_width := maxf(20.0, size.x - LABEL_WIDTH - VALUE_WIDTH - 6.0)
	for index in KEYS.size():
		var key: String = KEYS[index]
		var y := index * row_height + (row_height - 19.0) * 0.5
		draw_string(font, Vector2(0, y + 14), key.capitalize(), HORIZONTAL_ALIGNMENT_LEFT, LABEL_WIDTH, 12, ModWorkshopForm.MUTED)
		draw_rect(Rect2(bar_x, y + 4, bar_width, 10), Color8(19, 21, 23))
		var value := float(stats.get(key, 0))
		draw_rect(Rect2(bar_x, y + 4, bar_width * clampf(value / cap, 0.0, 1.0), 10), COLORS[index])
		if original.has(key) and not is_equal_approx(float(original[key]), value):
			var tick_x := bar_x + bar_width * clampf(float(original[key]) / cap, 0.0, 1.0)
			draw_line(Vector2(tick_x, y + 1), Vector2(tick_x, y + 17), Color.WHITE, 2.0)
		draw_string(font, Vector2(bar_x + bar_width + 6, y + 14), str(int(value)), HORIZONTAL_ALIGNMENT_LEFT, VALUE_WIDTH, 12, ModWorkshopForm.INK)
