extends SceneTree

const GAME_STATE_SCRIPT := preload("res://scripts/autoload/game_state.gd")
const BASE_PRODUCTION_STATE_SCRIPT := preload("res://scripts/base_production_state.gd")

var _failures := 0


func _init() -> void:
	_test_intermediate_purchase_and_base_batch()
	_test_worker_requirement_and_cancel_refund()
	if _failures == 0:
		print("Base production tests passed.")
	else:
		push_error("Base production tests failed: %d failure(s)." % _failures)
	quit(_failures)


func _test_intermediate_purchase_and_base_batch() -> void:
	var state = GAME_STATE_SCRIPT.new()
	state._ready()
	state.initialize_base_from_map(_load_json("res://maps/starter_house.json"))
	_expect(not _has_trade_good(state.get_available_trade_goods(), "packaging_stock"), "intermediate suppliers stay hidden during onboarding")
	_complete_intro(state)
	_expect(_has_trade_good(state.get_available_trade_goods(), "packaging_stock"), "depot completion unlocks intermediate suppliers")
	_expect(_has_trade_good(state.get_available_trade_goods(), "plain_wraps"), "depot completion unlocks manufactured outputs for sale")

	var packaging_order: Dictionary = state.place_buy_order(2, 5, "packaging_stock")
	_expect(bool(packaging_order.get("ok", false)), "player can order packaging stock")
	var packaging_trip: Dictionary = state.get_trade_trips()[0]
	state.deposit_buy_order(str(packaging_trip.get("id", "")))
	var textile_order: Dictionary = state.place_buy_order(1, 9, "clean_textiles")
	_expect(bool(textile_order.get("ok", false)), "player can order clean textiles")
	var textile_trip: Dictionary = state.get_trade_trips()[0]
	state.deposit_buy_order(str(textile_trip.get("id", "")))
	_expect(state.get_stock("packaging_stock") == 2 and state.get_stock("clean_textiles") == 1, "intermediate deliveries enter base storage")

	var rows: Array = state.get_base_production_rows()
	_expect(rows.size() == 3, "starter workbench exposes three production recipes")
	var start: Dictionary = state.start_base_production("basic_workbench", "make_plain_wraps")
	_expect(bool(start.get("ok", false)), "workbench starts a batch with available inputs")
	_expect(state.get_stock("packaging_stock") == 0 and state.get_stock("clean_textiles") == 0, "starting a batch reserves its inputs")
	state.advance_base_production(19.0)
	_expect(state.get_stock("plain_wraps") == 0, "batch does not finish before its duration")
	var completed: Array = state.advance_base_production(1.0)
	_expect(completed.size() == 1, "batch completes after enough game time")
	_expect(state.get_stock("plain_wraps") == 3, "manufactured output enters normal storage")
	_expect(state.get_base_production_jobs().is_empty(), "completed batch frees the workbench")
	state.free()


func _test_worker_requirement_and_cancel_refund() -> void:
	var production = BASE_PRODUCTION_STATE_SCRIPT.new()
	production.load_recipes("res://data/production/base_recipes.json")
	var context := {
		"inventory": {"paper_forms": 2, "packaging_stock": 1},
		"storage_inventory": {"paper_forms": 2, "packaging_stock": 1},
		"storage_capacity": 20,
		"facilities": [{"id": "press", "name": "Press", "type": "production", "capacity": 1, "workers_required": 1, "recipe_ids": ["make_clean_labels"]}],
		"ready_production_workers": 0,
		"unit_weights": {},
		"good_names": {},
	}
	var blocked: Dictionary = production.start_job(context, "press", "make_clean_labels")
	_expect(not bool(blocked.get("ok", false)), "future facilities can require production workers")
	context["ready_production_workers"] = 1
	var started: Dictionary = production.start_job(context, "press", "make_clean_labels")
	_expect(bool(started.get("ok", false)), "staffed production facility starts work")
	var canceled: Dictionary = production.cancel_job(context, "press")
	_expect(bool(canceled.get("ok", false)), "active production can be canceled")
	_expect(int(context["inventory"].get("paper_forms", 0)) == 2 and int(context["inventory"].get("packaging_stock", 0)) == 1, "canceling returns reserved inputs")


func _complete_intro(state) -> void:
	state.record_intro_mission_event("trade_order_placed", {"order_type": "buy", "good_id": "fast_food"})
	state.record_intro_mission_event("trade_buy_delivered", {"good_id": "fast_food", "quantity": 1})
	state.record_intro_mission_event("trade_sale_completed", {"good_id": "fast_food", "quantity": 1})
	state.record_intro_mission_event("crew_hired", {"role": "muscle"})
	state.record_intro_mission_event("squad_order_issued", {"order_type": "follow"})
	state.record_intro_mission_event("raid_completed", {"target_id": "abandoned_depot"})


func _has_trade_good(goods: Array, good_id: String) -> bool:
	for good in goods:
		if good is Dictionary and str(good.get("id", "")) == good_id:
			return true
	return false


func _load_json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		_failures += 1
		push_error("FAIL: %s" % label)
