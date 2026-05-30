extends RefCounted
class_name ProgressionTracker

var rules: Array = []
var metrics: Dictionary = {}
var event_counts: Dictionary = {}
var unlocked: Dictionary = {}
var completed_rules: Dictionary = {}
var triggered_events: Array = []
var current_day: int = 0

var _rng = RandomNumberGenerator.new()
var _seed: int = 4242


func set_seed(seed: int) -> void:
	_seed = seed
	_rng.seed = _seed


func load_rules(path: String) -> void:
	_rng.seed = _seed
	rules.clear()
	metrics.clear()
	event_counts.clear()
	unlocked.clear()
	completed_rules.clear()
	triggered_events.clear()
	current_day = 0

	var data: Dictionary = _load_json(path)
	for item in data.get("rules", []):
		if item is Dictionary:
			rules.append(item.duplicate(true))


func record_event(event_type: String, payload: Dictionary = {}) -> Array:
	event_counts[event_type] = int(event_counts.get(event_type, 0)) + 1

	match event_type:
		"sale":
			_add_metric("sold_value", float(payload.get("value", 0.0)))
			_add_item_metric("sold_quantity", str(payload.get("item_id", "")), float(payload.get("quantity", 0.0)))
		"crafted":
			_add_metric("crafted_quantity", float(payload.get("quantity", 0.0)))
			_add_item_metric("crafted_quantity", str(payload.get("item_id", "")), float(payload.get("quantity", 0.0)))
		"kill":
			_add_metric("kills", 1.0)
		_:
			for metric_name in payload.get("metrics", {}):
				_add_metric(str(metric_name), float(payload["metrics"][metric_name]))

	return evaluate_rules()


func advance_day(days: int = 1) -> Array:
	var triggered = []
	for _index in range(max(0, days)):
		current_day += 1
		triggered.append_array(_evaluate_daily_rules())
	return triggered


func evaluate_rules() -> Array:
	var triggered = []
	for rule in rules:
		if _is_rule_completed(rule) and not bool(rule.get("repeat", false)):
			continue
		if _rule_matches(rule):
			triggered.append_array(_fire_rule(rule))
	return triggered


func is_unlocked(unlock_id: String) -> bool:
	return bool(unlocked.get(unlock_id, false))


func get_metric(metric_name: String, item_id: String = "") -> float:
	var key = _metric_key(metric_name, item_id)
	return float(metrics.get(key, 0.0))


func get_event_count(event_type: String) -> int:
	return int(event_counts.get(event_type, 0))


func consume_triggered_events() -> Array:
	var events = triggered_events.duplicate(true)
	triggered_events.clear()
	return events


func _evaluate_daily_rules() -> Array:
	var triggered = []
	for rule in rules:
		if str(rule.get("type", "")) != "random_interval":
			continue
		if _is_rule_completed(rule) and not bool(rule.get("repeat", false)):
			continue
		var interval_days = max(1, int(rule.get("interval_days", 1)))
		if current_day % interval_days != 0:
			continue
		if _rng.randf() <= float(rule.get("chance", 0.0)):
			triggered.append_array(_fire_rule(rule))
	return triggered


func _rule_matches(rule: Dictionary) -> bool:
	match str(rule.get("type", "")):
		"metric_threshold":
			return get_metric(str(rule.get("metric", ""))) >= float(rule.get("threshold", 0.0))
		"item_metric_threshold":
			return get_metric(str(rule.get("metric", "")), str(rule.get("item_id", ""))) >= float(rule.get("threshold", 0.0))
		"event_count_threshold":
			return get_event_count(str(rule.get("event_type", ""))) >= int(rule.get("threshold", 0))
		_:
			return false


func _fire_rule(rule: Dictionary) -> Array:
	var rule_id = str(rule.get("id", ""))
	if rule_id != "" and not bool(rule.get("repeat", false)):
		completed_rules[rule_id] = true

	var triggered = []
	for action in rule.get("actions", []):
		if not (action is Dictionary):
			continue
		var event = _apply_action(rule, action)
		if not event.is_empty():
			triggered.append(event)
			triggered_events.append(event)
	return triggered


func _apply_action(rule: Dictionary, action: Dictionary) -> Dictionary:
	var action_type = str(action.get("type", ""))
	var action_id = str(action.get("id", ""))
	match action_type:
		"unlock":
			if action_id == "":
				return {}
			unlocked[action_id] = true
			return {
				"type": "unlock",
				"id": action_id,
				"rule_id": rule.get("id", ""),
				"message": action.get("message", "Unlocked: %s" % action_id),
			}
		"event":
			if action_id == "":
				return {}
			return {
				"type": "event",
				"id": action_id,
				"rule_id": rule.get("id", ""),
				"message": action.get("message", ""),
			}
		_:
			return {}


func _add_metric(metric_name: String, amount: float) -> void:
	if metric_name == "":
		return
	metrics[_metric_key(metric_name)] = float(metrics.get(_metric_key(metric_name), 0.0)) + amount


func _add_item_metric(metric_name: String, item_id: String, amount: float) -> void:
	if metric_name == "" or item_id == "":
		return
	metrics[_metric_key(metric_name, item_id)] = float(metrics.get(_metric_key(metric_name, item_id), 0.0)) + amount


func _metric_key(metric_name: String, item_id: String = "") -> String:
	return metric_name if item_id == "" else "%s:%s" % [metric_name, item_id]


func _is_rule_completed(rule: Dictionary) -> bool:
	return bool(completed_rules.get(str(rule.get("id", "")), false))


func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("Missing progression data file: %s" % path)
		return {}

	var file = FileAccess.open(path, FileAccess.READ)
	var parsed = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		return parsed

	push_error("Invalid progression data file: %s" % path)
	return {}

