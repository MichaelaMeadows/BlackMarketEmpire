extends Node

signal state_changed
signal progression_event_triggered(event: Dictionary)

const MARKET_SIMULATION_SCRIPT = preload("res://scripts/market_simulation.gd")
const PROGRESSION_TRACKER_SCRIPT = preload("res://scripts/progression_tracker.gd")
const ECONOMY_DATA_PATH = "res://data/economy"
const PROGRESSION_DATA_PATH = "res://data/progression/unlock_rules.json"
const GOOD_KEY = "fast_food"
const STARTING_MARKET_ID = "rook_market"
const DAYS_PER_WEEK = 7
const UNEMPLOYMENT_BENEFITS_WEEKLY = 25
const RUNNER_CARRY_CAPACITY_KG = 5
const TRADE_SOURCE_INFINITE = -1

var cash: int = 100
var heat: int = 0
var current_scope: String = "neighborhood"
var product_name: String = "Fast-Food"
var active_market_id: String = STARTING_MARKET_ID
var day_count: int = 0
var market
var progression
var inventory: Dictionary = {
	"fast_food": 0,
}
var current_base: Dictionary = {}
var base_rooms: Array = []
var base_facilities: Array = []
var owned_facilities_by_slot: Dictionary = {}
var crew_roster: Array = []
var storage_inventory: Dictionary = {
	"fast_food": 0,
}
var storage_capacity: int = 0
var trade_sources: Dictionary = {
	"fast_food": {
		"id": "burger_stop",
		"name": "Fast-Food",
		"source_name": "Burger Stop",
		"buy_price": 3,
		"sell_price": 6,
		"distance": 2,
		"distance_label": "2 blocks",
		"source_inventory": TRADE_SOURCE_INFINITE,
		"unit_weight_kg": 2,
		"legal": true,
		"unlocked": true,
	},
}
var weekly_income_sources: Array = [
	{"id": "unemployment_benefits", "name": "Unemployment Benefits", "amount": UNEMPLOYMENT_BENEFITS_WEEKLY},
]
var transport_tasks: Array = [
	{"id": "corner_pickup", "name": "Corner Pickup", "required_job": "Runner", "duration_days": 1, "reward": 8, "capacity_kg": 5},
	{"id": "supply_drop", "name": "Supply Drop", "required_job": "Runner", "duration_days": 1, "reward": 10, "capacity_kg": 4},
]
var active_trade_orders: Dictionary = {}
var active_trade_trips: Dictionary = {}
var reserved_sell_inventory: Dictionary = {}
var next_trade_order_id: int = 1
var next_trade_trip_id: int = 1
var raid_targets: Array = []
var active_raid_target: Dictionary = {}
var raid_stats: Dictionary = {
	"launched": 0,
	"joined": 0,
	"completed": 0,
}

func _ready() -> void:
	_ensure_market()
	_ensure_progression()
	product_name = str(market.get_good(GOOD_KEY).get("name", product_name))
	storage_inventory[GOOD_KEY] = get_stock()


func buy_from_supplier(quantity: int = 1, unit_price: int = -1, good_id: String = GOOD_KEY) -> Dictionary:
	_ensure_market()
	if unit_price < 0:
		unit_price = get_current_buy_price(good_id, active_market_id)
	var total_cost: int = quantity * unit_price
	if cash < total_cost:
		return _result(false, "Not enough cash.")

	var acquired: int = _take_remote_source_inventory(good_id, quantity)
	if acquired < quantity:
		_restore_remote_source_inventory(good_id, acquired)
		return _result(false, "Local supply is tight.")

	cash -= total_cost
	inventory[good_id] = get_stock(good_id) + quantity
	storage_inventory[good_id] = get_stock(good_id)
	if not _is_trade_good_legal(good_id):
		heat = min(100, heat + quantity)
	_maybe_upgrade_scope()
	state_changed.emit()
	return _result(true, "Bought %d for $%d." % [quantity, total_cost])


func sell_to_buyer(quantity: int = 1, unit_price: int = -1, good_id: String = GOOD_KEY) -> Dictionary:
	_ensure_market()
	if get_stock(good_id) < quantity:
		return _result(false, "No stock to move.")

	if unit_price < 0:
		unit_price = get_current_sell_price(good_id, active_market_id)
	var total_sale: int = quantity * unit_price
	inventory[good_id] = get_stock(good_id) - quantity
	storage_inventory[good_id] = get_stock(good_id)
	cash += total_sale
	if not _is_trade_good_legal(good_id):
		heat = min(100, heat + quantity * 2)
	_restore_remote_source_inventory(good_id, quantity)
	record_progression_event("sale", {
		"item_id": good_id,
		"quantity": quantity,
		"value": total_sale,
		"market_id": active_market_id,
	})
	_maybe_upgrade_scope()
	state_changed.emit()
	return _result(true, "Sold %d for $%d." % [quantity, total_sale])


func place_buy_order(quantity: int = -1, unit_price: int = -1, good_id: String = GOOD_KEY) -> Dictionary:
	_ensure_market()
	if not _has_runner():
		return _result(false, "No runner is available.")
	if not _is_trade_good_unlocked(good_id):
		return _result(false, "That product is not available yet.")
	if unit_price < 0:
		unit_price = get_current_buy_price(good_id, active_market_id)
	if unit_price <= 0:
		return _result(false, "No buy price is available.")

	var desired_quantity: int = get_runner_trip_unit_capacity(good_id) if quantity <= 0 else quantity
	var affordable_quantity: int = int(floor(float(cash) / float(unit_price)))
	var order_quantity: int = min(desired_quantity, affordable_quantity)
	if order_quantity <= 0:
		return _result(false, "Not enough cash.")

	var acquired: int = _take_remote_source_inventory(good_id, order_quantity)
	if acquired <= 0:
		_restore_remote_source_inventory(good_id, acquired)
		return _result(false, "Local supply is tight.")
	order_quantity = acquired
	if order_quantity <= 0:
		return _result(false, "Local supply is tight.")

	var total_cost: int = order_quantity * unit_price
	cash -= total_cost
	var order: Dictionary = _create_trade_order("buy", good_id, order_quantity, unit_price, total_cost)
	active_trade_orders[order["id"]] = order
	if not _is_trade_good_legal(good_id):
		heat = min(100, heat + order_quantity)
	var trips: Array = dispatch_queued_trade_trips()
	state_changed.emit()
	var result := _result(true, "%s %d unit buy order for $%d." % [
		"Started" if not trips.is_empty() else "Queued",
		order_quantity,
		total_cost,
	])
	result["order"] = _get_trade_order(str(order.get("id", "")))
	result["trips"] = trips
	return result


func place_sell_order(quantity: int = -1, unit_price: int = -1, good_id: String = GOOD_KEY) -> Dictionary:
	_ensure_market()
	if not _has_runner():
		return _result(false, "No runner is available.")
	if not _is_trade_good_unlocked(good_id):
		return _result(false, "That product is not available yet.")
	var desired_quantity: int = get_runner_trip_unit_capacity(good_id) if quantity <= 0 else quantity
	var order_quantity: int = min(desired_quantity, get_available_sell_stock(good_id))
	if order_quantity <= 0:
		return _result(false, "No stock to move.")
	if unit_price < 0:
		unit_price = get_current_sell_price(good_id, active_market_id)
	if unit_price <= 0:
		return _result(false, "No sell price is available.")

	var total_sale: int = order_quantity * unit_price
	var order: Dictionary = _create_trade_order("sell", good_id, order_quantity, unit_price, total_sale)
	active_trade_orders[order["id"]] = order
	reserved_sell_inventory[good_id] = int(reserved_sell_inventory.get(good_id, 0)) + order_quantity
	var trips: Array = dispatch_queued_trade_trips()
	state_changed.emit()
	var result := _result(true, "%s %d unit sell order." % [
		"Started" if not trips.is_empty() else "Queued",
		order_quantity,
	])
	result["order"] = _get_trade_order(str(order.get("id", "")))
	result["trips"] = trips
	return result


func pick_up_sell_order(trip_id: String) -> Dictionary:
	var trip: Dictionary = _get_trade_trip(trip_id)
	if trip.is_empty() or str(trip.get("type", "")) != "sell":
		return _result(false, "Sell trip not found.")
	var good_id: String = str(trip.get("good_id", GOOD_KEY))
	var quantity: int = int(trip.get("quantity", 0))
	if get_stock(good_id) < quantity:
		_cancel_trade_trip(trip_id)
		state_changed.emit()
		return _result(false, "Storage no longer has enough goods.")

	inventory[good_id] = get_stock(good_id) - quantity
	storage_inventory[good_id] = get_stock(good_id)
	trip["picked_up"] = true
	trip["status"] = "away"
	active_trade_trips[trip_id] = trip
	reserved_sell_inventory[good_id] = max(0, int(reserved_sell_inventory.get(good_id, 0)) - quantity)
	state_changed.emit()
	return _result(true, "Picked up %d unit from storage." % quantity)


func deposit_buy_order(trip_id: String) -> Dictionary:
	var trip: Dictionary = _get_trade_trip(trip_id)
	if trip.is_empty() or str(trip.get("type", "")) != "buy":
		return _result(false, "Buy trip not found.")
	var good_id: String = str(trip.get("good_id", GOOD_KEY))
	var quantity: int = int(trip.get("quantity", 0))
	var available_space: int = get_storage_capacity() - get_storage_used()
	var needed_space: int = quantity * get_unit_weight_kg(good_id)
	if available_space < needed_space:
		return _result(false, "Storage is full. Runner is waiting.")

	inventory[good_id] = get_stock(good_id) + quantity
	storage_inventory[good_id] = get_stock(good_id)
	_complete_trade_trip(trip_id)
	_maybe_upgrade_scope()
	var trips: Array = dispatch_queued_trade_trips()
	state_changed.emit()
	var result := _result(true, "Stored %d unit." % quantity)
	result["trips"] = trips
	return result


func complete_sell_order(trip_id: String) -> Dictionary:
	var trip: Dictionary = _get_trade_trip(trip_id)
	if trip.is_empty() or str(trip.get("type", "")) != "sell":
		return _result(false, "Sell trip not found.")
	var good_id: String = str(trip.get("good_id", GOOD_KEY))
	var quantity: int = int(trip.get("quantity", 0))
	var total_sale: int = int(trip.get("value", 0))
	cash += total_sale
	if not _is_trade_good_legal(good_id):
		heat = min(100, heat + quantity * 2)
	_restore_remote_source_inventory(good_id, quantity)
	record_progression_event("sale", {
		"item_id": good_id,
		"quantity": quantity,
		"value": total_sale,
		"market_id": active_market_id,
	})
	_complete_trade_trip(trip_id)
	_maybe_upgrade_scope()
	var trips: Array = dispatch_queued_trade_trips()
	state_changed.emit()
	var result := _result(true, "Runner returned with $%d." % total_sale)
	result["trips"] = trips
	return result


func get_trade_orders() -> Array:
	var orders: Array = []
	for order_id in active_trade_orders:
		var order: Variant = active_trade_orders[order_id]
		if order is Dictionary:
			orders.append(order.duplicate(true))
	return orders


func get_trade_trips() -> Array:
	var trips: Array = []
	for trip_id in active_trade_trips:
		var trip: Variant = active_trade_trips[trip_id]
		if trip is Dictionary:
			trips.append(_decorate_trade_trip(trip))
	return trips


func update_trade_trip_progress(trip_id: String, phase: String, eta_seconds: float) -> void:
	if not active_trade_trips.has(trip_id):
		return
	var trip: Dictionary = _get_trade_trip(trip_id)
	trip["phase"] = phase
	trip["eta_seconds"] = eta_seconds
	trip["eta_label"] = _format_trade_eta(eta_seconds, phase)
	active_trade_trips[trip_id] = trip


func get_trade_order_rows() -> Array:
	var rows: Array = []
	for order_id in active_trade_orders:
		var order: Variant = active_trade_orders[order_id]
		if not (order is Dictionary):
			continue
		var pending_quantity: int = int(order.get("pending_quantity", 0))
		if pending_quantity <= 0:
			continue
		var good_id := str(order.get("good_id", GOOD_KEY))
		var unit_weight: int = get_unit_weight_kg(good_id)
		rows.append({
			"id": str(order.get("id", "")),
			"row_type": "order",
			"direction": _format_trade_direction(str(order.get("type", ""))),
			"type": str(order.get("type", "")),
			"good_id": good_id,
			"good_name": _get_trade_good_name(good_id),
			"status": "Queued",
			"quantity": pending_quantity,
			"unit_weight_kg": unit_weight,
			"holding_weight_kg": 0,
			"load_weight_kg": pending_quantity * unit_weight,
			"runner": "Waiting",
			"eta_seconds": -1.0,
			"eta_label": "Queued",
			"risk_label": "Low",
		})

	for trip_id in active_trade_trips:
		var trip: Variant = active_trade_trips[trip_id]
		if trip is Dictionary:
			rows.append(_build_trade_trip_row(trip))
	return rows


func get_available_sell_stock(good_id: String = GOOD_KEY) -> int:
	return max(0, get_stock(good_id) - int(reserved_sell_inventory.get(good_id, 0)))


func get_unit_weight_kg(good_id: String = GOOD_KEY) -> int:
	var source: Dictionary = _get_trade_source(good_id)
	if source.is_empty():
		return 1
	return max(1, int(source.get("unit_weight_kg", 1)))


func get_runner_trip_unit_capacity(good_id: String = GOOD_KEY) -> int:
	return int(floor(float(RUNNER_CARRY_CAPACITY_KG) / float(get_unit_weight_kg(good_id))))


func dispatch_queued_trade_trips() -> Array:
	var dispatched: Array = []
	while true:
		var crew_index: int = _find_idle_runner_index()
		if crew_index < 0:
			break
		var order_id: String = _find_dispatchable_trade_order_id()
		if order_id == "":
			break
		var order: Dictionary = active_trade_orders[order_id]
		var trip_quantity: int = min(get_runner_trip_unit_capacity(str(order.get("good_id", GOOD_KEY))), int(order.get("pending_quantity", 0)))
		if trip_quantity <= 0:
			break
		var crew_member: Dictionary = crew_roster[crew_index]
		var trip: Dictionary = _create_trade_trip(order, crew_member, trip_quantity)
		active_trade_trips[trip["id"]] = trip
		order["pending_quantity"] = int(order.get("pending_quantity", 0)) - trip_quantity
		order["in_flight_quantity"] = int(order.get("in_flight_quantity", 0)) + trip_quantity
		order["status"] = "in_flight"
		active_trade_orders[order_id] = order
		_set_crew_trade_assignment(crew_index, "Buying" if str(order.get("type", "")) == "buy" else "Selling", str(trip["id"]))
		dispatched.append(trip.duplicate(true))
	return dispatched


func pay_fixer(cost: int = 25, heat_reduction: int = 12) -> Dictionary:
	if cash < cost:
		return _result(false, "The fixer wants $%d." % cost)

	cash -= cost
	heat = max(0, heat - heat_reduction)
	state_changed.emit()
	return _result(true, "Heat reduced.")


func initialize_base_from_map(map_data: Dictionary) -> void:
	current_base = map_data.get("base", {}).duplicate(true)
	base_rooms = _extract_base_rooms(map_data)
	base_facilities = _read_dictionary_array(map_data.get("facilities", []))
	raid_targets = _read_dictionary_array(map_data.get("raid_targets", []))
	owned_facilities_by_slot.clear()
	storage_capacity = 0

	for facility in base_facilities:
		var slot_id: String = str(facility.get("slot_id", ""))
		if slot_id != "":
			owned_facilities_by_slot[slot_id] = facility
		if str(facility.get("type", "")) == "storage":
			storage_capacity += int(facility.get("capacity", 0))

	crew_roster = _extract_crew_from_map(map_data)
	if storage_inventory.is_empty():
			storage_inventory[GOOD_KEY] = get_stock(GOOD_KEY)
	else:
		storage_inventory[GOOD_KEY] = get_stock(GOOD_KEY)
	state_changed.emit()


func get_base_summary() -> Dictionary:
	var fallback_name: String = "No Base"
	return {
		"id": str(current_base.get("id", "")),
		"name": str(current_base.get("name", fallback_name)),
		"tier": str(current_base.get("tier", "none")),
		"owned": bool(current_base.get("owned", false)),
		"next_base_hint": str(current_base.get("next_base_hint", "")),
		"room_count": base_rooms.size(),
		"facility_count": base_facilities.size(),
		"crew_count": crew_roster.size(),
		"storage_capacity": storage_capacity,
		"storage_used": get_storage_used(),
		"weekly_income": get_weekly_income_total(),
		"weekly_payroll": get_weekly_payroll_total(),
		"weekly_net": get_weekly_net_income(),
	}


func get_base_rooms() -> Array:
	return base_rooms.duplicate(true)


func get_base_facilities() -> Array:
	return base_facilities.duplicate(true)


func get_owned_facility_for_slot(slot_id: String) -> Dictionary:
	var facility = owned_facilities_by_slot.get(slot_id, {})
	if facility is Dictionary:
		return facility.duplicate(true)
	return {}


func get_crew_roster() -> Array:
	var living_roster: Array = []
	for crew_member in crew_roster:
		if crew_member is Dictionary and _is_crew_member_alive(crew_member):
			living_roster.append(crew_member.duplicate(true))
	return living_roster


func get_ready_crew_count() -> int:
	var count: int = 0
	for crew_member in crew_roster:
		if not (crew_member is Dictionary):
			continue
		if not _is_crew_member_alive(crew_member):
			continue
		if str(crew_member.get("status", "Ready")) == "Ready":
			count += 1
	return count


func get_weekly_income_sources() -> Array:
	return weekly_income_sources.duplicate(true)


func get_weekly_income_total() -> int:
	var total: int = 0
	for source in weekly_income_sources:
		if source is Dictionary:
			total += int(source.get("amount", 0))
	return total


func get_weekly_payroll_total() -> int:
	var total: int = 0
	for crew_member in crew_roster:
		if crew_member is Dictionary:
			total += int(crew_member.get("upkeep", 0))
	return total


func get_weekly_net_income() -> int:
	return get_weekly_income_total() - get_weekly_payroll_total()


func get_transport_tasks() -> Array:
	return transport_tasks.duplicate(true)


func assign_crew_to_transport_task(crew_id: String, task_id: String) -> Dictionary:
	var crew_index: int = _find_crew_index(crew_id)
	if crew_index < 0:
		return _result(false, "Crew member not found.")
	var task: Dictionary = _find_transport_task(task_id)
	if task.is_empty():
		return _result(false, "Transport task not found.")

	var crew_member: Dictionary = crew_roster[crew_index]
	if not _is_crew_member_alive(crew_member):
		return _result(false, "%s is not available." % str(crew_member.get("name", "Crew")))
	if not _crew_can_do_task(crew_member, task):
		return _result(false, "%s cannot do that task." % str(crew_member.get("name", "Crew")))

	crew_member["assigned_task"] = task_id
	crew_member["status"] = "Assigned"
	crew_roster[crew_index] = crew_member
	state_changed.emit()
	return _result(true, "%s assigned to %s." % [
		str(crew_member.get("name", "Crew")),
		str(task.get("name", "task")),
	])


func clear_crew_assignment(crew_id: String) -> Dictionary:
	var crew_index: int = _find_crew_index(crew_id)
	if crew_index < 0:
		return _result(false, "Crew member not found.")
	var crew_member: Dictionary = crew_roster[crew_index]
	if not _is_crew_member_alive(crew_member):
		return _result(false, "%s is not available." % str(crew_member.get("name", "Crew")))
	crew_member["assigned_task"] = ""
	crew_member["status"] = "Ready"
	crew_roster[crew_index] = crew_member
	state_changed.emit()
	return _result(true, "%s is ready." % str(crew_member.get("name", "Crew")))


func remove_crew_member(crew_id: String) -> Dictionary:
	var crew_index: int = _find_crew_index(crew_id)
	if crew_index < 0:
		return _result(false, "Crew member not found.")

	var crew_member: Dictionary = crew_roster[crew_index]
	var crew_name := str(crew_member.get("name", "Crew"))
	var trip_ids_to_cancel: Array = []
	for trip_id in active_trade_trips:
		var trip: Variant = active_trade_trips[trip_id]
		if trip is Dictionary and str(trip.get("crew_id", "")) == crew_id:
			trip_ids_to_cancel.append(str(trip_id))
	for trip_id in trip_ids_to_cancel:
		_cancel_trade_trip(str(trip_id))

	crew_roster.remove_at(crew_index)
	state_changed.emit()
	return _result(true, "%s died and was removed from the crew." % crew_name)


func get_storage_capacity() -> int:
	return storage_capacity


func get_storage_used() -> int:
	var total: int = 0
	for good_id in storage_inventory:
		total += int(storage_inventory[good_id]) * get_unit_weight_kg(str(good_id))
	return total


func get_storage_snapshot() -> Dictionary:
	return {
		"capacity": storage_capacity,
		"used": get_storage_used(),
		"inventory": storage_inventory.duplicate(true),
	}


func get_raid_targets() -> Array:
	return raid_targets.duplicate(true)


func resolve_raid_target(target_id: String) -> Dictionary:
	for target in raid_targets:
		if target is Dictionary and str(target.get("id", "")) == target_id:
			return target.duplicate(true)
	return {}


func start_raid(target_id: String, join_player: bool = false) -> Dictionary:
	var target: Dictionary = resolve_raid_target(target_id)
	if target.is_empty():
		return _result(false, "Raid target is not available.")

	var crew_required: int = int(target.get("crew_required", 1))
	if get_ready_crew_count() < crew_required:
		return _result(false, "Not enough ready crew.")

	active_raid_target = target
	raid_stats["launched"] = int(raid_stats.get("launched", 0)) + 1
	if join_player:
		raid_stats["joined"] = int(raid_stats.get("joined", 0)) + 1
	record_progression_event("raid_started", {
		"target_id": target_id,
		"metrics": {"raids_started": 1},
	})
	state_changed.emit()
	return _result(true, "Raid started: %s." % str(target.get("name", target_id)))


func complete_active_raid(success: bool = true) -> Dictionary:
	if active_raid_target.is_empty():
		return _result(false, "No active raid.")
	var target_name: String = str(active_raid_target.get("name", "Raid"))
	if success:
		raid_stats["completed"] = int(raid_stats.get("completed", 0)) + 1
		cash += 35
		inventory[GOOD_KEY] = get_stock(GOOD_KEY) + 2
		storage_inventory[GOOD_KEY] = get_stock(GOOD_KEY)
		record_progression_event("raid_completed", {
			"target_id": str(active_raid_target.get("id", "")),
			"metrics": {"raids_completed": 1},
		})
	active_raid_target = {}
	state_changed.emit()
	return _result(success, "%s complete." % target_name)


func get_active_raid_target() -> Dictionary:
	return active_raid_target.duplicate(true)


func get_raid_stats() -> Dictionary:
	return raid_stats.duplicate(true)


func get_stock(good_id: String = GOOD_KEY) -> int:
	return int(inventory.get(good_id, 0))


func get_current_buy_price(good_id: String = GOOD_KEY, market_id: String = "") -> int:
	_ensure_market()
	var source: Dictionary = _get_trade_source(good_id)
	if not source.is_empty():
		return int(source.get("buy_price", 0))
	return market.get_buy_price(_resolve_market_id(market_id), good_id)


func get_current_sell_price(good_id: String = GOOD_KEY, market_id: String = "") -> int:
	_ensure_market()
	var source: Dictionary = _get_trade_source(good_id)
	if not source.is_empty():
		return int(source.get("sell_price", 0))
	return market.get_sell_price(_resolve_market_id(market_id), good_id)


func get_market_snapshot(market_id: String = "") -> Array:
	_ensure_market()
	return market.get_market_snapshot(_resolve_market_id(market_id))


func get_available_trade_goods() -> Array:
	var goods: Array = []
	for good_id in trade_sources:
		if not _is_trade_good_unlocked(str(good_id)):
			continue
		var source: Dictionary = _get_trade_source(str(good_id))
		goods.append({
			"id": str(good_id),
			"name": str(source.get("name", str(good_id).capitalize().replace("_", " "))),
			"source_name": str(source.get("source_name", "Remote Source")),
			"buy_price": get_current_buy_price(str(good_id)),
			"sell_price": get_current_sell_price(str(good_id)),
			"unit_weight_kg": get_unit_weight_kg(str(good_id)),
			"runner_trip_units": get_runner_trip_unit_capacity(str(good_id)),
			"distance": int(source.get("distance", 0)),
			"distance_label": get_trade_distance_label(str(good_id)),
			"base_inventory": get_stock(str(good_id)),
			"available_sell_inventory": get_available_sell_stock(str(good_id)),
			"remote_inventory": get_remote_inventory_for_good(str(good_id)),
			"remote_inventory_label": get_remote_inventory_label(str(good_id)),
			"legal": bool(source.get("legal", false)),
		})
	return goods


func get_remote_inventory_for_good(good_id: String) -> int:
	var source: Dictionary = _get_trade_source(good_id)
	if source.is_empty():
		return int(floor(_get_market_inventory(good_id)))
	return int(source.get("source_inventory", 0))


func get_remote_inventory_label(good_id: String) -> String:
	var remote_inventory: int = get_remote_inventory_for_good(good_id)
	if remote_inventory == TRADE_SOURCE_INFINITE:
		return "Infinite"
	return "%d units" % remote_inventory


func get_trade_distance_label(good_id: String) -> String:
	var source: Dictionary = _get_trade_source(good_id)
	if source.is_empty():
		return "Local"
	return str(source.get("distance_label", "%d blocks" % int(source.get("distance", 0))))


func advance_market(days: int = 1) -> void:
	_ensure_market()
	_ensure_progression()
	market.advance_day(days)
	_apply_weekly_finances(days)
	_record_recent_production()
	_emit_progression_events(progression.advance_day(days))
	state_changed.emit()


func apply_market_supply_shift(good_id: String, amount: float) -> void:
	_ensure_market()
	if amount >= 0.0:
		market.add_inventory(active_market_id, good_id, amount)
	else:
		market.remove_inventory(active_market_id, good_id, abs(amount))
	state_changed.emit()


func apply_market_demand_shift(good_id: String, amount: float) -> void:
	_ensure_market()
	market.apply_demand_shift(good_id, amount)
	state_changed.emit()


func record_progression_event(event_type: String, payload: Dictionary = {}) -> Array:
	_ensure_progression()
	var triggered: Array = progression.record_event(event_type, payload)
	_emit_progression_events(triggered)
	if not triggered.is_empty():
		state_changed.emit()
	return triggered


func record_kill(target_type: String = "npc") -> Array:
	return record_progression_event("kill", {
		"target_type": target_type,
	})


func is_unlocked(unlock_id: String) -> bool:
	_ensure_progression()
	return progression.is_unlocked(unlock_id)


func get_progress_metric(metric_name: String, item_id: String = "") -> float:
	_ensure_progression()
	return progression.get_metric(metric_name, item_id)


func get_scope_label() -> String:
	return current_scope.capitalize()


func get_scope_description() -> String:
	match current_scope:
		"global":
			return "Global routes, shell networks, and market shocks are starting to matter."
		"nation":
			return "National supply lines and regional pressure now shape the operation."
		"city":
			return "Districts, crews, and citywide heat are becoming the real game."
		_:
			return "Every deal is still local, personal, and risky."


func _maybe_upgrade_scope() -> void:
	var next_scope: String = current_scope
	if cash >= 10000:
		next_scope = "global"
	elif cash >= 2500:
		next_scope = "nation"
	elif cash >= 500:
		next_scope = "city"

	current_scope = next_scope


func _ensure_market() -> void:
	if market != null:
		return
	market = MARKET_SIMULATION_SCRIPT.new()
	market.load_data(ECONOMY_DATA_PATH)
	active_market_id = market.active_market_id


func _ensure_progression() -> void:
	if progression != null:
		return
	progression = PROGRESSION_TRACKER_SCRIPT.new()
	progression.load_rules(PROGRESSION_DATA_PATH)


func _extract_base_rooms(map_data: Dictionary) -> Array:
	var rooms: Array = []
	for building in map_data.get("buildings", []):
		if not (building is Dictionary):
			continue
		var building_id: String = str(building.get("id", ""))
		for room in building.get("rooms", []):
			if not (room is Dictionary):
				continue
			var normalized: Dictionary = room.duplicate(true)
			normalized["building_id"] = building_id
			if not normalized.has("slot_ids"):
				normalized["slot_ids"] = []
			rooms.append(normalized)
	return rooms


func _extract_crew_from_map(map_data: Dictionary) -> Array:
	var roster: Array = []
	for npc in map_data.get("npcs", []):
		if not (npc is Dictionary):
			continue
		if str(npc.get("faction", "")) != "player_crew":
			continue
		var staff_data: Dictionary = npc.get("staff", {})
		roster.append({
			"id": str(npc.get("id", "")),
			"name": str(npc.get("name", "Crew")),
			"role": str(npc.get("role", "crew")),
			"job": str(staff_data.get("job", npc.get("role", "Crew"))),
			"status": str(staff_data.get("status", "Ready")),
			"assigned_task": str(staff_data.get("assigned_task", "")),
			"task_types": staff_data.get("task_types", []),
			"upkeep": int(staff_data.get("upkeep", 0)),
			"health": int(npc.get("health", 60)),
			"color": npc.get("color", []),
		})
	return roster


func _read_dictionary_array(value: Variant) -> Array:
	var result: Array = []
	if value is Array:
		for item in value:
			if item is Dictionary:
				result.append(item.duplicate(true))
	return result


func _apply_weekly_finances(days: int) -> void:
	var previous_week: int = int(day_count / DAYS_PER_WEEK)
	day_count += max(0, days)
	var current_week: int = int(day_count / DAYS_PER_WEEK)
	var weeks_elapsed: int = max(0, current_week - previous_week)
	if weeks_elapsed <= 0:
		return
	cash += weeks_elapsed * get_weekly_net_income()
	record_progression_event("weekly_finances", {
		"metrics": {
			"unemployment_benefits": weeks_elapsed * get_weekly_income_total(),
			"payroll_paid": weeks_elapsed * get_weekly_payroll_total(),
		},
	})


func _find_crew_index(crew_id: String) -> int:
	for index in range(crew_roster.size()):
		var crew_member: Variant = crew_roster[index]
		if crew_member is Dictionary and str(crew_member.get("id", "")) == crew_id:
			return index
	return -1


func _is_crew_member_alive(crew_member: Dictionary) -> bool:
	return int(crew_member.get("health", 1)) > 0


func _find_idle_runner_index() -> int:
	for index in range(crew_roster.size()):
		var crew_member: Variant = crew_roster[index]
		if not (crew_member is Dictionary):
			continue
		if not _is_crew_member_alive(crew_member):
			continue
		if str(crew_member.get("job", "")) != "Runner":
			continue
		if str(crew_member.get("status", "Ready")) != "Ready":
			continue
		var task_types: Variant = crew_member.get("task_types", [])
		if task_types is Array and task_types.has("transport"):
			return index
	return -1


func _has_runner() -> bool:
	for crew_member in crew_roster:
		if not (crew_member is Dictionary):
			continue
		if not _is_crew_member_alive(crew_member):
			continue
		if str(crew_member.get("job", "")) != "Runner":
			continue
		var task_types: Variant = crew_member.get("task_types", [])
		if task_types is Array and task_types.has("transport"):
			return true
	return false


func _find_dispatchable_trade_order_id() -> String:
	for order_id in active_trade_orders:
		var order: Variant = active_trade_orders[order_id]
		if order is Dictionary and int(order.get("pending_quantity", 0)) > 0:
			return str(order_id)
	return ""


func _get_trade_source(good_id: String) -> Dictionary:
	var source: Variant = trade_sources.get(good_id, {})
	if source is Dictionary:
		return source.duplicate(true)
	return {}


func _get_trade_good_name(good_id: String) -> String:
	var source: Dictionary = _get_trade_source(good_id)
	if not source.is_empty():
		return str(source.get("name", good_id.capitalize().replace("_", " ")))
	_ensure_market()
	var good: Dictionary = market.get_good(good_id)
	if not good.is_empty():
		return str(good.get("name", good_id.capitalize().replace("_", " ")))
	return good_id.capitalize().replace("_", " ")


func _is_trade_good_unlocked(good_id: String) -> bool:
	var source: Dictionary = _get_trade_source(good_id)
	return not source.is_empty() and bool(source.get("unlocked", false))


func _is_trade_good_legal(good_id: String) -> bool:
	var source: Dictionary = _get_trade_source(good_id)
	return bool(source.get("legal", false))


func _take_remote_source_inventory(good_id: String, quantity: int) -> int:
	if quantity <= 0:
		return 0
	if trade_sources.has(good_id):
		var source: Dictionary = trade_sources[good_id]
		var source_inventory: int = int(source.get("source_inventory", 0))
		if source_inventory == TRADE_SOURCE_INFINITE:
			return quantity
		var acquired: int = min(quantity, max(0, source_inventory))
		source["source_inventory"] = source_inventory - acquired
		trade_sources[good_id] = source
		return acquired

	_ensure_market()
	var acquired_from_market: float = market.remove_inventory(active_market_id, good_id, float(quantity))
	return int(floor(acquired_from_market))


func _restore_remote_source_inventory(good_id: String, quantity: int) -> void:
	if quantity <= 0:
		return
	if trade_sources.has(good_id):
		var source: Dictionary = trade_sources[good_id]
		var source_inventory: int = int(source.get("source_inventory", 0))
		if source_inventory != TRADE_SOURCE_INFINITE:
			source["source_inventory"] = source_inventory + quantity
			trade_sources[good_id] = source
		return

	_ensure_market()
	market.add_inventory(active_market_id, good_id, float(quantity))


func _get_market_inventory(good_id: String) -> float:
	_ensure_market()
	for item in market.get_market_snapshot(active_market_id):
		if item is Dictionary and str(item.get("id", "")) == good_id:
			return float(item.get("inventory", 0.0))
	return 0.0


func _create_trade_order(order_type: String, good_id: String, quantity: int, unit_price: int, value: int) -> Dictionary:
	var order_id := "trade_order_%d" % next_trade_order_id
	next_trade_order_id += 1
	return {
		"id": order_id,
		"type": order_type,
		"good_id": good_id,
		"total_quantity": quantity,
		"pending_quantity": quantity,
		"in_flight_quantity": 0,
		"completed_quantity": 0,
		"unit_price": unit_price,
		"value": value,
		"market_id": active_market_id,
		"status": "queued",
		"trip_ids": [],
	}


func _get_trade_order(order_id: String) -> Dictionary:
	var order: Variant = active_trade_orders.get(order_id, {})
	if order is Dictionary:
		return order.duplicate(true)
	return {}


func _create_trade_trip(order: Dictionary, crew_member: Dictionary, quantity: int) -> Dictionary:
	var trip_id := "trade_trip_%d" % next_trade_trip_id
	next_trade_trip_id += 1
	var order_id := str(order.get("id", ""))
	var order_trip_ids: Array = order.get("trip_ids", [])
	order_trip_ids.append(trip_id)
	order["trip_ids"] = order_trip_ids
	active_trade_orders[order_id] = order
	return {
		"id": trip_id,
		"order_id": order_id,
		"type": str(order.get("type", "")),
		"crew_id": str(crew_member.get("id", "")),
		"crew_name": str(crew_member.get("name", "Runner")),
		"good_id": str(order.get("good_id", GOOD_KEY)),
		"quantity": quantity,
		"unit_price": int(order.get("unit_price", 0)),
		"value": quantity * int(order.get("unit_price", 0)),
		"market_id": active_market_id,
		"status": "in_flight",
		"phase": "queued",
		"eta_seconds": -1.0,
		"eta_label": "Queued",
		"risk_label": "Low",
		"picked_up": false,
	}


func _get_trade_trip(trip_id: String) -> Dictionary:
	var trip: Variant = active_trade_trips.get(trip_id, {})
	if trip is Dictionary:
		return trip.duplicate(true)
	return {}


func _decorate_trade_trip(trip: Dictionary) -> Dictionary:
	var decorated := trip.duplicate(true)
	var good_id := str(decorated.get("good_id", GOOD_KEY))
	var unit_weight := get_unit_weight_kg(good_id)
	var phase := str(decorated.get("phase", ""))
	decorated["good_name"] = _get_trade_good_name(good_id)
	decorated["direction"] = _format_trade_direction(str(decorated.get("type", "")))
	decorated["unit_weight_kg"] = unit_weight
	decorated["load_weight_kg"] = int(decorated.get("quantity", 0)) * unit_weight
	decorated["holding_weight_kg"] = _get_trade_trip_holding_weight_kg(decorated)
	decorated["status_label"] = _format_trade_trip_status(decorated)
	decorated["eta_label"] = _format_trade_eta(float(decorated.get("eta_seconds", -1.0)), phase)
	decorated["risk_label"] = str(decorated.get("risk_label", "Low"))
	return decorated


func _build_trade_trip_row(trip: Dictionary) -> Dictionary:
	var decorated := _decorate_trade_trip(trip)
	return {
		"id": str(decorated.get("id", "")),
		"row_type": "trip",
		"direction": str(decorated.get("direction", "")),
		"type": str(decorated.get("type", "")),
		"good_id": str(decorated.get("good_id", GOOD_KEY)),
		"good_name": str(decorated.get("good_name", "Product")),
		"status": str(decorated.get("status_label", "In flight")),
		"quantity": int(decorated.get("quantity", 0)),
		"unit_weight_kg": int(decorated.get("unit_weight_kg", 1)),
		"holding_weight_kg": int(decorated.get("holding_weight_kg", 0)),
		"load_weight_kg": int(decorated.get("load_weight_kg", 0)),
		"runner": str(decorated.get("crew_name", "Runner")),
		"eta_seconds": float(decorated.get("eta_seconds", -1.0)),
		"eta_label": str(decorated.get("eta_label", "Calculating")),
		"risk_label": str(decorated.get("risk_label", "Low")),
	}


func _get_trade_trip_holding_weight_kg(trip: Dictionary) -> int:
	var order_type := str(trip.get("type", ""))
	var phase := str(trip.get("phase", ""))
	var quantity := int(trip.get("quantity", 0))
	var unit_weight := get_unit_weight_kg(str(trip.get("good_id", GOOD_KEY)))
	if order_type == "buy" and ["away_buy", "to_storage", "waiting_storage"].has(phase):
		return quantity * unit_weight
	if order_type == "sell" and bool(trip.get("picked_up", false)) and ["to_exit", "away_sell"].has(phase):
		return quantity * unit_weight
	return 0


func _format_trade_direction(order_type: String) -> String:
	return "Incoming" if order_type == "buy" else "Outgoing"


func _format_trade_trip_status(trip: Dictionary) -> String:
	var order_type := str(trip.get("type", ""))
	match str(trip.get("phase", "")):
		"to_exit":
			return "Heading out" if order_type == "buy" else "Leaving with goods"
		"away_buy":
			return "Buying"
		"to_storage":
			return "Returning to storage" if order_type == "buy" else "Going to storage"
		"waiting_storage":
			return "Waiting for storage"
		"away_sell":
			return "Selling"
		"return_idle":
			return "Returning with cash"
		"queued":
			return "Queued"
	return str(trip.get("status", "In flight")).capitalize().replace("_", " ")


func _format_trade_eta(eta_seconds: float, phase: String = "") -> String:
	if phase == "waiting_storage":
		return "Waiting"
	if eta_seconds < 0.0:
		return "Queued"
	var rounded_seconds := int(ceil(eta_seconds))
	if rounded_seconds <= 0:
		return "Any moment"
	return "%ds" % rounded_seconds


func _set_crew_trade_assignment(crew_index: int, status: String, assignment_id: String) -> void:
	var crew_member: Dictionary = crew_roster[crew_index]
	crew_member["assigned_task"] = assignment_id
	crew_member["status"] = status
	crew_roster[crew_index] = crew_member


func _complete_trade_trip(trip_id: String) -> void:
	var trip: Dictionary = _get_trade_trip(trip_id)
	if trip.is_empty():
		return
	var order_id: String = str(trip.get("order_id", ""))
	var order: Dictionary = _get_trade_order(order_id)
	if not order.is_empty():
		var quantity: int = int(trip.get("quantity", 0))
		order["in_flight_quantity"] = max(0, int(order.get("in_flight_quantity", 0)) - quantity)
		order["completed_quantity"] = int(order.get("completed_quantity", 0)) + quantity
		order["status"] = "queued" if int(order.get("pending_quantity", 0)) > 0 else "in_flight"
		if int(order.get("completed_quantity", 0)) >= int(order.get("total_quantity", 0)):
			active_trade_orders.erase(order_id)
		else:
			active_trade_orders[order_id] = order
	var crew_index: int = _find_crew_index(str(trip.get("crew_id", "")))
	if crew_index >= 0:
		_set_crew_trade_assignment(crew_index, "Ready", "")
	active_trade_trips.erase(trip_id)


func _cancel_trade_trip(trip_id: String) -> void:
	var trip: Dictionary = _get_trade_trip(trip_id)
	if trip.is_empty():
		return
	var order_id: String = str(trip.get("order_id", ""))
	var order: Dictionary = _get_trade_order(order_id)
	var quantity: int = int(trip.get("quantity", 0))
	var good_id: String = str(trip.get("good_id", GOOD_KEY))
	if str(trip.get("type", "")) == "sell" and bool(trip.get("picked_up", false)):
		inventory[good_id] = get_stock(good_id) + quantity
		storage_inventory[good_id] = get_stock(good_id)
		reserved_sell_inventory[good_id] = int(reserved_sell_inventory.get(good_id, 0)) + quantity
	if not order.is_empty():
		order["in_flight_quantity"] = max(0, int(order.get("in_flight_quantity", 0)) - quantity)
		order["pending_quantity"] = int(order.get("pending_quantity", 0)) + quantity
		order["status"] = "queued"
		active_trade_orders[order_id] = order
	var crew_index: int = _find_crew_index(str(trip.get("crew_id", "")))
	if crew_index >= 0:
		_set_crew_trade_assignment(crew_index, "Ready", "")
	active_trade_trips.erase(trip_id)


func _find_transport_task(task_id: String) -> Dictionary:
	for task in transport_tasks:
		if task is Dictionary and str(task.get("id", "")) == task_id:
			return task.duplicate(true)
	return {}


func _crew_can_do_task(crew_member: Dictionary, task: Dictionary) -> bool:
	var required_job: String = str(task.get("required_job", ""))
	if required_job != "" and str(crew_member.get("job", "")) != required_job:
		return false
	var task_types: Variant = crew_member.get("task_types", [])
	return task_types is Array and task_types.has("transport")


func _record_recent_production() -> void:
	if market == null or progression == null:
		return
	var production: Dictionary = market.get_recent_production(active_market_id)
	for good_id in production:
		var quantity: float = float(production[good_id])
		if quantity <= 0.0:
			continue
		record_progression_event("crafted", {
			"item_id": str(good_id),
			"quantity": quantity,
			"market_id": active_market_id,
		})


func _emit_progression_events(events: Array) -> void:
	for event in events:
		if event is Dictionary:
			progression_event_triggered.emit(event)


func _resolve_market_id(market_id: String) -> String:
	return active_market_id if market_id == "" else market_id


func _result(ok: bool, message: String) -> Dictionary:
	return {
		"ok": ok,
		"message": message,
	}
