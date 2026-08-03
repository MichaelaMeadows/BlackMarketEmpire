extends SceneTree

const MAP_LOADER_SCRIPT := preload("res://scripts/map_loader.gd")
const MAP_NAVIGATION_SCRIPT := preload("res://scripts/map_navigation.gd")
const STARTER_MAP_PATH := "res://maps/starter_house.json"

var _failures: int = 0


func _init() -> void:
	_test_starter_house_key_positions_are_walkable()
	_test_starter_house_room_geometry()
	_test_paths_route_through_gaps()
	_test_unreachable_rooms_fail_validation()
	_test_colliding_props_block_navigation()
	_test_two_room_gap_infers_one_interior_doorway()
	_test_blocked_doorway_map_reports_validation_issue()
	_test_region_ids_track_connected_components()
	_test_repeated_paths_use_bounded_cache()

	if _failures == 0:
		print("Map navigation tests passed.")
	else:
		push_error("Map navigation tests failed: %d failure(s)." % _failures)
	quit(_failures)


func _test_starter_house_key_positions_are_walkable() -> void:
	var map_loader = MAP_LOADER_SCRIPT.new()
	get_root().add_child(map_loader)
	_expect(map_loader.load_map(STARTER_MAP_PATH), "starter map loads for navigation")
	var navigation = map_loader.get_navigation()
	var benji_position := _npc_position(map_loader, "benji_runner")
	var storage_position := _facility_position(map_loader, "stash_shelf")
	_expect(navigation != null, "starter map creates navigation service")
	_expect(navigation.is_walkable(map_loader.get_player_start()), "player start is walkable")
	_expect(navigation.is_walkable(benji_position), "Benji start is walkable")
	_expect(navigation.is_walkable(storage_position), "storage approach is walkable")
	_expect(navigation.is_walkable(navigation.find_nearest_walkable(Vector2(0.0, 780.0))), "outside exit resolves to walkable edge")
	_expect(navigation.validate_map().is_empty(), "starter house rooms validate as reachable")
	map_loader.free()


func _test_starter_house_room_geometry() -> void:
	var map_loader = MAP_LOADER_SCRIPT.new()
	get_root().add_child(map_loader)
	_expect(map_loader.load_map(STARTER_MAP_PATH), "starter map loads for room geometry")
	var navigation = map_loader.get_navigation()
	_expect(navigation.get_room_id_at(map_loader.get_player_start()) == "bedroom", "player start resolves to bedroom")
	_expect(navigation.get_room_id_at(_npc_position(map_loader, "benji_runner")) == "living_room", "Benji resolves to living room")
	_expect(navigation.get_room_id_at(_facility_position(map_loader, "basic_workbench")) == "kitchen", "kitchen workbench resolves to kitchen")
	_expect(navigation.get_room_id_at(navigation.get_room("bathroom").get("position", Vector2.ZERO)) == "bathroom", "bathroom navigation point resolves to bathroom")
	_expect(navigation.get_room_id_at(_facility_position(map_loader, "stash_shelf")) == "basement_storage", "storage facility resolves to storage")
	_expect(navigation.get_room("spare_room").get("slot_ids", []).size() == 2, "spare room exposes two future build slots")
	_expect(navigation.get_room("living_room").get("building_id", "") == "starter_house", "room lookup returns building id")

	var has_front_door := false
	for doorway in navigation.get_doorways():
		if str(doorway.get("kind", "")) == "exterior" and str(doorway.get("side", "")) == "south":
			var position: Vector2 = doorway.get("position", Vector2.ZERO)
			if str(doorway.get("building_id", "")) == "starter_house":
				has_front_door = true
	_expect(has_front_door, "starter house exposes front exterior doorway")
	_expect(navigation.find_room_path("bedroom", "basement_storage") == ["bedroom", "bathroom", "basement_storage"], "room graph follows actual doors from bedroom to storage")
	_expect(navigation.find_room_path("living_room", "kitchen") == ["living_room", "kitchen"], "room graph directly connects adjacent living room and kitchen")
	_expect(navigation.find_room_path("living_room", "basement_storage") == ["living_room", "bathroom", "basement_storage"], "room graph follows the central rooms to storage")
	map_loader.free()


func _test_paths_route_through_gaps() -> void:
	var navigation = _new_navigation({
		"bounds": [0, 0, 320, 224],
		"player_start": [64, 64],
		"walls": [
			{"id": "divider", "rect": [128, 0, 32, 128], "collides": true},
		],
	})
	var path: PackedVector2Array = navigation.find_path(Vector2(64.0, 64.0), Vector2(224.0, 64.0))
	_expect(path.size() > 0, "path around divider is found")
	var routed_through_gap := false
	var crossed_wall := false
	var wall_rect := Rect2(128.0, 0.0, 32.0, 128.0)
	for waypoint in path:
		if waypoint.y > 128.0:
			routed_through_gap = true
		if wall_rect.has_point(waypoint):
			crossed_wall = true
	_expect(routed_through_gap, "path uses open gap around wall")
	_expect(not crossed_wall, "path waypoints avoid solid wall")


func _test_unreachable_rooms_fail_validation() -> void:
	var navigation = _new_navigation({
		"bounds": [0, 0, 320, 224],
		"player_start": [64, 64],
		"buildings": [
			{
				"id": "test_building",
				"rect": [0, 0, 320, 224],
				"collides": false,
				"rooms": [
					{"id": "unreachable_room", "rect": [192, 32, 96, 128]},
				],
			},
		],
		"walls": [
			{"id": "sealed_divider", "rect": [128, 0, 32, 224], "collides": true},
		],
	})
	var issues: Array = navigation.validate_map()
	_expect(not issues.is_empty(), "sealed map reports validation issue")
	_expect(str(issues[0]).contains("unreachable_room"), "validation issue names unreachable room")


func _test_colliding_props_block_navigation() -> void:
	var navigation = _new_navigation({
		"bounds": [0, 0, 256, 192],
		"player_start": [32, 96],
		"props": [
			{"id": "blocking_tree", "type": "tree", "position": [96, 96], "radius": 32, "collision_radius": 32, "collides": true},
		],
	})
	_expect(not navigation.is_walkable(Vector2(96.0, 96.0)), "colliding prop center is blocked")
	var path: PackedVector2Array = navigation.find_path(Vector2(32.0, 96.0), Vector2(192.0, 96.0))
	_expect(path.size() > 0, "path around colliding prop is found")
	for waypoint in path:
		_expect(waypoint.distance_to(Vector2(96.0, 96.0)) > 28.0, "path waypoint avoids blocking prop")


func _test_two_room_gap_infers_one_interior_doorway() -> void:
	var navigation = _new_navigation({
		"bounds": [0, 0, 320, 160],
		"player_start": [64, 64],
		"buildings": [
			{
				"id": "two_room_house",
				"rect": [0, 0, 320, 160],
				"collides": false,
				"rooms": [
					{"id": "left_room", "rect": [0, 0, 128, 128]},
					{"id": "right_room", "rect": [160, 0, 128, 128]},
				],
			},
		],
		"walls": [
			{"id": "divider_top", "rect": [128, 0, 32, 24], "collides": true},
			{"id": "divider_bottom", "rect": [128, 104, 32, 24], "collides": true},
		],
	})
	var interior_count := 0
	var connects_rooms := false
	for doorway in navigation.get_doorways():
		if str(doorway.get("kind", "")) != "interior":
			continue
		interior_count += 1
		connects_rooms = str(doorway.get("room_a", "")) == "left_room" and str(doorway.get("room_b", "")) == "right_room"
	_expect(interior_count == 1, "two-room wall gap infers one interior doorway")
	_expect(connects_rooms, "interior doorway connects authored room ids")
	_expect(navigation.find_room_path("left_room", "right_room") == ["left_room", "right_room"], "room graph crosses inferred doorway")


func _test_blocked_doorway_map_reports_validation_issue() -> void:
	var navigation = _new_navigation({
		"bounds": [0, 0, 320, 160],
		"player_start": [64, 64],
		"buildings": [
			{
				"id": "sealed_house",
				"rect": [0, 0, 320, 160],
				"collides": false,
				"rooms": [
					{"id": "left_room", "rect": [0, 0, 128, 128]},
					{"id": "right_room", "rect": [160, 0, 128, 128]},
				],
			},
		],
		"walls": [
			{"id": "sealed_divider", "rect": [128, 0, 32, 128], "collides": true},
		],
	})
	var issues: Array = navigation.validate_map()
	_expect(_issues_contain(issues, "right_room"), "blocked doorway validation names sealed room")
	_expect(_issues_contain(issues, "no inferred doorway") or _issues_contain(issues, "not reachable"), "blocked doorway validation reports blocked room reason")


func _test_region_ids_track_connected_components() -> void:
	var navigation = _new_navigation({
		"bounds": [0, 0, 320, 128],
		"player_start": [64, 64],
		"walls": [
			{"id": "island_divider", "rect": [144, 0, 32, 128], "collides": true},
		],
	})
	var left_region: int = navigation.get_region_id(Vector2(64.0, 64.0))
	var left_neighbor_region: int = navigation.get_region_id(Vector2(96.0, 64.0))
	var right_region: int = navigation.get_region_id(Vector2(240.0, 64.0))
	_expect(left_region >= 0, "region id resolves for walkable point")
	_expect(left_region == left_neighbor_region, "connected points share region id")
	_expect(left_region != right_region, "separated islands receive different region ids")


func _test_repeated_paths_use_bounded_cache() -> void:
	var navigation = _new_navigation({
		"bounds": [0, 0, 320, 224],
		"player_start": [32, 32],
		"walls": [{"id": "divider", "rect": [128, 0, 32, 128], "collides": true}],
	})
	var first_path: PackedVector2Array = navigation.find_path(Vector2(32, 32), Vector2(240, 32))
	var first_stats: Dictionary = navigation.get_path_cache_stats()
	var second_path: PackedVector2Array = navigation.find_path(Vector2(36, 36), Vector2(244, 36))
	var second_stats: Dictionary = navigation.get_path_cache_stats()
	_expect(not first_path.is_empty() and not second_path.is_empty(), "repeated cached routes remain usable")
	_expect(int(first_stats.get("misses", 0)) == 1, "first route performs one A* search")
	_expect(int(second_stats.get("hits", 0)) == 1, "same-cell route reuses cached A* result")
	_expect(int(second_stats.get("size", 0)) == 1, "same-cell route occupies one cache entry")


func _new_navigation(data: Dictionary):
	var navigation = MAP_NAVIGATION_SCRIPT.new()
	navigation.setup(data)
	return navigation


func _facility_position(map_loader, facility_id: String) -> Vector2:
	for facility in map_loader.get_facilities():
		if facility is Dictionary and str(facility.get("id", "")) == facility_id:
			return _read_vector2(facility.get("position", []))
	return Vector2.ZERO


func _npc_position(map_loader, npc_id: String) -> Vector2:
	for npc in map_loader.get_npcs():
		if npc is Dictionary and str(npc.get("id", "")) == npc_id:
			return _read_vector2(npc.get("position", []))
	return Vector2.ZERO


func _issues_contain(issues: Array, text: String) -> bool:
	for issue in issues:
		if str(issue).contains(text):
			return true
	return false


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
