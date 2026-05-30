extends RefCounted
class_name MarketSimulation

const DEFAULT_DATA_PATH = "res://data/economy"
const DEFAULT_MARKET_ID = "rook_market"

var goods: Dictionary = {}
var recipes: Array = []
var markets: Dictionary = {}
var routes: Dictionary = {}
var consumer_segments: Dictionary = {}
var active_market_id = DEFAULT_MARKET_ID
var current_day = 0
var recent_production: Dictionary = {}

var _rng = RandomNumberGenerator.new()
var _seed = 1337


func setup_defaults() -> void:
	load_data(DEFAULT_DATA_PATH)


func set_seed(seed: int) -> void:
	_seed = seed
	_rng.seed = _seed


func load_data(base_path: String) -> void:
	_rng.seed = _seed
	current_day = 0
	goods.clear()
	recipes.clear()
	markets.clear()
	routes.clear()
	consumer_segments.clear()
	recent_production.clear()

	var goods_data = _load_json("%s/goods.json" % base_path)
	var recipe_data = _load_json("%s/recipes.json" % base_path)
	var market_data = _load_json("%s/markets.json" % base_path)
	var route_data = _load_json("%s/routes.json" % base_path)
	var consumer_data = _load_json("%s/consumers.json" % base_path)

	for item in goods_data.get("goods", []):
		var good = _as_dictionary(item)
		goods[str(good.get("id", ""))] = good.duplicate(true)

	for item in recipe_data.get("recipes", []):
		recipes.append(_as_dictionary(item).duplicate(true))

	for item in consumer_data.get("segments", []):
		var segment = _as_dictionary(item)
		consumer_segments[str(segment.get("id", ""))] = segment.duplicate(true)

	active_market_id = str(market_data.get("active_market_id", DEFAULT_MARKET_ID))
	for item in market_data.get("markets", []):
		var market = _as_dictionary(item)
		var market_id = str(market.get("id", ""))
		markets[market_id] = _build_market_state(market)

	for item in route_data.get("routes", []):
		var route = _as_dictionary(item)
		routes[str(route.get("id", ""))] = route.duplicate(true)

	recalculate_prices()
	_update_trends()


func advance_day(days: int = 1) -> void:
	recent_production.clear()
	for _index in range(max(0, days)):
		current_day += 1
		_apply_anchor_supply()
		_run_production()
		_run_consumers()
		_run_trade()
		recalculate_prices()
		_update_trends()
		_update_desire()


func recalculate_prices() -> void:
	for market_id in markets:
		_recalculate_market_prices(market_id)


func get_good(good_id: String) -> Dictionary:
	if not goods.has(good_id):
		return {}
	return goods[good_id].duplicate(true)


func get_price(market_id: String, good_id: String = "") -> int:
	var resolved_market_id = _resolve_market_id(market_id)
	var resolved_good_id = _resolve_good_id(market_id, good_id)
	if not markets.has(resolved_market_id) or not goods.has(resolved_good_id):
		return 0
	return int(round(float(_get_market_prices(markets[resolved_market_id]).get(resolved_good_id, _get_base_price(resolved_good_id)))))


func get_buy_price(market_id: String, good_id: String = "") -> int:
	var resolved_good_id = _resolve_good_id(market_id, good_id)
	if not goods.has(resolved_good_id):
		return 0
	var spread = float(goods[resolved_good_id].get("spread", 0.25))
	return int(ceil(float(get_price(market_id, good_id)) * (1.0 + spread * 0.5)))


func get_sell_price(market_id: String, good_id: String = "") -> int:
	var resolved_good_id = _resolve_good_id(market_id, good_id)
	if not goods.has(resolved_good_id):
		return 0
	var spread = float(goods[resolved_good_id].get("spread", 0.25))
	return int(floor(float(get_price(market_id, good_id)) * (1.0 + spread)))


func add_inventory(market_id: String, good_id: String, quantity: float) -> void:
	if not markets.has(market_id) or not goods.has(good_id):
		return
	var inventory = _get_inventory(markets[market_id])
	inventory[good_id] = max(0.0, float(inventory.get(good_id, 0.0)) + quantity)
	_recalculate_market_prices(market_id)
	_update_market_trends(markets[market_id])


func remove_inventory(market_id: String, good_id: String, quantity: float) -> float:
	if not markets.has(market_id) or not goods.has(good_id):
		return 0.0
	var inventory = _get_inventory(markets[market_id])
	var available = float(inventory.get(good_id, 0.0))
	var removed = min(max(0.0, quantity), available)
	inventory[good_id] = available - removed
	_recalculate_market_prices(market_id)
	_update_market_trends(markets[market_id])
	return removed


func apply_route_modifier(route_id: String, capacity_delta: float, friction_delta: float, risk_delta: float) -> void:
	if not routes.has(route_id):
		return
	var route: Dictionary = routes[route_id]
	route["capacity"] = max(0.0, float(route.get("capacity", 0.0)) + capacity_delta)
	route["friction"] = clamp(float(route.get("friction", 0.0)) + friction_delta, 0.0, 1.0)
	route["risk"] = clamp(float(route.get("risk", 0.0)) + risk_delta, 0.0, 1.0)
	recalculate_prices()
	_update_trends()


func get_market_snapshot(market_id: String = "") -> Array:
	var resolved_market_id = active_market_id if market_id == "" else market_id
	if not markets.has(resolved_market_id):
		return []

	var market: Dictionary = markets[resolved_market_id]
	var snapshot = []
	var good_ids = goods.keys()
	good_ids.sort()
	for good_id in good_ids:
		var good: Dictionary = goods[good_id]
		snapshot.append({
			"id": good_id,
			"name": good.get("name", good_id),
			"category": good.get("category", "misc"),
			"price": get_price(resolved_market_id, good_id),
			"buy_price": get_buy_price(resolved_market_id, good_id),
			"sell_price": get_sell_price(resolved_market_id, good_id),
			"inventory": float(_get_inventory(market).get(good_id, 0.0)),
			"trend": _get_trends(market).get(good_id, "flat"),
			"scarcity": _get_scarcity_label(market, good_id),
			"route_pressure": _get_route_pressure(market).get(good_id, "quiet"),
			"demand_served": float(_get_demand_served(market).get(good_id, 0.0)),
			"demand_unserved": float(_get_demand_unserved(market).get(good_id, 0.0)),
		})
	return snapshot


func get_recent_production(market_id: String = "") -> Dictionary:
	var resolved_market_id = active_market_id if market_id == "" else market_id
	if not recent_production.has(resolved_market_id):
		return {}
	return recent_production[resolved_market_id].duplicate(true)


func apply_supply_shift(good_id: String, amount: float) -> void:
	add_inventory(active_market_id, good_id, amount * 100.0)


func apply_demand_shift(good_id: String, amount: float) -> void:
	if not markets.has(active_market_id) or not goods.has(good_id):
		return
	var market: Dictionary = markets[active_market_id]
	var pressure = _get_demand_unserved(market)
	pressure[good_id] = max(0.0, float(pressure.get(good_id, 0.0)) + amount * 100.0)
	_recalculate_market_prices(active_market_id)
	_update_market_trends(market)


func _build_market_state(market: Dictionary) -> Dictionary:
	var state = market.duplicate(true)
	state["inventory"] = _normalize_good_float_dict(market.get("inventory", {}))
	state["prices"] = {}
	state["previous_prices"] = {}
	state["trend"] = {}
	state["scarcity"] = {}
	state["demand_served"] = {}
	state["demand_unserved"] = {}
	state["production"] = {}
	state["route_pressure"] = {}
	state["desire"] = {}

	for good_id in goods:
		_get_inventory(state)[good_id] = float(_get_inventory(state).get(good_id, 0.0))
		_get_market_prices(state)[good_id] = _get_base_price(good_id)
		_get_previous_prices(state)[good_id] = _get_base_price(good_id)

	for segment_id in _get_market_segments(state):
		_get_desire(state)[segment_id] = {}
		var segment: Dictionary = consumer_segments.get(segment_id, {})
		for good_id in _as_dictionary(segment.get("demands", {})).keys():
			_get_desire(state)[segment_id][good_id] = 1.0

	return state


func _recalculate_market_prices(market_id: String) -> void:
	if not markets.has(market_id):
		return
	var market: Dictionary = markets[market_id]
	for good_id in goods:
		var previous_price = float(_get_market_prices(market).get(good_id, _get_base_price(good_id)))
		_get_previous_prices(market)[good_id] = previous_price
		_get_market_prices(market)[good_id] = _calculate_price(market_id, good_id)


func _apply_anchor_supply() -> void:
	for market_id in markets:
		var market: Dictionary = markets[market_id]
		var inventory = _get_inventory(market)
		for good_id in goods:
			var good: Dictionary = goods[good_id]
			if not bool(good.get("basic_anchor", false)):
				continue
			var anchor_supply = float(good.get("anchor_supply", 500.0))
			inventory[good_id] = max(float(inventory.get(good_id, 0.0)), anchor_supply)


func _run_production() -> void:
	for market_id in markets:
		var market: Dictionary = markets[market_id]
		_reset_good_totals(_get_production(market))
		for recipe in recipes:
			if not _recipe_allowed_in_market(recipe, market):
				continue
			_produce_recipe(market, recipe)


func _produce_recipe(market: Dictionary, recipe: Dictionary) -> void:
	var output = _as_dictionary(recipe.get("output", {}))
	var output_good_id = str(output.get("good", ""))
	if output_good_id == "" or not goods.has(output_good_id):
		return

	var capacity = float(recipe.get("capacity", 0.0)) * _get_market_capacity_modifier(market, recipe)
	var output_quantity = max(0.001, float(output.get("quantity", 1.0)))
	var max_runs = capacity / output_quantity
	var inputs = _as_dictionary(recipe.get("inputs", {}))
	for input_good_id in inputs:
		var needed_per_run = max(0.001, float(inputs[input_good_id]))
		max_runs = min(max_runs, float(_get_inventory(market).get(input_good_id, 0.0)) / needed_per_run)

	var runs = max(0.0, floor(max_runs))
	if runs <= 0.0:
		return

	for input_good_id in inputs:
		_get_inventory(market)[input_good_id] = max(0.0, float(_get_inventory(market).get(input_good_id, 0.0)) - float(inputs[input_good_id]) * runs)

	var produced = output_quantity * runs * float(recipe.get("efficiency", 1.0))
	_get_inventory(market)[output_good_id] = float(_get_inventory(market).get(output_good_id, 0.0)) + produced
	_get_production(market)[output_good_id] = float(_get_production(market).get(output_good_id, 0.0)) + produced
	var market_id = str(market.get("id", ""))
	if market_id != "":
		if not recent_production.has(market_id):
			recent_production[market_id] = {}
		recent_production[market_id][output_good_id] = float(recent_production[market_id].get(output_good_id, 0.0)) + produced


func _run_consumers() -> void:
	for market_id in markets:
		var market: Dictionary = markets[market_id]
		_reset_good_totals(_get_demand_served(market))
		_reset_good_totals(_get_demand_unserved(market))
		for segment_id in _get_market_segments(market):
			var segment_weight = float(_get_market_segments(market).get(segment_id, 1.0))
			var segment: Dictionary = consumer_segments.get(segment_id, {})
			for good_id in _as_dictionary(segment.get("demands", {})).keys():
				_consume_good(market_id, market, segment_id, segment, good_id, segment_weight)


func _consume_good(market_id: String, market: Dictionary, segment_id: String, segment: Dictionary, good_id: String, segment_weight: float) -> void:
	if not goods.has(good_id):
		return

	var demand = _as_dictionary(_as_dictionary(segment.get("demands", {})).get(good_id, {}))
	var desire = float(_get_desire(market).get(segment_id, {}).get(good_id, 1.0))
	var requested_quantity = float(demand.get("quantity", 0.0)) * segment_weight * desire
	var min_price = float(demand.get("min_price", 0.0))
	var max_price = float(demand.get("max_price", min_price))
	if bool(goods[good_id].get("habit_forming", false)):
		max_price *= 1.0 + clamp(desire - 1.0, 0.0, 3.0) * 0.35

	var price = float(get_price(market_id, good_id))
	var willingness = _get_willingness(price, min_price, max_price, float(demand.get("elasticity", 1.0)))
	var wanted = requested_quantity * willingness
	var available = float(_get_inventory(market).get(good_id, 0.0))
	var served = min(available, wanted)
	var unserved = max(0.0, wanted - served)

	_get_inventory(market)[good_id] = available - served
	_get_demand_served(market)[good_id] = float(_get_demand_served(market).get(good_id, 0.0)) + served
	_get_demand_unserved(market)[good_id] = float(_get_demand_unserved(market).get(good_id, 0.0)) + unserved


func _run_trade() -> void:
	for market_id in markets:
		_reset_good_labels(_get_route_pressure(markets[market_id]), "quiet")

	for route_id in routes:
		var route: Dictionary = routes[route_id]
		var from_id = str(route.get("from", ""))
		var to_id = str(route.get("to", ""))
		if not markets.has(from_id) or not markets.has(to_id):
			continue

		var capacity_left = float(route.get("capacity", 0.0)) * max(0.0, 1.0 - float(route.get("risk", 0.0)))
		var good_ids = goods.keys()
		good_ids.sort()
		for good_id in good_ids:
			if capacity_left <= 0.0:
				break
			capacity_left -= _trade_good_between_markets(from_id, to_id, good_id, capacity_left, route)


func _trade_good_between_markets(market_a_id: String, market_b_id: String, good_id: String, capacity_left: float, route: Dictionary) -> float:
	var price_a = float(get_price(market_a_id, good_id))
	var price_b = float(get_price(market_b_id, good_id))
	var average_price = max(1.0, (price_a + price_b) * 0.5)
	var price_gap = abs(price_a - price_b)
	var friction_threshold = average_price * (float(route.get("friction", 0.08)) + float(route.get("distance", 1.0)) * 0.01)
	if price_gap <= friction_threshold:
		return 0.0

	var source_id = market_a_id if price_a < price_b else market_b_id
	var target_id = market_b_id if source_id == market_a_id else market_a_id
	var source: Dictionary = markets[source_id]
	var target: Dictionary = markets[target_id]
	var target_stock = _get_target_stock(source, good_id)
	var available = max(0.0, float(_get_inventory(source).get(good_id, 0.0)) - target_stock * 0.45)
	var gap_ratio = clamp((price_gap - friction_threshold) / average_price, 0.0, 1.5)
	var moved = min(available, capacity_left, max(0.0, float(route.get("capacity", 0.0)) * gap_ratio * 0.35))
	if moved <= 0.0:
		return 0.0

	_get_inventory(source)[good_id] = float(_get_inventory(source).get(good_id, 0.0)) - moved
	_get_inventory(target)[good_id] = float(_get_inventory(target).get(good_id, 0.0)) + moved
	_get_route_pressure(source)[good_id] = "exporting"
	_get_route_pressure(target)[good_id] = "importing"
	return moved


func _calculate_price(market_id: String, good_id: String) -> float:
	var market: Dictionary = markets[market_id]
	var good: Dictionary = goods[good_id]
	var base_price = _get_base_price(good_id)
	var stock = float(_get_inventory(market).get(good_id, 0.0))
	var target_stock = max(1.0, _get_target_stock(market, good_id))
	var scarcity_ratio = clamp((target_stock - stock) / target_stock, -0.55, 3.0)
	_get_scarcity(market)[good_id] = scarcity_ratio

	var served = float(_get_demand_served(market).get(good_id, 0.0))
	var unserved = float(_get_demand_unserved(market).get(good_id, 0.0))
	var demand_pressure = unserved / max(1.0, served + unserved)
	var input_pressure = _get_input_cost_pressure(market_id, good_id)
	var import_relief = _get_import_relief(market_id, good_id)
	var desire_pressure = _get_average_desire_pressure(market, good_id)
	var drift = _rng.randf_range(-float(good.get("volatility", 0.05)), float(good.get("volatility", 0.05))) * 0.03

	var multiplier = 1.0
	multiplier += scarcity_ratio * 0.32
	multiplier += demand_pressure * 0.45
	multiplier += (input_pressure - 1.0) * 0.35
	multiplier += desire_pressure * 0.20
	multiplier -= import_relief
	multiplier += drift

	var price = max(1.0, base_price * max(0.35, multiplier))
	if bool(good.get("basic_anchor", false)):
		price = clamp(price, float(good.get("anchor_min", base_price * 0.85)), float(good.get("anchor_max", base_price * 1.15)))
	return round(price)


func _update_trends() -> void:
	for market_id in markets:
		_update_market_trends(markets[market_id])


func _update_market_trends(market: Dictionary) -> void:
	for good_id in goods:
		var current_price = float(_get_market_prices(market).get(good_id, _get_base_price(good_id)))
		var previous_price = float(_get_previous_prices(market).get(good_id, current_price))
		var ratio = (current_price - previous_price) / max(1.0, previous_price)
		if ratio > 0.04:
			_get_trends(market)[good_id] = "rising"
		elif ratio < -0.04:
			_get_trends(market)[good_id] = "falling"
		else:
			_get_trends(market)[good_id] = "flat"


func _update_desire() -> void:
	for market_id in markets:
		var market: Dictionary = markets[market_id]
		for segment_id in _get_market_segments(market):
			var segment: Dictionary = consumer_segments.get(segment_id, {})
			if not _get_desire(market).has(segment_id):
				_get_desire(market)[segment_id] = {}
			for good_id in _as_dictionary(segment.get("demands", {})).keys():
				var current_desire = float(_get_desire(market)[segment_id].get(good_id, 1.0))
				if bool(goods.get(good_id, {}).get("habit_forming", false)):
					var served = float(_get_demand_served(market).get(good_id, 0.0))
					var unserved = float(_get_demand_unserved(market).get(good_id, 0.0))
					var fulfillment = served / max(1.0, served + unserved)
					if served > 0.0 and fulfillment >= 0.45:
						current_desire += float(goods[good_id].get("habit_gain", 0.025)) * fulfillment
					else:
						current_desire -= float(goods[good_id].get("habit_decay", 0.012))
					_get_desire(market)[segment_id][good_id] = clamp(current_desire, 0.55, float(goods[good_id].get("habit_max", 2.4)))
				else:
					_get_desire(market)[segment_id][good_id] = lerp(current_desire, 1.0, 0.08)


func _get_target_stock(market: Dictionary, good_id: String) -> float:
	var target = 6.0
	for segment_id in _get_market_segments(market):
		var weight = float(_get_market_segments(market).get(segment_id, 1.0))
		var segment: Dictionary = consumer_segments.get(segment_id, {})
		var demand = _as_dictionary(_as_dictionary(segment.get("demands", {})).get(good_id, {}))
		target += float(demand.get("quantity", 0.0)) * weight * 3.0
	for recipe in recipes:
		var inputs = _as_dictionary(recipe.get("inputs", {}))
		for input_good_id in inputs.keys():
			if input_good_id == good_id:
				target += float(inputs.get(input_good_id, 0.0)) * 2.0
		var output = _as_dictionary(recipe.get("output", {}))
		if str(output.get("good", "")) == good_id:
			target += float(output.get("quantity", 0.0)) * 2.0
	return target


func _get_input_cost_pressure(market_id: String, good_id: String) -> float:
	var total_pressure = 0.0
	var count = 0
	for recipe in recipes:
		var output = _as_dictionary(recipe.get("output", {}))
		if str(output.get("good", "")) != good_id:
			continue
		var input_cost = 0.0
		var base_input_cost = 0.0
		var inputs = _as_dictionary(recipe.get("inputs", {}))
		for input_good_id in inputs.keys():
			var quantity = float(inputs[input_good_id])
			input_cost += float(get_price(market_id, input_good_id)) * quantity
			base_input_cost += _get_base_price(input_good_id) * quantity
		total_pressure += input_cost / max(1.0, base_input_cost)
		count += 1
	return 1.0 if count == 0 else total_pressure / float(count)


func _get_import_relief(market_id: String, good_id: String) -> float:
	var local_price = float(get_price(market_id, good_id))
	var relief = 0.0
	for route_id in routes:
		var route: Dictionary = routes[route_id]
		var neighbor_id = ""
		if str(route.get("from", "")) == market_id:
			neighbor_id = str(route.get("to", ""))
		elif str(route.get("to", "")) == market_id:
			neighbor_id = str(route.get("from", ""))
		if neighbor_id == "" or not markets.has(neighbor_id):
			continue
		var neighbor_price = float(get_price(neighbor_id, good_id))
		var neighbor_stock = float(_get_inventory(markets[neighbor_id]).get(good_id, 0.0))
		if neighbor_price < local_price and neighbor_stock > _get_target_stock(markets[neighbor_id], good_id):
			relief += min(0.08, ((local_price - neighbor_price) / max(1.0, local_price)) * 0.25)
	return clamp(relief, 0.0, 0.18)


func _get_average_desire_pressure(market: Dictionary, good_id: String) -> float:
	var total = 0.0
	var count = 0
	for segment_id in _get_desire(market):
		if _get_desire(market)[segment_id].has(good_id):
			total += float(_get_desire(market)[segment_id][good_id]) - 1.0
			count += 1
	return 0.0 if count == 0 else total / float(count)


func _recipe_allowed_in_market(recipe: Dictionary, market: Dictionary) -> bool:
	var allowed_tags = _as_array(recipe.get("district_tags", []))
	if allowed_tags.is_empty():
		return true
	var market_tags = _as_array(market.get("tags", []))
	for tag in allowed_tags:
		if market_tags.has(tag):
			return true
	return false


func _get_market_capacity_modifier(market: Dictionary, recipe: Dictionary) -> float:
	var modifiers = _as_dictionary(market.get("production_modifiers", {}))
	var output = _as_dictionary(recipe.get("output", {}))
	var output_good_id = str(output.get("good", ""))
	var recipe_id = str(recipe.get("id", ""))
	var category = str(goods.get(output_good_id, {}).get("category", ""))
	return float(modifiers.get(recipe_id, modifiers.get(output_good_id, modifiers.get(category, 1.0))))


func _get_willingness(price: float, min_price: float, max_price: float, elasticity: float) -> float:
	if price <= min_price:
		return 1.0
	if price >= max_price:
		return 0.0
	var price_range = max(1.0, max_price - min_price)
	return pow(clamp((max_price - price) / price_range, 0.0, 1.0), max(0.1, elasticity))


func _get_scarcity_label(market: Dictionary, good_id: String) -> String:
	var scarcity = float(_get_scarcity(market).get(good_id, 0.0))
	if scarcity > 0.7:
		return "scarce"
	if scarcity > 0.25:
		return "tight"
	if scarcity < -0.25:
		return "surplus"
	return "steady"


func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("Missing economy data file: %s" % path)
		return {}

	var file = FileAccess.open(path, FileAccess.READ)
	var text = file.get_as_text()
	var parsed = JSON.parse_string(text)
	if parsed is Dictionary:
		return parsed

	push_error("Invalid economy data file: %s" % path)
	return {}


func _normalize_good_float_dict(value: Variant) -> Dictionary:
	var result = {}
	if value is Dictionary:
		for key in value:
			result[str(key)] = float(value[key])
	return result


func _as_dictionary(value: Variant) -> Dictionary:
	if value is Dictionary:
		return value
	return {}


func _as_array(value: Variant) -> Array:
	if value is Array:
		return value
	return []


func _reset_good_totals(values: Dictionary) -> void:
	values.clear()
	for good_id in goods:
		values[good_id] = 0.0


func _reset_good_labels(values: Dictionary, label: String) -> void:
	values.clear()
	for good_id in goods:
		values[good_id] = label


func _resolve_market_id(market_id: String) -> String:
	return active_market_id if not markets.has(market_id) else market_id


func _resolve_good_id(market_id: String, good_id: String) -> String:
	if good_id != "":
		return good_id
	return market_id


func _get_base_price(good_id: String) -> float:
	return float(goods.get(good_id, {}).get("base_price", 1.0))


func _get_inventory(market: Dictionary) -> Dictionary:
	return market["inventory"]


func _get_market_prices(market: Dictionary) -> Dictionary:
	return market["prices"]


func _get_previous_prices(market: Dictionary) -> Dictionary:
	return market["previous_prices"]


func _get_trends(market: Dictionary) -> Dictionary:
	return market["trend"]


func _get_scarcity(market: Dictionary) -> Dictionary:
	return market["scarcity"]


func _get_demand_served(market: Dictionary) -> Dictionary:
	return market["demand_served"]


func _get_demand_unserved(market: Dictionary) -> Dictionary:
	return market["demand_unserved"]


func _get_production(market: Dictionary) -> Dictionary:
	return market["production"]


func _get_route_pressure(market: Dictionary) -> Dictionary:
	return market["route_pressure"]


func _get_desire(market: Dictionary) -> Dictionary:
	return market["desire"]


func _get_market_segments(market: Dictionary) -> Dictionary:
	return market.get("consumer_segments", {})

