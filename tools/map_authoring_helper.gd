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
		"rooms": options.get("rooms", []),
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
				walls.append_array(divider_wall(id_prefix, divider, thickness, interior_wall_color, minimum_gap))

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
