extends RefCounted
class_name MapAuthoringHelper

static func exterior_walls(id_prefix: String, rect: Rect2, thickness: float = 24.0, doors: Dictionary = {}) -> Array:
	var walls: Array = []
	_add_horizontal_wall(walls, "%s_north" % id_prefix, rect.position, rect.size.x, thickness, doors.get("north", []))
	_add_horizontal_wall(walls, "%s_south" % id_prefix, Vector2(rect.position.x, rect.end.y - thickness), rect.size.x, thickness, doors.get("south", []))
	_add_vertical_wall(walls, "%s_west" % id_prefix, rect.position, rect.size.y, thickness, doors.get("west", []))
	_add_vertical_wall(walls, "%s_east" % id_prefix, Vector2(rect.end.x - thickness, rect.position.y), rect.size.y, thickness, doors.get("east", []))
	return walls


static func horizontal_wall(id: String, x: float, y: float, width: float, thickness: float = 24.0) -> Dictionary:
	return {
		"id": id,
		"rect": [x, y, width, thickness],
		"collides": true,
	}


static func vertical_wall(id: String, x: float, y: float, height: float, thickness: float = 24.0) -> Dictionary:
	return {
		"id": id,
		"rect": [x, y, thickness, height],
		"collides": true,
	}


static func tree(id: String, position: Vector2, radius: float = 24.0, collides: bool = true) -> Dictionary:
	return {
		"id": id,
		"type": "tree",
		"position": [position.x, position.y],
		"radius": radius,
		"collision_radius": radius * 0.55,
		"collides": collides,
	}


static func _add_horizontal_wall(walls: Array, id: String, start: Vector2, width: float, thickness: float, doors: Array) -> void:
	var cursor := 0.0
	var door_index := 0
	for door in doors:
		if not (door is Array) or door.size() < 2:
			continue
		var door_array: Array = door
		var door_start: float = max(0.0, float(door_array[0]))
		var door_width: float = max(0.0, float(door_array[1]))
		if door_start > cursor:
			walls.append(horizontal_wall("%s_%d" % [id, door_index], start.x + cursor, start.y, door_start - cursor, thickness))
			door_index += 1
		cursor = max(cursor, door_start + door_width)
	if cursor < width:
		walls.append(horizontal_wall("%s_%d" % [id, door_index], start.x + cursor, start.y, width - cursor, thickness))


static func _add_vertical_wall(walls: Array, id: String, start: Vector2, height: float, thickness: float, doors: Array) -> void:
	var cursor := 0.0
	var door_index := 0
	for door in doors:
		if not (door is Array) or door.size() < 2:
			continue
		var door_array: Array = door
		var door_start: float = max(0.0, float(door_array[0]))
		var door_height: float = max(0.0, float(door_array[1]))
		if door_start > cursor:
			walls.append(vertical_wall("%s_%d" % [id, door_index], start.x, start.y + cursor, door_start - cursor, thickness))
			door_index += 1
		cursor = max(cursor, door_start + door_height)
	if cursor < height:
		walls.append(vertical_wall("%s_%d" % [id, door_index], start.x, start.y + cursor, height - cursor, thickness))
