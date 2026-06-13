extends SceneTree

const BASIC_NPC_SCENE_PATH := "res://scenes/npc/BasicNpc.tscn"
const MAP_NAVIGATION_SCRIPT := preload("res://scripts/map_navigation.gd")

var _failures: int = 0
var _spawned_nodes: Array = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_attackers_enter_base_and_defenders_engage()
	_test_defenders_intercept_multiple_attackers_near_entry()

	_cleanup_nodes()
	if _failures == 0:
		print("NPC base attack simulation tests passed.")
	else:
		push_error("NPC base attack simulation tests failed: %d failure(s)." % _failures)
	quit(_failures)


func _test_attackers_enter_base_and_defenders_engage() -> void:
	_cleanup_nodes()
	var simulation := _create_base_attack_simulation(
		_base_map_data(),
		[
			_unit_data("rival_attacker", "Rival Attacker", "rival", Vector2(0.0, 156.0), "base_attack", ["player_crew"]),
		],
		[
			_unit_data("home_guard", "Home Guard", "player_crew", Vector2(-34.0, -24.0), "home_defense", ["rival"]),
			_unit_data("stash_guard", "Stash Guard", "player_crew", Vector2(40.0, -18.0), "home_defense", ["rival"]),
		]
	)
	var attacker: CharacterBody2D = simulation.get("attackers", [])[0]
	var defenders: Array = simulation.get("defenders", [])
	var navigation = simulation.get("navigation")
	var starting_distance := float(simulation.get("starting_attacker_distance", 0.0))
	var attacker_has_base_path := _path_reaches_base(navigation, attacker.global_position)

	_run_combat_simulation(simulation, 7.5)

	var final_distance := attacker.global_position.distance_to(Vector2.ZERO)
	var attacker_room := str(navigation.get_room_id_at(attacker.global_position))
	var defenders_engaged := 0
	var defenders_near_base := 0
	for defender in defenders:
		if not is_instance_valid(defender):
			continue
		var ai = defender.get("combat_ai")
		if ai != null and (ai.current_target == attacker or ["CHASING", "ATTACKING", "TAKING_COVER", "PEEKING"].has(ai.get_state_name())):
			defenders_engaged += 1
		if defender.global_position.distance_to(Vector2.ZERO) <= 150.0:
			defenders_near_base += 1

	_expect(attacker_has_base_path, "attacker has a navigation route through the entry into the base")
	_expect(final_distance < starting_distance - 35.0 or attacker_room == "base_floor" or _unit_took_damage(attacker), "attacker advances toward the base unless intercepted by defenders")
	_expect(defenders_engaged >= 1 or _any_unit_took_damage([attacker] + defenders), "at least one defender engages or damages the base attacker")
	_expect(defenders_near_base >= 1, "defenders protect the building instead of abandoning the base area")
	_expect(_any_unit_took_damage([attacker] + defenders), "the base attack simulation produces combat pressure")


func _test_defenders_intercept_multiple_attackers_near_entry() -> void:
	_cleanup_nodes()
	var simulation := _create_base_attack_simulation(
		_base_map_data(),
		[
			_unit_data("left_raider", "Left Raider", "rival", Vector2(-52.0, 168.0), "base_attack", ["player_crew"]),
			_unit_data("right_raider", "Right Raider", "rival", Vector2(58.0, 168.0), "base_attack", ["player_crew"]),
		],
		[
			_unit_data("door_guard", "Door Guard", "player_crew", Vector2(0.0, 42.0), "home_defense", ["rival"]),
			_unit_data("room_guard", "Room Guard", "player_crew", Vector2(-58.0, -36.0), "home_defense", ["rival"]),
		]
	)
	var attackers: Array = simulation.get("attackers", [])
	var defenders: Array = simulation.get("defenders", [])
	var navigation = simulation.get("navigation")
	var attackers_with_base_paths := 0
	for attacker in attackers:
		if is_instance_valid(attacker) and _path_reaches_base(navigation, attacker.global_position):
			attackers_with_base_paths += 1

	_run_combat_simulation(simulation, 8.0)

	var attackers_pressing_entry := 0
	for attacker in attackers:
		if not is_instance_valid(attacker):
			continue
		var attacker_room := str(navigation.get_room_id_at(attacker.global_position))
		if attacker_room == "base_floor" or attacker.global_position.y < 92.0:
			attackers_pressing_entry += 1

	var defenders_engaged := 0
	for defender in defenders:
		if not is_instance_valid(defender):
			continue
		var ai = defender.get("combat_ai")
		if ai != null and ["CHASING", "ATTACKING", "TAKING_COVER", "PEEKING"].has(ai.get_state_name()):
			defenders_engaged += 1

	_expect(attackers_with_base_paths >= 1, "attackers have navigation routes through the entry approach")
	_expect(attackers_pressing_entry >= 1 or _closest_cross_faction_distance(attackers, defenders) <= 95.0 or _any_unit_took_damage(attackers + defenders), "attackers press the entry approach unless intercepted by defenders")
	_expect(defenders_engaged >= 1, "defenders respond to attackers at the base entrance")
	_expect(_closest_cross_faction_distance(attackers, defenders) <= 95.0, "attackers and defenders close to a plausible fight distance near the building")
	_expect(_any_unit_took_damage(attackers + defenders), "multi-unit base attack produces at least some damage")


func _create_base_attack_simulation(map_data: Dictionary, attacker_data: Array, defender_data: Array) -> Dictionary:
	var navigation = MAP_NAVIGATION_SCRIPT.new()
	navigation.setup(map_data)
	_add_static_wall_colliders(map_data)

	var attackers: Array = []
	for data in attacker_data:
		if data is Dictionary:
			attackers.append(_spawn_unit(data, navigation))

	var defenders: Array = []
	for data in defender_data:
		if data is Dictionary:
			defenders.append(_spawn_unit(data, navigation))

	return {
		"navigation": navigation,
		"attackers": attackers,
		"defenders": defenders,
		"starting_attacker_distance": attackers[0].global_position.distance_to(Vector2.ZERO) if not attackers.is_empty() else 0.0,
	}


func _run_combat_simulation(simulation: Dictionary, seconds: float) -> void:
	var units: Array = []
	units.append_array(simulation.get("attackers", []))
	units.append_array(simulation.get("defenders", []))
	var steps := int(ceil(seconds / 0.1))
	for _index in range(steps):
		for unit in units:
			if not is_instance_valid(unit) or not unit.is_inside_tree():
				continue
			var gun = unit.get("gun")
			if gun != null and gun.has_method("_process"):
				gun._process(0.1)
			var melee_weapon = unit.get("melee_weapon")
			if melee_weapon != null and melee_weapon.has_method("_process"):
				melee_weapon._process(0.1)
		for unit in units:
			if not is_instance_valid(unit) or not unit.is_inside_tree():
				continue
			var ai = unit.get("combat_ai")
			if ai != null and ai.has_method("tick_ai"):
				ai.tick_ai(0.1)


func _spawn_unit(data: Dictionary, navigation) -> CharacterBody2D:
	var scene = load(BASIC_NPC_SCENE_PATH)
	var unit: CharacterBody2D = scene.instantiate()
	unit.setup(data)
	unit.global_position = _read_vector2(data.get("position", [0.0, 0.0]))
	root.add_child(unit)
	_spawned_nodes.append(unit)
	var ai = unit.get("combat_ai")
	if ai != null and ai.has_method("set_navigation"):
		ai.set_navigation(navigation)
	return unit


func _unit_data(unit_id: String, unit_name: String, faction: String, position: Vector2, squad_id: String, hostile_factions: Array) -> Dictionary:
	return {
		"id": unit_id,
		"name": unit_name,
		"role": "muscle",
		"faction": faction,
		"squad_id": squad_id,
		"position": [position.x, position.y],
		"health": 90,
		"ranged_weapon": false,
		"melee_weapon": {
			"name": "Test Bat",
			"weapon_type": "bat",
			"damage": 12,
			"range": 58,
			"arc_degrees": 100,
			"swing_cooldown": 0.55,
			"swing_duration": 0.12,
			"knockback": 30,
		},
		"ai": {
			"enabled": true,
			"faction": faction,
			"hostile_factions": hostile_factions,
			"role": "assault",
			"detection_radius": 280.0,
			"attack_range": 58.0,
			"preferred_range": 44.0,
			"chase_speed": 120.0,
			"reaction_time": 0.0,
			"target_memory_seconds": 2.0,
			"squad_id": squad_id,
			"preferred_spacing": 34.0,
		},
	}


func _base_map_data() -> Dictionary:
	return {
		"bounds": [-192, -160, 384, 384],
		"player_start": [0, 0],
		"navigation": {"cell_size": 16},
		"rooms": [
			{"id": "base_floor", "name": "Base Floor", "rect": [-96, -96, 192, 176]},
		],
		"walls": [
			{"id": "top_wall", "rect": [-112, -112, 224, 16], "collides": true},
			{"id": "left_wall", "rect": [-112, -112, 16, 208], "collides": true},
			{"id": "right_wall", "rect": [96, -112, 16, 208], "collides": true},
			{"id": "bottom_left_wall", "rect": [-112, 80, 76, 16], "collides": true},
			{"id": "bottom_right_wall", "rect": [36, 80, 76, 16], "collides": true},
		],
	}


func _add_static_wall_colliders(map_data: Dictionary) -> void:
	for wall in map_data.get("walls", []):
		if not (wall is Dictionary) or not bool(wall.get("collides", true)):
			continue
		var rect := _read_rect(wall.get("rect", []))
		var body := StaticBody2D.new()
		body.global_position = rect.position + rect.size * 0.5
		var shape := CollisionShape2D.new()
		var rectangle := RectangleShape2D.new()
		rectangle.size = rect.size
		shape.shape = rectangle
		body.add_child(shape)
		root.add_child(body)
		_spawned_nodes.append(body)


func _any_unit_took_damage(units: Array) -> bool:
	for unit in units:
		if _unit_took_damage(unit):
			return true
	return false


func _unit_took_damage(unit) -> bool:
	if not is_instance_valid(unit):
		return true
	var health = unit.get("health")
	return health != null and int(health.get("current_health")) < int(health.get("max_health"))


func _path_reaches_base(navigation, from_position: Vector2) -> bool:
	var path: PackedVector2Array = navigation.find_path(from_position, Vector2.ZERO)
	if path.is_empty():
		return from_position.distance_to(Vector2.ZERO) <= 24.0
	for point in path:
		if str(navigation.get_room_id_at(point)) == "base_floor" or point.distance_to(Vector2.ZERO) <= 24.0:
			return true
	return false


func _closest_cross_faction_distance(attackers: Array, defenders: Array) -> float:
	var closest := INF
	for attacker in attackers:
		if not is_instance_valid(attacker):
			continue
		for defender in defenders:
			if not is_instance_valid(defender):
				continue
			closest = min(closest, attacker.global_position.distance_to(defender.global_position))
	return closest


func _cleanup_nodes() -> void:
	for node in _spawned_nodes:
		if is_instance_valid(node):
			node.free()
	_spawned_nodes.clear()


func _read_rect(value: Variant) -> Rect2:
	if value is Array and value.size() >= 4:
		return Rect2(float(value[0]), float(value[1]), float(value[2]), float(value[3]))
	return Rect2()


func _read_vector2(value: Variant) -> Vector2:
	if value is Array and value.size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	return Vector2.ZERO


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		_failures += 1
		push_error("FAIL: %s" % label)
