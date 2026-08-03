extends SceneTree

const MAP_LOADER_SCRIPT := preload("res://scripts/map_loader.gd")
const MAP_PATH := "res://maps/starter_house.json"

var _failures: int = 0


func _init() -> void:
	_test_building_visibility_tracks_player_position()
	_test_closed_buildings_expose_door_gaps()

	if _failures == 0:
		print("Map visibility tests passed.")
	else:
		push_error("Map visibility tests failed: %d failure(s)." % _failures)
	quit(_failures)


func _test_building_visibility_tracks_player_position() -> void:
	var map_loader = MAP_LOADER_SCRIPT.new()
	get_root().add_child(map_loader)
	_expect(map_loader.load_map(MAP_PATH), "map loads for visibility test")

	var building: Dictionary = map_loader.get_map_data().get("buildings", [])[0]
	var starter_rect := _read_rect(building.get("rect", []))
	var interior_point := starter_rect.get_center()
	map_loader.set_player_position(map_loader.get_player_start())
	_expect(map_loader.is_position_visible(interior_point), "active house interior remains visible")
	_expect(map_loader.is_position_visible(Vector2(-560.0, -450.0)), "outside yard remains visible")

	map_loader.set_player_position(interior_point)
	_expect(map_loader.is_position_visible(map_loader.get_player_start()), "same house interior remains visible when still inside")

	map_loader.set_player_position(Vector2(0.0, 600.0))
	_expect(not map_loader.is_position_visible(interior_point), "house interior hides when player is outside")
	map_loader.free()


func _test_closed_buildings_expose_door_gaps() -> void:
	var map_loader = MAP_LOADER_SCRIPT.new()
	get_root().add_child(map_loader)
	map_loader.load_map(MAP_PATH)

	var building: Dictionary = map_loader.get_map_data().get("buildings", [])[0]
	var starter_rect := _read_rect(building.get("rect", []))
	_expect(not map_loader._find_exterior_door_gaps(starter_rect).is_empty(), "starter house has visible door gap")
	map_loader.free()


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		_failures += 1
		push_error("FAIL: %s" % label)


func _read_rect(value: Variant) -> Rect2:
	if value is Array and value.size() >= 4:
		return Rect2(float(value[0]), float(value[1]), float(value[2]), float(value[3]))
	return Rect2()
