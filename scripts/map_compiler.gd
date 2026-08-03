extends RefCounted
class_name MapCompiler

const MAP_AUTHORING_HELPER := preload("res://tools/map_authoring_helper.gd")


static func compile(source_data: Dictionary) -> Dictionary:
	var result: Dictionary = source_data.duplicate(true)
	var buildings: Array = result.get("buildings", []).duplicate(true) if result.get("buildings", []) is Array else []
	var walls: Array = result.get("walls", []).duplicate(true) if result.get("walls", []) is Array else []
	var layout_values: Variant = result.get("building_layouts", [])
	if layout_values is Array:
		for layout_value in layout_values:
			if not (layout_value is Dictionary):
				continue
			var layout_source: Dictionary = layout_value
			var rect := _read_rect(layout_source.get("rect", []))
			var layout := MAP_AUTHORING_HELPER.building_layout(str(layout_source.get("id", "building")), rect, layout_source)
			buildings.append(layout.get("building", {}))
			walls.append_array(layout.get("walls", []))
	result["buildings"] = buildings
	result["walls"] = walls
	result.erase("building_layouts")
	return result


static func _read_rect(value: Variant) -> Rect2:
	if value is Array and value.size() >= 4:
		return Rect2(float(value[0]), float(value[1]), float(value[2]), float(value[3]))
	return Rect2()
