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
	_expect(navigation != null, "starter map creates navigation service")
	_expect(navigation.is_walkable(map_loader.get_player_start()), "player start is walkable")
	_expect(navigation.is_walkable(Vector2(-300.0, -100.0)), "Benji start is walkable")
	_expect(navigation.is_walkable(Vector2(204.0, 184.0)), "storage approach is walkable")
	_expect(navigation.is_walkable(navigation.find_nearest_walkable(Vector2(0.0, 780.0))), "outside exit resolves to walkable edge")
	_expect(navigation.validate_map().is_empty(), "starter house rooms validate as reachable")
	map_loader.free()


func _test_starter_house_room_geometry() -> void:
	var map_loader = MAP_LOADER_SCRIPT.new()
	get_root().add_child(map_loader)
	_expect(map_loader.load_map(STARTER_MAP_PATH), "starter map loads for room geometry")
	var navigation = map_loader.get_navigation()
	_expect(navigation.get_room_id_at(map_loader.get_player_start()) == "bedroom", "player start resolves to bedroom")
	_expect(navigation.get_room_id_at(Vector2(-300.0, -100.0)) == "living_room", "Benji resolves to living room")
	_expect(navigation.get_room_id_at(Vector2(270.0, -180.0)) == "kitchen", "kitchen workbench resolves to kitchen")
	_expect(navigation.get_room_id_at(Vector2(-100.0, 120.0)) == "bathroom", "bathroom point resolves to bathroom")
	_expect(navigation.get_room_id_at(Vector2(204.0, 184.0)) == "basement_storage", "storage point resolves to storage")
	_expect(navigation.get_room("living_room").get("building_id", "") == "starter_house", "room lookup returns building id")

	var has_front_door := false
	for doorway in navigation.get_doorways():
		if str(doorway.get("kind", "")) == "exterior" and str(doorway.get("side", "")) == "south":
			var position: Vector2 = doorway.get("position", Vector2.ZERO)
			if abs(position.x) <= 96.0 and position.y >= 392.0:
				has_front_door = true
	_expect(has_front_door, "starter house exposes front exterior doorway")
	_expect(navigation.find_room_path("bedroom", "basement_storage").size() >= 2, "room graph paths bedroom to storage")
	_expect(navigation.find_room_path("living_room", "kitchen").size() >= 2, "room graph paths living room to kitchen")
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


func _new_navigation(data: Dictionary):
	var navigation = MAP_NAVIGATION_SCRIPT.new()
	navigation.setup(data)
	return navigation


func _issues_contain(issues: Array, text: String) -> bool:
	for issue in issues:
		if str(issue).contains(text):
			return true
	return false


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		_failures += 1
		push_error("FAIL: %s" % label)
