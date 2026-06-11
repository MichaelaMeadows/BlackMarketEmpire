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

	map_loader.set_player_position(Vector2(-300.0, 120.0))
	_expect(map_loader.is_position_visible(Vector2(-240.0, 210.0)), "active house interior remains visible")
	_expect(map_loader.is_position_visible(Vector2(-560.0, -450.0)), "outside yard remains visible")

	map_loader.set_player_position(Vector2(0.0, 0.0))
	_expect(map_loader.is_position_visible(Vector2(270.0, -180.0)), "same house interior remains visible when still inside")

	map_loader.set_player_position(Vector2(0.0, 600.0))
	_expect(not map_loader.is_position_visible(Vector2(270.0, -180.0)), "house interior hides when player is outside")
	map_loader.free()


func _test_closed_buildings_expose_door_gaps() -> void:
	var map_loader = MAP_LOADER_SCRIPT.new()
	get_root().add_child(map_loader)
	map_loader.load_map(MAP_PATH)

	var starter_rect := Rect2(-520.0, -360.0, 1040.0, 780.0)
	_expect(not map_loader._find_exterior_door_gaps(starter_rect).is_empty(), "starter house has visible door gap")
	map_loader.free()


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		_failures += 1
		push_error("FAIL: %s" % label)
