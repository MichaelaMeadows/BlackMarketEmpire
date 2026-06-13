extends SceneTree

const MAP_LOADER_SCRIPT := preload("res://scripts/map_loader.gd")
const MAP_NAVIGATION_SCRIPT := preload("res://scripts/map_navigation.gd")
const NAVIGATION_MOVER_SCRIPT := preload("res://scripts/navigation_mover.gd")
const STARTER_MAP_PATH := "res://maps/starter_house.json"

var _failures: int = 0


func _init() -> void:
	_test_npc_movement_respects_wall_barrier()
	_test_npc_can_path_to_base_points()

	if _failures == 0:
		print("NPC navigation tests passed.")
	else:
		push_error("NPC navigation tests failed: %d failure(s)." % _failures)
	quit(_failures)


func _test_npc_movement_respects_wall_barrier() -> void:
	var wall_rect := Rect2(128.0, 0.0, 32.0, 128.0)
	var navigation = MAP_NAVIGATION_SCRIPT.new()
	navigation.setup({
		"bounds": [0, 0, 320, 224],
		"player_start": [64, 64],
		"walls": [
			{"id": "divider", "rect": [128, 0, 32, 128], "collides": true},
		],
	})

	var npc := CharacterBody2D.new()
	npc.position = Vector2(64.0, 64.0)
	var target := Vector2(224.0, 64.0)
	var max_y := npc.position.y
	var entered_wall := false
	var completed := false
	for _index in range(96):
		completed = NAVIGATION_MOVER_SCRIPT.move_towards(npc, target, 120.0, 0.1, navigation)
		max_y = max(max_y, npc.position.y)
		if wall_rect.has_point(npc.position) or not navigation.is_walkable(npc.position):
			entered_wall = true
		if completed:
			break

	_expect(completed, "NPC reaches point beyond a wall barrier")
	_expect(max_y > wall_rect.end.y, "NPC routes through the open gap instead of crossing the barrier")
	_expect(not entered_wall, "NPC movement never enters wall or blocked navigation cells")
	npc.free()


func _test_npc_can_path_to_base_points() -> void:
	var map_loader = MAP_LOADER_SCRIPT.new()
	get_root().add_child(map_loader)
	_expect(map_loader.load_map(STARTER_MAP_PATH), "starter map loads for NPC base navigation")
	var navigation = map_loader.get_navigation()
	var wall_rects := _get_colliding_wall_rects(map_loader.get_map_data())
	var start := map_loader.get_player_start()
	var base_points := {
		"planning table": _facility_position(map_loader, "planning_table"),
		"kitchen workbench": _facility_position(map_loader, "basic_workbench"),
		"crew bunk": _facility_position(map_loader, "crew_bunk"),
		"stash shelf": _facility_position(map_loader, "stash_shelf") + Vector2(34.0, 34.0),
		"front exit": navigation.find_nearest_walkable(Vector2(0.0, 680.0)),
	}

	for label in base_points:
		var target: Vector2 = base_points[label]
		_expect(navigation.is_walkable(navigation.find_nearest_walkable(target)), "base point is walkable: %s" % label)
		_expect(_simulate_npc_path(start, target, navigation, wall_rects), "NPC can path from player start to %s" % label)

	map_loader.free()


func _simulate_npc_path(start: Vector2, target: Vector2, navigation, wall_rects: Array) -> bool:
	var npc := CharacterBody2D.new()
	npc.position = navigation.find_nearest_walkable(start)
	var completed := false
	var stayed_clear := true
	for _index in range(220):
		completed = NAVIGATION_MOVER_SCRIPT.move_towards(npc, target, 140.0, 0.08, navigation)
		if not navigation.is_walkable(npc.position) or _point_hits_rects(npc.position, wall_rects):
			stayed_clear = false
			break
		if completed:
			break
	npc.free()
	return completed and stayed_clear


func _get_colliding_wall_rects(map_data: Dictionary) -> Array:
	var rects: Array = []
	for item in map_data.get("walls", []):
		if item is Dictionary and bool(item.get("collides", true)):
			rects.append(_read_rect(item.get("rect", [])))
	for item in map_data.get("props", []):
		if item is Dictionary and bool(item.get("collides", false)):
			var position := _read_vector2(item.get("position", []))
			var radius := float(item.get("collision_radius", item.get("radius", 0.0)))
			rects.append(Rect2(position - Vector2(radius, radius), Vector2(radius * 2.0, radius * 2.0)))
	return rects


func _point_hits_rects(point: Vector2, rects: Array) -> bool:
	for rect in rects:
		if rect is Rect2 and rect.has_point(point):
			return true
	return false


func _facility_position(map_loader, facility_id: String) -> Vector2:
	for facility in map_loader.get_facilities():
		if facility is Dictionary and str(facility.get("id", "")) == facility_id:
			return _read_vector2(facility.get("position", []))
	return Vector2.ZERO


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
