extends RefCounted
class_name MapAuthoringHelper

const DEFAULT_BUILDING_WALL_THICKNESS := 28.0
const DEFAULT_BUILDING_DOOR_WIDTH := 112.0
const DEFAULT_PLAYER_CLEARANCE := 96.0

static func building_layout(id_prefix: String, rect: Rect2, options: Dictionary = {}) -> Dictionary:
	var thickness: float = float(options.get("thickness", DEFAULT_BUILDING_WALL_THICKNESS))
	var minimum_gap: float = max(
		float(options.get("minimum_gap", DEFAULT_PLAYER_CLEARANCE)),
		float(options.get("door_width", DEFAULT_BUILDING_DOOR_WIDTH))
	)
	var door_side: String = str(options.get("door_side", "south"))
	var door_width: float = max(float(options.get("door_width", DEFAULT_BUILDING_DOOR_WIDTH)), minimum_gap)
	var wall_color = options.get("wall_color", null)
	var interior_wall_color = options.get("interior_wall_color", wall_color)
	var rooms := _normalize_rooms(options.get("rooms", []), rect.position, bool(options.get("rooms_are_local", false)))
	var building := {
		"id": id_prefix,
		"name": str(options.get("name", id_prefix.capitalize())),
		"kind": str(options.get("kind", "building")),
		"visual_id": str(options.get("visual_id", id_prefix)),
		"floor_material": str(options.get("floor_material", "worn_floor")),
		"wall_material": str(options.get("wall_material", "painted_block")),
		"rect": _rect_to_array(rect),
		"color": options.get("color", [0.16, 0.18, 0.19]),
		"trim_color": options.get("trim_color", [0.30, 0.32, 0.30]),
		"collides": false,
		"rooms": rooms,
	}

	var doors_value: Variant = options.get("doors", {})
	var doors: Dictionary = doors_value if doors_value is Dictionary else {}
	if not doors.has(door_side):
		doors[door_side] = [_centered_door(rect, door_side, door_width)]

	var walls: Array = exterior_walls(id_prefix, rect, thickness, doors, wall_color, minimum_gap)
	var dividers_value: Variant = options.get("dividers", [])
	if dividers_value is Array:
		for divider in dividers_value:
			if divider is Dictionary:
				var normalized_divider: Dictionary = divider.duplicate(true)
				if bool(normalized_divider.get("local", false)):
					normalized_divider["x"] = rect.position.x + float(normalized_divider.get("x", 0.0))
					normalized_divider["y"] = rect.position.y + float(normalized_divider.get("y", 0.0))
				walls.append_array(divider_wall(id_prefix, normalized_divider, thickness, interior_wall_color, minimum_gap))

	var connections_value: Variant = options.get("room_connections", [])
	if connections_value is Array:
		for connection in connections_value:
			if connection is Dictionary:
				walls.append_array(room_connection_wall(id_prefix, rooms, connection, thickness, interior_wall_color, minimum_gap))

	return {
		"building": building,
		"walls": walls,
	}


static func exterior_walls(id_prefix: String, rect: Rect2, thickness: float = 24.0, doors: Dictionary = {}, color = null, minimum_gap: float = DEFAULT_PLAYER_CLEARANCE) -> Array:
	var walls: Array = []
	_add_horizontal_wall(walls, "%s_north" % id_prefix, rect.position, rect.size.x, thickness, doors.get("north", []), color, minimum_gap)
	_add_horizontal_wall(walls, "%s_south" % id_prefix, Vector2(rect.position.x, rect.end.y - thickness), rect.size.x, thickness, doors.get("south", []), color, minimum_gap)
	_add_vertical_wall(walls, "%s_west" % id_prefix, rect.position, rect.size.y, thickness, doors.get("west", []), color, minimum_gap)
	_add_vertical_wall(walls, "%s_east" % id_prefix, Vector2(rect.end.x - thickness, rect.position.y), rect.size.y, thickness, doors.get("east", []), color, minimum_gap)
	return walls


static func divider_wall(id_prefix: String, divider: Dictionary, thickness: float = DEFAULT_BUILDING_WALL_THICKNESS, color = null, minimum_gap: float = DEFAULT_PLAYER_CLEARANCE) -> Array:
	var walls: Array = []
	var axis: String = str(divider.get("axis", "horizontal"))
	var id: String = "%s_%s" % [id_prefix, str(divider.get("id", "divider"))]
	var doors: Array = _normalize_doors(divider.get("doors", []), minimum_gap)
	if axis == "vertical":
		_add_vertical_wall(
			walls,
			id,
			Vector2(float(divider.get("x", 0.0)), float(divider.get("y", 0.0))),
			float(divider.get("height", divider.get("length", 0.0))),
			thickness,
			doors,
			color,
			minimum_gap
		)
	else:
		_add_horizontal_wall(
			walls,
			id,
			Vector2(float(divider.get("x", 0.0)), float(divider.get("y", 0.0))),
			float(divider.get("width", divider.get("length", 0.0))),
			thickness,
			doors,
			color,
			minimum_gap
		)
	return walls


static func room_connection_wall(id_prefix: String, rooms: Array, connection: Dictionary, thickness: float = DEFAULT_BUILDING_WALL_THICKNESS, color = null, minimum_gap: float = DEFAULT_PLAYER_CLEARANCE) -> Array:
	var first: Dictionary = _find_room(rooms, str(connection.get("room_a", "")))
	var second: Dictionary = _find_room(rooms, str(connection.get("room_b", "")))
	if first.is_empty() or second.is_empty():
		return []
	var first_rect: Rect2 = _read_rect(first.get("rect", []))
	var second_rect: Rect2 = _read_rect(second.get("rect", []))
	var wall_id: String = str(connection.get("id", "%s_%s" % [str(first.get("id", "room_a")), str(second.get("id", "room_b"))]))
	var door_width: float = max(minimum_gap, float(connection.get("door_width", DEFAULT_BUILDING_DOOR_WIDTH)))

	var divider: Dictionary = {"id": wall_id}
	if first_rect.end.x <= second_rect.position.x or second_rect.end.x <= first_rect.position.x:
		var left_rect: Rect2 = first_rect if first_rect.get_center().x < second_rect.get_center().x else second_rect
		var right_rect: Rect2 = second_rect if left_rect == first_rect else first_rect
		var overlap_start: float = max(left_rect.position.y, right_rect.position.y)
		var overlap_end: float = min(left_rect.end.y, right_rect.end.y)
		var gap: float = right_rect.position.x - left_rect.end.x
		if overlap_end <= overlap_start or gap < 0.0:
			return []
		divider.merge({
			"axis": "vertical",
			"x": left_rect.end.x,
			"y": overlap_start,
			"height": overlap_end - overlap_start,
			"doors": [[max(0.0, (overlap_end - overlap_start - door_width) * 0.5), door_width]],
		})
		return divider_wall(id_prefix, divider, max(1.0, gap if gap > 0.0 else thickness), color, minimum_gap)

	if first_rect.end.y <= second_rect.position.y or second_rect.end.y <= first_rect.position.y:
		var top_rect: Rect2 = first_rect if first_rect.get_center().y < second_rect.get_center().y else second_rect
		var bottom_rect: Rect2 = second_rect if top_rect == first_rect else first_rect
		var overlap_start: float = max(top_rect.position.x, bottom_rect.position.x)
		var overlap_end: float = min(top_rect.end.x, bottom_rect.end.x)
		var gap: float = bottom_rect.position.y - top_rect.end.y
		if overlap_end <= overlap_start or gap < 0.0:
			return []
		divider.merge({
			"axis": "horizontal",
			"x": overlap_start,
			"y": top_rect.end.y,
			"width": overlap_end - overlap_start,
			"doors": [[max(0.0, (overlap_end - overlap_start - door_width) * 0.5), door_width]],
		})
		return divider_wall(id_prefix, divider, max(1.0, gap if gap > 0.0 else thickness), color, minimum_gap)
	return []


static func horizontal_wall(id: String, x: float, y: float, width: float, thickness: float = 24.0, color = null) -> Dictionary:
	var wall := {
		"id": id,
		"rect": [x, y, width, thickness],
		"collides": true,
	}
	if color != null:
		wall["color"] = color
	return wall


static func vertical_wall(id: String, x: float, y: float, height: float, thickness: float = 24.0, color = null) -> Dictionary:
	var wall := {
		"id": id,
		"rect": [x, y, thickness, height],
		"collides": true,
	}
	if color != null:
		wall["color"] = color
	return wall


static func tree(id: String, position: Vector2, radius: float = 24.0, collides: bool = true) -> Dictionary:
	return {
		"id": id,
		"type": "tree",
		"position": [position.x, position.y],
		"radius": radius,
		"collision_radius": radius * 0.55,
		"collides": collides,
	}


static func _normalize_rooms(rooms_value: Variant, offset: Vector2, rooms_are_local: bool) -> Array:
	var rooms: Array = []
	if not (rooms_value is Array):
		return rooms
	for room_value in rooms_value:
		if not (room_value is Dictionary):
			continue
		var room: Dictionary = room_value.duplicate(true)
		var room_rect := _read_rect(room.get("rect", []))
		if rooms_are_local:
			room_rect.position += offset
		room["rect"] = _rect_to_array(room_rect)
		rooms.append(room)
	return rooms


static func _find_room(rooms: Array, room_id: String) -> Dictionary:
	for room_value in rooms:
		if room_value is Dictionary and str(room_value.get("id", "")) == room_id:
			return room_value
	return {}


static func _add_horizontal_wall(walls: Array, id: String, start: Vector2, width: float, thickness: float, doors: Array, color = null, minimum_gap: float = DEFAULT_PLAYER_CLEARANCE) -> void:
	var cursor := 0.0
	var door_index := 0
	for door in _normalize_doors(doors, minimum_gap):
		var door_start: float = clamp(float(door[0]), 0.0, width)
		var door_width: float = min(max(minimum_gap, float(door[1])), width - door_start)
		if door_start > cursor:
			walls.append(horizontal_wall("%s_%d" % [id, door_index], start.x + cursor, start.y, door_start - cursor, thickness, color))
			door_index += 1
		cursor = max(cursor, door_start + door_width)
	if cursor < width:
		walls.append(horizontal_wall("%s_%d" % [id, door_index], start.x + cursor, start.y, width - cursor, thickness, color))


static func _add_vertical_wall(walls: Array, id: String, start: Vector2, height: float, thickness: float, doors: Array, color = null, minimum_gap: float = DEFAULT_PLAYER_CLEARANCE) -> void:
	var cursor := 0.0
	var door_index := 0
	for door in _normalize_doors(doors, minimum_gap):
		var door_start: float = clamp(float(door[0]), 0.0, height)
		var door_height: float = min(max(minimum_gap, float(door[1])), height - door_start)
		if door_start > cursor:
			walls.append(vertical_wall("%s_%d" % [id, door_index], start.x, start.y + cursor, door_start - cursor, thickness, color))
			door_index += 1
		cursor = max(cursor, door_start + door_height)
	if cursor < height:
		walls.append(vertical_wall("%s_%d" % [id, door_index], start.x, start.y + cursor, height - cursor, thickness, color))


static func _normalize_doors(doors: Variant, minimum_gap: float) -> Array:
	var normalized: Array = []
	if not (doors is Array):
		return normalized
	for door in doors:
		if not (door is Array) or door.size() < 2:
			continue
		var door_array: Array = door
		var door_start: float = max(0.0, float(door_array[0]))
		var door_width: float = max(minimum_gap, float(door_array[1]))
		normalized.append([door_start, door_width])
	normalized.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	return normalized


static func _centered_door(rect: Rect2, side: String, width: float) -> Array:
	if side == "east" or side == "west":
		return [max(0.0, rect.size.y * 0.5 - width * 0.5), width]
	return [max(0.0, rect.size.x * 0.5 - width * 0.5), width]


static func _rect_to_array(rect: Rect2) -> Array:
	return [rect.position.x, rect.position.y, rect.size.x, rect.size.y]


static func _read_rect(value: Variant) -> Rect2:
	if value is Rect2:
		return value
	if value is Array and value.size() >= 4:
		return Rect2(float(value[0]), float(value[1]), float(value[2]), float(value[3]))
	return Rect2()
