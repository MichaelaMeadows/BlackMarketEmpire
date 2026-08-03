extends RefCounted
class_name MapValidator

const MAP_NAVIGATION_SCRIPT := preload("res://scripts/map_navigation.gd")
const MAP_COMPILER := preload("res://scripts/map_compiler.gd")
const RECT_COLLECTIONS := ["zones", "walls", "triggers"]
const POSITION_COLLECTIONS := ["props", "npcs", "contacts", "facilities", "cover", "activity_points"]
const ID_COLLECTIONS := ["zones", "buildings", "walls", "props", "npcs", "contacts", "facilities", "cover", "activity_points", "raid_targets", "triggers"]


static func validate(map_data: Dictionary, source_path: String = "", include_navigation: bool = true) -> Array[String]:
	var issues: Array[String] = []
	map_data = MAP_COMPILER.compile(map_data)
	_require_string(map_data, "id", "Map", issues)
	_require_string(map_data, "name", "Map", issues)

	var schema_version := int(map_data.get("schema_version", 0))
	if schema_version < 1:
		issues.append("Map schema_version must be a positive integer.")

	var bounds := _read_rect(map_data.get("bounds", []))
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		issues.append("Map bounds must be [x, y, width, height] with positive dimensions.")

	if not _is_vector2_value(map_data.get("player_start", null)):
		issues.append("Map player_start must be a two-number array.")
	elif bounds.size.x > 0.0 and bounds.size.y > 0.0 and not bounds.has_point(_read_vector2(map_data.get("player_start", []))):
		issues.append("Map player_start lies outside map bounds.")

	for collection_name in ID_COLLECTIONS:
		_validate_collection_type(map_data, collection_name, issues)
		_validate_unique_ids(map_data.get(collection_name, []), collection_name, issues)

	for collection_name in RECT_COLLECTIONS:
		_validate_rect_items(map_data.get(collection_name, []), collection_name, issues)
	for collection_name in POSITION_COLLECTIONS:
		_validate_position_items(map_data.get(collection_name, []), collection_name, bounds, issues)

	var room_lookup := _validate_buildings_and_rooms(map_data, bounds, issues)
	_validate_facilities(map_data.get("facilities", []), room_lookup, issues)
	_validate_raid_targets(map_data.get("raid_targets", []), source_path, issues)

	if include_navigation and bounds.size.x > 0.0 and bounds.size.y > 0.0:
		var navigation = MAP_NAVIGATION_SCRIPT.new()
		navigation.setup(map_data)
		for navigation_issue in navigation.validate_map():
			issues.append("Navigation: %s" % str(navigation_issue))

	return issues


static func _validate_buildings_and_rooms(map_data: Dictionary, bounds: Rect2, issues: Array[String]) -> Dictionary:
	var room_lookup: Dictionary = {}
	for building_value in map_data.get("buildings", []):
		if not (building_value is Dictionary):
			issues.append("buildings contains a non-object entry.")
			continue
		var building: Dictionary = building_value
		var building_id := str(building.get("id", "<missing>"))
		var building_rect := _read_rect(building.get("rect", []))
		if building_rect.size.x <= 0.0 or building_rect.size.y <= 0.0:
			issues.append("Building %s has an invalid rect." % building_id)
		if building.get("rooms", []) is Array and not building.get("rooms", []).is_empty() and bool(building.get("collides", true)):
			issues.append("Building %s has rooms but collides as one solid rectangle." % building_id)
		if not (building.get("rooms", []) is Array):
			issues.append("Building %s rooms must be an array." % building_id)
			continue
		for room_value in building.get("rooms", []):
			if not (room_value is Dictionary):
				issues.append("Building %s contains a non-object room." % building_id)
				continue
			var room: Dictionary = room_value
			var room_id := str(room.get("id", ""))
			if room_id == "":
				issues.append("Building %s contains a room without an id." % building_id)
				continue
			if room_lookup.has(room_id):
				issues.append("Room id %s is duplicated across the map." % room_id)
				continue
			var room_rect := _read_rect(room.get("rect", []))
			if room_rect.size.x <= 0.0 or room_rect.size.y <= 0.0:
				issues.append("Room %s has an invalid rect." % room_id)
			elif not building_rect.encloses(room_rect):
				issues.append("Room %s extends outside building %s." % [room_id, building_id])
			room_lookup[room_id] = {"room": room, "building_id": building_id, "rect": room_rect}
	return room_lookup


static func _validate_facilities(facilities: Variant, room_lookup: Dictionary, issues: Array[String]) -> void:
	if not (facilities is Array):
		return
	for facility_value in facilities:
		if not (facility_value is Dictionary):
			continue
		var facility: Dictionary = facility_value
		var facility_id := str(facility.get("id", "<missing>"))
		var room_id := str(facility.get("room_id", ""))
		if room_id == "":
			continue
		if not room_lookup.has(room_id):
			issues.append("Facility %s references unknown room %s." % [facility_id, room_id])
			continue
		var room_info: Dictionary = room_lookup[room_id]
		if _is_vector2_value(facility.get("position", null)) and not (room_info.get("rect", Rect2()) as Rect2).has_point(_read_vector2(facility.get("position", []))):
			issues.append("Facility %s position lies outside room %s." % [facility_id, room_id])
		var slot_id := str(facility.get("slot_id", ""))
		var room: Dictionary = room_info.get("room", {})
		if slot_id != "" and not room.get("slot_ids", []).has(slot_id):
			issues.append("Facility %s uses slot %s, but room %s does not declare it." % [facility_id, slot_id, room_id])


static func _validate_raid_targets(targets: Variant, source_path: String, issues: Array[String]) -> void:
	if not (targets is Array):
		return
	for target_value in targets:
		if not (target_value is Dictionary):
			continue
		var target: Dictionary = target_value
		var target_id := str(target.get("id", "<missing>"))
		var path := str(target.get("path", ""))
		if path == "":
			issues.append("Raid target %s has no map path." % target_id)
		elif not FileAccess.file_exists(path):
			issues.append("Raid target %s references missing map %s%s." % [target_id, path, " from " + source_path if source_path != "" else ""])


static func _validate_collection_type(map_data: Dictionary, collection_name: String, issues: Array[String]) -> void:
	if map_data.has(collection_name) and not (map_data[collection_name] is Array):
		issues.append("Map collection %s must be an array." % collection_name)


static func _validate_unique_ids(items: Variant, collection_name: String, issues: Array[String]) -> void:
	if not (items is Array):
		return
	var seen: Dictionary = {}
	for item_value in items:
		if not (item_value is Dictionary):
			issues.append("%s contains a non-object entry." % collection_name)
			continue
		var item: Dictionary = item_value
		var item_id := str(item.get("id", ""))
		if item_id == "":
			issues.append("%s contains an entry without an id." % collection_name)
		elif seen.has(item_id):
			issues.append("%s id %s is duplicated." % [collection_name, item_id])
		else:
			seen[item_id] = true


static func _validate_rect_items(items: Variant, collection_name: String, issues: Array[String]) -> void:
	if not (items is Array):
		return
	for item_value in items:
		if not (item_value is Dictionary):
			continue
		var item: Dictionary = item_value
		var rect := _read_rect(item.get("rect", []))
		if rect.size.x <= 0.0 or rect.size.y <= 0.0:
			issues.append("%s item %s has an invalid rect." % [collection_name, str(item.get("id", "<missing>"))])


static func _validate_position_items(items: Variant, collection_name: String, bounds: Rect2, issues: Array[String]) -> void:
	if not (items is Array):
		return
	for item_value in items:
		if not (item_value is Dictionary):
			continue
		var item: Dictionary = item_value
		if not _is_vector2_value(item.get("position", null)):
			issues.append("%s item %s has an invalid position." % [collection_name, str(item.get("id", "<missing>"))])
			continue
		if bounds.size.x > 0.0 and bounds.size.y > 0.0 and not bounds.has_point(_read_vector2(item.get("position", []))):
			issues.append("%s item %s lies outside map bounds." % [collection_name, str(item.get("id", "<missing>"))])


static func _require_string(data: Dictionary, key: String, label: String, issues: Array[String]) -> void:
	if str(data.get(key, "")).strip_edges() == "":
		issues.append("%s %s must be a non-empty string." % [label, key])


static func _is_vector2_value(value: Variant) -> bool:
	return value is Array and value.size() >= 2 and (value[0] is int or value[0] is float) and (value[1] is int or value[1] is float)


static func _read_rect(value: Variant) -> Rect2:
	if value is Array and value.size() >= 4:
		return Rect2(float(value[0]), float(value[1]), float(value[2]), float(value[3]))
	return Rect2()


static func _read_vector2(value: Variant) -> Vector2:
	if value is Array and value.size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	return Vector2.ZERO
