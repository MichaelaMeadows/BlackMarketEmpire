extends Node

signal state_changed
signal progression_event_triggered(event: Dictionary)

const MARKET_SIMULATION_SCRIPT = preload("res://scripts/market_simulation.gd")
const PROGRESSION_TRACKER_SCRIPT = preload("res://scripts/progression_tracker.gd")
const ECONOMY_DATA_PATH = "res://data/economy"
const PROGRESSION_DATA_PATH = "res://data/progression/unlock_rules.json"
const GOOD_KEY = "street_goods"
const STARTING_MARKET_ID = "rook_market"

var cash: int = 120
var heat: int = 0
var current_scope: String = "neighborhood"
var product_name: String = "Street Goods"
var active_market_id: String = STARTING_MARKET_ID
var market
var progression
var inventory: Dictionary = {
	"street_goods": 8,
}

func _ready() -> void:
	_ensure_market()
	_ensure_progression()
	product_name = str(market.get_good(GOOD_KEY).get("name", product_name))


func buy_from_supplier(quantity: int = 1, unit_price: int = -1) -> Dictionary:
	_ensure_market()
	if unit_price < 0:
		unit_price = get_current_buy_price(GOOD_KEY, active_market_id)
	var total_cost: int = quantity * unit_price
	if cash < total_cost:
		return _result(false, "Not enough cash.")

	var acquired: float = market.remove_inventory(active_market_id, GOOD_KEY, float(quantity))
	if acquired < float(quantity):
		market.add_inventory(active_market_id, GOOD_KEY, acquired)
		return _result(false, "Local supply is tight.")

	cash -= total_cost
	inventory[GOOD_KEY] = get_stock() + quantity
	heat = min(100, heat + quantity)
	_maybe_upgrade_scope()
	state_changed.emit()
	return _result(true, "Bought %d for $%d." % [quantity, total_cost])


func sell_to_buyer(quantity: int = 1, unit_price: int = -1) -> Dictionary:
	_ensure_market()
	if get_stock() < quantity:
		return _result(false, "No stock to move.")

	if unit_price < 0:
		unit_price = get_current_sell_price(GOOD_KEY, active_market_id)
	var total_sale: int = quantity * unit_price
	inventory[GOOD_KEY] = get_stock() - quantity
	cash += total_sale
	heat = min(100, heat + quantity * 2)
	market.add_inventory(active_market_id, GOOD_KEY, float(quantity))
	record_progression_event("sale", {
		"item_id": GOOD_KEY,
		"quantity": quantity,
		"value": total_sale,
		"market_id": active_market_id,
	})
	_maybe_upgrade_scope()
	state_changed.emit()
	return _result(true, "Sold %d for $%d." % [quantity, total_sale])


func pay_fixer(cost: int = 25, heat_reduction: int = 12) -> Dictionary:
	if cash < cost:
		return _result(false, "The fixer wants $%d." % cost)

	cash -= cost
	heat = max(0, heat - heat_reduction)
	state_changed.emit()
	return _result(true, "Heat reduced.")


func get_stock() -> int:
	return int(inventory.get(GOOD_KEY, 0))


func get_current_buy_price(good_id: String = GOOD_KEY, market_id: String = "") -> int:
	_ensure_market()
	return market.get_buy_price(_resolve_market_id(market_id), good_id)


func get_current_sell_price(good_id: String = GOOD_KEY, market_id: String = "") -> int:
	_ensure_market()
	return market.get_sell_price(_resolve_market_id(market_id), good_id)


func get_market_snapshot(market_id: String = "") -> Array:
	_ensure_market()
	return market.get_market_snapshot(_resolve_market_id(market_id))


func advance_market(days: int = 1) -> void:
	_ensure_market()
	_ensure_progression()
	market.advance_day(days)
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
