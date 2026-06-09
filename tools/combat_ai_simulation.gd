extends SceneTree

const BASIC_NPC_SCENE_PATH = "res://scenes/npc/BasicNpc.tscn"
const COMBAT_AI_SCENE_PATH = "res://scenes/combat/CombatAiController.tscn"

var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_run_weapon_profile_simulation()
	_run_range_role_simulation()
	_run_cover_survival_simulation()
	_run_squad_contact_simulation()
	_run_reload_cover_simulation()

	if _failures == 0:
		print("")
		print("Combat AI simulations passed.")
		quit(0)
	else:
		push_error("Combat AI simulations failed: %d failure(s)." % _failures)
		quit(_failures)


func _run_weapon_profile_simulation() -> void:
	print("")
	print("Combat AI Simulation: weapon_profiles")
	var shooter: CharacterBody2D = _new_unit("profile_shooter", "crew", Vector2.ZERO)
	if not _require_objects("weapon_profiles setup", [shooter]):
		return
	var weapons := [
		{"name": "Pistol", "weapon_type": "pistol", "accuracy": 0.78, "base_spread_degrees": 10.0, "recoil_per_shot": 1.0},
		{"name": "Rifle", "weapon_type": "rifle", "accuracy": 0.88, "base_spread_degrees": 7.0, "recoil_per_shot": 1.6},
		{"name": "SMG", "weapon_type": "smg", "accuracy": 0.62, "base_spread_degrees": 15.0, "recoil_per_shot": 1.2},
		{"name": "Shotgun", "weapon_type": "shotgun", "accuracy": 0.70, "base_spread_degrees": 12.0, "projectiles_per_shot": 5, "projectile_spread_degrees": 24.0, "recoil_per_shot": 2.0},
	]

	for weapon in weapons:
		var gun = shooter.get("gun")
		if not _require_objects("weapon profile gun", [gun]):
			return
		gun.setup(weapon)
		gun.set_seed(10)
		shooter.velocity = Vector2.ZERO
		var standing_spread: float = gun.get_effective_spread_degrees(shooter)
		gun.try_fire(shooter, Vector2.RIGHT)
		var recoil_spread: float = gun.get_effective_spread_degrees(shooter)
		shooter.velocity = Vector2(220.0, 0.0)
		var moving_spread: float = gun.get_effective_spread_degrees(shooter)
		print("%s standing %.2f recoil %.2f moving %.2f projectiles %d" % [
			str(weapon["name"]),
			standing_spread,
			recoil_spread,
			moving_spread,
			int(gun.get("projectiles_per_shot")),
		])
		_expect(recoil_spread >= standing_spread, "%s recoil does not reduce spread" % weapon["name"])
		_expect(moving_spread >= recoil_spread, "%s moving spread is at least recoil spread" % weapon["name"])

	shooter.free()


func _run_range_role_simulation() -> void:
	print("")
	print("Combat AI Simulation: range_roles")
	var shotgunner: CharacterBody2D = _new_unit("shotgunner", "crew", Vector2.ZERO, {
		"weapon_type": "shotgun",
		"effective_range": 120.0,
		"preferred_range": 80.0,
		"accuracy": 0.72,
	})
	var rifleman: CharacterBody2D = _new_unit("rifleman", "crew", Vector2(0, 140), {
		"weapon_type": "rifle",
		"effective_range": 430.0,
		"preferred_range": 320.0,
		"accuracy": 0.88,
	})
	var smg: CharacterBody2D = _new_unit("smg", "crew", Vector2(0, -140), {
		"weapon_type": "smg",
		"effective_range": 240.0,
		"preferred_range": 150.0,
		"accuracy": 0.62,
	})
	var target: CharacterBody2D = _new_unit("target", "rival", Vector2(280, 0))
	if not _require_objects("range_roles units", [shotgunner, rifleman, smg, target]):
		_free_nodes([shotgunner, rifleman, smg, target])
		return
	var shotgun_ai = _new_ai(shotgunner, {"hostile_factions": ["rival"], "detection_radius": 500.0, "reaction_time": 0.0})
	var rifle_ai = _new_ai(rifleman, {"hostile_factions": ["rival"], "detection_radius": 500.0, "role": "support", "reaction_time": 0.0})
	var smg_ai = _new_ai(smg, {"hostile_factions": ["rival"], "detection_radius": 500.0, "reaction_time": 0.0})
	if not _require_objects("range_roles AI", [shotgun_ai, rifle_ai, smg_ai]):
		_free_nodes([shotgunner, rifleman, smg, target])
		return

	shotgun_ai.tick_ai(0.1)
	rifle_ai.tick_ai(0.1)
	smg_ai.tick_ai(0.1)
	print("shotgun=%s rifle=%s smg=%s" % [shotgun_ai.get_state_name(), rifle_ai.get_state_name(), smg_ai.get_state_name()])
	_expect(shotgun_ai.get_state_name() == "CHASING", "shotgunner closes distance")
	_expect(rifle_ai.get_state_name() == "ATTACKING", "rifleman engages at range")
	_expect(["CHASING", "ATTACKING"].has(smg_ai.get_state_name()), "SMG unit either advances or fires within role range")

	_free_nodes([shotgunner, rifleman, smg, target])


func _run_cover_survival_simulation() -> void:
	print("")
	print("Combat AI Simulation: cover_survival")
	var open_unit: CharacterBody2D = _new_unit("open", "crew", Vector2.ZERO)
	var cover_unit: CharacterBody2D = _new_unit("cover", "crew", Vector2.ZERO)
	var target: CharacterBody2D = _new_unit("target", "rival", Vector2(180, 0))
	var blocker := _new_wall(Vector2(-60, 0), Vector2(20, 220))
	if not _require_objects("cover_survival units", [open_unit, cover_unit, target, blocker]):
		_free_nodes([open_unit, cover_unit, target, blocker])
		return
	var open_ai = _new_ai(open_unit, {"hostile_factions": ["rival"], "detection_radius": 400.0, "cover_health_fraction": 0.2, "reaction_time": 0.0})
	var cover_ai = _new_ai(cover_unit, {"hostile_factions": ["rival"], "detection_radius": 400.0, "cover_health_fraction": 0.9, "reaction_time": 0.0})
	if not _require_objects("cover_survival AI", [open_ai, cover_ai]):
		_free_nodes([open_unit, cover_unit, target, blocker])
		return
	open_unit.position = Vector2(0, -80)
	cover_unit.position = Vector2(0, 80)
	open_unit.get("health").apply_damage(40)
	cover_unit.get("health").apply_damage(40)

	for _step in range(8):
		open_ai.tick_ai(0.16)
		cover_ai.tick_ai(0.16)

	print("open=%s cover=%s" % [open_ai.get_state_name(), cover_ai.get_state_name()])
	_expect(cover_ai.get_state_name() != open_ai.get_state_name(), "cover unit changes behavior relative to open unit")
	_expect(["TAKING_COVER", "IN_COVER", "PEEKING"].has(cover_ai.get_state_name()), "cover unit seeks or uses cover")

	_free_nodes([open_unit, cover_unit, target, blocker])


func _run_squad_contact_simulation() -> void:
	print("")
	print("Combat AI Simulation: squad_contact")
	var scout: CharacterBody2D = _new_unit("scout", "crew", Vector2.ZERO)
	var support: CharacterBody2D = _new_unit("support", "crew", Vector2(-80, 36), {
		"weapon_type": "rifle",
		"accuracy": 0.86,
		"effective_range": 420.0,
		"preferred_range": 300.0,
	})
	var target: CharacterBody2D = _new_unit("target", "rival", Vector2(260, 0))
	if not _require_objects("squad_contact units", [scout, support, target]):
		_free_nodes([scout, support, target])
		return
	var scout_ai = _new_ai(scout, {"hostile_factions": ["rival"], "detection_radius": 420.0, "attack_range": 160.0, "squad_id": "sim"})
	var support_ai = _new_ai(support, {"hostile_factions": ["rival"], "detection_radius": 80.0, "squad_id": "sim"})
	if not _require_objects("squad_contact AI", [scout_ai, support_ai]):
		_free_nodes([scout, support, target])
		return

	for step in range(6):
		scout_ai.tick_ai(0.16)
		support_ai.tick_ai(0.16)
		print("step %d scout=%s support=%s support_target=%s" % [
			step,
			scout_ai.get_state_name(),
			support_ai.get_state_name(),
			str(support_ai.current_target == target),
		])

	_expect(support_ai.current_target == target, "support adopts scout target report")
	_expect(scout.velocity.distance_to(support.velocity) > 0.01, "squad members do not move as a single stacked vector")

	_free_nodes([scout, support, target])


func _run_reload_cover_simulation() -> void:
	print("")
	print("Combat AI Simulation: reload_cover")
	var unit: CharacterBody2D = _new_unit("reloader", "crew", Vector2.ZERO, {
		"magazine_size": 4,
		"ammo_in_magazine": 0,
		"reload_time": 0.5,
	})
	var target: CharacterBody2D = _new_unit("target", "rival", Vector2(180, 0))
	if not _require_objects("reload_cover units", [unit, target]):
		_free_nodes([unit, target])
		return
	var ai = _new_ai(unit, {"hostile_factions": ["rival"], "detection_radius": 400.0, "attack_range": 240.0, "reaction_time": 0.0})
	if not _require_objects("reload_cover AI", [ai]):
		_free_nodes([unit, target])
		return

	ai.tick_ai(0.1)
	print("state=%s reloading=%s" % [ai.get_state_name(), str(unit.get("gun").is_reloading())])
	_expect(unit.get("gun").is_reloading(), "empty unit starts reload")
	_expect(["TAKING_COVER", "RELOADING_IN_COVER", "IN_COVER"].has(ai.get_state_name()), "empty unit seeks cover before re-engaging")

	_free_nodes([unit, target])


func _new_unit(unit_name: String, faction: String, position: Vector2, weapon_data: Dictionary = {}) -> CharacterBody2D:
	var unit = _instantiate_scene(BASIC_NPC_SCENE_PATH)
	if unit == null:
		return null
	if not (unit is CharacterBody2D) or not unit.has_method("setup"):
		_expect(false, "BasicNpc scene provides CharacterBody2D setup unit")
		unit.free()
		return null
	var final_weapon_data := {
		"damage": 8,
		"projectile_speed": 500.0,
		"projectile_lifetime": 1.0,
		"fire_cooldown": 0.5,
	}
	for key in weapon_data:
		final_weapon_data[key] = weapon_data[key]

	unit.name = unit_name
	unit.call("setup", {
		"name": unit_name,
		"faction": faction,
		"health": 100,
		"weapon": final_weapon_data,
	})
	if not _unit_has_combat_components(unit):
		unit.free()
		return null
	unit.global_position = position
	root.add_child(unit)
	return unit


func _new_ai(owner: CharacterBody2D, config: Dictionary):
	if owner == null:
		_expect(false, "creates AI owner")
		return null
	var ai = _instantiate_scene(COMBAT_AI_SCENE_PATH)
	if ai == null:
		return null
	if not ai.has_method("setup") or not ai.has_method("tick_ai"):
		_expect(false, "Combat AI scene provides setup and tick_ai")
		ai.free()
		return null
	owner.add_child(ai)
	owner.set("combat_ai", ai)
	var ai_config := config.duplicate()
	ai_config["faction"] = str(owner.call("get_faction"))
	ai.setup(owner, ai_config)
	return ai


func _instantiate_scene(path: String):
	var scene = load(path)
	if scene == null:
		_expect(false, "loads scene: %s" % path)
		return null
	var instance = scene.instantiate()
	if instance == null:
		_expect(false, "instantiates scene: %s" % path)
		return null
	return instance


func _unit_has_combat_components(unit: Node) -> bool:
	var unit_health = unit.get("health")
	if unit_health == null or not unit_health.has_method("setup") or not unit_health.has_method("get_health_fraction"):
		_expect(false, "unit has scripted health component")
		return false

	var unit_gun = unit.get("gun")
	if unit_gun == null or not unit_gun.has_method("setup") or not unit_gun.has_method("try_fire") or not unit_gun.has_method("is_reloading"):
		_expect(false, "unit has scripted gun component")
		return false
	return true


func _new_wall(position: Vector2, size: Vector2) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.global_position = position
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = size
	shape.shape = rectangle
	body.add_child(shape)
	root.add_child(body)
	return body


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


func _require_objects(label: String, objects: Array) -> bool:
	for object in objects:
		if object == null:
			_expect(false, "%s created required objects" % label)
			return false
	return true
