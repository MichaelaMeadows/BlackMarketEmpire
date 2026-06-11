extends SceneTree

const MAP_LOADER_SCRIPT := preload("res://scripts/map_loader.gd")
const GAME_STATE_SCRIPT := preload("res://scripts/autoload/game_state.gd")
const MAP_PATH := "res://maps/starter_house.json"

var _failures: int = 0
var _state


func _init() -> void:
	_state = GAME_STATE_SCRIPT.new()
	_state._ready()
	_test_base_state_initializes_from_map()
	_test_raid_readiness_uses_base_crew()
	_test_runner_trade_orders()

	if _failures == 0:
		print("Base state tests passed.")
	else:
		push_error("Base state tests failed: %d failure(s)." % _failures)
	quit(_failures)


func _test_base_state_initializes_from_map() -> void:
	var map_loader = MAP_LOADER_SCRIPT.new()
	get_root().add_child(map_loader)
	_expect(map_loader.load_map(MAP_PATH), "starter house map loads")

	_state.initialize_base_from_map(map_loader.get_map_data())
	var summary: Dictionary = _state.get_base_summary()
	_expect(summary.get("id") == "cypress_house", "base id initializes")
	_expect(summary.get("tier") == "house", "base tier initializes")
	_expect(int(summary.get("room_count", 0)) == 5, "base room count initializes")
	_expect(int(summary.get("facility_count", 0)) == 5, "base facilities initialize")
	_expect(_state.cash == 100, "starting cash is $100")
	_expect(_state.get_stock() == 0, "base starts without stored product")
	_expect(_state.get_storage_capacity() == 20, "starter base stores 20 KG")
	_expect(_state.get_storage_snapshot()["inventory"].get(_state.GOOD_KEY) == _state.get_stock(), "base storage tracks starting stock")
	_expect(not _state.get_owned_facility_for_slot("planning_table").is_empty(), "slot facility lookup works")
	_expect(_state.get_weekly_income_total() == 25, "unemployment benefits pay weekly")
	_expect(_state.get_weekly_payroll_total() == 10, "Benji payroll is $10/week")
	_state.advance_market(7)
	_expect(_state.cash == 115, "weekly benefits minus payroll apply after a week")
	map_loader.free()


func _test_raid_readiness_uses_base_crew() -> void:
	var roster: Array = _state.get_crew_roster()
	_expect(roster.size() == 1, "starter house initializes one crew member")
	_expect(roster[0].get("name") == "Benji", "starter employee is Benji")
	_expect(roster[0].get("job") == "Runner", "Benji is a runner")
	_expect(_state.get_ready_crew_count() == 1, "starter crew is ready")
	var task_result: Dictionary = _state.assign_crew_to_transport_task("benji_runner", "corner_pickup")
	_expect(bool(task_result.get("ok", false)), "Benji can be assigned to transport tasks")
	_state.clear_crew_assignment("benji_runner")

	var result: Dictionary = _state.start_raid("abandoned_depot", false)
	_expect(bool(result.get("ok", false)), "ready crew can start depot raid")
	_expect(_state.get_active_raid_target().get("id") == "abandoned_depot", "active raid target records")
	_state.complete_active_raid(false)

	var removal_result: Dictionary = _state.remove_crew_member("benji_runner")
	_expect(bool(removal_result.get("ok", false)), "dead crew member can be removed")
	_expect(_state.get_crew_roster().is_empty(), "dead crew member is removed from roster")
	_expect(_state.get_ready_crew_count() == 0, "dead crew member is removed from eligible ready crew")
	result = _state.start_raid("abandoned_depot", false)
	_expect(not bool(result.get("ok", false)), "dead crew member cannot satisfy raid crew requirement")
	var buy_result: Dictionary = _state.place_buy_order(1)
	_expect(not bool(buy_result.get("ok", false)), "dead runner cannot take trade orders")


func _test_runner_trade_orders() -> void:
	var state = GAME_STATE_SCRIPT.new()
	state._ready()
	var map_loader = MAP_LOADER_SCRIPT.new()
	get_root().add_child(map_loader)
	_expect(map_loader.load_map(MAP_PATH), "starter house map loads for trade orders")
	state.initialize_base_from_map(map_loader.get_map_data())
	var trade_goods: Array = state.get_available_trade_goods()
	_expect(trade_goods.size() == 1, "early market exposes one trade good")
	_expect(trade_goods[0].get("id") == "fast_food", "early market starts with legal fast-food")
	_expect(int(trade_goods[0].get("buy_price", 0)) < int(trade_goods[0].get("sell_price", 0)), "fast-food has a profitable buy/sell spread")
	_expect(int(trade_goods[0].get("unit_weight_kg", 0)) == 2, "fast-food weighs 2 KG per unit")
	_expect(trade_goods[0].get("remote_inventory_label") == "Infinite", "fast-food remote supply is infinite")
	_expect(trade_goods[0].get("distance_label") == "2 blocks", "fast-food source exposes distance")

	var buy_result: Dictionary = state.place_buy_order(10)
	_expect(bool(buy_result.get("ok", false)), "idle runner can take a buy order")
	var buy_order: Dictionary = buy_result.get("order", {})
	var bought_quantity: int = int(buy_order.get("total_quantity", 0))
	var buy_value: int = int(buy_order.get("value", 0))
	var buy_trips: Array = buy_result.get("trips", [])
	_expect(bought_quantity == 10, "buy order records the requested unit quantity")
	_expect(buy_trips.size() == 1, "buy order dispatches one runner trip immediately")
	_expect(int(buy_trips[0].get("quantity", 0)) == state.get_runner_trip_unit_capacity(), "first buy trip uses runner weight capacity")
	_expect(state.cash == 100 - buy_value, "buy order deducts cash immediately")
	_expect(state.get_stock() == 0, "buy order goods are not stored until runner returns")
	_expect(state.heat == 0, "legal buy order does not add heat")
	_expect(state.get_ready_crew_count() == 0, "runner is busy during buy order")
	_expect(state.get_trade_orders().size() == 1, "parent buy order remains active while runner travels")
	_expect(state.get_trade_trips().size() == 1, "buy trip is tracked in flight")
	var buy_order_rows: Array = state.get_trade_order_rows()
	var buy_queued_row: Dictionary = _find_order_row(buy_order_rows, "order", "Incoming")
	var buy_trip_row: Dictionary = _find_order_row(buy_order_rows, "trip", "Incoming")
	_expect(not buy_queued_row.is_empty(), "buy order manifest includes queued remainder")
	_expect(not buy_trip_row.is_empty(), "buy order manifest includes in-flight trip")
	_expect(int(buy_trip_row.get("load_weight_kg", 0)) == int(buy_trips[0].get("quantity", 0)) * state.get_unit_weight_kg(), "buy trip manifest records load weight")
	_expect(int(buy_trip_row.get("holding_weight_kg", -1)) == 0, "runner holds no buy goods while heading out")
	state.update_trade_trip_progress(str(buy_trips[0].get("id", "")), "away_buy", 3.2)
	buy_trip_row = _find_order_row(state.get_trade_order_rows(), "trip", "Incoming")
	_expect(str(buy_trip_row.get("eta_label", "")) == "4s", "buy trip manifest rounds ETA")
	_expect(int(buy_trip_row.get("holding_weight_kg", 0)) == int(buy_trip_row.get("load_weight_kg", -1)), "runner holds buy goods after reaching source")
	var deposit_result: Dictionary = _complete_buy_trips(state, buy_trips)
	_expect(bool(deposit_result.get("ok", false)), "queued buy trips can deposit when storage has space")
	_expect(state.get_stock() == bought_quantity, "returned goods enter storage")
	_expect(state.get_storage_used() == bought_quantity * state.get_unit_weight_kg(), "storage usage counts item weight")
	_expect(state.get_ready_crew_count() == 1, "runner is ready after buy delivery")
	_expect(state.get_trade_orders().is_empty(), "parent buy order clears after all trips deliver")
	_expect(state.get_trade_trips().is_empty(), "buy trips clear after delivery")

	var sell_result: Dictionary = state.place_sell_order(10)
	_expect(bool(sell_result.get("ok", false)), "idle runner can take a sell order")
	var sell_order: Dictionary = sell_result.get("order", {})
	var sold_quantity: int = int(sell_order.get("total_quantity", 0))
	var sell_value: int = int(sell_order.get("value", 0))
	var sell_trips: Array = sell_result.get("trips", [])
	var cash_before_sale_return: int = state.cash
	_expect(sold_quantity == bought_quantity, "sell order can queue more than one runner load")
	_expect(sell_trips.size() == 1, "sell order dispatches one runner trip immediately")
	_expect(int(sell_trips[0].get("quantity", 0)) == state.get_runner_trip_unit_capacity(), "first sell trip uses runner weight capacity")
	_expect(state.get_available_sell_stock() == 0, "queued sell order reserves stock")
	_expect(state.get_stock() == bought_quantity, "sell order waits until runner reaches storage")
	_expect(state.cash == cash_before_sale_return, "sell order cash waits until runner returns")
	var sell_order_rows: Array = state.get_trade_order_rows()
	var sell_queued_row: Dictionary = _find_order_row(sell_order_rows, "order", "Outgoing")
	var sell_trip_row: Dictionary = _find_order_row(sell_order_rows, "trip", "Outgoing")
	_expect(not sell_queued_row.is_empty(), "sell order manifest includes queued remainder")
	_expect(not sell_trip_row.is_empty(), "sell order manifest includes outgoing trip")
	_expect(str(sell_trip_row.get("risk_label", "")) == "Low", "trade manifest includes future risk field")
	var complete_result: Dictionary = _complete_sell_trips(state, sell_trips)
	_expect(bool(complete_result.get("ok", false)), "queued sell trips complete when runner returns")
	_expect(state.get_stock() == bought_quantity - sold_quantity, "completed sell goods leave storage")
	_expect(state.cash == cash_before_sale_return + sell_value, "sell order adds cash on return")
	_expect(state.heat == 0, "legal sell order does not add heat")
	_expect(state.get_ready_crew_count() == 1, "runner is ready after sell return")
	_expect(state.get_trade_orders().is_empty(), "parent sell order clears after all trips return")
	_expect(state.get_trade_trips().is_empty(), "sell trips clear after return")
	map_loader.free()


func _find_order_row(rows: Array, row_type: String, direction: String) -> Dictionary:
	for row in rows:
		if not (row is Dictionary):
			continue
		if str(row.get("row_type", "")) == row_type and str(row.get("direction", "")) == direction:
			return row
	return {}


func _complete_buy_trips(state, trips: Array) -> Dictionary:
	var result: Dictionary = {"ok": true, "message": ""}
	var pending_trips: Array = trips
	while not pending_trips.is_empty():
		var trip: Dictionary = pending_trips.pop_front()
		result = state.deposit_buy_order(str(trip.get("id", "")))
		if not bool(result.get("ok", false)):
			return result
		pending_trips.append_array(result.get("trips", []))
	return result


func _complete_sell_trips(state, trips: Array) -> Dictionary:
	var result: Dictionary = {"ok": true, "message": ""}
	var pending_trips: Array = trips
	while not pending_trips.is_empty():
		var trip: Dictionary = pending_trips.pop_front()
		var pickup_result: Dictionary = state.pick_up_sell_order(str(trip.get("id", "")))
		if not bool(pickup_result.get("ok", false)):
			return pickup_result
		result = state.complete_sell_order(str(trip.get("id", "")))
		if not bool(result.get("ok", false)):
			return result
		pending_trips.append_array(result.get("trips", []))
	return result


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		_failures += 1
		push_error("FAIL: %s" % label)
