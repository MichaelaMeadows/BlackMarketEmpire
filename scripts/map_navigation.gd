extends RefCounted
class_name MapNavigation

const DEFAULT_CELL_SIZE := 32.0
const MAX_NEAREST_CELL_RADIUS := 32
const DERIVED_COVER_OFFSET := 44.0
const DOORWAY_SAMPLE_SPACING_FACTOR := 0.5
const MAX_ROOM_GAP_FACTOR := 3.0

var map_data: Dictionary = {}
var bounds := Rect2(-2000.0, -2000.0, 4000.0, 4000.0)
var cell_size := DEFAULT_CELL_SIZE
var grid_size := Vector2i.ZERO
var astar := AStarGrid2D.new()

var _blocker_rects: Array = []
var _blocker_circles: Array = []
var _cover_points: Array = []
var _rooms: Array = []
var _rooms_by_id: Dictionary = {}
var _doorways: Array = []
var _room_graph: Dictionary = {}
var _cell_regions: Dictionary = {}


func setup(new_map_data: Dictionary) -> void:
	map_data = new_map_data.duplicate(true)
	bounds = _read_rect(map_data.get("bounds", [-2000.0, -2000.0, 4000.0, 4000.0]))
	var navigation_data: Dictionary = map_data.get("navigation", {}) if map_data.get("navigation", {}) is Dictionary else {}
	cell_size = max(8.0, float(navigation_data.get("cell_size", DEFAULT_CELL_SIZE)))
	grid_size = Vector2i(max(1, int(ceil(bounds.size.x / cell_size))), max(1, int(ceil(bounds.size.y / cell_size))))

	_build_blockers()
	_configure_astar()
	_apply_blockers()
	_apply_navigation_overrides(navigation_data)
	_build_cover_points()
	_build_geometry()


func find_path(from: Vector2, to: Vector2) -> PackedVector2Array:
	var from_cell := _nearest_walkable_cell(from)
	var to_position := to if is_walkable(to) else find_nearest_walkable(to)
	var to_cell := _nearest_walkable_cell(to_position)
	var result := PackedVector2Array()
	if from_cell == Vector2i(-1, -1) or to_cell == Vector2i(-1, -1):
		return result

	var id_path: Array = astar.get_id_path(from_cell, to_cell)
	if id_path.is_empty():
		if from.distance_to(to_position) <= cell_size:
			result.append(to_position)
		return result

	for id in id_path:
		result.append(_cell_to_world(id))

	if result.size() > 0 and result[0].distance_to(from) <= cell_size * 0.75:
		result.remove_at(0)
	if result.size() == 0 or result[result.size() - 1].distance_to(to_position) > 1.0:
		result.append(to_position)
	return result


func is_walkable(position: Vector2) -> bool:
	if not bounds.has_point(position):
		return false
	var cell := _world_to_cell(position)
	if not _is_valid_cell(cell):
		return false
	return not astar.is_point_solid(cell)


func find_nearest_walkable(position: Vector2) -> Vector2:
	if is_walkable(position):
		return position
	var cell := _world_to_cell_clamped(position)
	if _is_valid_cell(cell) and not astar.is_point_solid(cell):
		return _cell_to_world(cell)

	var best_cell := Vector2i(-1, -1)
	var best_distance := INF
	for radius in range(1, MAX_NEAREST_CELL_RADIUS + 1):
		for x in range(cell.x - radius, cell.x + radius + 1):
			for y in range(cell.y - radius, cell.y + radius + 1):
				if x != cell.x - radius and x != cell.x + radius and y != cell.y - radius and y != cell.y + radius:
					continue
				var candidate := Vector2i(x, y)
				if not _is_valid_cell(candidate) or astar.is_point_solid(candidate):
					continue
				var distance := _cell_to_world(candidate).distance_to(position)
				if distance < best_distance:
					best_distance = distance
					best_cell = candidate
		if best_cell != Vector2i(-1, -1):
			return _cell_to_world(best_cell)

	for x in range(grid_size.x):
		for y in range(grid_size.y):
			var candidate := Vector2i(x, y)
			if astar.is_point_solid(candidate):
				continue
			var distance := _cell_to_world(candidate).distance_to(position)
			if distance < best_distance:
				best_distance = distance
				best_cell = candidate
	if best_cell == Vector2i(-1, -1):
		return bounds.get_center()
	return _cell_to_world(best_cell)


func find_cover(from: Vector2, threat: Vector2, radius: float, faction: String = "") -> Dictionary:
	var best_cover: Dictionary = {}
	var best_score := -INF
	var reachable_radius: float = max(radius, cell_size)
	for cover in _cover_points:
		if not (cover is Dictionary):
			continue
		var position: Vector2 = cover.get("position", Vector2.ZERO)
		if from.distance_to(position) > reachable_radius:
			continue
		if not is_walkable(position):
			continue
		if find_path(from, position).is_empty() and from.distance_to(position) > cell_size:
			continue

		var has_blocker := _segment_hits_blocker(position, threat)
		var score := float(cover.get("quality", 1.0)) * 12.0
		if has_blocker:
			score += 180.0
		else:
			score -= 20.0
		score += min(position.distance_to(threat) * 0.08, 70.0)
		score -= from.distance_to(position) * 0.18
		if faction != "" and str(cover.get("faction", "")) == faction:
			score += 8.0
		if score > best_score:
			best_score = score
			best_cover = cover.duplicate(true)
			best_cover["line_blocked"] = has_blocker
	if best_cover.is_empty():
		return {}
	return best_cover


func get_room_at(position: Vector2) -> Dictionary:
	for room in _rooms:
		var rect: Rect2 = room.get("rect", Rect2())
		if rect.has_point(position):
			return room.duplicate(true)
	return {}


func get_room_id_at(position: Vector2) -> String:
	var room := get_room_at(position)
	return str(room.get("id", ""))


func get_room(room_id: String) -> Dictionary:
	if not _rooms_by_id.has(room_id):
		return {}
	return _rooms_by_id[room_id].duplicate(true)


func get_rooms() -> Array:
	return _duplicate_array(_rooms)


func get_doorways() -> Array:
	return _duplicate_array(_doorways)


func get_room_graph() -> Dictionary:
	return _room_graph.duplicate(true)


func find_room_path(from_room_id: String, to_room_id: String) -> Array[String]:
	var result: Array[String] = []
	if from_room_id == "" or to_room_id == "":
		return result
	if from_room_id == to_room_id:
		result.append(from_room_id)
		return result
	if not _room_graph.has(from_room_id) or not _room_graph.has(to_room_id):
		return result

	var frontier: Array[String] = [from_room_id]
	var came_from: Dictionary = {from_room_id: ""}
	while not frontier.is_empty():
		var current: String = frontier.pop_front()
		for neighbor in _room_graph.get(current, []):
			var neighbor_id := str(neighbor)
			if came_from.has(neighbor_id):
				continue
			came_from[neighbor_id] = current
			if neighbor_id == to_room_id:
				var cursor := to_room_id
				while cursor != "":
					result.push_front(cursor)
					cursor = str(came_from.get(cursor, ""))
				return result
			frontier.append(neighbor_id)
	return result


func get_region_id(position: Vector2) -> int:
	var cell := _world_to_cell(position)
	if not _is_valid_cell(cell) or astar.is_point_solid(cell):
		cell = _nearest_walkable_cell(position)
	if not _is_valid_cell(cell) or astar.is_point_solid(cell):
		return -1
	return int(_cell_regions.get(cell, -1))


func validate_map() -> Array:
	var issues: Array = []
	var start := find_nearest_walkable(_read_vector2(map_data.get("player_start", [0.0, 0.0])))
	if not is_walkable(start):
		issues.append("Player start is not walkable.")

	var exterior_region_ids := _get_exterior_doorway_region_ids(issues)
	for room in _rooms:
		var room_id := str(room.get("id", "room"))
		var room_position: Vector2 = room.get("position", Vector2.ZERO)
		var room_region := int(room.get("region_id", -1))
		if not bool(room.get("walkable", false)):
			issues.append("Room %s has no walkable interior." % room_id)
			continue
		if find_path(start, room_position).is_empty() and start.distance_to(room_position) > cell_size:
			issues.append("Room %s is not reachable from the player start." % room_id)
		if not _room_has_doorway(room_id):
			issues.append("Room %s has no inferred doorway." % room_id)
		if exterior_region_ids.is_empty() or not exterior_region_ids.has(room_region):
			issues.append("Room %s has no path to an exterior doorway." % room_id)
	return issues


func _build_geometry() -> void:
	_build_regions()
	_build_rooms()
	_build_doorways()
	_build_room_graph()


func _build_regions() -> void:
	_cell_regions.clear()
	var next_region := 0
	for x in range(grid_size.x):
		for y in range(grid_size.y):
			var cell := Vector2i(x, y)
			if astar.is_point_solid(cell) or _cell_regions.has(cell):
				continue
			_flood_region(cell, next_region)
			next_region += 1


func _flood_region(start_cell: Vector2i, region_id: int) -> void:
	var frontier: Array[Vector2i] = [start_cell]
	_cell_regions[start_cell] = region_id
	while not frontier.is_empty():
		var current: Vector2i = frontier.pop_front()
		for neighbor in _get_region_neighbors(current):
			if not _is_valid_cell(neighbor) or astar.is_point_solid(neighbor) or _cell_regions.has(neighbor):
				continue
			_cell_regions[neighbor] = region_id
			frontier.append(neighbor)


func _get_region_neighbors(cell: Vector2i) -> Array[Vector2i]:
	return [
		cell + Vector2i.RIGHT,
		cell + Vector2i.LEFT,
		cell + Vector2i.DOWN,
		cell + Vector2i.UP,
	]


func _build_rooms() -> void:
	_rooms.clear()
	_rooms_by_id.clear()
	for building in map_data.get("buildings", []):
		if not (building is Dictionary):
			continue
		var building_id := str(building.get("id", "building"))
		var building_rect := _read_rect(building.get("rect", []))
		for room in building.get("rooms", []):
			if not (room is Dictionary):
				continue
			var room_data: Dictionary = room.duplicate(true)
			var room_id := str(room_data.get("id", "room_%d" % _rooms.size()))
			var room_rect := _read_rect(room_data.get("rect", []))
			var room_position := _find_walkable_point_in_rect(room_rect)
			var walkable := room_position != Vector2.INF
			if not walkable:
				room_position = room_rect.get_center()
			room_data["id"] = room_id
			room_data["building_id"] = building_id
			room_data["building_rect"] = building_rect
			room_data["rect"] = room_rect
			room_data["position"] = room_position
			room_data["walkable"] = walkable
			room_data["region_id"] = get_region_id(room_position) if walkable else -1
			_rooms.append(room_data)
			_rooms_by_id[room_id] = room_data


func _build_doorways() -> void:
	_doorways.clear()
	for building in map_data.get("buildings", []):
		if not (building is Dictionary):
			continue
		var building_id := str(building.get("id", "building"))
		var building_rect := _read_rect(building.get("rect", []))
		_add_exterior_doorways(building_id, building_rect)
		_add_interior_doorways(building_id)


func _add_exterior_doorways(building_id: String, building_rect: Rect2) -> void:
	for gap in _find_exterior_gaps(building_rect):
		if not (gap is Dictionary):
			continue
		var side := str(gap.get("side", "south"))
		var width := float(gap.get("width", 0.0))
		var start := float(gap.get("start", 0.0))
		var position := _exterior_gap_position(building_rect, side, start, width)
		var walkable_position := find_nearest_walkable(position)
		var room_id := _find_nearest_room_id_for_doorway(walkable_position, building_id)
		_doorways.append({
			"id": "%s_exterior_%s_%d" % [building_id, side, _doorways.size()],
			"kind": "exterior",
			"building_id": building_id,
			"room_a": room_id,
			"room_b": "",
			"position": walkable_position,
			"width": width,
			"side": side,
		})


func _add_interior_doorways(building_id: String) -> void:
	var building_rooms := _get_rooms_for_building(building_id)
	for first_index in range(building_rooms.size()):
		for second_index in range(first_index + 1, building_rooms.size()):
			var first: Dictionary = building_rooms[first_index]
			var second: Dictionary = building_rooms[second_index]
			var adjacency := _get_room_adjacency(first, second)
			if adjacency.is_empty():
				continue
			_add_interior_doorway_runs(first, second, adjacency)


func _add_interior_doorway_runs(first: Dictionary, second: Dictionary, adjacency: Dictionary) -> void:
	var samples := _sample_adjacency_openings(adjacency)
	for sample_run in samples:
		if not (sample_run is Array) or sample_run.is_empty():
			continue
		var position := _average_points(sample_run)
		var side := str(adjacency.get("side", "east"))
		_doorways.append({
			"id": "%s_%s_door_%d" % [str(first.get("id", "room")), str(second.get("id", "room")), _doorways.size()],
			"kind": "interior",
			"building_id": str(first.get("building_id", "")),
			"room_a": str(first.get("id", "")),
			"room_b": str(second.get("id", "")),
			"position": position,
			"width": max(cell_size, sample_run.size() * max(8.0, cell_size * DOORWAY_SAMPLE_SPACING_FACTOR)),
			"side": side,
		})


func _build_room_graph() -> void:
	_room_graph.clear()
	for room in _rooms:
		_room_graph[str(room.get("id", ""))] = []

	for doorway in _doorways:
		if str(doorway.get("kind", "")) != "interior":
			continue
		_connect_room_ids(str(doorway.get("room_a", "")), str(doorway.get("room_b", "")))

	for first_index in range(_rooms.size()):
		for second_index in range(first_index + 1, _rooms.size()):
			var first: Dictionary = _rooms[first_index]
			var second: Dictionary = _rooms[second_index]
			if int(first.get("region_id", -1)) < 0 or int(first.get("region_id", -1)) != int(second.get("region_id", -2)):
				continue
			_connect_room_ids(str(first.get("id", "")), str(second.get("id", "")))


func _connect_room_ids(first_id: String, second_id: String) -> void:
	if first_id == "" or second_id == "" or first_id == second_id:
		return
	if not _room_graph.has(first_id) or not _room_graph.has(second_id):
		return
	var first_neighbors: Array = _room_graph[first_id]
	var second_neighbors: Array = _room_graph[second_id]
	if not first_neighbors.has(second_id):
		first_neighbors.append(second_id)
	if not second_neighbors.has(first_id):
		second_neighbors.append(first_id)
	_room_graph[first_id] = first_neighbors
	_room_graph[second_id] = second_neighbors


func _find_walkable_point_in_rect(rect: Rect2) -> Vector2:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return Vector2.INF
	var center := rect.get_center()
	if rect.has_point(center) and is_walkable(center):
		return center

	var best_position := Vector2.INF
	var best_distance := INF
	for cell in _cells_overlapping_rect(rect):
		var position := _cell_to_world(cell)
		if not rect.has_point(position) or astar.is_point_solid(cell):
			continue
		var distance := position.distance_to(center)
		if distance < best_distance:
			best_distance = distance
			best_position = position
	return best_position


func _get_rooms_for_building(building_id: String) -> Array:
	var result: Array = []
	for room in _rooms:
		if str(room.get("building_id", "")) == building_id:
			result.append(room)
	return result


func _find_exterior_gaps(building_rect: Rect2) -> Array:
	var gaps: Array = []
	gaps.append_array(_find_horizontal_exterior_gaps(building_rect, "north", building_rect.position.y))
	gaps.append_array(_find_horizontal_exterior_gaps(building_rect, "south", building_rect.end.y))
	gaps.append_array(_find_vertical_exterior_gaps(building_rect, "west", building_rect.position.x))
	gaps.append_array(_find_vertical_exterior_gaps(building_rect, "east", building_rect.end.x))
	return gaps


func _find_horizontal_exterior_gaps(building_rect: Rect2, side: String, edge_y: float) -> Array:
	var spans: Array = []
	for item in map_data.get("walls", []):
		if not (item is Dictionary) or not bool(item.get("collides", true)):
			continue
		var wall_rect := _read_rect(item.get("rect", []))
		if wall_rect.size.x <= wall_rect.size.y:
			continue
		if wall_rect.end.x <= building_rect.position.x or wall_rect.position.x >= building_rect.end.x:
			continue
		if side == "north" and abs(wall_rect.position.y - edge_y) > 4.0:
			continue
		if side == "south" and abs(wall_rect.end.y - edge_y) > 4.0:
			continue
		spans.append([
			clamp(wall_rect.position.x - building_rect.position.x, 0.0, building_rect.size.x),
			clamp(wall_rect.end.x - building_rect.position.x, 0.0, building_rect.size.x),
		])
	return _door_gaps_from_spans(side, spans, building_rect.size.x)


func _find_vertical_exterior_gaps(building_rect: Rect2, side: String, edge_x: float) -> Array:
	var spans: Array = []
	for item in map_data.get("walls", []):
		if not (item is Dictionary) or not bool(item.get("collides", true)):
			continue
		var wall_rect := _read_rect(item.get("rect", []))
		if wall_rect.size.y <= wall_rect.size.x:
			continue
		if wall_rect.end.y <= building_rect.position.y or wall_rect.position.y >= building_rect.end.y:
			continue
		if side == "west" and abs(wall_rect.position.x - edge_x) > 4.0:
			continue
		if side == "east" and abs(wall_rect.end.x - edge_x) > 4.0:
			continue
		spans.append([
			clamp(wall_rect.position.y - building_rect.position.y, 0.0, building_rect.size.y),
			clamp(wall_rect.end.y - building_rect.position.y, 0.0, building_rect.size.y),
		])
	return _door_gaps_from_spans(side, spans, building_rect.size.y)


func _door_gaps_from_spans(side: String, spans: Array, length: float) -> Array:
	var gaps: Array = []
	if spans.is_empty():
		return gaps
	spans.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))

	var cursor := 0.0
	var minimum_width: float = max(24.0, cell_size * 0.75)
	for span in spans:
		if not (span is Array) or span.size() < 2:
			continue
		var span_start := float(span[0])
		var span_end := float(span[1])
		if span_start - cursor >= minimum_width:
			gaps.append({"side": side, "start": cursor, "width": span_start - cursor})
		cursor = max(cursor, span_end)
	if length - cursor >= minimum_width:
		gaps.append({"side": side, "start": cursor, "width": length - cursor})
	return gaps


func _exterior_gap_position(building_rect: Rect2, side: String, start: float, width: float) -> Vector2:
	var offset := start + width * 0.5
	match side:
		"north":
			return Vector2(building_rect.position.x + offset, building_rect.position.y)
		"east":
			return Vector2(building_rect.end.x, building_rect.position.y + offset)
		"west":
			return Vector2(building_rect.position.x, building_rect.position.y + offset)
		_:
			return Vector2(building_rect.position.x + offset, building_rect.end.y)


func _find_nearest_room_id_for_doorway(position: Vector2, building_id: String) -> String:
	var best_room_id := ""
	var best_distance := INF
	var doorway_region := get_region_id(position)
	for room in _rooms:
		if str(room.get("building_id", "")) != building_id:
			continue
		if int(room.get("region_id", -1)) != doorway_region:
			continue
		var room_position: Vector2 = room.get("position", Vector2.ZERO)
		var distance := room_position.distance_to(position)
		if distance < best_distance:
			best_distance = distance
			best_room_id = str(room.get("id", ""))
	return best_room_id


func _get_room_adjacency(first: Dictionary, second: Dictionary) -> Dictionary:
	var first_rect: Rect2 = first.get("rect", Rect2())
	var second_rect: Rect2 = second.get("rect", Rect2())
	var max_gap := cell_size * MAX_ROOM_GAP_FACTOR
	var candidates: Array = []

	if first_rect.end.x <= second_rect.position.x or second_rect.end.x <= first_rect.position.x:
		var left: Dictionary = first if first_rect.get_center().x <= second_rect.get_center().x else second
		var right: Dictionary = second if left == first else first
		var left_rect: Rect2 = left.get("rect", Rect2())
		var right_rect: Rect2 = right.get("rect", Rect2())
		var gap := right_rect.position.x - left_rect.end.x
		var overlap_start: float = max(left_rect.position.y, right_rect.position.y)
		var overlap_end: float = min(left_rect.end.y, right_rect.end.y)
		if gap >= 0.0 and gap <= max_gap and overlap_end - overlap_start >= cell_size:
			candidates.append({
				"axis": "y",
				"line": left_rect.end.x + gap * 0.5,
				"start": overlap_start,
				"end": overlap_end,
				"side": "east" if left == first else "west",
			})

	if first_rect.end.y <= second_rect.position.y or second_rect.end.y <= first_rect.position.y:
		var top: Dictionary = first if first_rect.get_center().y <= second_rect.get_center().y else second
		var bottom: Dictionary = second if top == first else first
		var top_rect: Rect2 = top.get("rect", Rect2())
		var bottom_rect: Rect2 = bottom.get("rect", Rect2())
		var gap := bottom_rect.position.y - top_rect.end.y
		var overlap_start: float = max(top_rect.position.x, bottom_rect.position.x)
		var overlap_end: float = min(top_rect.end.x, bottom_rect.end.x)
		if gap >= 0.0 and gap <= max_gap and overlap_end - overlap_start >= cell_size:
			candidates.append({
				"axis": "x",
				"line": top_rect.end.y + gap * 0.5,
				"start": overlap_start,
				"end": overlap_end,
				"side": "south" if top == first else "north",
			})

	if candidates.is_empty():
		return {}
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("end", 0.0)) - float(a.get("start", 0.0)) > float(b.get("end", 0.0)) - float(b.get("start", 0.0))
	)
	return candidates[0]


func _sample_adjacency_openings(adjacency: Dictionary) -> Array:
	var runs: Array = []
	var current_run: Array = []
	var start := float(adjacency.get("start", 0.0))
	var end := float(adjacency.get("end", 0.0))
	var step: float = max(8.0, cell_size * DOORWAY_SAMPLE_SPACING_FACTOR)
	var sample_count: int = max(1, int(ceil((end - start) / step)))
	for index in range(sample_count + 1):
		var offset: float = min(end, start + float(index) * step)
		var position := _adjacency_sample_position(adjacency, offset)
		if is_walkable(position):
			current_run.append(position)
		elif not current_run.is_empty():
			runs.append(current_run)
			current_run = []
	if not current_run.is_empty():
		runs.append(current_run)
	return runs


func _adjacency_sample_position(adjacency: Dictionary, offset: float) -> Vector2:
	var line := float(adjacency.get("line", 0.0))
	if str(adjacency.get("axis", "x")) == "x":
		return Vector2(offset, line)
	return Vector2(line, offset)


func _average_points(points: Array) -> Vector2:
	if points.is_empty():
		return Vector2.ZERO
	var total := Vector2.ZERO
	for point in points:
		total += point as Vector2
	return total / float(points.size())


func _get_exterior_doorway_region_ids(issues: Array) -> Array:
	var region_ids: Array = []
	for doorway in _doorways:
		if str(doorway.get("kind", "")) != "exterior":
			continue
		var position: Vector2 = doorway.get("position", Vector2.ZERO)
		if not is_walkable(position):
			issues.append("Exterior doorway %s is blocked by navigation." % str(doorway.get("id", "doorway")))
			continue
		var region_id := get_region_id(position)
		if region_id >= 0 and not region_ids.has(region_id):
			region_ids.append(region_id)
	return region_ids


func _room_has_doorway(room_id: String) -> bool:
	for doorway in _doorways:
		if str(doorway.get("room_a", "")) == room_id or str(doorway.get("room_b", "")) == room_id:
			return true
	return false


func _duplicate_array(items: Array) -> Array:
	var result: Array = []
	for item in items:
		if item is Dictionary:
			result.append(item.duplicate(true))
		else:
			result.append(item)
	return result


func _configure_astar() -> void:
	astar = AStarGrid2D.new()
	astar.region = Rect2i(Vector2i.ZERO, grid_size)
	astar.cell_size = Vector2(cell_size, cell_size)
	astar.offset = bounds.position + Vector2(cell_size * 0.5, cell_size * 0.5)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.update()


func _build_blockers() -> void:
	_blocker_rects.clear()
	_blocker_circles.clear()

	for collection_name in ["buildings", "walls"]:
		for item in map_data.get(collection_name, []):
			if not (item is Dictionary) or not bool(item.get("collides", true)):
				continue
			var rect := _read_rect(item.get("rect", []))
			if rect.size.x > 0.0 and rect.size.y > 0.0:
				_blocker_rects.append(rect)

	for item in map_data.get("props", []):
		if not (item is Dictionary) or not bool(item.get("collides", false)):
			continue
		_blocker_circles.append({
			"position": _read_vector2(item.get("position", [0.0, 0.0])),
			"radius": float(item.get("collision_radius", item.get("radius", 22.0))),
		})


func _apply_blockers() -> void:
	for x in range(grid_size.x):
		for y in range(grid_size.y):
			var cell := Vector2i(x, y)
			astar.set_point_solid(cell, _cell_is_blocked(cell))


func _apply_navigation_overrides(navigation_data: Dictionary) -> void:
	for item in navigation_data.get("blocked", []):
		_apply_navigation_override(item, true)
	for item in navigation_data.get("walkable", []):
		_apply_navigation_override(item, false)


func _apply_navigation_override(item: Variant, solid: bool) -> void:
	if item is Dictionary and item.has("rect"):
		for cell in _cells_overlapping_rect(_read_rect(item.get("rect", []))):
			astar.set_point_solid(cell, solid)
	elif item is Dictionary and item.has("position"):
		var radius := float(item.get("radius", cell_size * 0.5))
		for cell in _cells_overlapping_circle(_read_vector2(item.get("position", [])), radius):
			astar.set_point_solid(cell, solid)
	elif item is Array and item.size() >= 4:
		for cell in _cells_overlapping_rect(_read_rect(item)):
			astar.set_point_solid(cell, solid)


func _build_cover_points() -> void:
	_cover_points.clear()
	for item in map_data.get("cover", []):
		if not (item is Dictionary):
			continue
		var cover: Dictionary = item.duplicate(true)
		if cover.has("position"):
			cover["position"] = _read_vector2(cover.get("position", []))
		elif cover.has("rect"):
			cover["position"] = _read_rect(cover.get("rect", [])).get_center()
		else:
			continue
		cover["quality"] = float(cover.get("quality", 1.0))
		_cover_points.append(cover)

	for rect in _blocker_rects:
		_add_derived_rect_cover(rect)
	for circle in _blocker_circles:
		_add_derived_circle_cover(circle)


func _add_derived_rect_cover(rect: Rect2) -> void:
	var samples := [
		Vector2(rect.position.x - DERIVED_COVER_OFFSET, rect.get_center().y),
		Vector2(rect.end.x + DERIVED_COVER_OFFSET, rect.get_center().y),
		Vector2(rect.get_center().x, rect.position.y - DERIVED_COVER_OFFSET),
		Vector2(rect.get_center().x, rect.end.y + DERIVED_COVER_OFFSET),
	]
	for position in samples:
		if is_walkable(position):
			_cover_points.append({"id": "derived_rect_cover", "position": position, "quality": 1.0})


func _add_derived_circle_cover(circle: Dictionary) -> void:
	var center: Vector2 = circle.get("position", Vector2.ZERO)
	var offset := float(circle.get("radius", 16.0)) + DERIVED_COVER_OFFSET
	for direction in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		var position: Vector2 = center + direction * offset
		if is_walkable(position):
			_cover_points.append({"id": "derived_circle_cover", "position": position, "quality": 0.8})


func _cell_is_blocked(cell: Vector2i) -> bool:
	var cell_rect := _cell_rect(cell)
	for rect in _blocker_rects:
		if cell_rect.intersects(rect, true) or rect.has_point(cell_rect.get_center()):
			return true
	for circle in _blocker_circles:
		var position: Vector2 = circle.get("position", Vector2.ZERO)
		var radius := float(circle.get("radius", 0.0))
		if _rect_circle_intersects(cell_rect, position, radius):
			return true
	return false


func _cells_overlapping_rect(rect: Rect2) -> Array:
	var cells: Array = []
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return cells
	var start := _world_to_cell_clamped(rect.position)
	var end := _world_to_cell_clamped(rect.end)
	for x in range(start.x, end.x + 1):
		for y in range(start.y, end.y + 1):
			var cell := Vector2i(x, y)
			if _is_valid_cell(cell) and _cell_rect(cell).intersects(rect, true):
				cells.append(cell)
	return cells


func _cells_overlapping_circle(position: Vector2, radius: float) -> Array:
	var cells: Array = []
	var rect := Rect2(position - Vector2(radius, radius), Vector2(radius * 2.0, radius * 2.0))
	for cell in _cells_overlapping_rect(rect):
		if _rect_circle_intersects(_cell_rect(cell), position, radius):
			cells.append(cell)
	return cells


func _segment_hits_blocker(from: Vector2, to: Vector2) -> bool:
	var distance := from.distance_to(to)
	var steps: int = max(1, int(ceil(distance / max(4.0, cell_size * 0.5))))
	for index in range(steps + 1):
		var point := from.lerp(to, float(index) / float(steps))
		for rect in _blocker_rects:
			if rect.has_point(point):
				return true
		for circle in _blocker_circles:
			if point.distance_to(circle.get("position", Vector2.ZERO)) <= float(circle.get("radius", 0.0)):
				return true
	return false


func _rect_circle_intersects(rect: Rect2, center: Vector2, radius: float) -> bool:
	var closest := Vector2(
		clamp(center.x, rect.position.x, rect.end.x),
		clamp(center.y, rect.position.y, rect.end.y)
	)
	return closest.distance_to(center) <= radius


func _nearest_walkable_cell(position: Vector2) -> Vector2i:
	var nearest := find_nearest_walkable(position)
	var cell := _world_to_cell(nearest)
	if _is_valid_cell(cell) and not astar.is_point_solid(cell):
		return cell
	return Vector2i(-1, -1)


func _world_to_cell(position: Vector2) -> Vector2i:
	return Vector2i(
		int(floor((position.x - bounds.position.x) / cell_size)),
		int(floor((position.y - bounds.position.y) / cell_size))
	)


func _world_to_cell_clamped(position: Vector2) -> Vector2i:
	var cell := _world_to_cell(position)
	return Vector2i(clamp(cell.x, 0, max(0, grid_size.x - 1)), clamp(cell.y, 0, max(0, grid_size.y - 1)))


func _cell_to_world(cell: Vector2i) -> Vector2:
	return bounds.position + Vector2(float(cell.x) + 0.5, float(cell.y) + 0.5) * cell_size


func _cell_rect(cell: Vector2i) -> Rect2:
	return Rect2(bounds.position + Vector2(float(cell.x), float(cell.y)) * cell_size, Vector2(cell_size, cell_size))


func _is_valid_cell(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < grid_size.x and cell.y < grid_size.y


func _read_rect(value: Variant) -> Rect2:
	if value is Array and value.size() >= 4:
		return Rect2(float(value[0]), float(value[1]), float(value[2]), float(value[3]))
	return Rect2()


func _read_vector2(value: Variant) -> Vector2:
	if value is Array and value.size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	return Vector2.ZERO
