extends SceneTree

const MAIN_SCENE := preload("res://scenes/main.tscn")
const IMPACT_TEXTURE := preload("res://content/base/art/battle/visual_moves/936_Utilities_SpriteHandler_mv_yellowAndOrangeImpact.png")

var failures: Array[String] = []

func _initialize() -> void:
	var main := MAIN_SCENE.instantiate() as Control
	root.add_child(main)
	call_deferred("_run_fall_animation", main)

func _run_fall_animation(main: Control) -> void:
	await process_frame
	var fall_texture := main.vfx_catalog.texture_for(85) as Texture2D
	var source_top_defaults: Dictionary = main.vfx_catalog.profile_for(3)
	var source_rotate_defaults: Dictionary = main.vfx_catalog.profile_for(15)
	var target := BattleCombatantView.new()
	target.team = 1
	target.position = Vector2(420.0, 260.0)
	target.minion_sprite = Sprite2D.new()
	target.minion_sprite.texture = fall_texture
	target.add_child(target.minion_sprite)
	main.combatant_layer.add_child(target)
	_check(String(source_top_defaults.get("family", "")) == "fall_from_top" and int(source_top_defaults.get("count", 0)) == 3 and is_equal_approx(float(source_top_defaults.get("impact_speed", 0.0)), 0.75) and String(source_top_defaults.get("impact_sprite", "")) == "mv_yellowAndOrangeImpact" and String(source_rotate_defaults.get("family", "")) == "rotate_into_target" and int(source_rotate_defaults.get("count", 0)) == 1 and is_equal_approx(float(source_rotate_defaults.get("impact_speed", 0.0)), 0.4), "generated animation profiles must expose the recovered source constructor defaults")
	var source_profile := {
		"count": 2,
		"delay": 0.1,
		"impact_speed": 0.35,
		"pre_impact_bounces": 1,
		"impact_visible": true,
		"master_scale": 1.0,
	}
	main._last_move_visual_duration_seconds = 0.0
	var before: int = main.move_vfx_layer.get_child_count()
	var hit_time: float = main._animate_fall_onto_target(fall_texture, target, source_profile)
	var visible_children: int = main.move_vfx_layer.get_child_count() - before
	var moving_sprite := main.move_vfx_layer.get_child(before) as Sprite2D if visible_children > 0 else null
	var start_y := moving_sprite.position.y if moving_sprite != null else 0.0
	_check(fall_texture != null and visible_children == 4 and is_equal_approx(hit_time, 1.15) and is_equal_approx(main._last_move_visual_duration_seconds, 1.65), "fall moves must create one falling sprite and one impact burst per object, preserve first-contact timing, and hold presentation through the final burst")
	await create_timer(0.4).timeout
	_check(moving_sprite != null and is_instance_valid(moving_sprite) and moving_sprite.position.y < start_y - 1.0, "configured pre-impact bounces must visibly lift the falling sprite before it drops")
	await create_timer(0.8).timeout
	var impact_revealed := false
	for child in main.move_vfx_layer.get_children():
		if child is Sprite2D and (child as Sprite2D).texture == IMPACT_TEXTURE and (child as Sprite2D).modulate.a > 0.5:
			impact_revealed = true
	_check(impact_revealed, "the source impact sprite must appear at the contact phase")
	var hidden_profile := {"count": 1, "impact_speed": 0.35, "pre_impact_bounces": 0, "impact_visible": false}
	main._last_move_visual_duration_seconds = 0.0
	var hidden_before: int = main.move_vfx_layer.get_child_count()
	var hidden_hit_time: float = main._animate_fall_onto_target(fall_texture, target, hidden_profile)
	var hidden_effect_count := 0
	for index in range(hidden_before, main.move_vfx_layer.get_child_count()):
		var child: Node = main.move_vfx_layer.get_child(index)
		if child is Sprite2D and (child as Sprite2D).texture == IMPACT_TEXTURE:
			hidden_effect_count += 1
	_check(main.move_vfx_layer.get_child_count() - hidden_before == 1 and hidden_effect_count == 0 and is_equal_approx(hidden_hit_time, 0.55) and is_equal_approx(main._last_move_visual_duration_seconds, 0.55), "impact_visible=false must suppress the burst without changing the hit time")
	var top_profile := {"count": 2, "delay": 0.3, "impact_speed": 0.5, "scale_step": 0.2, "master_scale": 0.5, "random_start_time": 0.0, "extra_distance": 8.0, "impact_visible": true}
	main._last_move_visual_duration_seconds = 0.0
	var top_before: int = main.move_vfx_layer.get_child_count()
	var top_hit_time: float = main._animate_fall_from_top(fall_texture, target, top_profile)
	var top_fall := main.move_vfx_layer.get_child(top_before) as Sprite2D
	var top_impact := main.move_vfx_layer.get_child(top_before + 1) as Sprite2D
	_check(main.move_vfx_layer.get_child_count() - top_before == 4 and is_equal_approx(top_hit_time, 0.5) and is_equal_approx(top_fall.scale.x, 0.5) and is_equal_approx(top_impact.scale.x, 1.0) and is_equal_approx(main._last_move_visual_duration_seconds, 1.25), "fall-from-top must preserve source scale/spacing, create per-object impact bursts, and include its configured move hold")
	var top_hidden_profile := {"count": 1, "impact_speed": 0.5, "random_start_time": 0.0, "impact_visible": false}
	var top_hidden_before: int = main.move_vfx_layer.get_child_count()
	main._animate_fall_from_top(fall_texture, target, top_hidden_profile)
	var top_hidden_impacts := 0
	for index in range(top_hidden_before, main.move_vfx_layer.get_child_count()):
		var child: Node = main.move_vfx_layer.get_child(index)
		if child is Sprite2D and (child as Sprite2D).texture == IMPACT_TEXTURE:
			top_hidden_impacts += 1
	_check(main.move_vfx_layer.get_child_count() - top_hidden_before == 1 and top_hidden_impacts == 0, "fall-from-top profiles with impacts disabled must keep only their falling sprite")
	var rotate_profile := {"count": 2, "delay": 0.06, "impact_speed": 0.4, "scale_step": 0.2, "master_scale": 0.75, "extra_distance": 8.0, "impact_visible": true}
	main._last_move_visual_duration_seconds = 0.0
	var rotate_before: int = main.move_vfx_layer.get_child_count()
	var rotate_hit_time: float = main._animate_rotate_at_target(fall_texture, target, rotate_profile)
	var rotating_sprite := main.move_vfx_layer.get_child(rotate_before) as Sprite2D
	var rotate_impact := main.move_vfx_layer.get_child(rotate_before + 1) as Sprite2D
	_check(main.move_vfx_layer.get_child_count() - rotate_before == 4 and is_equal_approx(rotate_hit_time, 0.4) and is_equal_approx(rotating_sprite.rotation_degrees, -90.0) and is_equal_approx(rotating_sprite.scale.x, 0.75) and is_equal_approx(rotate_impact.scale.x, 1.0) and is_equal_approx(main._last_move_visual_duration_seconds, 0.86), "rotate-into-target must use source scale, contact burst, object stagger, and completion timing")
	var rotate_hidden_profile := {"count": 1, "impact_speed": 0.4, "impact_visible": false}
	var rotate_hidden_before: int = main.move_vfx_layer.get_child_count()
	main._last_move_visual_duration_seconds = 0.0
	main._animate_rotate_at_target(fall_texture, target, rotate_hidden_profile)
	var rotate_hidden_impacts := 0
	for index in range(rotate_hidden_before, main.move_vfx_layer.get_child_count()):
		var child: Node = main.move_vfx_layer.get_child(index)
		if child is Sprite2D and (child as Sprite2D).texture == IMPACT_TEXTURE:
			rotate_hidden_impacts += 1
	_check(main.move_vfx_layer.get_child_count() - rotate_hidden_before == 1 and rotate_hidden_impacts == 0, "rotate-into-target profiles with impacts disabled must omit only the impact burst")
	main.queue_free()
	await process_frame
	if failures.is_empty():
		print("PASS: impact animation families (%d checks)" % 9)
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("FAIL: %d of 9 impact-animation checks" % failures.size())
		quit(1)

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
