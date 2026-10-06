extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var healing_actor := CombatantState.from_setup({"instance_id": "healer", "team": 0, "max_health": 100, "health": 100, "level": 5, "max_healing_stat": 10})
	var heal := EffectDefinition.new()
	heal.kind = EffectDefinition.Kind.HEAL
	heal.scaling = EffectDefinition.Scaling.HEALING
	heal.can_critical = true
	heal.amount = 0
	var healing_events: Array = []
	var context := {"actor": healing_actor, "target": healing_actor, "rng": BattleRng.new(1, [0, 0, 0, 0]), "emit": func(_kind, _source, _target, values: Dictionary) -> void: healing_events.append(values)}
	var executor := HealEffectExecutor.new()
	executor.execute(heal, context)
	assert(not healing_events[0].feedback_has_healing and not healing_events[0].critical, "Zero-calculated healing must not advertise a critical")
	heal.amount = 10
	executor.execute(heal, context)
	assert(healing_events[1].amount == 0 and healing_events[1].feedback_has_healing, "Full-health clipping must not suppress a positive calculated heal's source feedback")
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate() as Control
	root.add_child(main)
	await main._start_battle()
	main.busy = true
	var view := main.combatant_views["enemy-1"] as BattleCombatantView
	var other := main.combatant_views["enemy-2"] as BattleCombatantView
	main._apply_event_values(BattleEvent.new(0, &"frozen", &"player-1", &"enemy-1"))
	await main._wait_until_usec(Time.get_ticks_usec() + 250000)
	var midway: Vector3 = view._condition_tint_material.get_shader_parameter("rgb_multiplier")
	assert(midway.x < 0.95 and midway.x > 0.5, "Freeze tint must ease in instead of snapping")
	await main._wait_until_usec(Time.get_ticks_usec() + 850000)
	assert(_vector(view, "rgb_multiplier").is_equal_approx(Vector3.ONE * 0.5))
	assert(_vector(view, "rgb_offset").is_equal_approx(Vector3(0.1, 0.3, 0.5)))
	assert(_vector(other, "rgb_offset").is_equal_approx(Vector3.ZERO), "Shader materials must be unique to each minion")
	if DisplayServer.get_name() != "headless":
		await _check_pixels(view)
	main._apply_event_values(BattleEvent.new(1, &"stunned", &"player-1", &"enemy-1"))
	await main._wait_until_usec(Time.get_ticks_usec() + 1100000)
	assert(_vector(view, "rgb_offset").is_equal_approx(Vector3(0.5, 0.5, 0.2)), "Stun must use source yellow, replacing a prior freeze tint")
	main._apply_event_values(BattleEvent.new(2, &"thawed", &"enemy-1", &"enemy-1"))
	await main._wait_until_usec(Time.get_ticks_usec() + 1100000)
	assert(_vector(view, "rgb_multiplier").is_equal_approx(Vector3.ONE) and _vector(view, "rgb_offset").is_equal_approx(Vector3.ZERO))
	assert(view.state_cache.stunned, "Removing source tint must not remove a still-active stun rule")
	main._apply_event_values(BattleEvent.new(3, &"stunned", &"player-1", &"enemy-1"))
	await main._wait_until_usec(Time.get_ticks_usec() + 300000)
	main._apply_event_values(BattleEvent.new(4, &"buffs_debuffs_cleared", &"player-1", &"enemy-1"))
	await main._wait_until_usec(Time.get_ticks_usec() + 1100000)
	assert(_vector(view, "rgb_offset").is_equal_approx(Vector3.ZERO), "Interrupted tint must clear without a stale tween restoring it")
	var popup_count := [0]
	view.child_entered_tree.connect(func(child: Node) -> void:
		if child is Sprite2D and child.texture in [BattleCombatantView.SUPER_EFFECTIVE_POPUP, BattleCombatantView.NOT_EFFECTIVE_POPUP, BattleCombatantView.CRITICAL_POPUP]: popup_count[0] += 1
	)
	for multiplier in [1.2, 1.4, 0.8, 0.7]: view.show_impact_feedback(multiplier, false)
	assert(popup_count[0] == 0, "Labels must use source >1.4 / <0.7 thresholds")
	view.show_impact_feedback(1.401, true)
	view.show_impact_feedback(0.699, false)
	assert(popup_count[0] == 3)
	main._animate_event(BattleEvent.new(5, &"healed", &"enemy-1", &"enemy-1", {"amount": 8, "effectiveness": 2.0, "critical": true, "feedback_has_healing": false}))
	main._animate_event(BattleEvent.new(6, &"damage", &"player-1", &"enemy-1", {"amount": 1}))
	await main._wait_until_usec(Time.get_ticks_usec() + 75000)
	assert(popup_count[0] == 3, "A zero-calculated heal must not invent effectiveness/critical feedback")
	assert(view.minion_sprite.modulate == Color.WHITE, "Ordinary damage must not add a non-source red flash")
	assert(not view.get_children().any(func(child: Node) -> bool: return child is Label and child.text == "+8"))
	main.queue_free()
	await process_frame
	print("PASS: one-second source additive freeze/stun tints, isolated materials, thaw/cleanse and interrupted tween clearing, exact feedback thresholds and no added heal numbers/hit flashes")
	quit(0)

func _vector(view: BattleCombatantView, parameter: String) -> Vector3:
	return view._condition_tint_material.get_shader_parameter(parameter)

func _check_pixels(view: BattleCombatantView) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(8, 8)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var bitmap := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	bitmap.fill(Color(0.2, 0.4, 0.6, 1.0))
	bitmap.set_pixel(0, 0, Color.TRANSPARENT)
	var sprite := Sprite2D.new()
	sprite.centered = false
	sprite.texture = ImageTexture.create_from_image(bitmap)
	sprite.material = view._condition_tint_material
	viewport.add_child(sprite)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var rendered := viewport.get_texture().get_image()
	var pixel := rendered.get_pixel(4, 4)
	assert(absf(pixel.r - 0.2) < 0.03 and absf(pixel.g - 0.5) < 0.03 and absf(pixel.b - 0.8) < 0.03, "Rendered tint must add source RGB offset, not multiply/darken: %s" % pixel)
	assert(rendered.get_pixel(0, 0).a == 0, "Tint must preserve transparent bitmap edges")
	viewport.queue_free()
