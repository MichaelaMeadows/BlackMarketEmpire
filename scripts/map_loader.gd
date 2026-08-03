extends Node2D
class_name MapLoader

const MAP_NAVIGATION_SCRIPT := preload("res://scripts/map_navigation.gd")
const MAP_COMPILER := preload("res://scripts/map_compiler.gd")
const WORLD_ASSETS := preload("res://scripts/visuals/world_asset_catalog.gd")
const DEFAULT_BACKGROUND := Color(0.06, 0.07, 0.075)
const DEFAULT_GRID_COLOR := Color(0.10, 0.11, 0.12)
const DEFAULT_BUILDING_COLOR := Color(0.16, 0.18, 0.19)
const DEFAULT_BUILDING_TRIM := Color(0.28, 0.32, 0.33)
const DEFAULT_WALL_COLOR := Color(0.33, 0.34, 0.32)
const DEFAULT_ZONE_COLOR := Color(0.10, 0.14, 0.10, 0.65)
const DEFAULT_TREE_COLOR := Color(0.12, 0.33, 0.16)
const ASPHALT := Color(0.055, 0.058, 0.060, 1.0)
const CONCRETE := Color(0.105, 0.108, 0.104, 1.0)
const DIRT := Color(0.090, 0.075, 0.055, 1.0)
const WOODS := Color(0.050, 0.125, 0.060, 0.86)
const INTERIOR_SHADOW := Color(0.0, 0.0, 0.0, 0.22)
const WALL_SHADOW := Color(0.0, 0.0, 0.0, 0.28)
const WARM_LIGHT := Color(1.0, 0.70, 0.30, 0.20)
const COLD_LIGHT := Color(0.35, 0.65, 0.92, 0.16)
const ROOF_SHADOW := Color(0.0, 0.0, 0.0, 0.30)
const ROOF_HIGHLIGHT := Color(1.0, 0.86, 0.55, 0.10)
const MIN_VISIBLE_DOOR_GAP := 56.0

var map_data: Dictionary = {}
var map_path: String = ""
var player_position := Vector2.ZERO
var active_building_id := ""
var navigation
var texture_cache: Dictionary = {}

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED

func load_map(path: String) -> bool:
	map_path = path
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Could not open map file: %s" % path)
		map_data = _empty_map()
		_rebuild_navigation()
		queue_redraw()
		return false

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Map file is not a JSON object: %s" % path)
		map_data = _empty_map()
		_rebuild_navigation()
		queue_redraw()
		return false

	map_data = MAP_COMPILER.compile(parsed)
	texture_cache.clear()
	_rebuild_navigation()
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


func get_base_data() -> Dictionary:
	return map_data.get("base", {})


func get_facilities() -> Array:
	return map_data.get("facilities", [])


func get_raid_targets() -> Array:
	return map_data.get("raid_targets", [])


func get_map_data() -> Dictionary:
	return map_data


func get_navigation():
	return navigation


func get_title() -> String:
	return str(map_data.get("name", "Unknown Map"))


func set_player_position(new_position: Vector2) -> void:
	player_position = new_position
	var new_active_building_id := _get_building_id_at_position(player_position)
	if new_active_building_id != active_building_id:
		active_building_id = new_active_building_id
		queue_redraw()


func is_position_visible(world_position: Vector2) -> bool:
	var building_id := _get_building_id_at_position(world_position)
	return building_id == "" or building_id == active_building_id


func _draw() -> void:
	var bounds: Rect2 = _read_rect(map_data.get("bounds", [-2000.0, -2000.0, 4000.0, 4000.0]))
	_draw_ground(bounds)
	_draw_zone_collection("zones", DEFAULT_ZONE_COLOR)
	_draw_grid(bounds)
	_draw_buildings()
	_draw_walls()
	_draw_props()
	_draw_light_overlays()
	_draw_roofs()


func _draw_ground(bounds: Rect2) -> void:
	draw_rect(bounds, _read_color(map_data.get("background_color", []), DEFAULT_BACKGROUND))
	_draw_pixel_noise(bounds, Color(0.08, 0.09, 0.088, 0.18), 160.0, 12.0)


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


func _draw_zone_collection(collection_name: String, fill_fallback: Color) -> void:
	for item in map_data.get(collection_name, []):
		var rect: Rect2 = _read_rect(item.get("rect", []))
		var material := str(item.get("visual_id", item.get("id", "")))
		var fill_color: Color = _read_color(item.get("color", []), _zone_material_color(material, fill_fallback))
		draw_rect(rect, fill_color)
		_draw_material_texture(rect, material, 0.86)
		_draw_zone_details(rect, material, fill_color)


func _draw_buildings() -> void:
	for item in map_data.get("buildings", []):
		var rect: Rect2 = _read_rect(item.get("rect", []))
		var fill_color: Color = _read_color(item.get("color", []), DEFAULT_BUILDING_COLOR)
		var trim_color: Color = _read_color(item.get("trim_color", []), DEFAULT_BUILDING_TRIM)
		var floor_material := str(item.get("floor_material", item.get("visual_id", "worn_floor")))
		draw_rect(rect.grow(8.0), INTERIOR_SHADOW)
		draw_rect(rect, _floor_material_color(floor_material, fill_color))
		_draw_material_texture(rect, floor_material, 0.92)
		for room in item.get("rooms", []):
			var room_rect: Rect2 = _read_rect(room.get("rect", []))
			var room_color: Color = _read_color(room.get("color", []), _floor_material_color(str(room.get("floor_material", floor_material)), fill_color))
			draw_rect(room_rect, Color(room_color.r, room_color.g, room_color.b, 0.42))
			var room_material := str(room.get("floor_material", floor_material))
			_draw_material_texture(room_rect, room_material, 0.94)
			draw_rect(room_rect, trim_color.darkened(0.35), false, 2.0)
		draw_rect(rect, trim_color, false, float(item.get("outline_width", 3.0)))
		_draw_building_details(rect, str(item.get("kind", "building")), trim_color)


func _draw_walls() -> void:
	for item in map_data.get("walls", []):
		var rect: Rect2 = _read_rect(item.get("rect", []))
		var fill_color: Color = _read_color(item.get("color", []), DEFAULT_WALL_COLOR)
		draw_rect(Rect2(rect.position + Vector2(4.0, 5.0), rect.size), WALL_SHADOW)
		draw_rect(rect, fill_color.darkened(0.15))
		draw_rect(Rect2(rect.position, Vector2(rect.size.x, min(rect.size.y, 5.0))), fill_color.lightened(0.18))
		draw_rect(rect, fill_color.darkened(0.32), false, 2.0)
		_draw_wall_marks(rect, fill_color)


func _draw_props() -> void:
	for item in map_data.get("props", []):
		var prop_type: String = str(item.get("type", "tree"))
		var position: Vector2 = _read_vector2(item.get("position", [0.0, 0.0]))
		var prop_scale: float = float(item.get("scale", 1.0))
		if _draw_sprite_item(item, position, prop_scale):
			continue
		match prop_type:
			"tree":
				var radius: float = float(item.get("radius", 22.0))
				var color: Color = _read_color(item.get("color", []), DEFAULT_TREE_COLOR)
				_draw_tree(position, radius * prop_scale, color)
			"trash":
				_draw_trash(position, prop_scale, _read_color(item.get("color", []), Color(0.13, 0.15, 0.14)))
			"crate":
				_draw_crate(position, prop_scale, _read_color(item.get("color", []), Color(0.33, 0.22, 0.13)))
			"streetlight":
				_draw_streetlight(position, prop_scale)
			"window_light":
				pass
			"sign":
				_draw_sign(position, prop_scale, _read_color(item.get("color", []), Color(0.70, 0.26, 0.20)))
			"furniture":
				_draw_furniture(position, prop_scale, _read_color(item.get("color", []), Color(0.25, 0.19, 0.14)))
			"sofa":
				_draw_sofa(position, prop_scale, _read_color(item.get("color", []), Color(0.20, 0.24, 0.22)))
			"bed":
				_draw_bed(position, prop_scale, _read_color(item.get("color", []), Color(0.18, 0.20, 0.23)))
			"rug":
				_draw_rug(position, prop_scale, _read_color(item.get("color", []), Color(0.36, 0.18, 0.15)))
			"table":
				_draw_table(position, prop_scale, _read_color(item.get("color", []), Color(0.25, 0.17, 0.11)))
			"chair":
				_draw_chair(position, prop_scale, _read_color(item.get("color", []), Color(0.22, 0.16, 0.11)))
			"appliance":
				_draw_appliance(position, prop_scale, _read_color(item.get("color", []), Color(0.24, 0.27, 0.27)))
			"sink":
				_draw_sink(position, prop_scale)
			"toilet":
				_draw_toilet(position, prop_scale)
			"shelf":
				_draw_shelf(position, prop_scale, _read_color(item.get("color", []), Color(0.18, 0.13, 0.09)))
			"cabinet":
				_draw_cabinet(position, prop_scale, _read_color(item.get("color", []), Color(0.24, 0.17, 0.11)))
			"boxes":
				_draw_boxes(position, prop_scale, _read_color(item.get("color", []), Color(0.32, 0.22, 0.13)))
			_:
				_draw_crate(position, prop_scale, _read_color(item.get("color", []), DEFAULT_WALL_COLOR))


func _draw_light_overlays() -> void:
	for item in map_data.get("props", []):
		var position: Vector2 = _read_vector2(item.get("position", [0.0, 0.0]))
		match str(item.get("type", "")):
			"streetlight":
				_draw_light_pool(position, 118.0 * float(item.get("scale", 1.0)), COLD_LIGHT)
			"window_light":
				_draw_light_pool(position, 78.0 * float(item.get("scale", 1.0)), WARM_LIGHT)


func _draw_roofs() -> void:
	for item in map_data.get("buildings", []):
		var rect: Rect2 = _read_rect(item.get("rect", []))
		var building_id := str(item.get("id", ""))
		if building_id == active_building_id:
			continue

		var fill_color: Color = _read_color(item.get("color", []), DEFAULT_BUILDING_COLOR)
		var trim_color: Color = _read_color(item.get("trim_color", []), DEFAULT_BUILDING_TRIM)
		var roof_color: Color = _read_color(item.get("roof_color", []), _roof_color(str(item.get("kind", "building")), fill_color, trim_color))
		draw_rect(rect.grow(7.0), ROOF_SHADOW)
		draw_rect(rect, roof_color)
		_draw_roof_surface(rect, roof_color)
		draw_rect(rect, trim_color.darkened(0.22), false, 4.0)
		_draw_visible_doors(rect, trim_color)


func _zone_material_color(material: String, fallback: Color) -> Color:
	if material.contains("road") or material.contains("asphalt"):
		return ASPHALT
	if material.contains("wood") or material.contains("grass"):
		return WOODS
	if material.contains("dirt"):
		return DIRT
	return fallback


func _floor_material_color(material: String, fallback: Color) -> Color:
	if material.contains("concrete") or material.contains("store"):
		return CONCRETE
	if material.contains("wood"):
		return Color(0.16, 0.12, 0.09)
	if material.contains("tile"):
		return Color(0.13, 0.14, 0.13)
	return fallback


func _draw_zone_details(rect: Rect2, material: String, fill_color: Color) -> void:
	if material.contains("road") or material.contains("asphalt"):
		_draw_pixel_noise(rect, fill_color.lightened(0.16), 96.0, 6.0)
		_draw_road_wear(rect)
		draw_rect(Rect2(rect.position, Vector2(rect.size.x, 5.0)), Color(0.14, 0.15, 0.15, 0.74))
		draw_rect(Rect2(Vector2(rect.position.x, rect.end.y - 5.0), Vector2(rect.size.x, 5.0)), Color(0.025, 0.028, 0.030, 0.55))
		draw_rect(Rect2(rect.position, Vector2(5.0, rect.size.y)), Color(0.14, 0.15, 0.15, 0.55))
		draw_rect(Rect2(Vector2(rect.end.x - 5.0, rect.position.y), Vector2(5.0, rect.size.y)), Color(0.025, 0.028, 0.030, 0.48))
	elif material.contains("wood") or material.contains("grass"):
		_draw_pixel_noise(rect, Color(0.16, 0.30, 0.13, 0.22), 84.0, 8.0)


func _draw_material_texture(rect: Rect2, material: String, alpha: float = 1.0) -> void:
	var texture: Texture2D = WORLD_ASSETS.get_surface_texture(material)
	if texture == null:
		return
	draw_texture_rect(texture, rect, true, Color(1.0, 1.0, 1.0, alpha))


func _roof_color(kind: String, fill_color: Color, trim_color: Color) -> Color:
	if kind == "police_station":
		return Color(0.105, 0.125, 0.145)
	if kind == "warehouse":
		return Color(0.125, 0.130, 0.120)
	if kind == "store":
		return trim_color.darkened(0.34)
	return fill_color.darkened(0.18)


func _draw_roof_surface(rect: Rect2, roof_color: Color) -> void:
	_draw_pixel_noise(rect, roof_color.lightened(0.18), 88.0, 7.0)
	for y in range(int(rect.position.y) + 42, int(rect.end.y), 96):
		draw_line(Vector2(rect.position.x + 18.0, y), Vector2(rect.end.x - 18.0, y), roof_color.darkened(0.20), 2.0)
	draw_rect(Rect2(rect.position, Vector2(rect.size.x, 8.0)), ROOF_HIGHLIGHT)


func _draw_visible_doors(rect: Rect2, trim_color: Color) -> void:
	var door_gaps: Array = _find_exterior_door_gaps(rect)
	if door_gaps.is_empty():
		door_gaps.append({
			"side": "south",
			"start": max(0.0, rect.size.x * 0.5 - 56.0),
			"width": 112.0,
		})

	for gap in door_gaps:
		if not (gap is Dictionary):
			continue
		_draw_door_gap(rect, gap, trim_color)


func _draw_door_gap(rect: Rect2, gap: Dictionary, trim_color: Color) -> void:
	var side := str(gap.get("side", "south"))
	var start := float(gap.get("start", 0.0))
	var width := float(gap.get("width", 112.0))
	var door_color := Color(0.025, 0.022, 0.020, 1.0)
	var mat_color := Color(0.58, 0.42, 0.24, 0.72)
	match side:
		"north":
			var north_door := Rect2(Vector2(rect.position.x + start, rect.position.y - 4.0), Vector2(width, 24.0))
			draw_rect(north_door, door_color)
			draw_rect(Rect2(north_door.position + Vector2(10.0, -14.0), Vector2(max(18.0, width - 20.0), 10.0)), mat_color)
			draw_rect(north_door.grow(3.0), trim_color.lightened(0.16), false, 2.0)
		"east":
			var east_door := Rect2(Vector2(rect.end.x - 20.0, rect.position.y + start), Vector2(24.0, width))
			draw_rect(east_door, door_color)
			draw_rect(Rect2(east_door.position + Vector2(28.0, 10.0), Vector2(10.0, max(18.0, width - 20.0))), mat_color)
			draw_rect(east_door.grow(3.0), trim_color.lightened(0.16), false, 2.0)
		"west":
			var west_door := Rect2(Vector2(rect.position.x - 4.0, rect.position.y + start), Vector2(24.0, width))
			draw_rect(west_door, door_color)
			draw_rect(Rect2(west_door.position + Vector2(-14.0, 10.0), Vector2(10.0, max(18.0, width - 20.0))), mat_color)
			draw_rect(west_door.grow(3.0), trim_color.lightened(0.16), false, 2.0)
		_:
			var south_door := Rect2(Vector2(rect.position.x + start, rect.end.y - 20.0), Vector2(width, 24.0))
			draw_rect(south_door, door_color)
			draw_rect(Rect2(south_door.position + Vector2(10.0, 28.0), Vector2(max(18.0, width - 20.0), 10.0)), mat_color)
			draw_rect(south_door.grow(3.0), trim_color.lightened(0.16), false, 2.0)


func _find_exterior_door_gaps(building_rect: Rect2) -> Array:
	var gaps: Array = []
	gaps.append_array(_find_horizontal_door_gaps(building_rect, "north", building_rect.position.y))
	gaps.append_array(_find_horizontal_door_gaps(building_rect, "south", building_rect.end.y))
	gaps.append_array(_find_vertical_door_gaps(building_rect, "west", building_rect.position.x))
	gaps.append_array(_find_vertical_door_gaps(building_rect, "east", building_rect.end.x))
	return gaps


func _find_horizontal_door_gaps(building_rect: Rect2, side: String, edge_y: float) -> Array:
	var spans: Array = []
	for item in map_data.get("walls", []):
		var wall_rect: Rect2 = _read_rect(item.get("rect", []))
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
	return _gaps_from_spans(side, spans, building_rect.size.x)


func _find_vertical_door_gaps(building_rect: Rect2, side: String, edge_x: float) -> Array:
	var spans: Array = []
	for item in map_data.get("walls", []):
		var wall_rect: Rect2 = _read_rect(item.get("rect", []))
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
	return _gaps_from_spans(side, spans, building_rect.size.y)


func _gaps_from_spans(side: String, spans: Array, length: float) -> Array:
	var gaps: Array = []
	if spans.is_empty():
		return gaps
	spans.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))

	var cursor := 0.0
	for span in spans:
		if not (span is Array) or span.size() < 2:
			continue
		var span_start := float(span[0])
		var span_end := float(span[1])
		if span_start - cursor >= MIN_VISIBLE_DOOR_GAP:
			gaps.append({"side": side, "start": cursor, "width": span_start - cursor})
		cursor = max(cursor, span_end)
	if length - cursor >= MIN_VISIBLE_DOOR_GAP:
		gaps.append({"side": side, "start": cursor, "width": length - cursor})
	return gaps


func _draw_floor_tiles(rect: Rect2, light: Color, dark: Color) -> void:
	var tile := 32
	for x in range(int(rect.position.x), int(rect.end.x), tile):
		draw_line(Vector2(x, rect.position.y), Vector2(x, rect.end.y), dark, 1.0)
	for y in range(int(rect.position.y), int(rect.end.y), tile):
		draw_line(Vector2(rect.position.x, y), Vector2(rect.end.x, y), dark, 1.0)
	_draw_pixel_noise(rect, light, 72.0, 5.0)


func _draw_room_floor_details(rect: Rect2, material: String, color: Color) -> void:
	if material.contains("tile") or material.contains("bath"):
		for x in range(int(rect.position.x), int(rect.end.x), 32):
			draw_line(Vector2(x, rect.position.y), Vector2(x, rect.end.y), color.darkened(0.28), 1.0)
		for y in range(int(rect.position.y), int(rect.end.y), 32):
			draw_line(Vector2(rect.position.x, y), Vector2(rect.end.x, y), color.darkened(0.28), 1.0)
	elif material.contains("carpet") or material.contains("rug"):
		draw_rect(rect.grow(-12.0), Color(color.r, color.g, color.b, 0.25))
		_draw_pixel_noise(rect.grow(-10.0), color.lightened(0.18), 58.0, 4.0)
	elif material.contains("wood"):
		for y in range(int(rect.position.y) + 18, int(rect.end.y), 38):
			draw_line(Vector2(rect.position.x + 12.0, y), Vector2(rect.end.x - 12.0, y), color.darkened(0.24), 1.0)
		_draw_pixel_noise(rect, color.lightened(0.16), 84.0, 4.0)
	else:
		_draw_pixel_noise(rect, color.lightened(0.10), 76.0, 4.0)


func _draw_building_details(rect: Rect2, kind: String, trim_color: Color) -> void:
	var door_width := 64.0 if kind != "police_station" else 86.0
	var door_rect := Rect2(Vector2(rect.get_center().x - door_width * 0.5, rect.end.y - 12.0), Vector2(door_width, 18.0))
	draw_rect(door_rect, Color(0.03, 0.025, 0.022, 1.0))
	draw_rect(door_rect.grow(3.0), trim_color.lightened(0.10), false, 2.0)
	for x in [rect.position.x + 70.0, rect.end.x - 110.0]:
		var window := Rect2(Vector2(x, rect.position.y + 22.0), Vector2(42.0, 12.0))
		draw_rect(window, Color(1.0, 0.70, 0.28, 0.38))
		draw_rect(window, trim_color.darkened(0.28), false, 2.0)


func _draw_wall_marks(rect: Rect2, color: Color) -> void:
	if rect.size.x > rect.size.y:
		for x in range(int(rect.position.x) + 28, int(rect.end.x), 72):
			draw_line(Vector2(x, rect.position.y + 3.0), Vector2(x + 18.0, rect.position.y + 3.0), color.lightened(0.10), 1.0)
	else:
		for y in range(int(rect.position.y) + 28, int(rect.end.y), 72):
			draw_line(Vector2(rect.position.x + 3.0, y), Vector2(rect.position.x + 3.0, y + 18.0), color.lightened(0.10), 1.0)


func _draw_road_wear(rect: Rect2) -> void:
	var lane_y := rect.get_center().y
	if rect.size.x > rect.size.y:
		for x in range(int(rect.position.x) + 80, int(rect.end.x), 220):
			draw_rect(Rect2(Vector2(x, lane_y - 2.0), Vector2(78.0, 4.0)), Color(0.22, 0.22, 0.19, 0.35))
	else:
		var lane_x := rect.get_center().x
		for y in range(int(rect.position.y) + 80, int(rect.end.y), 220):
			draw_rect(Rect2(Vector2(lane_x - 2.0, y), Vector2(4.0, 78.0)), Color(0.22, 0.22, 0.19, 0.35))
	for x in range(int(rect.position.x) + 60, int(rect.end.x), 280):
		var y := rect.position.y + float((x * 37) % max(1, int(rect.size.y)))
		draw_line(Vector2(x, y), Vector2(x + 34.0, y + 12.0), Color(0.0, 0.0, 0.0, 0.28), 2.0)


func _draw_pixel_noise(rect: Rect2, color: Color, spacing: float, size: float) -> void:
	for x in range(int(rect.position.x) + 12, int(rect.end.x), int(spacing)):
		for y in range(int(rect.position.y) + 9, int(rect.end.y), int(spacing)):
			var offset := Vector2(float((x * 13 + y * 7) % 31), float((x * 5 + y * 11) % 29))
			draw_rect(Rect2(Vector2(x, y) + offset, Vector2(size, max(2.0, size * 0.45))), color)


func _draw_tree(position: Vector2, radius: float, color: Color) -> void:
	draw_circle(position + Vector2(6.0, 8.0), radius * 0.72, Color(0.0, 0.0, 0.0, 0.24))
	draw_circle(position, radius, color.darkened(0.08))
	draw_circle(position + Vector2(-radius * 0.25, -radius * 0.18), radius * 0.48, color.lightened(0.20))
	draw_circle(position + Vector2(radius * 0.23, radius * 0.12), radius * 0.44, color.darkened(0.18))
	draw_rect(Rect2(position - Vector2(5.0, -radius * 0.45), Vector2(10.0, radius * 0.65)), Color(0.12, 0.075, 0.04))


func _draw_trash(position: Vector2, prop_scale: float, color: Color) -> void:
	var size := Vector2(22.0, 16.0) * prop_scale
	draw_rect(Rect2(position - size * 0.5 + Vector2(4.0, 5.0), size), Color(0.0, 0.0, 0.0, 0.24))
	draw_rect(Rect2(position - size * 0.5, size), color)
	draw_rect(Rect2(position - size * 0.5, Vector2(size.x, 4.0)), color.lightened(0.22))


func _draw_crate(position: Vector2, prop_scale: float, color: Color) -> void:
	var size := Vector2(28.0, 24.0) * prop_scale
	var rect := Rect2(position - size * 0.5, size)
	draw_rect(Rect2(rect.position + Vector2(4.0, 5.0), rect.size), Color(0.0, 0.0, 0.0, 0.24))
	draw_rect(rect, color)
	draw_rect(rect, color.darkened(0.32), false, 2.0)
	draw_line(rect.position, rect.end, color.darkened(0.18), 2.0)


func _draw_streetlight(position: Vector2, prop_scale: float) -> void:
	draw_rect(Rect2(position + Vector2(-3.0, -34.0) * prop_scale, Vector2(6.0, 54.0) * prop_scale), Color(0.08, 0.09, 0.10))
	draw_rect(Rect2(position + Vector2(-12.0, -40.0) * prop_scale, Vector2(24.0, 8.0) * prop_scale), Color(0.80, 0.86, 0.72))
	draw_circle(position + Vector2(0.0, -36.0) * prop_scale, 9.0 * prop_scale, Color(0.58, 0.76, 0.90, 0.20))


func _draw_sign(position: Vector2, prop_scale: float, color: Color) -> void:
	draw_rect(Rect2(position + Vector2(-2.0, -2.0) * prop_scale, Vector2(4.0, 28.0) * prop_scale), Color(0.08, 0.08, 0.075))
	draw_rect(Rect2(position + Vector2(-24.0, -22.0) * prop_scale, Vector2(48.0, 20.0) * prop_scale), color)
	draw_rect(Rect2(position + Vector2(-24.0, -22.0) * prop_scale, Vector2(48.0, 20.0) * prop_scale), color.darkened(0.35), false, 2.0)


func _draw_furniture(position: Vector2, prop_scale: float, color: Color) -> void:
	var rect := Rect2(position + Vector2(-22.0, -12.0) * prop_scale, Vector2(44.0, 24.0) * prop_scale)
	draw_rect(Rect2(rect.position + Vector2(3.0, 4.0), rect.size), Color(0.0, 0.0, 0.0, 0.20))
	draw_rect(rect, color)
	draw_rect(rect, color.lightened(0.14), false, 2.0)


func _draw_sofa(position: Vector2, prop_scale: float, color: Color) -> void:
	var body := Rect2(position + Vector2(-42.0, -18.0) * prop_scale, Vector2(84.0, 36.0) * prop_scale)
	draw_rect(Rect2(body.position + Vector2(4.0, 5.0), body.size), Color(0.0, 0.0, 0.0, 0.24))
	draw_rect(body, color)
	draw_rect(Rect2(body.position + Vector2(4.0, 4.0) * prop_scale, Vector2(76.0, 12.0) * prop_scale), color.lightened(0.12))
	draw_rect(Rect2(body.position, Vector2(12.0, body.size.y)), color.darkened(0.16))
	draw_rect(Rect2(Vector2(body.end.x - 12.0, body.position.y), Vector2(12.0, body.size.y)), color.darkened(0.16))
	draw_rect(body, color.darkened(0.36), false, 2.0)


func _draw_bed(position: Vector2, prop_scale: float, color: Color) -> void:
	var bed := Rect2(position + Vector2(-34.0, -50.0) * prop_scale, Vector2(68.0, 100.0) * prop_scale)
	draw_rect(Rect2(bed.position + Vector2(4.0, 5.0), bed.size), Color(0.0, 0.0, 0.0, 0.22))
	draw_rect(bed, color.darkened(0.08))
	draw_rect(Rect2(bed.position + Vector2(8.0, 8.0) * prop_scale, Vector2(52.0, 24.0) * prop_scale), Color(0.66, 0.62, 0.52))
	draw_rect(Rect2(bed.position + Vector2(8.0, 38.0) * prop_scale, Vector2(52.0, 54.0) * prop_scale), color.lightened(0.15))
	draw_rect(bed, color.darkened(0.38), false, 2.0)


func _draw_rug(position: Vector2, prop_scale: float, color: Color) -> void:
	var rug := Rect2(position + Vector2(-54.0, -34.0) * prop_scale, Vector2(108.0, 68.0) * prop_scale)
	draw_rect(rug, Color(color.r, color.g, color.b, 0.62))
	draw_rect(rug.grow(-8.0 * prop_scale), Color(color.lightened(0.18).r, color.lightened(0.18).g, color.lightened(0.18).b, 0.34))
	draw_rect(rug, color.darkened(0.24), false, 2.0)


func _draw_table(position: Vector2, prop_scale: float, color: Color) -> void:
	var table := Rect2(position + Vector2(-34.0, -22.0) * prop_scale, Vector2(68.0, 44.0) * prop_scale)
	draw_rect(Rect2(table.position + Vector2(4.0, 5.0), table.size), Color(0.0, 0.0, 0.0, 0.22))
	draw_rect(table, color)
	draw_rect(table.grow(-6.0 * prop_scale), color.lightened(0.14), false, 2.0)
	draw_rect(table, color.darkened(0.34), false, 2.0)


func _draw_chair(position: Vector2, prop_scale: float, color: Color) -> void:
	var seat := Rect2(position + Vector2(-12.0, -12.0) * prop_scale, Vector2(24.0, 24.0) * prop_scale)
	draw_rect(Rect2(seat.position + Vector2(3.0, 4.0), seat.size), Color(0.0, 0.0, 0.0, 0.20))
	draw_rect(seat, color)
	draw_rect(Rect2(seat.position + Vector2(0.0, -8.0) * prop_scale, Vector2(24.0, 8.0) * prop_scale), color.darkened(0.12))
	draw_rect(seat, color.darkened(0.32), false, 2.0)


func _draw_appliance(position: Vector2, prop_scale: float, color: Color) -> void:
	var appliance := Rect2(position + Vector2(-24.0, -24.0) * prop_scale, Vector2(48.0, 48.0) * prop_scale)
	draw_rect(Rect2(appliance.position + Vector2(4.0, 5.0), appliance.size), Color(0.0, 0.0, 0.0, 0.20))
	draw_rect(appliance, color)
	draw_rect(appliance.grow(-7.0 * prop_scale), color.darkened(0.20), false, 2.0)
	draw_circle(appliance.position + Vector2(14.0, 14.0) * prop_scale, 3.0 * prop_scale, color.lightened(0.35))
	draw_rect(appliance, color.darkened(0.40), false, 2.0)


func _draw_sink(position: Vector2, prop_scale: float) -> void:
	var sink := Rect2(position + Vector2(-20.0, -14.0) * prop_scale, Vector2(40.0, 28.0) * prop_scale)
	draw_rect(Rect2(sink.position + Vector2(3.0, 4.0), sink.size), Color(0.0, 0.0, 0.0, 0.18))
	draw_rect(sink, Color(0.52, 0.56, 0.54))
	draw_rect(sink.grow(-7.0 * prop_scale), Color(0.20, 0.24, 0.24), false, 2.0)
	draw_circle(sink.get_center(), 3.0 * prop_scale, Color(0.05, 0.06, 0.06))


func _draw_toilet(position: Vector2, prop_scale: float) -> void:
	draw_rect(Rect2(position + Vector2(-13.0, -24.0) * prop_scale, Vector2(26.0, 18.0) * prop_scale), Color(0.54, 0.56, 0.52))
	draw_circle(position + Vector2(0.0, 8.0) * prop_scale, 16.0 * prop_scale, Color(0.58, 0.60, 0.56))
	draw_circle(position + Vector2(0.0, 8.0) * prop_scale, 8.0 * prop_scale, Color(0.16, 0.18, 0.18))
	draw_circle(position + Vector2(0.0, 8.0) * prop_scale, 16.0 * prop_scale, Color(0.24, 0.26, 0.24, 0.0))


func _draw_shelf(position: Vector2, prop_scale: float, color: Color) -> void:
	var shelf := Rect2(position + Vector2(-18.0, -42.0) * prop_scale, Vector2(36.0, 84.0) * prop_scale)
	draw_rect(Rect2(shelf.position + Vector2(4.0, 5.0), shelf.size), Color(0.0, 0.0, 0.0, 0.20))
	draw_rect(shelf, color)
	for y in range(1, 4):
		var shelf_y := shelf.position.y + float(y) * shelf.size.y / 4.0
		draw_line(Vector2(shelf.position.x + 4.0, shelf_y), Vector2(shelf.end.x - 4.0, shelf_y), color.lightened(0.18), 2.0)
	draw_rect(shelf, color.darkened(0.36), false, 2.0)


func _draw_cabinet(position: Vector2, prop_scale: float, color: Color) -> void:
	var cabinet := Rect2(position + Vector2(-28.0, -14.0) * prop_scale, Vector2(56.0, 28.0) * prop_scale)
	draw_rect(Rect2(cabinet.position + Vector2(3.0, 4.0), cabinet.size), Color(0.0, 0.0, 0.0, 0.20))
	draw_rect(cabinet, color)
	draw_line(Vector2(cabinet.get_center().x, cabinet.position.y + 3.0), Vector2(cabinet.get_center().x, cabinet.end.y - 3.0), color.darkened(0.24), 2.0)
	draw_rect(cabinet, color.darkened(0.32), false, 2.0)


func _draw_boxes(position: Vector2, prop_scale: float, color: Color) -> void:
	_draw_crate(position + Vector2(-13.0, 8.0) * prop_scale, prop_scale * 0.9, color)
	_draw_crate(position + Vector2(16.0, 4.0) * prop_scale, prop_scale * 0.8, color.lightened(0.08))
	_draw_crate(position + Vector2(2.0, -18.0) * prop_scale, prop_scale * 0.75, color.darkened(0.05))


func _draw_sprite_item(item: Dictionary, position: Vector2, prop_scale: float) -> bool:
	var sprite_data := _resolve_sprite_data(item)
	if sprite_data.is_empty():
		return false
	var texture_path := str(sprite_data.get("path", ""))
	if texture_path == "":
		return false
	var texture: Texture2D = _get_texture(texture_path)
	if texture == null:
		return false

	var size := _read_vector2(sprite_data.get("size", item.get("sprite_size", [])))
	if size == Vector2.ZERO:
		size = texture.get_size()
	size *= prop_scale * float(sprite_data.get("scale", 1.0))
	var offset := _read_vector2(sprite_data.get("offset", item.get("sprite_offset", [0.0, 0.0]))) * prop_scale
	var rect := Rect2(position - size * 0.5 + offset, size)
	var rotation_degrees := float(sprite_data.get("rotation_degrees", item.get("rotation_degrees", 0.0)))
	var tint: Color = _read_color(sprite_data.get("tint", item.get("tint", [])), Color.WHITE)
	if not is_equal_approx(rotation_degrees, 0.0):
		draw_set_transform(position + offset, deg_to_rad(rotation_degrees), Vector2.ONE)
		draw_texture_rect(texture, Rect2(-size * 0.5, size), false, tint)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		draw_texture_rect(texture, rect, false, tint)
	return true


func _resolve_sprite_data(item: Dictionary) -> Dictionary:
	var sprite_value: Variant = item.get("sprite", {})
	if sprite_value is Dictionary and not sprite_value.is_empty():
		return sprite_value
	if sprite_value is String:
		return {"path": str(sprite_value)}
	if item.has("sprite_path"):
		return {"path": str(item.get("sprite_path", "")), "size": item.get("sprite_size", [])}

	var assets_value: Variant = map_data.get("sprite_assets", {})
	if not (assets_value is Dictionary):
		return {}
	var visual_id := str(item.get("visual_id", item.get("id", "")))
	var asset_value: Variant = assets_value.get(visual_id, {})
	if asset_value is Dictionary:
		return asset_value
	if asset_value is String:
		return {"path": str(asset_value)}
	return {}


func _get_texture(path: String) -> Texture2D:
	if texture_cache.has(path):
		return texture_cache[path]
	if not ResourceLoader.exists(path):
		texture_cache[path] = null
		return null
	var texture: Resource = load(path)
	if texture is Texture2D:
		texture_cache[path] = texture
		return texture
	texture_cache[path] = null
	return null


func _draw_light_pool(position: Vector2, radius: float, color: Color) -> void:
	draw_circle(position, radius, Color(color.r, color.g, color.b, color.a * 0.28))
	draw_circle(position, radius * 0.55, Color(color.r, color.g, color.b, color.a))


func _rebuild_collision() -> void:
	for child in get_children():
		child.queue_free()

	for collection_name in ["buildings", "walls"]:
		for item in map_data.get(collection_name, []):
			if not bool(item.get("collides", true)):
				continue
			_add_rect_collision(_read_rect(item.get("rect", [])), str(item.get("id", collection_name)))

	for item in map_data.get("props", []):
		if not bool(item.get("collides", false)):
			continue
		_add_circle_collision(
			_read_vector2(item.get("position", [0.0, 0.0])),
			float(item.get("collision_radius", item.get("radius", 22.0))),
			str(item.get("id", "prop"))
		)


func _rebuild_navigation() -> void:
	navigation = MAP_NAVIGATION_SCRIPT.new()
	navigation.setup(map_data)


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


func _add_circle_collision(position: Vector2, radius: float, id: String) -> void:
	var body := StaticBody2D.new()
	body.name = "Collision_%s" % id
	body.position = position
	add_child(body)

	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = radius
	shape.shape = circle
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


func _get_building_id_at_position(world_position: Vector2) -> String:
	for item in map_data.get("buildings", []):
		var rect: Rect2 = _read_rect(item.get("rect", []))
		if rect.has_point(world_position):
			return str(item.get("id", ""))
	return ""


func _empty_map() -> Dictionary:
	return {
		"name": "Empty Map",
		"bounds": [-2000.0, -2000.0, 4000.0, 4000.0],
		"player_start": [0.0, 0.0],
		"buildings": [],
		"walls": [],
		"zones": [],
		"props": [],
		"npcs": [],
		"contacts": [],
		"facilities": [],
		"cover": [],
		"activity_points": [],
		"raid_targets": [],
		"triggers": [],
	}
