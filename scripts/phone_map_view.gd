extends Control

const MAP_BACKGROUND := Color(0.020, 0.026, 0.030)
const MAP_SURFACE := Color(0.055, 0.064, 0.066)
const BUILDING_COLOR := Color(0.24, 0.27, 0.28)
const WALL_COLOR := Color(0.68, 0.66, 0.58)
const ZONE_COLOR := Color(0.10, 0.23, 0.12, 0.72)
const ROAD_COLOR := Color(0.075, 0.080, 0.082)
const PROP_COLOR := Color(0.18, 0.42, 0.20)
const NPC_COLOR := Color(0.72, 0.78, 0.82)
const CONTACT_COLOR := Color(0.94, 0.72, 0.24)
const PLAYER_COLOR := Color(0.08, 0.82, 0.84)

var map_data: Dictionary = {}
var player_position := Vector2.ZERO

func set_map_data(new_map_data: Dictionary) -> void:
	map_data = new_map_data
	queue_redraw()


func set_player_position(new_position: Vector2) -> void:
	player_position = new_position
	queue_redraw()


func _draw() -> void:
	if map_data.is_empty() or size.x <= 1.0 or size.y <= 1.0:
		return

	var map_rect: Rect2 = _get_map_rect()
	draw_rect(Rect2(Vector2.ZERO, size), MAP_BACKGROUND)
	draw_rect(map_rect, MAP_SURFACE)
	draw_rect(map_rect, Color(0.60, 0.72, 0.70, 0.18), false, 1.0)
	_draw_grid(map_rect)
	_draw_rect_items("zones", map_rect, ZONE_COLOR)
	_draw_rect_items("buildings", map_rect, BUILDING_COLOR)
	_draw_rect_items("walls", map_rect, WALL_COLOR)
	_draw_props(map_rect)
	_draw_npcs(map_rect)
	_draw_contacts(map_rect)
	_draw_player_marker(_world_to_map(player_position, map_rect))


func _draw_grid(map_rect: Rect2) -> void:
	var grid: Dictionary = map_data.get("grid", {})
	if not bool(grid.get("enabled", true)):
		return

	var bounds: Rect2 = _get_world_bounds()
	var spacing: float = float(grid.get("spacing", 80.0))
	var line_color := Color(0.13, 0.15, 0.16)
	for x in range(int(bounds.position.x), int(bounds.end.x) + 1, int(spacing)):
		var top := _world_to_map(Vector2(x, bounds.position.y), map_rect)
		var bottom := _world_to_map(Vector2(x, bounds.end.y), map_rect)
		draw_line(top, bottom, line_color, 1.0)
	for y in range(int(bounds.position.y), int(bounds.end.y) + 1, int(spacing)):
		var left := _world_to_map(Vector2(bounds.position.x, y), map_rect)
		var right := _world_to_map(Vector2(bounds.end.x, y), map_rect)
		draw_line(left, right, line_color, 1.0)


func _draw_rect_items(collection_name: String, map_rect: Rect2, fallback_color: Color) -> void:
	for item in map_data.get(collection_name, []):
		var world_rect: Rect2 = _read_rect(item.get("rect", []))
		var map_item_rect: Rect2 = Rect2(
			_world_to_map(world_rect.position, map_rect),
			_world_to_map(world_rect.end, map_rect) - _world_to_map(world_rect.position, map_rect)
		)
		var visual_id := str(item.get("visual_id", item.get("id", "")))
		var color := ROAD_COLOR if visual_id.contains("road") else _read_color(item.get("color", []), fallback_color)
		draw_rect(map_item_rect, color)
		draw_rect(map_item_rect, Color(0.82, 0.86, 0.78, 0.22), false, 1.0)


func _draw_props(map_rect: Rect2) -> void:
	for item in map_data.get("props", []):
		var position: Vector2 = _world_to_map(_read_vector2(item.get("position", [0.0, 0.0])), map_rect)
		match str(item.get("type", "")):
			"streetlight":
				draw_circle(position, 2.5, Color(0.45, 0.68, 0.90, 0.86))
			"trash", "crate", "furniture":
				draw_rect(Rect2(position - Vector2(1.8, 1.8), Vector2(3.6, 3.6)), Color(0.42, 0.34, 0.24, 0.72))
			_:
				draw_circle(position, 2.2, _read_color(item.get("color", []), PROP_COLOR))


func _draw_npcs(map_rect: Rect2) -> void:
	for item in map_data.get("npcs", []):
		var position: Vector2 = _world_to_map(_read_vector2(item.get("position", [0.0, 0.0])), map_rect)
		draw_circle(position, 3.2, _read_color(item.get("color", []), NPC_COLOR))
		draw_circle(position, 4.8, Color(0.72, 0.78, 0.82, 0.16))


func _draw_contacts(map_rect: Rect2) -> void:
	for item in map_data.get("contacts", []):
		var position: Vector2 = _world_to_map(_read_vector2(item.get("position", [0.0, 0.0])), map_rect)
		var color := _read_color(item.get("color", []), CONTACT_COLOR)
		var diamond := PackedVector2Array([
			position + Vector2(0.0, -5.0),
			position + Vector2(5.0, 0.0),
			position + Vector2(0.0, 5.0),
			position + Vector2(-5.0, 0.0),
		])
		draw_colored_polygon(diamond, color)
		draw_polyline(PackedVector2Array([diamond[0], diamond[1], diamond[2], diamond[3], diamond[0]]), Color(0.02, 0.025, 0.03), 1.0)


func _draw_player_marker(position: Vector2) -> void:
	draw_circle(position, 8.0, Color(0.08, 0.82, 0.84, 0.20))
	draw_circle(position, 5.0, PLAYER_COLOR)
	draw_circle(position, 2.0, Color(0.02, 0.03, 0.035))


func _get_map_rect() -> Rect2:
	var margin: float = 12.0
	var available: Vector2 = size - Vector2(margin * 2.0, margin * 2.0)
	var bounds: Rect2 = _get_world_bounds()
	var scale: float = min(available.x / bounds.size.x, available.y / bounds.size.y)
	var map_size: Vector2 = bounds.size * scale
	return Rect2((size - map_size) * 0.5, map_size)


func _world_to_map(world_position: Vector2, map_rect: Rect2) -> Vector2:
	var bounds: Rect2 = _get_world_bounds()
	var normalized: Vector2 = (world_position - bounds.position) / bounds.size
	return map_rect.position + normalized * map_rect.size


func _get_world_bounds() -> Rect2:
	return _read_rect(map_data.get("bounds", [-1200.0, -900.0, 2400.0, 1800.0]))


func _read_rect(value: Variant) -> Rect2:
	if value is Array and value.size() >= 4:
		return Rect2(float(value[0]), float(value[1]), float(value[2]), float(value[3]))
	return Rect2(0.0, 0.0, 1.0, 1.0)


func _read_vector2(value: Variant) -> Vector2:
	if value is Array and value.size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	return Vector2.ZERO


func _read_color(value: Variant, fallback: Color) -> Color:
	if value is Array and value.size() >= 3:
		var alpha: float = float(value[3]) if value.size() >= 4 else 1.0
		return Color(float(value[0]), float(value[1]), float(value[2]), alpha)
	return fallback
