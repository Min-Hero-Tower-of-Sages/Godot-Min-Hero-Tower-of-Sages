class_name SourceMenuTransition
extends RefCounted

## TopDownMenuScreen.ApplyMenu*Animation: 0.1s lead-in, 0.5s entrance,
## 0.5s exit and 0.1s cleanup. Group only menu visuals, not its shade/tooltips.
static func visual_group(view: Control) -> Control:
	var existing: Variant = view.get_meta("source_transition_visuals") if view.has_meta("source_transition_visuals") else null
	if is_instance_valid(existing) and not existing.is_queued_for_deletion() and view.is_ancestor_of(existing):
		return existing as Control
	var group := Control.new()
	group.name = "SourceMenuVisuals"
	group.size = view.size
	group.pivot_offset = view.get_meta("source_transition_center", view.size * 0.5)
	group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var visuals := view.get_children()
	view.add_child(group)
	for child in visuals:
		if child.is_queued_for_deletion():
			continue
		if bool(child.get_meta("source_transition_background", false)):
			continue
		if child is Control and not child is ColorRect and not child is BattleMoveTooltip:
			child.reparent(group, false)
	view.set_meta("source_transition_visuals", group)
	return group

static func enter(view: Control, scale_in: bool = false) -> void:
	_stop_previous_transition(view)
	var group := visual_group(view)
	group.modulate.a = 0.0
	group.scale = Vector2.ONE * (0.9 if scale_in else 1.0)
	view.set_meta("source_transition_scale", scale_in)
	var tween := view.create_tween().set_parallel(true)
	view.set_meta("source_transition_tween", tween)
	tween.tween_property(group, "modulate:a", 1.0, 0.5).set_delay(0.1)
	if scale_in:
		tween.tween_property(group, "scale", Vector2.ONE, 0.5).set_delay(0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

static func exit(view: Control) -> Tween:
	_stop_previous_transition(view)
	var group := visual_group(view)
	var guard := Control.new()
	guard.name = "MenuTransitionInputGuard"
	guard.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	guard.mouse_filter = Control.MOUSE_FILTER_STOP
	guard.z_index = 4095
	view.add_child(guard)
	var tween := view.create_tween().set_parallel(true)
	view.set_meta("source_transition_tween", tween)
	tween.tween_property(group, "modulate:a", 0.0, 0.5)
	for child in view.get_children():
		if child is ColorRect and bool(child.get_meta("source_local_menu_overlay", false)):
			if child.has_meta("source_local_menu_overlay_tween"):
				var overlay_entrance: Tween = child.get_meta("source_local_menu_overlay_tween")
				if is_instance_valid(overlay_entrance):
					overlay_entrance.kill()
			tween.tween_property(child, "color:a", 0.0, 0.5)
	if bool(view.get_meta("source_transition_scale", false)):
		tween.tween_property(group, "scale", Vector2.ONE * 0.9, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.chain().tween_interval(0.1)
	return tween

static func _stop_previous_transition(view: Control) -> void:
	if not view.has_meta("source_transition_tween"):
		return
	var previous: Variant = view.get_meta("source_transition_tween")
	if is_instance_valid(previous) and previous.is_running():
		previous.kill()
