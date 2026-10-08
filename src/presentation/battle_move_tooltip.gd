class_name BattleMoveTooltip
extends PanelContainer

const BURBIN_FONT := preload("res://content/base/fonts/BurbinCasual.ttf")

var title: Label
var details: RichTextLabel
var type_icon: TextureRect

func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color8(94, 100, 116, 242)
	frame.border_color = Color8(229, 230, 232, 217)
	frame.set_border_width_all(2)
	frame.set_corner_radius_all(3)
	frame.content_margin_left = 7
	frame.content_margin_right = 7
	frame.content_margin_top = 5
	frame.content_margin_bottom = 12 # Source type badge overlays the footer, not a separate row.
	add_theme_stylebox_override("panel", frame)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 0)
	add_child(column)
	title = Label.new()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", BURBIN_FONT)
	title.add_theme_font_size_override("font_size", 21)
	title.add_theme_color_override("font_color", Color8(242, 242, 242))
	title.custom_minimum_size.x = 200
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(title)
	details = RichTextLabel.new()
	details.bbcode_enabled = true
	details.fit_content = true
	details.scroll_active = false
	details.autowrap_mode = TextServer.AUTOWRAP_OFF
	details.custom_minimum_size.x = 200
	details.add_theme_font_override("normal_font", BURBIN_FONT)
	details.add_theme_font_size_override("normal_font_size", 14)
	details.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(details)
	type_icon = TextureRect.new()
	type_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# The badge overhangs into the frame's footer; a RichTextLabel clips its
	# children by default, which cut the badge's lower half off.
	details.clip_contents = false
	details.add_child(type_icon)
	details.resized.connect(_position_type_icon)

func show_move(move: MoveDefinition) -> void:
	title.text = move.display_name
	var rows: Array[String] = []
	for effect in move.effects:
		if effect == null:
			continue
		# These effects carry their useful value in chance/duration rather
		# than amount. The old amount==0 filter hid their descriptions.
		if effect.kind in [EffectDefinition.Kind.STUN, EffectDefinition.Kind.FREEZE, EffectDefinition.Kind.CLEAR_BUFFS_DEBUFFS]:
			var chance_label: String = {EffectDefinition.Kind.STUN: "Stun Chance", EffectDefinition.Kind.FREEZE: "Freeze Chance", EffectDefinition.Kind.CLEAR_BUFFS_DEBUFFS: "Buff/Debuff Clear Chance"}[effect.kind]
			rows.append(_row(chance_label, "%d%%" % effect.chance_percent, "#fff568"))
			continue
		if effect.kind == EffectDefinition.Kind.REVIVE:
			rows.append(_row("Revive", "%d%% health" % effect.amount, "#82de76"))
			continue
		if effect.kind in [EffectDefinition.Kind.APPLY_STATUS, EffectDefinition.Kind.REMOVE_STATUS]:
			continue # Paired with the damage/time-damage effect in imported moves.
		if effect.amount == 0 and effect.random_bonus == 0:
			continue
		if _is_combined_debuff(move, effect) and effect.target_scope == EffectDefinition.TargetScope.ACTOR:
			continue # Source emits one "target/your" line for the paired effects.
		var label := effect.display_name
		match effect.kind:
			EffectDefinition.Kind.DAMAGE: label = "Damage"
			EffectDefinition.Kind.HEAL: label = "Self Heal" if effect.target_scope == EffectDefinition.TargetScope.ACTOR else "Healing"
			EffectDefinition.Kind.PERIODIC_DAMAGE: label = "Time Damage"
			EffectDefinition.Kind.PERIODIC_HEAL: label = "Time Healing"
			EffectDefinition.Kind.SHIELD: label = "Shield"
			EffectDefinition.Kind.SELF_DAMAGE: label = "Recoil"
			EffectDefinition.Kind.ENERGY: label = "Energy Restored"
			EffectDefinition.Kind.HEALTH_PERCENT_DAMAGE: label = "Remove Health"
			EffectDefinition.Kind.REDIRECT_DAMAGE:
				rows.append("[color=#e5e6e8]Redirects[/color][color=#fff568] %d%% of damage to this minion[/color]" % effect.amount)
				continue
		var displayed_amount := effect.amount
		var displayed_random := effect.random_bonus
		if effect.kind in [EffectDefinition.Kind.PERIODIC_DAMAGE, EffectDefinition.Kind.PERIODIC_HEAL]:
			displayed_amount *= effect.duration
			displayed_random *= effect.duration
		var amount_text := str(displayed_amount)
		if effect.random_bonus > 0:
			amount_text += "-%d" % (displayed_amount + displayed_random)
		if effect.kind in [EffectDefinition.Kind.STAT_PERCENT, EffectDefinition.Kind.STAT_STAGE]:
			var stat_name := String(effect.stat_type_id).get_file()
			if stat_name.is_empty():
				stat_name = "health" # BaseMinionMove's default stat name.
			var percentage := effect.amount
			if effect.kind == EffectDefinition.Kind.STAT_STAGE:
				percentage = roundi((LegacyCombatModifiers.stat_stage_rate(effect.amount) - 1.0) * 100.0)
			if move.is_passive or move.is_global_passive:
				var prefix := "Increases group" if move.is_global_passive else "Increase"
				rows.append("[color=#e5e6e8]%s[/color][color=#82de76] %s by %d%%[/color]" % [prefix, stat_name, percentage])
				continue
			var owner_text := "target/your" if _is_combined_debuff(move, effect) else "your" if effect.target_scope == EffectDefinition.TargetScope.ACTOR else "targets"
			label = "%s %s %s" % ["Increases" if percentage >= 0 else "Reduces", owner_text, stat_name]
			amount_text = "%s%d%%" % ["+" if percentage >= 0 else "", percentage]
		elif effect.kind in [EffectDefinition.Kind.ARMOR, EffectDefinition.Kind.REFLECT, EffectDefinition.Kind.CRITICAL_CHANCE]:
			var attribute: String = {EffectDefinition.Kind.ARMOR: "armor", EffectDefinition.Kind.REFLECT: "reflect damage", EffectDefinition.Kind.CRITICAL_CHANCE: "critical hit chance"}[effect.kind]
			if move.is_passive or move.is_global_passive:
				rows.append("[color=#e5e6e8]%s[/color][color=%s] %s by %d%%[/color]" % ["Increases group" if move.is_global_passive else "Increase", "#fff568" if effect.kind == EffectDefinition.Kind.REFLECT else "#82de76", attribute, effect.amount])
				continue
			label = "Reflect Damage" if effect.kind == EffectDefinition.Kind.REFLECT else "%s %s %s" % ["Increases" if effect.amount >= 0 else "Reduces", "your" if effect.target_scope == EffectDefinition.TargetScope.ACTOR else "targets", attribute]
			amount_text = "%s%d%%" % ["+" if effect.amount >= 0 else "", effect.amount]
		elif effect.kind == EffectDefinition.Kind.ENERGY and effect.scaling == EffectDefinition.Scaling.ENERGY_STAT_PERCENT:
			amount_text += "%"
			if effect.target_scope == EffectDefinition.TargetScope.ACTOR:
				amount_text += " on self"
		elif effect.kind == EffectDefinition.Kind.HEALTH_PERCENT_DAMAGE:
			amount_text = "-%d%%%s" % [absi(effect.amount), " on self" if effect.target_scope == EffectDefinition.TargetScope.ACTOR else ""]
		if effect.duration > 0 and effect.kind in [EffectDefinition.Kind.PERIODIC_DAMAGE, EffectDefinition.Kind.PERIODIC_HEAL]:
			amount_text += " over %d turns" % effect.duration
		var value_color := "#ff7133" if effect.kind in [EffectDefinition.Kind.DAMAGE, EffectDefinition.Kind.PERIODIC_DAMAGE, EffectDefinition.Kind.SELF_DAMAGE, EffectDefinition.Kind.HEALTH_PERCENT_DAMAGE] or effect.amount < 0 else "#82de76"
		if effect.kind == EffectDefinition.Kind.ENERGY:
			value_color = "#7ad3e9"
		elif effect.kind == EffectDefinition.Kind.REFLECT:
			value_color = "#fff568"
		if effect.chance_percent < 100:
			amount_text += "[/color][color=%s] (Chance %d%%)" % ["#ffbd7c" if effect.amount < 0 else "#c0e9ba", effect.chance_percent]
		rows.append("[color=#e5e6e8]%s: [/color][color=%s]%s[/color]" % [label, value_color, amount_text])
		if effect.duration > 0 and effect.kind in [EffectDefinition.Kind.ARMOR, EffectDefinition.Kind.REFLECT]:
			rows.append(_row("Turns active", str(effect.duration), "#fff568"))
	if not move.is_passive and not move.is_global_passive:
		_append_target_row(rows, "Enemies Hit", move.enemy_target_count, move.random_targets, "#ff7133")
		_append_target_row(rows, "Allies Hit", move.ally_target_count, move.random_targets, "#82de76")
		if move.exhaust_turns > 0:
			rows.append(_row("Exhaustion", "%d %s" % [move.exhaust_turns, "turn" if move.exhaust_turns == 1 else "turns"], "#e57dff"))
		if move.charge_turns > 0:
			rows.append(_row("Charge", "%d %s" % [move.charge_turns, "turn" if move.charge_turns == 1 else "turns"], "#e57dff"))
	if move.accuracy_percent < 100:
		rows.append("[color=#e5e6e8]Accuracy: [/color][color=#fff568]%d%%[/color]" % move.accuracy_percent)
	if move.cooldown_turns > 0:
		rows.append("[color=#e5e6e8]Cooldown: [/color][color=#7ad3e9]%d %s[/color]" % [move.cooldown_turns, "turn" if move.cooldown_turns == 1 else "turns"])
	if move.energy_cost > 0:
		rows.append("[color=#e5e6e8]Energy: [/color][color=#7ad3e9]%d[/color]" % move.energy_cost)
	# Source builds descriptions in field order, not combat execution order.
	# Imported effect order intentionally remains untouched for battle logic.
	rows = _source_ordered_rows(rows)
	for effect in move.effects:
		if effect != null and effect.kind == EffectDefinition.Kind.REDIRECT_DAMAGE and effect.amount > 0:
			rows.assign(["[color=#e5e6e8]Redirects[/color][color=#fff568] %d%% of damage to this minion[/color]" % effect.amount])
			break # BaseMinionMove replaces, rather than appends to, the description.
	details.text = "\n".join(rows)
	# Flash's auto-sized, non-wrapping description expands to its longest
	# line. A fixed 200px Godot column wrapped long stat descriptions instead.
	var title_width := BURBIN_FONT.get_string_size(move.display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 21).x
	var content_width := maxf(200.0, title_width * 1.1 if title_width > 200.0 else 200.0)
	for line in details.get_parsed_text().split("\n"):
		content_width = maxf(content_width, BURBIN_FONT.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 4.0)
	title.custom_minimum_size.x = content_width
	details.custom_minimum_size.x = content_width
	type_icon.texture = SourceMenuArt.texture("moveDescription_type_%s" % String(move.type_id).get_file())
	type_icon.visible = type_icon.texture != null and move.type_id != &"base:type/none"
	visible = true
	reset_size()
	_position_type_icon.call_deferred()

func _position_type_icon() -> void:
	if type_icon.texture == null:
		return
	type_icon.position = Vector2(details.size.x - type_icon.texture.get_width() + 6.0, details.get_content_height() - 11.0)

func _is_combined_debuff(move: MoveDefinition, effect: EffectDefinition) -> bool:
	if effect.kind != EffectDefinition.Kind.STAT_STAGE or effect.amount >= 0:
		return false
	for other in move.effects:
		if other == null or other == effect:
			continue
		if other.kind == effect.kind and other.stat_type_id == effect.stat_type_id and other.amount == effect.amount and other.chance_percent == effect.chance_percent and other.duration == effect.duration:
			if (other.target_scope == EffectDefinition.TargetScope.ACTOR) != (effect.target_scope == EffectDefinition.TargetScope.ACTOR):
				return true
	return false

func _source_ordered_rows(rows: Array[String]) -> Array[String]:
	var ordered: Array[String] = []
	var remaining: Array[String] = rows.duplicate()
	var groups: Array[String] = ["Damage:", "Time Damage:", "Enemies Hit:", "Healing:", "Time Healing:", "Shield:", "Allies Hit:", "Recoil:", "Self Heal:", "Remove Health:", "Increases your armor:", "Increases targets armor:", "Reduces your armor:", "Reduces targets armor:", "Reduces", "Increases", "Reflect Damage:", "Stun Chance:", "Freeze Chance:", "Exhaustion:", "Charge:", "Buff/Debuff Clear Chance:", "Energy Restored:", "Turns active:", "Accuracy:", "Cooldown:", "Energy:"]
	for prefix in groups:
		var index := 0
		while index < remaining.size():
			var row := remaining[index]
			var text := row.substr(row.find("]") + 1)
			if text.begins_with(prefix):
				ordered.append(row)
				remaining.remove_at(index)
			else:
				index += 1
	ordered.append_array(remaining)
	return ordered

func _row(label: String, value: String, color: String) -> String:
	return "[color=#e5e6e8]%s: [/color][color=%s]%s[/color]" % [label, color, value]

func _append_target_row(rows: Array[String], label: String, count: int, random: bool, color: String) -> void:
	if count > 1 or (count == 1 and random):
		rows.append(_row(label, "All" if count == 5 else "%d%s" % [count, " random" if random else ""], color))

func follow_mouse(mouse_position: Vector2, viewport_size: Vector2) -> void:
	position = Vector2(mouse_position.x - size.x * 0.5 + 5.0, mouse_position.y - size.y)
	position.x = clampf(position.x, 0.0, maxf(0.0, viewport_size.x - size.x))
	position.y = maxf(10.0, position.y)
