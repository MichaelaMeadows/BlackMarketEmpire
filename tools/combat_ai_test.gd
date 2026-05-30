extends SceneTree

const BASIC_NPC_SCRIPT = preload("res://scripts/basic_npc.gd")
const COMBAT_AI_SCRIPT = preload("res://scripts/combat_ai_controller.gd")

var _failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_hostile_factions_are_explicit()
	_test_detects_visible_hostile()
	_test_attacks_target_in_range()
	_test_chases_target_out_of_range()
	_test_low_health_tries_to_take_cover()
	_test_follow_anchor_without_hostiles()
	_test_combat_follow_leash_keeps_units_together()
	_test_attacked_units_remember_attacker_faction()

	if _failures == 0:
		print("Combat AI tests passed.")
	else:
		push_error("Combat AI tests failed: %d failure(s)." % _failures)
	quit(_failures)


func _test_hostile_factions_are_explicit() -> void:
	var owner: CharacterBody2D = _new_unit("guard", "crew", Vector2.ZERO)
	var ally: CharacterBody2D = _new_unit("ally", "crew", Vector2(80, 0))
	var bystander: CharacterBody2D = _new_unit("bystander", "neutral", Vector2(120, 0))
	var target: CharacterBody2D = _new_unit("target", "rival", Vector2(160, 0))
	var ai = _new_ai(owner, {"hostile_factions": ["rival"]})

	_expect(not ai.is_hostile(ally), "same faction is not hostile")
	_expect(not ai.is_hostile(bystander), "unlisted faction is not hostile")
	_expect(ai.is_hostile(target), "listed hostile faction is hostile")

	_free_nodes([owner, ally, bystander, target])


func _test_detects_visible_hostile() -> void:
	var owner: CharacterBody2D = _new_unit("guard", "crew", Vector2.ZERO)
	var target: CharacterBody2D = _new_unit("target", "rival", Vector2(180, 0))
	var ai = _new_ai(owner, {"hostile_factions": ["rival"], "detection_radius": 300.0})

	_expect(ai.find_visible_hostile() == target, "AI finds nearest visible hostile inside detection radius")

	_free_nodes([owner, target])


func _test_attacks_target_in_range() -> void:
	var owner: CharacterBody2D = _new_unit("guard", "crew", Vector2.ZERO)
	var target: CharacterBody2D = _new_unit("target", "rival", Vector2(180, 0))
	var ai = _new_ai(owner, {
		"hostile_factions": ["rival"],
		"detection_radius": 400.0,
		"attack_range": 240.0,
	})

	ai.tick_ai(0.1)
	_expect(ai.get_state_name() == "ATTACKING", "AI attacks visible target inside weapon range")
	_expect(owner.gun.cooldown_remaining > 0.0, "AI fires its gun when attacking")

	_free_nodes([owner, target])


func _test_chases_target_out_of_range() -> void:
	var owner: CharacterBody2D = _new_unit("guard", "crew", Vector2.ZERO)
	var target: CharacterBody2D = _new_unit("target", "rival", Vector2(360, 0))
	var ai = _new_ai(owner, {
		"hostile_factions": ["rival"],
		"detection_radius": 500.0,
		"attack_range": 180.0,
		"chase_speed": 120.0,
	})

	ai.tick_ai(0.1)
	_expect(ai.get_state_name() == "CHASING", "AI chases visible target outside weapon range")
	_expect(owner.velocity.x > 0.0 and abs(owner.velocity.y) < 0.01, "AI chase velocity points toward target")

	_free_nodes([owner, target])


func _test_low_health_tries_to_take_cover() -> void:
	var owner: CharacterBody2D = _new_unit("guard", "crew", Vector2.ZERO)
	var target: CharacterBody2D = _new_unit("target", "rival", Vector2(180, 0))
	var ai = _new_ai(owner, {
		"hostile_factions": ["rival"],
		"detection_radius": 400.0,
		"attack_range": 260.0,
		"cover_health_fraction": 0.75,
		"cover_search_radius": 120.0,
	})
	owner.health.apply_damage(40)

	ai.tick_ai(0.1)
	_expect(ai.get_state_name() == "TAKING_COVER", "wounded AI enters cover behavior")
	_expect(ai.cover_position.distance_to(target.global_position) > owner.global_position.distance_to(target.global_position), "cover fallback moves away from hostile")

	_free_nodes([owner, target])


func _test_follow_anchor_without_hostiles() -> void:
	var owner: CharacterBody2D = _new_unit("guard", "crew", Vector2.ZERO)
	var leader: CharacterBody2D = _new_unit("leader", "crew", Vector2(260, 0))
	var ai = _new_ai(owner, {"hostile_factions": ["rival"], "follow_speed": 90.0})
	ai.set_follow_target(leader, 80.0)

	ai.tick_ai(0.1)
	_expect(ai.get_state_name() == "FOLLOWING", "AI follows assigned anchor when idle")
	_expect(owner.velocity.x > 0.0, "AI follow velocity points toward anchor")

	_free_nodes([owner, leader])


func _test_combat_follow_leash_keeps_units_together() -> void:
	var owner: CharacterBody2D = _new_unit("guard", "crew", Vector2.ZERO)
	var leader: CharacterBody2D = _new_unit("leader", "crew", Vector2(-500, 0))
	var target: CharacterBody2D = _new_unit("target", "rival", Vector2(180, 0))
	var ai = _new_ai(owner, {
		"hostile_factions": ["rival"],
		"detection_radius": 400.0,
		"attack_range": 260.0,
		"combat_follow_leash": 200.0,
	})
	ai.set_follow_target(leader, 80.0, 200.0)

	ai.tick_ai(0.1)
	_expect(ai.get_state_name() == "FOLLOWING", "AI regroups with follow anchor when combat leash is exceeded")
	_expect(owner.velocity.x < 0.0, "AI regroup velocity points back toward anchor")

	_free_nodes([owner, leader, target])


func _test_attacked_units_remember_attacker_faction() -> void:
	var owner: CharacterBody2D = _new_unit("guard", "crew", Vector2.ZERO)
	var attacker: CharacterBody2D = _new_unit("attacker", "rival", Vector2(180, 0))
	var ai = _new_ai(owner, {"hostile_factions": []})

	ai.notify_attacked_by(attacker)
	_expect(ai.is_hostile(attacker), "AI treats a damaging attacker faction as hostile")
	_expect(ai.current_target == attacker, "AI targets the unit that attacked it")

	_free_nodes([owner, attacker])


func _new_unit(unit_name: String, faction: String, position: Vector2) -> CharacterBody2D:
	var unit := BASIC_NPC_SCRIPT.new() as CharacterBody2D
	unit.name = unit_name
	unit.setup({
		"name": unit_name,
		"faction": faction,
		"health": 100,
		"weapon": {
			"damage": 8,
			"projectile_speed": 500.0,
			"projectile_lifetime": 1.0,
			"fire_cooldown": 0.5,
		},
	})
	unit.global_position = position
	root.add_child(unit)
	return unit


func _new_ai(owner: CharacterBody2D, config: Dictionary) -> Node:
	var ai: Node = COMBAT_AI_SCRIPT.new()
	owner.add_child(ai)
	var ai_config := config.duplicate()
	ai_config["faction"] = owner.get_faction()
	ai.setup(owner, ai_config)
	return ai


func _free_nodes(nodes: Array) -> void:
	for node in nodes:
		if node != null and is_instance_valid(node):
			node.free()


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		_failures += 1
		push_error("FAIL: %s" % label)
