extends SceneTree

const MAP_LOADER_SCRIPT := preload("res://scripts/map_loader.gd")
const STARTER_MAP_PATH := "res://maps/starter_house.json"

var _failures: int = 0


func _init() -> void:
	_test_starter_map_sprite_assets_resolve()
	_test_starter_rooms_have_distinct_floor_materials()
	_test_missing_sprite_uses_procedural_fallback()

	if _failures == 0:
		print("Map visual asset tests passed.")
	else:
		push_error("Map visual asset tests failed: %d failure(s)." % _failures)
	quit(_failures)


func _test_starter_map_sprite_assets_resolve() -> void:
	var map_loader = MAP_LOADER_SCRIPT.new()
	get_root().add_child(map_loader)
	_expect(map_loader.load_map(STARTER_MAP_PATH), "starter map loads for visual assets")
	var sofa_sprite: Dictionary = map_loader._resolve_sprite_data({"visual_id": "worn_sofa"})
	_expect(str(sofa_sprite.get("path", "")).ends_with("worn_sofa.svg"), "visual_id resolves sprite asset path")
	_expect(_read_vector2(sofa_sprite.get("size", [])).x >= 90.0, "sprite asset exposes intended size")
	map_loader.free()


func _test_starter_rooms_have_distinct_floor_materials() -> void:
	var map_loader = MAP_LOADER_SCRIPT.new()
	get_root().add_child(map_loader)
	map_loader.load_map(STARTER_MAP_PATH)
	var rooms: Array = map_loader.get_map_data().get("buildings", [])[0].get("rooms", [])
	var materials: Dictionary = {}
	for room in rooms:
		if room is Dictionary:
			materials[str(room.get("id", ""))] = str(room.get("floor_material", ""))
	_expect(materials.get("living_room", "") == "worn_carpet", "living room has carpet material")
	_expect(materials.get("kitchen", "") == "old_tile", "kitchen has tile material")
	_expect(materials.get("bathroom", "") == "bath_tile", "bathroom has tile material")
	_expect(materials.get("basement_storage", "") == "bare_concrete", "storage has concrete material")
	map_loader.free()


func _test_missing_sprite_uses_procedural_fallback() -> void:
	var map_loader = MAP_LOADER_SCRIPT.new()
	get_root().add_child(map_loader)
	map_loader.load_map(STARTER_MAP_PATH)
	_expect(not map_loader._draw_sprite_item({"sprite_path": "res://assets/sprites/props/missing.png"}, Vector2.ZERO, 1.0), "missing sprite declines texture draw")
	map_loader.free()


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
