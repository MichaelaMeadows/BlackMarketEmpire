extends Node

signal state_changed

const GOOD_KEY := "street_goods"

var cash: int = 120
var heat: int = 0
var current_scope: String = "neighborhood"
var product_name: String = "Street Goods"
var inventory: Dictionary = {
	"street_goods": 8,
}

func buy_from_supplier(quantity: int = 1, unit_price: int = 12) -> Dictionary:
	var total_cost := quantity * unit_price
	if cash < total_cost:
		return _result(false, "Not enough cash.")

	cash -= total_cost
	inventory[GOOD_KEY] = get_stock() + quantity
	heat = min(100, heat + quantity)
	_maybe_upgrade_scope()
	state_changed.emit()
	return _result(true, "Bought %d for $%d." % [quantity, total_cost])


func sell_to_buyer(quantity: int = 1, unit_price: int = 18) -> Dictionary:
	if get_stock() < quantity:
		return _result(false, "No stock to move.")

	var total_sale := quantity * unit_price
	inventory[GOOD_KEY] = get_stock() - quantity
	cash += total_sale
	heat = min(100, heat + quantity * 2)
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
	var next_scope := current_scope
	if cash >= 10000:
		next_scope = "global"
	elif cash >= 2500:
		next_scope = "nation"
	elif cash >= 500:
		next_scope = "city"

	current_scope = next_scope


func _result(ok: bool, message: String) -> Dictionary:
	return {
		"ok": ok,
		"message": message,
	}
