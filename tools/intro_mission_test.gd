extends SceneTree

const GAME_STATE_SCRIPT := preload("res://scripts/autoload/game_state.gd")
const INTRO_MISSION_TRACKER_SCRIPT := preload("res://scripts/intro_mission_tracker.gd")

var _failures := 0


func _init() -> void:
	_test_tracker_is_sequential_and_ends()
	_test_game_state_intro_flow()
	if _failures == 0:
		print("Intro mission tests passed.")
	else:
		push_error("Intro mission tests failed: %d failure(s)." % _failures)
	quit(_failures)


func _test_tracker_is_sequential_and_ends() -> void:
	var tracker = INTRO_MISSION_TRACKER_SCRIPT.new()
	_expect(tracker.load_missions("res://data/progression/intro_missions.json"), "intro mission data loads")
	_expect(str(tracker.get_snapshot().get("id", "")) == "first_order", "intro begins with the first buy order")
	var ignored: Dictionary = tracker.record_event("crew_hired", {"role": "muscle"})
	_expect(not bool(ignored.get("changed", false)), "future mission actions do not skip the sequence")
	tracker.record_event("trade_order_placed", {"order_type": "sell", "good_id": "fast_food"})
	_expect(str(tracker.get_snapshot().get("id", "")) == "first_order", "wrong event details do not advance a mission")
	tracker.record_event("trade_order_placed", {"order_type": "buy", "good_id": "fast_food"})
	_expect(str(tracker.get_snapshot().get("id", "")) == "receive_first_goods", "matching event advances to the next mission")


func _test_game_state_intro_flow() -> void:
	var state = GAME_STATE_SCRIPT.new()
	state._ready()
	state.initialize_base_from_map(_load_json("res://maps/starter_house.json"))
	_expect(str(state.get_intro_mission_snapshot().get("id", "")) == "first_order", "GameState exposes the current intro mission")

	var buy: Dictionary = state.place_buy_order(1, 5, "fast_food")
	_expect(bool(buy.get("ok", false)), "tutorial buy order succeeds")
	_expect(str(state.get_intro_mission_snapshot().get("id", "")) == "receive_first_goods", "buy order advances the intro")
	var buy_trip: Dictionary = state.get_trade_trips()[0]
	var deposit: Dictionary = state.deposit_buy_order(str(buy_trip.get("id", "")))
	_expect(bool(deposit.get("ok", false)), "tutorial goods reach storage")
	_expect(str(state.get_intro_mission_snapshot().get("id", "")) == "complete_first_sale", "delivery advances the intro")

	var sell: Dictionary = state.place_sell_order(1, 8, "fast_food")
	_expect(bool(sell.get("ok", false)), "tutorial sell order succeeds")
	var sell_trip: Dictionary = state.get_trade_trips()[0]
	state.pick_up_sell_order(str(sell_trip.get("id", "")))
	var sale_complete: Dictionary = state.complete_sell_order(str(sell_trip.get("id", "")))
	_expect(bool(sale_complete.get("ok", false)), "tutorial sale completes")
	_expect(str(state.get_intro_mission_snapshot().get("id", "")) == "hire_muscle", "completed sale advances the intro")

	var muscle_candidate: Dictionary = {}
	for candidate in state.get_available_hires():
		if candidate is Dictionary and str(candidate.get("role", "")) == "muscle":
			muscle_candidate = candidate
			break
	_expect(not muscle_candidate.is_empty(), "starter hiring pool offers tutorial muscle")
	var hire: Dictionary = state.hire_employee(str(muscle_candidate.get("id", "")))
	_expect(bool(hire.get("ok", false)), "tutorial muscle hire succeeds")
	_expect(str(state.get_intro_mission_snapshot().get("id", "")) == "command_crew", "muscle hire advances the intro")

	state.record_intro_mission_event("squad_order_issued", {"order_type": "hold"})
	_expect(str(state.get_intro_mission_snapshot().get("id", "")) == "complete_depot_raid", "squad order advances the intro")
	var raid_start: Dictionary = state.start_raid("abandoned_depot", true)
	_expect(bool(raid_start.get("ok", false)), "tutorial depot raid starts")
	var raid_complete: Dictionary = state.complete_active_raid(true)
	_expect(bool(raid_complete.get("ok", false)), "tutorial depot raid completes")
	_expect(bool(state.get_intro_mission_snapshot().get("complete", false)), "intro ends in open-ended play")
	state.free()


func _load_json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		_failures += 1
		push_error("FAIL: %s" % label)
