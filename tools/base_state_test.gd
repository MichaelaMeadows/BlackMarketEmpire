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
	_test_game_clock_advances_days()
	_test_raid_readiness_uses_base_crew()
	_test_departure_death_excludes_crew_from_raid()
	_test_hiring_pool()
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
	_expect(_state.get_base_role_limit("transporter") == 5, "starter base allows five transporters")
	_expect(_state.get_base_role_limit("muscle") == 3, "starter base allows three muscle")
	_expect(_state.get_base_role_limit("production") == 0, "starter base starts with no producer slots")
	_expect(_state.can_base_accept_role("transporter"), "starter base has room for more transporters")
	_expect(_state.can_base_accept_role("muscle"), "starter base has room for muscle")
	_expect(not _state.can_base_accept_role("production"), "starter base cannot hire producers yet")
	var role_limits: Dictionary = summary.get("role_limits", {})
	var role_counts: Dictionary = summary.get("role_counts", {})
	_expect(int(role_limits.get("transporter", 0)) == 5, "base summary exposes transporter limit")
	_expect(int(role_limits.get("muscle", 0)) == 3, "base summary exposes muscle limit")
	_expect(int(role_limits.get("production", -1)) == 0, "base summary exposes producer limit")
	_expect(int(role_counts.get("transporter", 0)) == 1, "base summary counts one transporter")
	_expect(int(role_counts.get("muscle", -1)) == 0, "base summary counts no muscle")
	_expect(int(role_counts.get("production", -1)) == 0, "base summary counts no producers")
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


func _test_game_clock_advances_days() -> void:
	var state = GAME_STATE_SCRIPT.new()
	state._ready()
	_expect(is_equal_approx(state.get_day_length_seconds(), 360.0), "one game day lasts six minutes")
	_expect(state.get_clock_label() == "Sun, Apr 20, 2025  00:00", "calendar starts on April 20 2025 at midnight")
	var start_snapshot: Dictionary = state.get_clock_snapshot()
	_expect(int(start_snapshot.get("year", 0)) == 2025, "clock snapshot exposes calendar year")
	_expect(int(start_snapshot.get("month", 0)) == 4, "clock snapshot exposes calendar month")
	_expect(int(start_snapshot.get("day_of_month", 0)) == 20, "clock snapshot exposes calendar day")
	var half_day_result: Dictionary = state.advance_game_time(180.0)
	_expect(int(half_day_result.get("days_advanced", -1)) == 0, "half a day does not advance calendar day")
	_expect(state.get_clock_label() == "Sun, Apr 20, 2025  12:00", "half a six-minute day reads noon on start date")
	var rollover_result: Dictionary = state.advance_game_time(180.0)
	_expect(int(rollover_result.get("days_advanced", 0)) == 1, "six minutes advances one game day")
	_expect(state.day_count == 1, "clock rollover increments day count")
	_expect(state.get_clock_label() == "Mon, Apr 21, 2025  00:00", "clock rolls to next calendar day")


func _test_raid_readiness_uses_base_crew() -> void:
	var roster: Array = _state.get_crew_roster()
	_expect(roster.size() == 1, "starter house initializes one crew member")
	_expect(roster[0].get("name") == "Benji", "starter employee is Benji")
	_expect(roster[0].get("role") == "transporter", "Benji is a transporter")
	_expect(roster[0].get("role_name") == "Transporter", "Benji exposes a role label")
	_expect(roster[0].get("archetype") == "dealer", "Benji is a dealer transporter")
	_expect(roster[0].get("job") == "Dealer", "Benji keeps a legacy job label")
	_expect(int(roster[0].get("carry_capacity_kg", 0)) == 5, "dealer transporter carries 5 KG")
	_expect(_state.get_ready_crew_count() == 1, "starter crew is ready")
	_expect(_state.get_ready_crew_count("transporter") == 1, "starter transporter is ready")
	_expect(_state.get_ready_crew_count("muscle") == 0, "starter crew has no muscle")
	var task_result: Dictionary = _state.assign_crew_to_transport_task("benji_runner", "corner_pickup")
	_expect(bool(task_result.get("ok", false)), "Benji can be assigned to transport tasks")
	_state.clear_crew_assignment("benji_runner")

	var result: Dictionary = _state.start_raid("abandoned_depot", false)
	_expect(bool(result.get("ok", false)), "ready crew can start depot raid")
	_expect(_state.get_active_raid_target().get("id") == "abandoned_depot", "active raid target records")
	_state.complete_active_raid(false)

	var send_result: Dictionary = _state.send_raid("abandoned_depot", ["benji_runner"])
	_expect(bool(send_result.get("ok", false)), "selected crew can be sent toward raid")
	_expect(str(_state.get_active_raid_target().get("mode", "")) == "departing", "sent raid waits for crew departure")
	var leaving_benji: Dictionary = _find_crew_member(_state.get_crew_roster(), "benji_runner")
	_expect(str(leaving_benji.get("status", "")) == "Leaving", "sent crew leaves ready duty before raid starts")
	_expect(_state.get_ready_crew_count() == 0, "departing crew is not counted as ready")
	_expect(int(_state.get_raid_stats().get("launched", 0)) == 1, "previous joined raid is the only launched raid before departure finishes")
	var begin_result: Dictionary = _state.begin_sent_raid(["benji_runner"])
	_expect(bool(begin_result.get("ok", false)), "departed crew starts raid after leaving map")
	_expect(str(_state.get_active_raid_target().get("mode", "")) == "sent", "departed raid records active mode")
	var raiding_benji: Dictionary = _find_crew_member(_state.get_crew_roster(), "benji_runner")
	_expect(str(raiding_benji.get("status", "")) == "Raiding", "departed crew participates in raid")
	var sent_complete_result: Dictionary = _state.complete_active_raid(true)
	_expect(bool(sent_complete_result.get("ok", false)), "sent raid can resolve")
	var raid_report: Dictionary = _state.get_last_raid_report()
	_expect(bool(raid_report.get("success", false)), "sent raid records a successful report")
	_expect(PackedStringArray(raid_report.get("survivors", [])).has("Benji"), "sent raid report records returned crew")
	_expect(PackedStringArray(raid_report.get("enemy_casualties", [])).has("Depot Guard"), "sent raid report records enemy deaths")
	_expect(PackedStringArray(raid_report.get("enemy_casualties", [])).has("Depot Lookout"), "sent raid report records all defeated enemies")
	var returned_benji: Dictionary = _find_crew_member(_state.get_crew_roster(), "benji_runner")
	_expect(str(returned_benji.get("status", "")) == "Ready", "surviving sent crew returns ready")
	_expect(int(returned_benji.get("health", 0)) < int(returned_benji.get("max_health", 0)), "surviving sent crew can return wounded")
	var wounded_health := int(returned_benji.get("health", 0))
	_state.advance_market(2)
	returned_benji = _find_crew_member(_state.get_crew_roster(), "benji_runner")
	_expect(int(returned_benji.get("health", 0)) == wounded_health + 2, "wounded crew heals slowly over days")
	_state.set_player_health(75, 100)
	_state.advance_market(3)
	_expect(int(_state.get_player_health().get("health", 0)) == 78, "player heals slowly over days")
	_expect(_state.get_ready_crew_count() == 1, "surviving sent crew counts as ready again")

	var removal_result: Dictionary = _state.remove_crew_member("benji_runner")
	_expect(bool(removal_result.get("ok", false)), "dead crew member can be removed")
	_expect(_state.get_crew_roster().is_empty(), "dead crew member is removed from roster")
	_expect(_state.get_ready_crew_count() == 0, "dead crew member is removed from eligible ready crew")
	result = _state.start_raid("abandoned_depot", false)
	_expect(not bool(result.get("ok", false)), "dead crew member cannot satisfy raid crew requirement")
	var buy_result: Dictionary = _state.place_buy_order(1)
	_expect(not bool(buy_result.get("ok", false)), "dead transporter cannot take trade orders")


func _test_departure_death_excludes_crew_from_raid() -> void:
	var state = GAME_STATE_SCRIPT.new()
	state._ready()
	var map_loader = MAP_LOADER_SCRIPT.new()
	get_root().add_child(map_loader)
	_expect(map_loader.load_map(MAP_PATH), "starter house map loads for departure death")
	state.initialize_base_from_map(map_loader.get_map_data())

	var send_result: Dictionary = state.send_raid("abandoned_depot", ["benji_runner"])
	_expect(bool(send_result.get("ok", false)), "crew can start leaving for a raid")
	var removal_result: Dictionary = state.remove_crew_member("benji_runner")
	_expect(bool(removal_result.get("ok", false)), "crew can die before leaving the map")
	var begin_result: Dictionary = state.begin_sent_raid(["benji_runner"])
	_expect(not bool(begin_result.get("ok", false)), "dead departing crew does not participate in raid")
	_expect(state.get_active_raid_target().is_empty(), "raid cancels if nobody reaches the exit")
	_expect(int(state.get_raid_stats().get("launched", 0)) == 0, "departure death does not count as a launched raid")
	map_loader.free()


func _test_hiring_pool() -> void:
	var state = GAME_STATE_SCRIPT.new()
	state._ready()
	var map_loader = MAP_LOADER_SCRIPT.new()
	get_root().add_child(map_loader)
	_expect(map_loader.load_map(MAP_PATH), "starter house map loads for hiring")
	state.initialize_base_from_map(map_loader.get_map_data())

	var hires: Array = state.get_available_hires()
	_expect(hires.size() == 2, "starter hiring pool starts with two candidates")
	_expect(str(hires[0].get("archetype", "")) == "thug", "first starter hire is a thug")
	_expect(str(hires[1].get("archetype", "")) == "thug", "second starter hire is a thug")
	_expect(str(hires[0].get("name", "")) != "", "hire candidate exposes a name")
	_expect(int(hires[0].get("price", 0)) > 0, "hire candidate exposes a price")
	_expect(str(hires[0].get("job", "")) != "", "hire candidate exposes a job")
	_expect(str(hires[0].get("role", "")) != "", "hire candidate exposes a role")
	_expect(bool(hires[0].get("can_hire", false)), "affordable starter candidate can be hired")
	_expect(bool(hires[1].get("can_hire", false)), "second starter thug is also affordable")
	_expect(not bool(hires[0].get("ranged_weapon", true)), "thug candidate has no ranged weapon")
	_expect(hires[0].get("weapon") == null, "thug candidate weapon slot is empty")
	var candidate_melee: Variant = hires[0].get("melee_weapon", {})
	_expect(candidate_melee is Dictionary, "thug candidate starts with melee weapon data")

	var cash_before_hire: int = state.cash
	var roster_size_before_hire: int = state.get_crew_roster().size()
	var hire_price: int = int(hires[0].get("price", 0))
	var hire_result: Dictionary = state.hire_employee(str(hires[0].get("id", "")))
	_expect(bool(hire_result.get("ok", false)), "candidate can be hired")
	_expect(state.cash == cash_before_hire - hire_price, "hiring spends candidate price")
	_expect(state.get_crew_roster().size() == roster_size_before_hire + 1, "hiring adds a crew member")
	var hired_member: Dictionary = hire_result.get("crew_member", {})
	var hired_id := str(hired_member.get("id", ""))
	_expect(hired_id.begins_with("hireling_"), "hired crew receives a persistent crew id")
	_expect(str(hired_member.get("faction", "")) == "player_crew", "hired crew is marked as player crew")
	_expect(str(hired_member.get("archetype", "")) == "thug", "hired starter crew is a thug")
	_expect(not bool(hired_member.get("ranged_weapon", true)), "hired thug has no ranged weapon")
	_expect(hired_member.get("weapon") == null, "hired thug has no ranged weapon data")
	var hired_melee: Dictionary = hired_member.get("melee_weapon", {})
	_expect(str(hired_melee.get("weapon_type", "")) == "bat", "hired thug starts with a bat")
	var remaining_hires: Array = state.get_available_hires()
	var second_candidate: Dictionary = remaining_hires[0]
	var second_hire: Dictionary = state.hire_employee(str(second_candidate.get("id", "")))
	_expect(bool(second_hire.get("ok", false)), "can buy two starter thugs with starting cash")
	_expect(state.get_ready_crew_count("muscle") == 2, "two hired thugs count as ready muscle")
	state.initialize_base_from_map(map_loader.get_map_data())
	_expect(_has_crew_member(state.get_crew_roster(), hired_id), "same base reload preserves hired crew")
	_expect(state.get_available_hires().size() == 0, "hiring both starter thugs empties the pool")
	state.advance_market(2)
	_expect(state.get_available_hires().size() == 0, "hiring pool does not refill before cadence")
	state.advance_market(1)
	_expect(state.get_available_hires().size() == 1, "hiring pool gains a candidate after cadence")
	map_loader.free()


func _test_runner_trade_orders() -> void:
	var state = GAME_STATE_SCRIPT.new()
	state._ready()
	var map_loader = MAP_LOADER_SCRIPT.new()
	get_root().add_child(map_loader)
	_expect(map_loader.load_map(MAP_PATH), "starter house map loads for trade orders")
	state.initialize_base_from_map(map_loader.get_map_data())
	var trade_goods: Array = state.get_available_trade_goods()
	_expect(trade_goods.size() == 1, "early market exposes one trade good")
	_expect(trade_goods[0].get("id") == "fast_food", "early market starts with fast food")
	_expect(trade_goods[0].get("name") == "Fast Food", "fast food name omits legality")
	_expect(trade_goods[0].get("legality") == "legal", "fast food legality is legal")
	_expect(trade_goods[0].get("legality_label") == "Legal", "fast food exposes a legality label")
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
	_expect(str(buy_queued_row.get("legality_label", "")) == "Legal", "queued order details expose legality")
	_expect(int(buy_queued_row.get("unit_price", 0)) > 0, "queued order details expose unit price")
	_expect(int(buy_queued_row.get("value", 0)) == buy_value, "queued order details expose total value")
	_expect(str(buy_trip_row.get("order_id", "")) == str(buy_order.get("id", "")), "trip details keep parent order id")
	_expect(str(buy_trip_row.get("trip_id", "")) == str(buy_trips[0].get("id", "")), "trip details expose trip id")
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
	_expect(str(sell_trip_row.get("legality_label", "")) == "Legal", "sell trip details expose legality")
	_expect(int(sell_trip_row.get("unit_price", 0)) > 0, "sell trip details expose unit price")
	_expect(int(sell_trip_row.get("value", 0)) > 0, "sell trip details expose trip value")
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


func _has_crew_member(roster: Array, crew_id: String) -> bool:
	for crew_member in roster:
		if crew_member is Dictionary and str(crew_member.get("id", "")) == crew_id:
			return true
	return false


func _find_crew_member(roster: Array, crew_id: String) -> Dictionary:
	for crew_member in roster:
		if crew_member is Dictionary and str(crew_member.get("id", "")) == crew_id:
			return crew_member
	return {}


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		_failures += 1
		push_error("FAIL: %s" % label)
