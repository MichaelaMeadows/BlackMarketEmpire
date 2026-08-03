extends RefCounted
class_name TradeState

const NPC_ROLE_CATALOG_SCRIPT = preload("res://scripts/npc_role_catalog.gd")

const DEFAULT_GOOD_ID := "fast_food"
const DEFAULT_CARRY_CAPACITY_KG := 5
const SOURCE_INFINITE := -1
const LEGALITY_LEGAL := "legal"
const LEGALITY_ILLICIT := "illicit"
const LEGALITY_CONTROLLED := "controlled"
const LEGALITY_ILLEGAL := "illegal"
const LEGALITY_TABOO := "taboo"

var trade_sources: Dictionary = {
	"fast_food": {
		"id": "burger_stop",
		"name": "Fast Food",
		"source_name": "Burger Stop",
		"buy_price": 3,
		"sell_price": 6,
		"distance": 2,
		"distance_label": "2 blocks",
		"source_inventory": SOURCE_INFINITE,
		"unit_weight_kg": 2,
		"legality": LEGALITY_LEGAL,
		"unlocked": true,
	},
	"bootleg_media": {
		"id": "corner_media_seller",
		"name": "Bootleg Media",
		"source_name": "Corner Media Seller",
		"buy_price": 6,
		"sell_price": 11,
		"distance": 3,
		"distance_label": "3 blocks",
		"source_inventory": 36,
		"unit_weight_kg": 1,
		"legality": LEGALITY_ILLICIT,
		"unlocked": false,
	},
}
var active_orders: Dictionary = {}
var active_trips: Dictionary = {}
var reserved_sell_inventory: Dictionary = {}
var next_order_id := 1
var next_trip_id := 1


func buy_from_supplier(context: Dictionary, quantity: int = 1, unit_price: int = -1, good_id: String = DEFAULT_GOOD_ID) -> Dictionary:
	if unit_price < 0:
		unit_price = get_current_buy_price(context, good_id)
	var total_cost := quantity * unit_price
	if int(context.get("cash", 0)) < total_cost:
		return _result(false, "Not enough cash.")
	var acquired := _take_remote_source_inventory(context, good_id, quantity)
	if acquired < quantity:
		_restore_remote_source_inventory(context, good_id, acquired)
		return _result(false, "Local supply is tight.")
	context["cash"] = int(context.get("cash", 0)) - total_cost
	_add_stock(context, good_id, quantity)
	if not is_good_legal(good_id):
		context["heat"] = min(100, int(context.get("heat", 0)) + quantity)
	return _result(true, "Bought %d for $%d." % [quantity, total_cost])


func sell_to_buyer(context: Dictionary, quantity: int = 1, unit_price: int = -1, good_id: String = DEFAULT_GOOD_ID) -> Dictionary:
	if _get_stock(context, good_id) < quantity:
		return _result(false, "No stock to move.")
	if unit_price < 0:
		unit_price = get_current_sell_price(context, good_id)
	var total_sale := quantity * unit_price
	_add_stock(context, good_id, -quantity)
	context["cash"] = int(context.get("cash", 0)) + total_sale
	if not is_good_legal(good_id):
		context["heat"] = min(100, int(context.get("heat", 0)) + quantity * 2)
	_restore_remote_source_inventory(context, good_id, quantity)
	var result := _result(true, "Sold %d for $%d." % [quantity, total_sale])
	result["progression_events"] = [_sale_event(context, good_id, quantity, total_sale)]
	return result


func place_buy_order(context: Dictionary, quantity: int = -1, unit_price: int = -1, good_id: String = DEFAULT_GOOD_ID) -> Dictionary:
	if not _has_transporter(context):
		return _result(false, "No transporter is available.")
	if not is_good_unlocked(good_id):
		return _result(false, "That product is not available yet.")
	if unit_price < 0:
		unit_price = get_current_buy_price(context, good_id)
	if unit_price <= 0:
		return _result(false, "No buy price is available.")
	var desired_quantity := get_trip_unit_capacity(context, good_id) if quantity <= 0 else quantity
	var affordable_quantity := int(floor(float(context.get("cash", 0)) / float(unit_price)))
	var order_quantity: int = min(desired_quantity, affordable_quantity)
	if order_quantity <= 0:
		return _result(false, "Not enough cash.")
	var acquired := _take_remote_source_inventory(context, good_id, order_quantity)
	if acquired <= 0:
		return _result(false, "Local supply is tight.")
	order_quantity = acquired
	var total_cost: int = order_quantity * unit_price
	context["cash"] = int(context.get("cash", 0)) - total_cost
	var order := _create_order(context, "buy", good_id, order_quantity, unit_price, total_cost)
	active_orders[order["id"]] = order
	if not is_good_legal(good_id):
		context["heat"] = min(100, int(context.get("heat", 0)) + order_quantity)
	var trips := dispatch_queued_trips(context)
	var result := _result(true, "%s %d unit buy order for $%d." % ["Started" if not trips.is_empty() else "Queued", order_quantity, total_cost])
	result["order"] = get_order(str(order.get("id", "")))
	result["trips"] = trips
	return result


func place_sell_order(context: Dictionary, quantity: int = -1, unit_price: int = -1, good_id: String = DEFAULT_GOOD_ID) -> Dictionary:
	if not _has_transporter(context):
		return _result(false, "No transporter is available.")
	if not is_good_unlocked(good_id):
		return _result(false, "That product is not available yet.")
	var desired_quantity := get_trip_unit_capacity(context, good_id) if quantity <= 0 else quantity
	var order_quantity: int = min(desired_quantity, get_available_sell_stock(context, good_id))
	if order_quantity <= 0:
		return _result(false, "No stock to move.")
	if unit_price < 0:
		unit_price = get_current_sell_price(context, good_id)
	if unit_price <= 0:
		return _result(false, "No sell price is available.")
	var total_sale: int = order_quantity * unit_price
	var order := _create_order(context, "sell", good_id, order_quantity, unit_price, total_sale)
	active_orders[order["id"]] = order
	reserved_sell_inventory[good_id] = int(reserved_sell_inventory.get(good_id, 0)) + order_quantity
	var trips := dispatch_queued_trips(context)
	var result := _result(true, "%s %d unit sell order." % ["Started" if not trips.is_empty() else "Queued", order_quantity])
	result["order"] = get_order(str(order.get("id", "")))
	result["trips"] = trips
	return result


func pick_up_sell_order(context: Dictionary, trip_id: String) -> Dictionary:
	var trip := get_trip(trip_id)
	if trip.is_empty() or str(trip.get("type", "")) != "sell":
		return _result(false, "Sell trip not found.")
	var good_id := str(trip.get("good_id", DEFAULT_GOOD_ID))
	var quantity := int(trip.get("quantity", 0))
	if _get_stock(context, good_id) < quantity:
		_cancel_trip(context, trip_id)
		return _result(false, "Storage no longer has enough goods.")
	_add_stock(context, good_id, -quantity)
	trip["picked_up"] = true
	trip["status"] = "away"
	active_trips[trip_id] = trip
	reserved_sell_inventory[good_id] = max(0, int(reserved_sell_inventory.get(good_id, 0)) - quantity)
	return _result(true, "Picked up %d unit from storage." % quantity)


func deposit_buy_order(context: Dictionary, trip_id: String) -> Dictionary:
	var trip := get_trip(trip_id)
	if trip.is_empty() or str(trip.get("type", "")) != "buy":
		return _result(false, "Buy trip not found.")
	var good_id := str(trip.get("good_id", DEFAULT_GOOD_ID))
	var quantity := int(trip.get("quantity", 0))
	var available_space := int(context.get("storage_capacity", 0)) - _get_storage_used(context)
	if available_space < quantity * get_unit_weight_kg(good_id):
		return _result(false, "Storage is full. Runner is waiting.")
	_add_stock(context, good_id, quantity)
	_complete_trip(context, trip_id)
	var result := _result(true, "Stored %d unit." % quantity)
	result["trips"] = dispatch_queued_trips(context)
	return result


func complete_sell_order(context: Dictionary, trip_id: String) -> Dictionary:
	var trip := get_trip(trip_id)
	if trip.is_empty() or str(trip.get("type", "")) != "sell":
		return _result(false, "Sell trip not found.")
	var good_id := str(trip.get("good_id", DEFAULT_GOOD_ID))
	var quantity := int(trip.get("quantity", 0))
	var total_sale := int(trip.get("value", 0))
	context["cash"] = int(context.get("cash", 0)) + total_sale
	if not is_good_legal(good_id):
		context["heat"] = min(100, int(context.get("heat", 0)) + quantity * 2)
	_restore_remote_source_inventory(context, good_id, quantity)
	_complete_trip(context, trip_id)
	var result := _result(true, "Runner returned with $%d." % total_sale)
	result["trips"] = dispatch_queued_trips(context)
	result["progression_events"] = [_sale_event(context, good_id, quantity, total_sale)]
	return result


func get_orders() -> Array:
	return _dictionary_values(active_orders)


func get_trips(context: Dictionary = {}) -> Array:
	var trips: Array = []
	for trip in active_trips.values():
		if trip is Dictionary:
			trips.append(trip.duplicate(true) if context.is_empty() else _decorate_trip(context, trip))
	return trips


func update_trip_progress(trip_id: String, phase: String, eta_seconds: float) -> void:
	var trip := get_trip(trip_id)
	if trip.is_empty():
		return
	trip["phase"] = phase
	trip["eta_seconds"] = eta_seconds
	active_trips[trip_id] = trip


func cancel_trip(context: Dictionary, trip_id: String) -> void:
	_cancel_trip(context, trip_id)


func get_order_rows(context: Dictionary) -> Array:
	var rows: Array = []
	for order in active_orders.values():
		if not (order is Dictionary) or int(order.get("pending_quantity", 0)) <= 0:
			continue
		var good_id := str(order.get("good_id", DEFAULT_GOOD_ID))
		var quantity := int(order.get("pending_quantity", 0))
		var weight := get_unit_weight_kg(good_id)
		rows.append({
			"id": str(order.get("id", "")), "order_id": str(order.get("id", "")), "trip_id": "", "row_type": "order",
			"direction": _format_direction(str(order.get("type", ""))), "type": str(order.get("type", "")), "good_id": good_id,
			"good_name": get_good_name(context, good_id), "legality_label": format_legality_label(get_good_legality(good_id)),
			"status": "Queued", "quantity": quantity, "total_quantity": int(order.get("total_quantity", 0)),
			"pending_quantity": quantity, "in_flight_quantity": int(order.get("in_flight_quantity", 0)),
			"completed_quantity": int(order.get("completed_quantity", 0)), "unit_weight_kg": weight,
			"holding_weight_kg": 0, "load_weight_kg": quantity * weight, "runner": "Waiting",
			"eta_seconds": -1.0, "eta_label": "Queued", "risk_label": "Low",
			"market_id": str(order.get("market_id", context.get("active_market_id", ""))),
			"unit_price": int(order.get("unit_price", 0)), "value": int(order.get("value", 0)),
		})
	for trip in active_trips.values():
		if trip is Dictionary:
			rows.append(_build_trip_row(context, trip))
	return rows


func dispatch_queued_trips(context: Dictionary) -> Array:
	var dispatched: Array = []
	while true:
		var crew_index := _find_idle_transporter_index(context)
		var order_id := _find_dispatchable_order_id()
		if crew_index < 0 or order_id == "":
			break
		var order: Dictionary = active_orders[order_id]
		var quantity: int = min(get_trip_unit_capacity(context, str(order.get("good_id", DEFAULT_GOOD_ID))), int(order.get("pending_quantity", 0)))
		if quantity <= 0:
			break
		var roster: Array = context.get("crew_roster", [])
		var trip := _create_trip(context, order, roster[crew_index], quantity)
		active_trips[trip["id"]] = trip
		order["pending_quantity"] = int(order.get("pending_quantity", 0)) - quantity
		order["in_flight_quantity"] = int(order.get("in_flight_quantity", 0)) + quantity
		order["status"] = "in_flight"
		active_orders[order_id] = order
		_set_crew_assignment(context, crew_index, "Buying" if str(order.get("type", "")) == "buy" else "Selling", str(trip["id"]))
		dispatched.append(trip.duplicate(true))
	return dispatched


func get_available_sell_stock(context: Dictionary, good_id: String = DEFAULT_GOOD_ID) -> int:
	return max(0, _get_stock(context, good_id) - int(reserved_sell_inventory.get(good_id, 0)))


func get_unit_weight_kg(good_id: String = DEFAULT_GOOD_ID) -> int:
	var source := get_source(good_id)
	return 1 if source.is_empty() else max(1, int(source.get("unit_weight_kg", 1)))


func get_trip_unit_capacity(context: Dictionary, good_id: String = DEFAULT_GOOD_ID) -> int:
	return int(floor(float(_get_best_transporter_capacity(context)) / float(get_unit_weight_kg(good_id))))


func get_current_buy_price(context: Dictionary, good_id: String, market_id: String = "") -> int:
	var source := get_source(good_id)
	if not source.is_empty():
		return int(source.get("buy_price", 0))
	return context.get("market").get_buy_price(_resolve_market_id(context, market_id), good_id)


func get_current_sell_price(context: Dictionary, good_id: String, market_id: String = "") -> int:
	var source := get_source(good_id)
	if not source.is_empty():
		return int(source.get("sell_price", 0))
	return context.get("market").get_sell_price(_resolve_market_id(context, market_id), good_id)


func get_available_goods(context: Dictionary) -> Array:
	var goods: Array = []
	for value in trade_sources.keys():
		var good_id := str(value)
		if not is_good_unlocked(good_id):
			continue
		var source := get_source(good_id)
		goods.append({
			"id": good_id, "name": str(source.get("name", good_id.capitalize().replace("_", " "))),
			"source_name": str(source.get("source_name", "Remote Source")), "buy_price": get_current_buy_price(context, good_id),
			"sell_price": get_current_sell_price(context, good_id), "unit_weight_kg": get_unit_weight_kg(good_id),
			"runner_trip_units": get_trip_unit_capacity(context, good_id), "transporter_trip_units": get_trip_unit_capacity(context, good_id),
			"distance": int(source.get("distance", 0)), "distance_label": get_distance_label(good_id),
			"base_inventory": _get_stock(context, good_id), "available_sell_inventory": get_available_sell_stock(context, good_id),
			"remote_inventory": get_remote_inventory(context, good_id), "remote_inventory_label": get_remote_inventory_label(context, good_id),
			"legality": get_good_legality(good_id), "legality_label": format_legality_label(get_good_legality(good_id)), "legal": is_good_legal(good_id),
		})
	return goods


func get_source(good_id: String) -> Dictionary:
	var source: Variant = trade_sources.get(good_id, {})
	return source.duplicate(true) if source is Dictionary else {}


func get_good_name(context: Dictionary, good_id: String) -> String:
	var source := get_source(good_id)
	if not source.is_empty():
		return str(source.get("name", good_id.capitalize().replace("_", " ")))
	var good: Dictionary = context.get("market").get_good(good_id)
	return str(good.get("name", good_id.capitalize().replace("_", " ")))


func is_good_unlocked(good_id: String) -> bool:
	var source := get_source(good_id)
	return not source.is_empty() and bool(source.get("unlocked", false))


func unlock_good(good_id: String) -> bool:
	if not trade_sources.has(good_id):
		return false
	var source: Dictionary = trade_sources[good_id]
	if bool(source.get("unlocked", false)):
		return false
	source["unlocked"] = true
	trade_sources[good_id] = source
	return true


func is_good_legal(good_id: String) -> bool:
	return get_good_legality(good_id) == LEGALITY_LEGAL


func get_good_legality(good_id: String) -> String:
	var source := get_source(good_id)
	if source.has("legality"):
		return normalize_legality(str(source.get("legality", LEGALITY_ILLICIT)))
	return LEGALITY_LEGAL if bool(source.get("legal", false)) else LEGALITY_ILLICIT


func normalize_legality(value: String) -> String:
	var normalized := value.strip_edges().to_lower()
	if [LEGALITY_LEGAL, LEGALITY_ILLICIT, LEGALITY_CONTROLLED, LEGALITY_ILLEGAL, LEGALITY_TABOO].has(normalized):
		return normalized
	return LEGALITY_ILLEGAL if normalized == "illiegal" else LEGALITY_ILLICIT


func format_legality_label(legality: String) -> String:
	return normalize_legality(legality).capitalize()


func get_remote_inventory(context: Dictionary, good_id: String) -> int:
	var source := get_source(good_id)
	return int(floor(_get_market_inventory(context, good_id))) if source.is_empty() else int(source.get("source_inventory", 0))


func get_remote_inventory_label(context: Dictionary, good_id: String) -> String:
	var amount := get_remote_inventory(context, good_id)
	return "Infinite" if amount == SOURCE_INFINITE else "%d units" % amount


func get_distance_label(good_id: String) -> String:
	var source := get_source(good_id)
	return "Local" if source.is_empty() else str(source.get("distance_label", "%d blocks" % int(source.get("distance", 0))))


func get_order(order_id: String) -> Dictionary:
	var order: Variant = active_orders.get(order_id, {})
	return order.duplicate(true) if order is Dictionary else {}


func get_trip(trip_id: String) -> Dictionary:
	var trip: Variant = active_trips.get(trip_id, {})
	return trip.duplicate(true) if trip is Dictionary else {}


func _create_order(context: Dictionary, order_type: String, good_id: String, quantity: int, unit_price: int, value: int) -> Dictionary:
	var order_id := "trade_order_%d" % next_order_id
	next_order_id += 1
	return {"id": order_id, "type": order_type, "good_id": good_id, "total_quantity": quantity, "pending_quantity": quantity,
		"in_flight_quantity": 0, "completed_quantity": 0, "unit_price": unit_price, "value": value,
		"market_id": str(context.get("active_market_id", "")), "status": "queued", "trip_ids": []}


func _create_trip(context: Dictionary, order: Dictionary, crew_member: Dictionary, quantity: int) -> Dictionary:
	var trip_id := "trade_trip_%d" % next_trip_id
	next_trip_id += 1
	var order_id := str(order.get("id", ""))
	var trip_ids: Array = order.get("trip_ids", [])
	trip_ids.append(trip_id)
	order["trip_ids"] = trip_ids
	active_orders[order_id] = order
	return {"id": trip_id, "order_id": order_id, "type": str(order.get("type", "")), "crew_id": str(crew_member.get("id", "")),
		"crew_name": str(crew_member.get("name", "Runner")), "good_id": str(order.get("good_id", DEFAULT_GOOD_ID)), "quantity": quantity,
		"unit_price": int(order.get("unit_price", 0)), "value": quantity * int(order.get("unit_price", 0)),
		"market_id": str(context.get("active_market_id", "")), "status": "in_flight", "phase": "queued", "eta_seconds": -1.0,
		"eta_label": "Queued", "risk_label": "Low", "picked_up": false}


func _complete_trip(context: Dictionary, trip_id: String) -> void:
	var trip := get_trip(trip_id)
	if trip.is_empty():
		return
	var order_id := str(trip.get("order_id", ""))
	var order := get_order(order_id)
	if not order.is_empty():
		var quantity := int(trip.get("quantity", 0))
		order["in_flight_quantity"] = max(0, int(order.get("in_flight_quantity", 0)) - quantity)
		order["completed_quantity"] = int(order.get("completed_quantity", 0)) + quantity
		order["status"] = "queued" if int(order.get("pending_quantity", 0)) > 0 else "in_flight"
		if int(order.get("completed_quantity", 0)) >= int(order.get("total_quantity", 0)):
			active_orders.erase(order_id)
		else:
			active_orders[order_id] = order
	_set_crew_ready(context, str(trip.get("crew_id", "")))
	active_trips.erase(trip_id)


func _cancel_trip(context: Dictionary, trip_id: String) -> void:
	var trip := get_trip(trip_id)
	if trip.is_empty():
		return
	var order_id := str(trip.get("order_id", ""))
	var order := get_order(order_id)
	var quantity := int(trip.get("quantity", 0))
	var good_id := str(trip.get("good_id", DEFAULT_GOOD_ID))
	if str(trip.get("type", "")) == "sell" and bool(trip.get("picked_up", false)):
		_add_stock(context, good_id, quantity)
		reserved_sell_inventory[good_id] = int(reserved_sell_inventory.get(good_id, 0)) + quantity
	if not order.is_empty():
		order["in_flight_quantity"] = max(0, int(order.get("in_flight_quantity", 0)) - quantity)
		order["pending_quantity"] = int(order.get("pending_quantity", 0)) + quantity
		order["status"] = "queued"
		active_orders[order_id] = order
	_set_crew_ready(context, str(trip.get("crew_id", "")))
	active_trips.erase(trip_id)


func _build_trip_row(context: Dictionary, trip: Dictionary) -> Dictionary:
	var decorated := _decorate_trip(context, trip)
	var quantity := int(decorated.get("quantity", 0))
	return {"id": str(decorated.get("id", "")), "order_id": str(decorated.get("order_id", "")), "trip_id": str(decorated.get("id", "")),
		"row_type": "trip", "direction": str(decorated.get("direction", "")), "type": str(decorated.get("type", "")),
		"good_id": str(decorated.get("good_id", DEFAULT_GOOD_ID)), "good_name": str(decorated.get("good_name", "Product")),
		"legality_label": str(decorated.get("legality_label", "Unknown")), "status": str(decorated.get("status_label", "In flight")),
		"quantity": quantity, "total_quantity": quantity, "pending_quantity": 0,
		"in_flight_quantity": quantity, "completed_quantity": 0, "unit_weight_kg": int(decorated.get("unit_weight_kg", 1)),
		"holding_weight_kg": int(decorated.get("holding_weight_kg", 0)), "load_weight_kg": int(decorated.get("load_weight_kg", 0)),
		"runner": str(decorated.get("crew_name", "Runner")), "eta_seconds": float(decorated.get("eta_seconds", -1.0)),
		"eta_label": str(decorated.get("eta_label", "Queued")), "risk_label": str(decorated.get("risk_label", "Low")),
		"market_id": str(decorated.get("market_id", context.get("active_market_id", ""))), "unit_price": int(decorated.get("unit_price", 0)),
		"value": int(decorated.get("value", 0)), "phase": str(decorated.get("phase", "")), "picked_up": bool(decorated.get("picked_up", false))}


func _decorate_trip(context: Dictionary, trip: Dictionary) -> Dictionary:
	var decorated := trip.duplicate(true)
	var good_id := str(decorated.get("good_id", DEFAULT_GOOD_ID))
	var weight := get_unit_weight_kg(good_id)
	var phase := str(decorated.get("phase", ""))
	decorated["good_name"] = get_good_name(context, good_id)
	decorated["direction"] = _format_direction(str(decorated.get("type", "")))
	decorated["unit_weight_kg"] = weight
	decorated["load_weight_kg"] = int(decorated.get("quantity", 0)) * weight
	decorated["holding_weight_kg"] = _get_holding_weight(decorated)
	decorated["status_label"] = _format_trip_status(decorated)
	decorated["eta_label"] = _format_eta(float(decorated.get("eta_seconds", -1.0)), phase)
	decorated["risk_label"] = str(decorated.get("risk_label", "Low"))
	decorated["legality_label"] = format_legality_label(get_good_legality(good_id))
	return decorated


func _take_remote_source_inventory(context: Dictionary, good_id: String, quantity: int) -> int:
	if quantity <= 0:
		return 0
	if trade_sources.has(good_id):
		var source: Dictionary = trade_sources[good_id]
		var available := int(source.get("source_inventory", 0))
		if available == SOURCE_INFINITE:
			return quantity
		var acquired: int = min(quantity, max(0, available))
		source["source_inventory"] = available - acquired
		trade_sources[good_id] = source
		return acquired
	return int(floor(context.get("market").remove_inventory(str(context.get("active_market_id", "")), good_id, float(quantity))))


func _restore_remote_source_inventory(context: Dictionary, good_id: String, quantity: int) -> void:
	if quantity <= 0:
		return
	if trade_sources.has(good_id):
		var source: Dictionary = trade_sources[good_id]
		var available := int(source.get("source_inventory", 0))
		if available != SOURCE_INFINITE:
			source["source_inventory"] = available + quantity
			trade_sources[good_id] = source
		return
	context.get("market").add_inventory(str(context.get("active_market_id", "")), good_id, float(quantity))


func _get_market_inventory(context: Dictionary, good_id: String) -> float:
	for item in context.get("market").get_market_snapshot(str(context.get("active_market_id", ""))):
		if item is Dictionary and str(item.get("id", "")) == good_id:
			return float(item.get("inventory", 0.0))
	return 0.0


func _get_stock(context: Dictionary, good_id: String) -> int:
	return int(context.get("inventory", {}).get(good_id, 0))


func _add_stock(context: Dictionary, good_id: String, amount: int) -> void:
	var inventory: Dictionary = context.get("inventory", {})
	var storage_inventory: Dictionary = context.get("storage_inventory", {})
	inventory[good_id] = int(inventory.get(good_id, 0)) + amount
	storage_inventory[good_id] = int(inventory.get(good_id, 0))


func _get_storage_used(context: Dictionary) -> int:
	var used := 0
	for good_id in context.get("storage_inventory", {}):
		used += int(context.get("storage_inventory", {})[good_id]) * get_unit_weight_kg(str(good_id))
	return used


func _find_idle_transporter_index(context: Dictionary) -> int:
	var roster: Array = context.get("crew_roster", [])
	for index in range(roster.size()):
		var member: Variant = roster[index]
		if member is Dictionary and int(member.get("health", 1)) > 0 and NPC_ROLE_CATALOG_SCRIPT.has_role(member, "transporter") \
				and str(member.get("status", "Ready")) == "Ready" and NPC_ROLE_CATALOG_SCRIPT.can_do_task_type(member, "transport"):
			return index
	return -1


func _has_transporter(context: Dictionary) -> bool:
	for member in context.get("crew_roster", []):
		if member is Dictionary and int(member.get("health", 1)) > 0 and NPC_ROLE_CATALOG_SCRIPT.has_role(member, "transporter") \
				and NPC_ROLE_CATALOG_SCRIPT.can_do_task_type(member, "transport"):
			return true
	return false


func _get_best_transporter_capacity(context: Dictionary) -> int:
	var capacity := DEFAULT_CARRY_CAPACITY_KG
	for member in context.get("crew_roster", []):
		if member is Dictionary and int(member.get("health", 1)) > 0 and NPC_ROLE_CATALOG_SCRIPT.has_role(member, "transporter"):
			capacity = max(capacity, NPC_ROLE_CATALOG_SCRIPT.get_carry_capacity_kg(member, DEFAULT_CARRY_CAPACITY_KG))
	return capacity


func _find_dispatchable_order_id() -> String:
	for order_id in active_orders:
		if int(active_orders[order_id].get("pending_quantity", 0)) > 0:
			return str(order_id)
	return ""


func _set_crew_assignment(context: Dictionary, index: int, status: String, assignment_id: String) -> void:
	var roster: Array = context.get("crew_roster", [])
	var member: Dictionary = roster[index]
	member["assigned_task"] = assignment_id
	member["status"] = status
	roster[index] = member


func _set_crew_ready(context: Dictionary, crew_id: String) -> void:
	var roster: Array = context.get("crew_roster", [])
	for index in range(roster.size()):
		if roster[index] is Dictionary and str(roster[index].get("id", "")) == crew_id:
			_set_crew_assignment(context, index, "Ready", "")
			return


func _get_holding_weight(trip: Dictionary) -> int:
	var phase := str(trip.get("phase", ""))
	var carrying := (str(trip.get("type", "")) == "buy" and ["away_buy", "to_storage", "waiting_storage"].has(phase)) \
		or (str(trip.get("type", "")) == "sell" and bool(trip.get("picked_up", false)) and ["to_exit", "away_sell"].has(phase))
	return int(trip.get("quantity", 0)) * get_unit_weight_kg(str(trip.get("good_id", DEFAULT_GOOD_ID))) if carrying else 0


func _format_direction(order_type: String) -> String:
	return "Incoming" if order_type == "buy" else "Outgoing"


func _format_trip_status(trip: Dictionary) -> String:
	var order_type := str(trip.get("type", ""))
	match str(trip.get("phase", "")):
		"to_exit": return "Heading out" if order_type == "buy" else "Leaving with goods"
		"away_buy": return "Buying"
		"to_storage": return "Returning to storage" if order_type == "buy" else "Going to storage"
		"waiting_storage": return "Waiting for storage"
		"away_sell": return "Selling"
		"return_idle": return "Returning with cash"
		"queued": return "Queued"
	return str(trip.get("status", "In flight")).capitalize().replace("_", " ")


func _format_eta(eta_seconds: float, phase: String) -> String:
	if phase == "waiting_storage": return "Waiting"
	if eta_seconds < 0.0: return "Queued"
	var seconds := int(ceil(eta_seconds))
	return "Any moment" if seconds <= 0 else "%ds" % seconds


func _resolve_market_id(context: Dictionary, market_id: String) -> String:
	return str(context.get("active_market_id", "")) if market_id == "" else market_id


func _sale_event(context: Dictionary, good_id: String, quantity: int, value: int) -> Dictionary:
	return {"type": "sale", "payload": {"item_id": good_id, "quantity": quantity, "value": value,
		"market_id": str(context.get("active_market_id", ""))}}


func _dictionary_values(values: Dictionary) -> Array:
	var result: Array = []
	for value in values.values():
		if value is Dictionary:
			result.append(value.duplicate(true))
	return result


func _result(ok: bool, message: String) -> Dictionary:
	return {"ok": ok, "message": message}
