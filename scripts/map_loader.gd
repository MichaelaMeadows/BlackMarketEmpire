extends Node2D
class_name MapLoader

const DEFAULT_BACKGROUND := Color(0.06, 0.07, 0.075)
const DEFAULT_GRID_COLOR := Color(0.10, 0.11, 0.12)
const DEFAULT_BUILDING_COLOR := Color(0.16, 0.18, 0.19)
const DEFAULT_BUILDING_TRIM := Color(0.28, 0.32, 0.33)
const DEFAULT_WALL_COLOR := Color(0.33, 0.34, 0.32)

var map_data: Dictionary = {}
var map_path: String = ""

func load_map(path: String) -> bool:
	map_path = path
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Could not open map file: %s" % path)
		map_data = _empty_map()
		queue_redraw()
		return false

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Map file is not a JSON object: %s" % path)
		map_data = _empty_map()
		queue_redraw()
		return false

	map_data = parsed
	_rebuild_collision()
	queue_redraw()
	return true


func save_map(path: String, data: Variant = null) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Could not save map file: %s" % path)
		return false

	var data_to_save: Dictionary = map_data
	if data is Dictionary:
		data_to_save = data
	elif data != null:
		push_error("Map data must be a Dictionary.")
		return false

	file.store_string(JSON.stringify(data_to_save, "\t"))
	return true


func get_player_start() -> Vector2:
	return _read_vector2(map_data.get("player_start", [0.0, 0.0]))


func get_contacts() -> Array:
	return map_data.get("contacts", [])


func get_npcs() -> Array:
	return map_data.get("npcs", [])


func get_map_data() -> Dictionary:
	return map_data


func get_title() -> String:
	return str(map_data.get("name", "Unknown Map"))


func _draw() -> void:
	var bounds: Rect2 = _read_rect(map_data.get("bounds", [-2000.0, -2000.0, 4000.0, 4000.0]))
	draw_rect(bounds, _read_color(map_data.get("background_color", []), DEFAULT_BACKGROUND))
	_draw_grid(bounds)
	_draw_rect_collection("buildings", DEFAULT_BUILDING_COLOR, DEFAULT_BUILDING_TRIM)
	_draw_rect_collection("walls", DEFAULT_WALL_COLOR, DEFAULT_WALL_COLOR)


func _draw_grid(bounds: Rect2) -> void:
	var grid: Dictionary = map_data.get("grid", {})
	if not bool(grid.get("enabled", true)):
		return

	var spacing: float = float(grid.get("spacing", 80.0))
	var color: Color = _read_color(grid.get("color", []), DEFAULT_GRID_COLOR)
	for x in range(int(bounds.position.x), int(bounds.end.x) + 1, int(spacing)):
		draw_line(Vector2(x, bounds.position.y), Vector2(x, bounds.end.y), color, 1.0)
	for y in range(int(bounds.position.y), int(bounds.end.y) + 1, int(spacing)):
		draw_line(Vector2(bounds.position.x, y), Vector2(bounds.end.x, y), color, 1.0)


func _draw_rect_collection(collection_name: String, fill_fallback: Color, trim_fallback: Color) -> void:
	for item in map_data.get(collection_name, []):
		var rect: Rect2 = _read_rect(item.get("rect", []))
		var fill_color: Color = _read_color(item.get("color", []), fill_fallback)
		var trim_color: Color = _read_color(item.get("trim_color", []), trim_fallback)
		draw_rect(rect, fill_color)
		draw_rect(rect, trim_color, false, float(item.get("outline_width", 3.0)))


func _rebuild_collision() -> void:
	for child in get_children():
		child.queue_free()

	for collection_name in ["buildings", "walls"]:
		for item in map_data.get(collection_name, []):
			if not bool(item.get("collides", true)):
				continue
			_add_rect_collision(_read_rect(item.get("rect", [])), str(item.get("id", collection_name)))


func _add_rect_collision(rect: Rect2, id: String) -> void:
	var body := StaticBody2D.new()
	body.name = "Collision_%s" % id
	body.position = rect.get_center()
	add_child(body)

	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = rect.size
	shape.shape = rectangle
	body.add_child(shape)


func _read_rect(value: Variant) -> Rect2:
	if value is Array and value.size() >= 4:
		return Rect2(float(value[0]), float(value[1]), float(value[2]), float(value[3]))
	return Rect2()


func _read_vector2(value: Variant) -> Vector2:
	if value is Array and value.size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	return Vector2.ZERO


func _read_color(value: Variant, fallback: Color) -> Color:
	if value is Array and value.size() >= 3:
		var alpha: float = float(value[3]) if value.size() >= 4 else 1.0
		return Color(float(value[0]), float(value[1]), float(value[2]), alpha)
	return fallback


func _empty_map() -> Dictionary:
	return {
		"name": "Empty Map",
		"bounds": [-2000.0, -2000.0, 4000.0, 4000.0],
		"player_start": [0.0, 0.0],
		"buildings": [],
		"walls": [],
		"npcs": [],
		"contacts": [],
		"triggers": [],
	}
