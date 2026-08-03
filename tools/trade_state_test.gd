extends SceneTree

const TRADE_STATE_SCRIPT := preload("res://scripts/trade_state.gd")
const MARKET_SIMULATION_SCRIPT := preload("res://scripts/market_simulation.gd")

var _failures := 0


func _init() -> void:
	_test_trade_order_lifecycle()
	if _failures == 0:
		print("Trade state tests passed.")
	else:
		push_error("Trade state tests failed: %d failure(s)." % _failures)
	quit(_failures)


func _test_trade_order_lifecycle() -> void:
	var market = MARKET_SIMULATION_SCRIPT.new()
	market.setup_defaults()
	var trade = TRADE_STATE_SCRIPT.new()
	var context := {
		"cash": 100,
		"heat": 0,
		"inventory": {"fast_food": 0},
		"storage_inventory": {"fast_food": 0},
		"storage_capacity": 20,
		"crew_roster": [{
			"id": "runner_1",
			"name": "Test Runner",
			"role": "transporter",
			"task_types": ["transport"],
			"carry_capacity_kg": 5,
			"health": 60,
			"status": "Ready",
			"assigned_task": "",
		}],
		"market": market,
		"active_market_id": "rook_market",
	}

	_expect(trade.get_current_buy_price(context, "fast_food") == 3, "trade state owns source pricing")
	var buy_result: Dictionary = trade.place_buy_order(context, 4, -1, "fast_food")
	_expect(bool(buy_result.get("ok", false)), "trade state accepts a valid buy order")
	_expect(int(context.get("cash", 0)) == 88, "trade state returns the cash mutation through its context")
	_expect(trade.get_orders().size() == 1, "trade state owns the parent order")
	_expect(trade.get_trips().size() == 1, "trade state dispatches the first capacity-limited trip")

	var first_trip: Dictionary = trade.get_trips()[0]
	var first_deposit: Dictionary = trade.deposit_buy_order(context, str(first_trip.get("id", "")))
	_expect(bool(first_deposit.get("ok", false)), "first buy trip deposits")
	_expect(int(context["inventory"].get("fast_food", 0)) == 2, "first trip changes shared inventory")
	_expect(trade.get_trips().size() == 1, "completing a trip dispatches the queued remainder")

	var second_trip: Dictionary = trade.get_trips()[0]
	var second_deposit: Dictionary = trade.deposit_buy_order(context, str(second_trip.get("id", "")))
	_expect(bool(second_deposit.get("ok", false)), "second buy trip deposits")
	_expect(int(context["inventory"].get("fast_food", 0)) == 4, "all purchased stock reaches storage")
	_expect(trade.get_orders().is_empty(), "completed parent order is removed")
	_expect(trade.get_trips().is_empty(), "completed trips are removed")

	var sell_result: Dictionary = trade.place_sell_order(context, 2, -1, "fast_food")
	var sell_trip: Dictionary = trade.get_trips()[0]
	_expect(bool(sell_result.get("ok", false)), "trade state accepts a valid sell order")
	_expect(bool(trade.pick_up_sell_order(context, str(sell_trip.get("id", ""))).get("ok", false)), "sell trip picks up reserved stock")
	var completion: Dictionary = trade.complete_sell_order(context, str(sell_trip.get("id", "")))
	_expect(bool(completion.get("ok", false)), "sell trip completes")
	_expect(int(context.get("cash", 0)) == 100, "completed sale returns cash through the context")
	var events: Array = completion.get("progression_events", [])
	_expect(events.size() == 1 and str(events[0].get("type", "")) == "sale", "trade state returns progression effects without owning progression")


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("PASS: %s" % message)
		return
	_failures += 1
	push_error("FAIL: %s" % message)
