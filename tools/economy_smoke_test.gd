extends SceneTree

const MARKET_SIMULATION_SCRIPT = preload("res://scripts/market_simulation.gd")
const GAME_STATE_SCRIPT = preload("res://scripts/autoload/game_state.gd")
const DATA_PATH = "res://data/economy"

var _failures: int = 0


func _init() -> void:
	_test_data_loads_and_references()
	_test_seeded_runs_are_deterministic()
	_test_daily_tick_order_updates_state()
	_test_basic_anchor_prices_stay_bounded()
	_test_local_inventory_changes_only_reprice_local_market()
	_test_connected_markets_trade_and_signal_route_pressure()
	_test_route_modifiers_change_trade_behavior()
	_test_disconnected_markets_do_not_equalize()
	_test_production_consumes_inputs_and_creates_outputs()
	_test_recipe_input_shortage_reduces_output_and_supports_prices()
	_test_consumers_respect_willingness_bands()
	_test_habit_desire_rises_when_served_and_decays_when_unmet()
	_test_snapshot_contains_player_facing_market_signals()
	_test_game_state_uses_active_district_prices()

	if _failures == 0:
		print("Economy tests passed.")
	else:
		push_error("Economy tests failed: %d failure(s)." % _failures)
	quit(_failures)


func _test_data_loads_and_references() -> void:
	var market = _new_market(7)
	_expect(market.goods.size() >= 25, "loads at least 25 goods")
	_expect(market.recipes.size() >= 12, "loads at least 12 recipes")
	_expect(market.markets.size() >= 6, "loads at least 6 markets")
	_expect(market.routes.size() >= 10, "loads at least 10 routes")
	_expect(market.consumer_segments.size() >= 8, "loads at least 8 consumer segments")
	_expect(market.markets.has(market.active_market_id), "active market id resolves")

	for recipe in market.recipes:
		var output: Dictionary = _as_dictionary(recipe.get("output", {}))
		_expect(market.goods.has(str(output.get("good", ""))), "recipe output resolves: %s" % recipe.get("id", "unknown"))
		for input_good_id in _as_dictionary(recipe.get("inputs", {})):
			_expect(market.goods.has(input_good_id), "recipe input resolves: %s -> %s" % [recipe.get("id", "unknown"), input_good_id])

	for route_id in market.routes:
		var route: Dictionary = market.routes[route_id]
		_expect(market.markets.has(str(route.get("from", ""))), "route source resolves: %s" % route_id)
		_expect(market.markets.has(str(route.get("to", ""))), "route target resolves: %s" % route_id)

	for market_id in market.markets:
		var district: Dictionary = market.markets[market_id]
		for segment_id in _as_dictionary(district.get("consumer_segments", {})):
			_expect(market.consumer_segments.has(segment_id), "market segment resolves: %s -> %s" % [market_id, segment_id])


func _test_seeded_runs_are_deterministic() -> void:
	var market_a = _new_market(101)
	var market_b = _new_market(101)
	market_a.advance_day(8)
	market_b.advance_day(8)
	_expect(market_a.get_price("rook_market", "street_goods") == market_b.get_price("rook_market", "street_goods"), "same seed produces same street goods price")
	_expect(market_a.get_price("glasswater", "rare_meds") == market_b.get_price("glasswater", "rare_meds"), "same seed produces same rare meds price")


func _test_daily_tick_order_updates_state() -> void:
	var market = _new_market(23)
	var day_before: int = int(market.current_day)
	var stock_before: float = _stock(market, "rook_market", "street_goods")
	market.advance_day()
	_expect(market.current_day == day_before + 1, "daily tick increments current day")
	_expect(_stock(market, "rook_market", "street_goods") != stock_before, "daily tick changes local inventory through production/consumption/trade")
	_expect(market.markets["rook_market"]["demand_served"].has("street_goods"), "daily tick records served demand")


func _test_basic_anchor_prices_stay_bounded() -> void:
	var market = _new_market(31)
	market.remove_inventory("rook_market", "industrial_supplies", 99999.0)
	var emptied_stock: float = _stock(market, "rook_market", "industrial_supplies")
	market.advance_day()
	var replenished_stock: float = _stock(market, "rook_market", "industrial_supplies")
	market.advance_day(20)
	var price: int = int(market.get_price("rook_market", "industrial_supplies"))
	_expect(replenished_stock > emptied_stock, "basic anchor replenishes external supply")
	_expect(price >= 10 and price <= 15, "basic anchor remains inside configured price band")


func _test_local_inventory_changes_only_reprice_local_market() -> void:
	var market = _new_market(37)
	var local_before: int = int(market.get_price("rook_market", "street_goods"))
	var remote_before: int = int(market.get_price("glasswater", "street_goods"))
	market.add_inventory("rook_market", "street_goods", 300.0)
	var local_after: int = int(market.get_price("rook_market", "street_goods"))
	var remote_after: int = int(market.get_price("glasswater", "street_goods"))
	_expect(local_after != local_before, "local stock action reprices local district")
	_expect(remote_after == remote_before, "local stock action does not instantly reprice remote district")


func _test_connected_markets_trade_and_signal_route_pressure() -> void:
	var market = _new_market(41)
	market.recipes.clear()
	market.routes = {
		"test_rook_east": {"id": "test_rook_east", "from": "rook_market", "to": "east_yards", "capacity": 500.0, "friction": 0.01, "risk": 0.0, "distance": 0.1}
	}
	market.add_inventory("east_yards", "street_goods", 900.0)
	market.remove_inventory("rook_market", "street_goods", 999.0)
	var rook_before: float = _stock(market, "rook_market", "street_goods")
	var east_before: float = _stock(market, "east_yards", "street_goods")
	var start_gap: int = int(abs(market.get_price("rook_market", "street_goods") - market.get_price("east_yards", "street_goods")))
	market._run_trade()
	market.recalculate_prices()
	market._update_trends()
	var rook_after: float = _stock(market, "rook_market", "street_goods")
	var east_after: float = _stock(market, "east_yards", "street_goods")
	var end_gap: int = int(abs(market.get_price("rook_market", "street_goods") - market.get_price("east_yards", "street_goods")))
	_expect(rook_after > rook_before, "connected route imports scarce goods into higher-price market")
	_expect(east_after < east_before, "connected route exports stock from lower-price market")
	_expect(end_gap < start_gap, "connected route narrows local price gap")
	_expect(end_gap > 0, "connected route does not instantly equalize prices")
	_expect(market.markets["rook_market"]["route_pressure"]["street_goods"] == "importing", "importing market exposes route pressure")
	_expect(market.markets["east_yards"]["route_pressure"]["street_goods"] == "exporting", "exporting market exposes route pressure")


func _test_route_modifiers_change_trade_behavior() -> void:
	var blocked = _new_market(43)
	blocked.recipes.clear()
	blocked.routes = {
		"test_rook_east": {"id": "test_rook_east", "from": "rook_market", "to": "east_yards", "capacity": 0.0, "friction": 0.01, "risk": 0.0, "distance": 0.1}
	}
	blocked.add_inventory("east_yards", "street_goods", 900.0)
	blocked.remove_inventory("rook_market", "street_goods", 999.0)
	var blocked_before: float = _stock(blocked, "rook_market", "street_goods")
	blocked.advance_day()
	var blocked_import: float = _stock(blocked, "rook_market", "street_goods") - blocked_before

	var open = _new_market(43)
	open.recipes.clear()
	open.routes = {
		"test_rook_east": {"id": "test_rook_east", "from": "rook_market", "to": "east_yards", "capacity": 0.0, "friction": 0.01, "risk": 0.0, "distance": 0.1}
	}
	open.add_inventory("east_yards", "street_goods", 900.0)
	open.remove_inventory("rook_market", "street_goods", 999.0)
	open.apply_route_modifier("test_rook_east", 500.0, 0.0, 0.0)
	var open_before: float = _stock(open, "rook_market", "street_goods")
	open.advance_day()
	var open_import: float = _stock(open, "rook_market", "street_goods") - open_before
	_expect(open_import > blocked_import, "route capacity modifier increases possible imports")


func _test_disconnected_markets_do_not_equalize() -> void:
	var market = _new_market(47)
	market.add_inventory("ridge_heights", "street_goods", 900.0)
	market.remove_inventory("rook_market", "street_goods", 999.0)
	var ridge_before: float = _stock(market, "ridge_heights", "street_goods")
	for _index in range(4):
		market.advance_day()
	var ridge_after: float = _stock(market, "ridge_heights", "street_goods")
	_expect(ridge_after <= ridge_before, "disconnected market does not export stock through missing route")


func _test_production_consumes_inputs_and_creates_outputs() -> void:
	var market = _new_market(53)
	var output_before: float = _stock(market, "south_arcade", "encrypted_devices")
	var input_before: float = _stock(market, "south_arcade", "quiet_access")
	market.advance_day()
	var output_after: float = _stock(market, "south_arcade", "encrypted_devices")
	var input_after: float = _stock(market, "south_arcade", "quiet_access")
	_expect(output_after > output_before, "production creates recipe output")
	_expect(input_after < input_before, "production consumes recipe input")
	_expect(float(market.markets["south_arcade"]["production"].get("encrypted_devices", 0.0)) > 0.0, "production totals are recorded")


func _test_recipe_input_shortage_reduces_output_and_supports_prices() -> void:
	var normal = _new_market(59)
	normal.advance_day()
	var normal_output: float = float(normal.markets["rook_market"]["production"].get("street_goods", 0.0))

	var stressed = _new_market(59)
	var baseline_price: int = int(stressed.get_price("rook_market", "street_goods"))
	stressed.remove_inventory("rook_market", "route_access", 9999.0)
	stressed.advance_day()
	var stressed_output: float = float(stressed.markets["rook_market"]["production"].get("street_goods", 0.0))
	var stressed_price: int = int(stressed.get_price("rook_market", "street_goods"))
	_expect(stressed_output < normal_output, "input shortage reduces dependent recipe output")
	_expect(stressed_price >= baseline_price, "input shortage does not make dependent good cheaper")


func _test_consumers_respect_willingness_bands() -> void:
	var cheap = _new_market(61)
	cheap.markets["rook_market"]["prices"]["street_goods"] = 8.0
	cheap.advance_day()
	var cheap_served: float = float(cheap.markets["rook_market"]["demand_served"].get("street_goods", 0.0))

	var expensive = _new_market(61)
	expensive.markets["rook_market"]["prices"]["street_goods"] = 999.0
	expensive.advance_day()
	var expensive_served: float = float(expensive.markets["rook_market"]["demand_served"].get("street_goods", 0.0))
	_expect(cheap_served > expensive_served, "consumer willingness band serves more demand at acceptable prices")


func _test_habit_desire_rises_when_served_and_decays_when_unmet() -> void:
	var served_market = _new_market(67)
	var desire_before: float = _desire(served_market, "rook_market", "street_regulars", "street_goods")
	served_market.add_inventory("rook_market", "street_goods", 500.0)
	served_market.advance_day(4)
	var desire_after: float = _desire(served_market, "rook_market", "street_regulars", "street_goods")
	_expect(desire_after > desire_before, "habit-forming demand raises desire when served")

	var unmet_market = _new_market(71)
	var unmet_before: float = _desire(unmet_market, "rook_market", "street_regulars", "street_goods")
	unmet_market.remove_inventory("rook_market", "street_goods", 9999.0)
	unmet_market.recipes.clear()
	unmet_market.routes.clear()
	unmet_market.advance_day(4)
	var unmet_after: float = _desire(unmet_market, "rook_market", "street_regulars", "street_goods")
	_expect(unmet_after < unmet_before, "habit-forming demand decays when unmet")


func _test_snapshot_contains_player_facing_market_signals() -> void:
	var market = _new_market(73)
	market.advance_day()
	var snapshot: Array = market.get_market_snapshot("rook_market")
	_expect(not snapshot.is_empty(), "market snapshot returns goods")
	var first: Dictionary = snapshot[0]
	_expect(first.has("price") and first.has("trend") and first.has("scarcity") and first.has("route_pressure"), "snapshot exposes partial market signals")
	_expect(first.has("buy_price") and first.has("sell_price"), "snapshot includes contact price helpers")


func _test_game_state_uses_active_district_prices() -> void:
	var state = GAME_STATE_SCRIPT.new()
	state._ready()
	var expected_buy: int = int(state.market.get_buy_price(state.active_market_id, "street_goods"))
	var expected_sell: int = int(state.market.get_sell_price(state.active_market_id, "street_goods"))
	_expect(state.get_current_buy_price("street_goods") == expected_buy, "GameState simulated buy price uses active district")
	_expect(state.get_current_sell_price("street_goods") == expected_sell, "GameState simulated sell price uses active district")
	state.free()


func _new_market(seed: int):
	var market = MARKET_SIMULATION_SCRIPT.new()
	market.set_seed(seed)
	market.load_data(DATA_PATH)
	return market


func _stock(market, market_id: String, good_id: String) -> float:
	return float(market.markets[market_id]["inventory"].get(good_id, 0.0))


func _desire(market, market_id: String, segment_id: String, good_id: String) -> float:
	return float(market.markets[market_id]["desire"][segment_id].get(good_id, 1.0))


func _as_dictionary(value: Variant) -> Dictionary:
	if value is Dictionary:
		return value
	return {}


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		_failures += 1
		push_error("FAIL: %s" % label)
