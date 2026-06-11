extends SceneTree

const PROGRESSION_TRACKER_SCRIPT = preload("res://scripts/progression_tracker.gd")
const GAME_STATE_SCRIPT = preload("res://scripts/autoload/game_state.gd")
const RULE_PATH = "res://data/progression/unlock_rules.json"

var _failures: int = 0


func _init() -> void:
	_test_rules_load()
	_test_sale_value_unlocks_once()
	_test_specific_item_sales_unlock()
	_test_kill_event_unlock()
	_test_random_interval_rule()
	_test_generic_metric_payload()
	_test_game_state_records_sale_progress()
	_test_game_state_records_daily_production_progress()

	if _failures == 0:
		print("Progression tests passed.")
	else:
		push_error("Progression tests failed: %d failure(s)." % _failures)
	quit(_failures)


func _test_rules_load() -> void:
	var tracker = _new_tracker(5)
	_expect(tracker.rules.size() >= 5, "loads sample progression rules")


func _test_sale_value_unlocks_once() -> void:
	var tracker = _new_tracker(7)
	var first: Array = tracker.record_event("sale", {
		"item_id": "street_goods",
		"quantity": 2,
		"value": 40,
	})
	var second: Array = tracker.record_event("sale", {
		"item_id": "street_goods",
		"quantity": 3,
		"value": 70,
	})
	var third: Array = tracker.record_event("sale", {
		"item_id": "street_goods",
		"quantity": 1,
		"value": 20,
	})
	_expect(first.is_empty(), "sale value below threshold does not unlock early")
	_expect(tracker.is_unlocked("bulk_buyer_intro"), "sale value threshold unlocks")
	_expect(_count_event(second, "bulk_buyer_intro") == 1, "sale value unlock fires when threshold is crossed")
	_expect(third.is_empty(), "non-repeat sale value rule does not fire twice")
	_expect(tracker.get_metric("sold_value") == 130.0, "sale value metric accumulates")


func _test_specific_item_sales_unlock() -> void:
	var tracker = _new_tracker(11)
	tracker.record_event("sale", {
		"item_id": "hush_tabs",
		"quantity": 20,
		"value": 1000,
	})
	_expect(not tracker.is_unlocked("street_goods_route"), "other item sales do not satisfy specific item rule")
	tracker.record_event("sale", {
		"item_id": "street_goods",
		"quantity": 12,
		"value": 180,
	})
	_expect(tracker.is_unlocked("street_goods_route"), "specific item quantity threshold unlocks")
	_expect(tracker.get_metric("sold_quantity", "street_goods") == 12.0, "item sale metric accumulates by good")


func _test_kill_event_unlock() -> void:
	var tracker = _new_tracker(13)
	var triggered: Array = tracker.record_event("kill", {"target_type": "npc"})
	_expect(tracker.is_unlocked("heat_attention"), "kill event count unlocks heat attention")
	_expect(_count_event(triggered, "heat_attention_warning") == 1, "kill event can trigger event action")
	_expect(tracker.get_event_count("kill") == 1, "kill event count increments")


func _test_random_interval_rule() -> void:
	var tracker = PROGRESSION_TRACKER_SCRIPT.new()
	tracker.set_seed(17)
	tracker.rules = [
		{
			"id": "daily_test",
			"type": "random_interval",
			"interval_days": 2,
			"chance": 1.0,
			"repeat": true,
			"actions": [{"type": "event", "id": "daily_test_event"}],
		}
	]
	var day_one: Array = tracker.advance_day()
	var day_two: Array = tracker.advance_day()
	var day_four: Array = tracker.advance_day(2)
	_expect(day_one.is_empty(), "random interval waits for interval day")
	_expect(_count_event(day_two, "daily_test_event") == 1, "random interval fires on interval day")
	_expect(_count_event(day_four, "daily_test_event") == 1, "repeat random interval can fire again")


func _test_generic_metric_payload() -> void:
	var tracker = PROGRESSION_TRACKER_SCRIPT.new()
	tracker.rules = [
		{
			"id": "custom_metric",
			"type": "metric_threshold",
			"metric": "crew_trust",
			"threshold": 3,
			"actions": [{"type": "unlock", "id": "trusted_runner"}],
		}
	]
	tracker.record_event("crew_helped", {"metrics": {"crew_trust": 2}})
	_expect(not tracker.is_unlocked("trusted_runner"), "custom metric below threshold waits")
	tracker.record_event("crew_helped", {"metrics": {"crew_trust": 1}})
	_expect(tracker.is_unlocked("trusted_runner"), "custom metric payload can unlock")


func _test_game_state_records_sale_progress() -> void:
	var state = GAME_STATE_SCRIPT.new()
	state._ready()
	state.inventory["street_goods"] = 20
	state.sell_to_buyer(12, 10, "street_goods")
	_expect(state.is_unlocked("bulk_buyer_intro"), "GameState sale records value progression")
	_expect(state.is_unlocked("street_goods_route"), "GameState sale records item quantity progression")
	state.free()


func _test_game_state_records_daily_production_progress() -> void:
	var state = GAME_STATE_SCRIPT.new()
	state._ready()
	state.advance_market(2)
	_expect(state.get_progress_metric("crafted_quantity", "street_goods") > 0.0, "GameState daily market advance records crafted item metrics")
	state.free()


func _new_tracker(seed: int):
	var tracker = PROGRESSION_TRACKER_SCRIPT.new()
	tracker.set_seed(seed)
	tracker.load_rules(RULE_PATH)
	return tracker


func _count_event(events: Array, event_id: String) -> int:
	var count: int = 0
	for event in events:
		if event is Dictionary and str(event.get("id", "")) == event_id:
			count += 1
	return count


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		_failures += 1
		push_error("FAIL: %s" % label)
