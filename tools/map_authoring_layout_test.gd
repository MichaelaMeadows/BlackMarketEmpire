extends SceneTree

const MAP_AUTHORING_HELPER := preload("res://tools/map_authoring_helper.gd")

var _failures: int = 0


func _init() -> void:
	_test_building_layout_generates_passable_doors()
	_test_existing_exterior_wall_signature_still_works()

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
