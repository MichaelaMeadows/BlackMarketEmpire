extends RefCounted
class_name IntroMissionTracker

var missions: Array = []
var current_index := 0
var current_progress := 0.0
var intro_complete := false
var final_title := "Operation Open"
var final_message := "The basics are handled. Build the operation your way."


func load_missions(path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Could not open intro mission data: %s" % path)
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		push_error("Intro mission data must contain a dictionary: %s" % path)
		return false
	missions = _read_dictionary_array(parsed.get("missions", []))
	final_title = str(parsed.get("final_title", final_title))
	final_message = str(parsed.get("final_message", final_message))
	reset()
	return not missions.is_empty()


func reset() -> void:
	current_index = 0
	current_progress = 0.0
	intro_complete = missions.is_empty()


func record_event(event_type: String, payload: Dictionary = {}) -> Dictionary:
	if intro_complete or current_index >= missions.size():
		return {"changed": false}
	var mission: Dictionary = missions[current_index]
	if str(mission.get("event_type", "")) != event_type or not _payload_matches(payload, mission.get("matches", {})):
		return {"changed": false}

	var increment_field := str(mission.get("increment_field", ""))
	var increment := float(payload.get(increment_field, 1.0)) if increment_field != "" else 1.0
	current_progress += maxf(0.0, increment)
	var target := maxf(1.0, float(mission.get("target", 1.0)))
	if current_progress < target:
		return {"changed": true, "completed": false, "snapshot": get_snapshot()}

	var completed_mission := mission.duplicate(true)
	current_index += 1
	current_progress = 0.0
	intro_complete = current_index >= missions.size()
	return {
		"changed": true,
		"completed": true,
		"completed_mission": completed_mission,
		"intro_complete": intro_complete,
		"snapshot": get_snapshot(),
	}


func get_snapshot() -> Dictionary:
	if intro_complete or current_index >= missions.size():
		return {
			"complete": true,
			"title": final_title,
			"description": final_message,
			"progress": 0.0,
			"target": 0.0,
		}
	var mission: Dictionary = missions[current_index]
	return {
		"complete": false,
		"index": current_index,
		"count": missions.size(),
		"id": str(mission.get("id", "")),
		"title": str(mission.get("title", "Next Step")),
		"description": str(mission.get("description", "")),
		"progress_label": str(mission.get("progress_label", "Progress")),
		"progress": current_progress,
		"target": maxf(1.0, float(mission.get("target", 1.0))),
	}


func _payload_matches(payload: Dictionary, matches: Variant) -> bool:
	if not (matches is Dictionary):
		return true
	for key in matches:
		if not payload.has(key) or payload[key] != matches[key]:
			return false
	return true


func _read_dictionary_array(value: Variant) -> Array:
	var result: Array = []
	if value is Array:
		for item in value:
			if item is Dictionary:
				result.append(item.duplicate(true))
	return result
