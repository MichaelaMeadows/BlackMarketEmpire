extends SceneTree

const MAP_VALIDATOR := preload("res://scripts/map_validator.gd")

var _failures := 0


func _init() -> void:
	_test_all_shipped_maps_validate()
	_test_validator_reports_authoring_errors()
	if _failures == 0:
		print("Map validation tests passed.")
	else:
		push_error("Map validation tests failed: %d failure(s)." % _failures)
	quit(_failures)


func _test_all_shipped_maps_validate() -> void:
	for path in _map_paths():
		var data := _load_json(path)
		var requires_current_navigation := int(data.get("schema_version", 0)) >= 2
		var issues: Array[String] = MAP_VALIDATOR.validate(data, path, requires_current_navigation)
		_expect(issues.is_empty(), "%s validates%s" % [path.get_file(), ": " + "; ".join(issues) if not issues.is_empty() else ""])


func _test_validator_reports_authoring_errors() -> void:
	var issues: Array[String] = MAP_VALIDATOR.validate({
		"schema_version": 2,
		"id": "broken_map",
		"name": "Broken Map",
		"bounds": [0, 0, 320, 240],
		"player_start": [32, 32],
		"buildings": [{
			"id": "building",
			"rect": [0, 0, 320, 240],
			"collides": false,
			"rooms": [
				{"id": "duplicate", "rect": [16, 16, 100, 100]},
				{"id": "duplicate", "rect": [400, 16, 100, 100]},
			],
		}],
		"facilities": [{"id": "bad_facility", "room_id": "missing", "slot_id": "missing_slot", "position": [40, 40]}],
		"raid_targets": [{"id": "missing_raid", "path": "res://maps/does_not_exist.json"}],
	}, "res://maps/broken.json", false)
	_expect(_contains(issues, "duplicated across the map"), "validator reports duplicate room ids")
	_expect(_contains(issues, "unknown room"), "validator reports invalid facility room references")
	_expect(_contains(issues, "missing map"), "validator reports missing raid maps")


func _map_paths() -> Array[String]:
	var paths: Array[String] = []
	var directory := DirAccess.open("res://maps")
	if directory == null:
		return paths
	directory.list_dir_begin()
	var file_name := directory.get_next()
	while file_name != "":
		if not directory.current_is_dir() and file_name.ends_with(".json"):
			paths.append("res://maps/%s" % file_name)
		file_name = directory.get_next()
	directory.list_dir_end()
	paths.sort()
	return paths


func _load_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}


func _contains(issues: Array[String], fragment: String) -> bool:
	for issue in issues:
		if issue.contains(fragment):
			return true
	return false


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		_failures += 1
		push_error("FAIL: %s" % label)
