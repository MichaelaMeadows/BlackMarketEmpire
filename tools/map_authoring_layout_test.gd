extends SceneTree

const MAP_AUTHORING_HELPER := preload("res://tools/map_authoring_helper.gd")
const MAP_COMPILER := preload("res://scripts/map_compiler.gd")
const MAP_VALIDATOR := preload("res://scripts/map_validator.gd")

var _failures: int = 0


func _init() -> void:
	_test_building_layout_generates_passable_doors()
	_test_existing_exterior_wall_signature_still_works()
	_test_room_connections_generate_coherent_layout()
	_test_map_compiler_expands_building_layouts()

	if _failures == 0:
		print("Map authoring helper tests passed.")
	else:
		push_error("Map authoring helper tests failed: %d failure(s)." % _failures)
	quit(_failures)


func _test_building_layout_generates_passable_doors() -> void:
	var layout: Dictionary = MAP_AUTHORING_HELPER.building_layout(
		"test_shop",
		Rect2(0.0, 0.0, 400.0, 300.0),
		{
			"name": "Test Shop",
			"kind": "store",
			"door_width": 40.0,
			"minimum_gap": 112.0,
			"wall_color": [0.4, 0.4, 0.4],
			"dividers": [
				{
					"id": "office_split",
					"axis": "vertical",
					"x": 200.0,
					"y": 28.0,
					"height": 244.0,
					"doors": [[60.0, 24.0]],
				}
			],
		}
	)

	var building: Dictionary = layout["building"]
	var walls: Array = layout["walls"]
	_expect(building.get("collides") == false, "building layout creates non-colliding floor")
	_expect(walls.size() == 7, "building layout creates exterior walls and split divider walls")
	_expect(_has_wall_rect(walls, "test_shop_south_0", [0.0, 272.0, 144.0, 28.0]), "south wall leaves centered left edge")
	_expect(_has_wall_rect(walls, "test_shop_south_1", [256.0, 272.0, 144.0, 28.0]), "south wall leaves 112 unit entrance")
	_expect(_has_wall_rect(walls, "test_shop_office_split_0", [200.0, 28.0, 28.0, 60.0]), "divider wall starts before passage")
	_expect(_has_wall_rect(walls, "test_shop_office_split_1", [200.0, 200.0, 28.0, 72.0]), "divider wall leaves 112 unit passage")


func _test_existing_exterior_wall_signature_still_works() -> void:
	var walls: Array = MAP_AUTHORING_HELPER.exterior_walls(
		"legacy",
		Rect2(0.0, 0.0, 200.0, 180.0),
		24.0,
		{"south": [[70.0, 60.0]]}
	)
	_expect(walls.size() == 5, "legacy exterior wall call remains valid")
	_expect(_has_wall_rect(walls, "legacy_south_0", [0.0, 156.0, 70.0, 24.0]), "legacy call keeps configured door start")
	_expect(_has_wall_rect(walls, "legacy_south_1", [166.0, 156.0, 34.0, 24.0]), "legacy call enforces minimum passage")


func _test_room_connections_generate_coherent_layout() -> void:
	var layout: Dictionary = MAP_AUTHORING_HELPER.building_layout(
		"connected_shop",
		Rect2(1000.0, 500.0, 500.0, 300.0),
		{
			"door_side": "west",
			"rooms_are_local": true,
			"rooms": [
				{"id": "shop_floor", "rect": [28, 28, 208, 244]},
				{"id": "shop_office", "rect": [264, 28, 208, 244]},
			],
			"room_connections": [
				{"room_a": "shop_floor", "room_b": "shop_office", "door_width": 112.0},
			],
		}
	)
	var building: Dictionary = layout["building"]
	var rooms: Array = building["rooms"]
	var walls: Array = layout["walls"]
	_expect(rooms[0].get("rect", []) == [1028.0, 528.0, 208.0, 244.0], "local room coordinates become map coordinates")
	_expect(_has_wall_rect(walls, "connected_shop_shop_floor_shop_office_0", [1236.0, 528.0, 28.0, 66.0]), "room connection generates first divider segment")
	_expect(_has_wall_rect(walls, "connected_shop_shop_floor_shop_office_1", [1236.0, 706.0, 28.0, 66.0]), "room connection generates second divider segment around door")

	var map_data := {
		"schema_version": 2,
		"id": "connected_layout_test",
		"name": "Connected Layout Test",
		"bounds": [900, 400, 700, 500],
		"player_start": [1100, 650],
		"buildings": [building],
		"walls": walls,
	}
	var issues: Array[String] = MAP_VALIDATOR.validate(map_data, "", true)
	_expect(issues.is_empty(), "generated connected building passes structural and navigation validation: %s" % "; ".join(issues))


func _test_map_compiler_expands_building_layouts() -> void:
	var compiled: Dictionary = MAP_COMPILER.compile({
		"walls": [{"id": "existing_fence", "rect": [0, 0, 10, 100], "collides": true}],
		"building_layouts": [{
			"id": "compiled_house",
			"rect": [100, 100, 400, 300],
			"rooms_are_local": true,
			"rooms": [{"id": "compiled_room", "rect": [28, 28, 344, 244]}],
		}],
	})
	_expect(not compiled.has("building_layouts"), "compiler removes authoring-only building layouts")
	_expect(compiled.get("buildings", []).size() == 1, "compiler emits runtime building records")
	_expect(compiled.get("walls", []).size() == 6, "compiler preserves existing walls and emits exterior walls")


func _has_wall_rect(walls: Array, id: String, rect: Array) -> bool:
	for wall in walls:
		if not (wall is Dictionary):
			continue
		if str(wall.get("id", "")) != id:
			continue
		var wall_rect: Array = wall.get("rect", [])
		if wall_rect.size() != rect.size():
			return false
		for index in rect.size():
			if not is_equal_approx(float(wall_rect[index]), float(rect[index])):
				return false
		return true
	return false


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		_failures += 1
		push_error("FAIL: %s" % label)
