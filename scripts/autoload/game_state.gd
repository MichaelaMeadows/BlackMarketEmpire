extends Node

signal state_changed
signal progression_event_triggered(event: Dictionary)
signal crew_hired(crew_member: Dictionary)
signal intro_mission_changed(snapshot: Dictionary, transition: Dictionary)

const MARKET_SIMULATION_SCRIPT = preload("res://scripts/market_simulation.gd")
const PROGRESSION_TRACKER_SCRIPT = preload("res://scripts/progression_tracker.gd")
const NPC_ROLE_CATALOG_SCRIPT = preload("res://scripts/npc_role_catalog.gd")
const NAME_GENERATOR_SCRIPT = preload("res://scripts/name_generator.gd")
const TRADE_STATE_SCRIPT = preload("res://scripts/trade_state.gd")
const INTRO_MISSION_TRACKER_SCRIPT = preload("res://scripts/intro_mission_tracker.gd")
const BASE_PRODUCTION_STATE_SCRIPT = preload("res://scripts/base_production_state.gd")
const ECONOMY_DATA_PATH = "res://data/economy"
const PROGRESSION_DATA_PATH = "res://data/progression/unlock_rules.json"
const INTRO_MISSION_DATA_PATH = "res://data/progression/intro_missions.json"
const BASE_PRODUCTION_DATA_PATH = "res://data/production/base_recipes.json"
const PRODUCTION_TRADE_GOODS := ["packaging_stock", "clean_textiles", "paper_forms", "repair_parts", "industrial_supplies", "plain_wraps", "clean_labels", "burner_parts"]
const GOOD_KEY = "fast_food"
const STARTING_MARKET_ID = "rook_market"
const DAYS_PER_WEEK = 7
const UNEMPLOYMENT_BENEFITS_WEEKLY = 25
const RUNNER_CARRY_CAPACITY_KG = 5
const TRADE_SOURCE_INFINITE = -1
const HIRE_CANDIDATE_REFRESH_DAYS = 3
const STARTING_HIRE_CANDIDATE_LIMIT = 2
const MAX_HIRE_CANDIDATE_LIMIT = 6
const DAILY_CREW_HEAL = 1
const DAILY_PLAYER_HEAL = 1
const DAY_LENGTH_SECONDS := 360.0
const CALENDAR_START := {
	"year": 2025,
	"month": 4,
	"day": 20,
	"hour": 0,
	"minute": 0,
	"second": 0,
}
const LEGALITY_LEGAL = "legal"
const LEGALITY_ILLICIT = "illicit"
const LEGALITY_CONTROLLED = "controlled"
const LEGALITY_ILLEGAL = "illegal"
const LEGALITY_TABOO = "taboo"
const HIRE_ARCHETYPE_SEQUENCE := ["thug", "thug", "dealer", "runner", "mercenary", "workshop_hand"]
const HIRE_ARCHETYPE_PRICES := {
	"dealer": 35,
	"runner": 30,
	"thug": 45,
	"mercenary": 120,
	"workshop_hand": 45,
}

var cash: int = 100
var heat: int = 0
var current_scope: String = "neighborhood"
var product_name: String = "Fast Food"
var active_market_id: String = STARTING_MARKET_ID
var day_count: int = 0
var day_time_seconds: float = 0.0
var player_health: int = 100
var player_max_health: int = 100
var market
var progression
var intro_missions
var base_production
var hire_name_generator = NAME_GENERATOR_SCRIPT.new(4177)
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
var trade_state = TRADE_STATE_SCRIPT.new()
var weekly_income_sources: Array = [
	{"id": "unemployment_benefits", "name": "Unemployment Benefits", "amount": UNEMPLOYMENT_BENEFITS_WEEKLY},
]
var transport_tasks: Array = [
	{"id": "corner_pickup", "name": "Corner Pickup", "required_role": "transporter", "duration_days": 1, "reward": 8, "capacity_kg": 5},
	{"id": "supply_drop", "name": "Supply Drop", "required_role": "transporter", "duration_days": 1, "reward": 10, "capacity_kg": 4},
]
var hire_candidates: Array = []
var hire_candidates_initialized := false
var hire_candidate_progress_days: int = 0
var next_hire_candidate_id: int = 1
var next_hired_crew_id: int = 1
var raid_targets: Array = []
var active_raid_target: Dictionary = {}
var raid_stats: Dictionary = {
	"launched": 0,
	"joined": 0,
	"completed": 0,
}
var last_raid_report: Dictionary = {}

func _ready() -> void:
	_ensure_market()
	_ensure_progression()
	_ensure_intro_missions()
	_ensure_base_production()
	product_name = str(market.get_good(GOOD_KEY).get("name", product_name))
	storage_inventory[GOOD_KEY] = get_stock()
	_ensure_hire_candidates()


func buy_from_supplier(quantity: int = 1, unit_price: int = -1, good_id: String = GOOD_KEY) -> Dictionary:
	var context := _trade_context()
	return _complete_trade_action(context, trade_state.buy_from_supplier(context, quantity, unit_price, good_id), true)


func sell_to_buyer(quantity: int = 1, unit_price: int = -1, good_id: String = GOOD_KEY) -> Dictionary:
	var context := _trade_context()
	return _complete_trade_action(context, trade_state.sell_to_buyer(context, quantity, unit_price, good_id), true)


func place_buy_order(quantity: int = -1, unit_price: int = -1, good_id: String = GOOD_KEY) -> Dictionary:
	var context := _trade_context()
	var result := _complete_trade_action(context, trade_state.place_buy_order(context, quantity, unit_price, good_id))
	if bool(result.get("ok", false)):
		var order: Dictionary = result.get("order", {})
		record_intro_mission_event("trade_order_placed", {
			"order_type": "buy", "good_id": str(order.get("good_id", good_id)),
			"quantity": int(order.get("total_quantity", 0)),
		})
	return result


func place_sell_order(quantity: int = -1, unit_price: int = -1, good_id: String = GOOD_KEY) -> Dictionary:
	var context := _trade_context()
	return _complete_trade_action(context, trade_state.place_sell_order(context, quantity, unit_price, good_id))


func pick_up_sell_order(trip_id: String) -> Dictionary:
	var context := _trade_context()
	return _complete_trade_action(context, trade_state.pick_up_sell_order(context, trip_id))


func deposit_buy_order(trip_id: String) -> Dictionary:
	var trip := trade_state.get_trip(trip_id)
	var context := _trade_context()
	var result := _complete_trade_action(context, trade_state.deposit_buy_order(context, trip_id), true)
	if bool(result.get("ok", false)) and not trip.is_empty():
		record_intro_mission_event("trade_buy_delivered", {
			"good_id": str(trip.get("good_id", GOOD_KEY)), "quantity": int(trip.get("quantity", 0)),
		})
	return result


func complete_sell_order(trip_id: String) -> Dictionary:
	var trip := trade_state.get_trip(trip_id)
	var context := _trade_context()
	var result := _complete_trade_action(context, trade_state.complete_sell_order(context, trip_id), true)
	if bool(result.get("ok", false)) and not trip.is_empty():
		record_intro_mission_event("trade_sale_completed", {
			"good_id": str(trip.get("good_id", GOOD_KEY)), "quantity": int(trip.get("quantity", 0)),
		})
	return result


func get_trade_orders() -> Array:
	return trade_state.get_orders()


func get_trade_trips() -> Array:
	return trade_state.get_trips(_trade_context())


func update_trade_trip_progress(trip_id: String, phase: String, eta_seconds: float) -> void:
	trade_state.update_trip_progress(trip_id, phase, eta_seconds)


func get_trade_order_rows() -> Array:
	return trade_state.get_order_rows(_trade_context())


func get_available_sell_stock(good_id: String = GOOD_KEY) -> int:
	return trade_state.get_available_sell_stock(_trade_context(), good_id)


func get_unit_weight_kg(good_id: String = GOOD_KEY) -> int:
	return trade_state.get_unit_weight_kg(good_id)


func get_runner_trip_unit_capacity(good_id: String = GOOD_KEY) -> int:
	return trade_state.get_trip_unit_capacity(_trade_context(), good_id)


func get_transporter_trip_unit_capacity(good_id: String = GOOD_KEY) -> int:
	return trade_state.get_trip_unit_capacity(_trade_context(), good_id)


func dispatch_queued_trade_trips() -> Array:
	return trade_state.dispatch_queued_trips(_trade_context())


func pay_fixer(cost: int = 25, heat_reduction: int = 12) -> Dictionary:
	if cash < cost:
		return _result(false, "The fixer wants $%d." % cost)

	cash -= cost
	heat = max(0, heat - heat_reduction)
	state_changed.emit()
	return _result(true, "Heat reduced.")


func initialize_base_from_map(map_data: Dictionary) -> void:
	var new_base: Dictionary = map_data.get("base", {}).duplicate(true)
	var previous_base_id := str(current_base.get("id", ""))
	var new_base_id := str(new_base.get("id", ""))
	var should_preserve_roster := previous_base_id != "" and previous_base_id == new_base_id and not crew_roster.is_empty()
	current_base = new_base
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

	if not should_preserve_roster:
		crew_roster = _extract_crew_from_map(map_data)
	if storage_inventory.is_empty():
			storage_inventory[GOOD_KEY] = get_stock(GOOD_KEY)
	else:
		storage_inventory[GOOD_KEY] = get_stock(GOOD_KEY)
	state_changed.emit()


func get_base_summary() -> Dictionary:
	var fallback_name: String = "No Base"
	var role_limits: Dictionary = get_base_role_limits()
	var role_counts: Dictionary = get_base_role_counts()
	return {
		"id": str(current_base.get("id", "")),
		"name": str(current_base.get("name", fallback_name)),
		"tier": str(current_base.get("tier", "none")),
		"owned": bool(current_base.get("owned", false)),
		"next_base_hint": str(current_base.get("next_base_hint", "")),
		"room_count": base_rooms.size(),
		"facility_count": base_facilities.size(),
		"crew_count": crew_roster.size(),
		"role_limits": role_limits,
		"role_counts": role_counts,
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


func get_available_hires() -> Array:
	_ensure_hire_candidates()
	var hires: Array = []
	for candidate in hire_candidates:
		if not (candidate is Dictionary):
			continue
		var row: Dictionary = candidate.duplicate(true)
		var role_id := str(row.get("role", ""))
		var price := int(row.get("price", 0))
		var block_reason := ""
		if cash < price:
			block_reason = "Need $%d." % price
		elif not can_base_accept_role(role_id):
			block_reason = "No %s slots available." % str(row.get("role_name", role_id.capitalize()))
		row["can_hire"] = block_reason == ""
		row["block_reason"] = block_reason
		hires.append(row)
	return hires


func hire_employee(candidate_id: String) -> Dictionary:
	_ensure_hire_candidates()
	var candidate_index := _find_hire_candidate_index(candidate_id)
	if candidate_index < 0:
		return _result(false, "That candidate is no longer available.")

	var candidate: Dictionary = hire_candidates[candidate_index]
	var role_id := str(candidate.get("role", ""))
	var price := int(candidate.get("price", 0))
	if cash < price:
		return _result(false, "Need $%d to hire %s." % [price, str(candidate.get("name", "them"))])
	if not can_base_accept_role(role_id):
		return _result(false, "No %s slots available." % str(candidate.get("role_name", role_id.capitalize())))

	cash -= price
	var crew_member := candidate.duplicate(true)
	crew_member["id"] = "hireling_%d" % next_hired_crew_id
	next_hired_crew_id += 1
	crew_member.erase("price")
	crew_member.erase("can_hire")
	crew_member.erase("block_reason")
	crew_member.erase("available_day")
	crew_member["status"] = "Ready"
	crew_member["assigned_task"] = ""
	crew_member["max_health"] = int(crew_member.get("max_health", crew_member.get("health", 60)))
	crew_member["health"] = clamp(int(crew_member.get("health", crew_member["max_health"])), 0, int(crew_member["max_health"]))
	crew_member["faction"] = "player_crew"
	crew_member["visual_id"] = _get_hire_visual_id(str(crew_member.get("archetype", "")))
	if not crew_member.has("color"):
		crew_member["color"] = _get_hire_color(str(crew_member.get("role", "")), str(crew_member.get("archetype", "")))
	_apply_default_hire_loadout(crew_member)
	crew_roster.append(crew_member)
	hire_candidates.remove_at(candidate_index)
	var result := _result(true, "Hired %s for $%d." % [str(crew_member.get("name", "Crew")), price])
	result["crew_member"] = crew_member.duplicate(true)
	record_intro_mission_event("crew_hired", {
		"crew_id": str(crew_member.get("id", "")),
		"role": str(crew_member.get("role", "")),
		"archetype": str(crew_member.get("archetype", "")),
	})
	crew_hired.emit(crew_member.duplicate(true))
	state_changed.emit()
	return result


func get_crew_count(role_id: String = "") -> int:
	var count: int = 0
	for crew_member in crew_roster:
		if not (crew_member is Dictionary):
			continue
		if not _is_crew_member_alive(crew_member):
			continue
		if role_id != "" and not NPC_ROLE_CATALOG_SCRIPT.has_role(crew_member, role_id):
			continue
		count += 1
	return count


func get_ready_crew_count(role_id: String = "") -> int:
	var count: int = 0
	for crew_member in crew_roster:
		if not (crew_member is Dictionary):
			continue
		if not _is_crew_member_alive(crew_member):
			continue
		if role_id != "" and not NPC_ROLE_CATALOG_SCRIPT.has_role(crew_member, role_id):
			continue
		if str(crew_member.get("status", "Ready")) == "Ready":
			count += 1
	return count


func set_player_health(current_health: int, max_health: int = -1) -> void:
	var previous_health := player_health
	var previous_max_health := player_max_health
	if max_health > 0:
		player_max_health = max(1, max_health)
	player_health = clamp(current_health, 0, player_max_health)
	if player_health == previous_health and player_max_health == previous_max_health:
		return
	state_changed.emit()


func get_player_health() -> Dictionary:
	return {
		"health": player_health,
		"max_health": player_max_health,
	}


func get_day_length_seconds() -> float:
	return DAY_LENGTH_SECONDS


func advance_game_time(delta_seconds: float) -> Dictionary:
	if delta_seconds <= 0.0:
		return {
			"days_advanced": 0,
			"clock_changed": false,
		}
	var previous_minute: int = _get_clock_minute_of_day()
	advance_base_production(delta_seconds)
	day_time_seconds += delta_seconds
	var days_advanced: int = 0
	while day_time_seconds >= DAY_LENGTH_SECONDS:
		day_time_seconds -= DAY_LENGTH_SECONDS
		days_advanced += 1
	if days_advanced > 0:
		advance_market(days_advanced)
	var current_minute: int = _get_clock_minute_of_day()
	return {
		"days_advanced": days_advanced,
		"clock_changed": current_minute != previous_minute or days_advanced > 0,
	}


func get_clock_snapshot() -> Dictionary:
	var minute_of_day: int = _get_clock_minute_of_day()
	var calendar_date: Dictionary = _get_calendar_date(day_count)
	return {
		"day": day_count + 1,
		"year": int(calendar_date.get("year", 2025)),
		"month": int(calendar_date.get("month", 4)),
		"month_name": _get_month_name(int(calendar_date.get("month", 4))),
		"day_of_month": int(calendar_date.get("day", 20)),
		"weekday": int(calendar_date.get("weekday", 0)),
		"weekday_name": _get_weekday_name(int(calendar_date.get("weekday", 0))),
		"hour": int(minute_of_day / 60),
		"minute": minute_of_day % 60,
		"day_progress": clampf(day_time_seconds / DAY_LENGTH_SECONDS, 0.0, 1.0),
		"day_length_seconds": DAY_LENGTH_SECONDS,
	}


func get_clock_label() -> String:
	var snapshot: Dictionary = get_clock_snapshot()
	return "%s, %s %d, %d  %02d:%02d" % [
		str(snapshot.get("weekday_name", "Sun")),
		str(snapshot.get("month_name", "Apr")),
		int(snapshot.get("day_of_month", 20)),
		int(snapshot.get("year", 2025)),
		int(snapshot.get("hour", 0)),
		int(snapshot.get("minute", 0)),
	]


func set_crew_health(crew_id: String, current_health: int, max_health: int = -1) -> Dictionary:
	var crew_index := _find_crew_index(crew_id)
	if crew_index < 0:
		return _result(false, "Crew member not found.")
	var crew_member: Dictionary = crew_roster[crew_index]
	var resolved_max_health: int = int(crew_member.get("max_health", crew_member.get("health", 60)))
	if max_health > 0:
		resolved_max_health = max(1, max_health)
	var resolved_health: int = clamp(current_health, 0, resolved_max_health)
	if int(crew_member.get("health", resolved_health)) == resolved_health and int(crew_member.get("max_health", resolved_max_health)) == resolved_max_health:
		return _result(true, "%s health unchanged." % str(crew_member.get("name", "Crew")))
	crew_member["max_health"] = resolved_max_health
	crew_member["health"] = resolved_health
	crew_roster[crew_index] = crew_member
	state_changed.emit()
	return _result(true, "%s health updated." % str(crew_member.get("name", "Crew")))


func heal_crew_over_time(days: int) -> void:
	_heal_roster(days)
	_heal_player(days)
	state_changed.emit()


func get_base_role_limits() -> Dictionary:
	var normalized_limits := {
		"transporter": 0,
		"muscle": 0,
		"production": 0,
	}
	var raw_limits: Variant = current_base.get("role_limits", current_base.get("staff_limits", {}))
	if raw_limits is Dictionary:
		for role_id in raw_limits:
			var normalized_role := NPC_ROLE_CATALOG_SCRIPT.normalize_role_id(str(role_id))
			if normalized_role == "":
				continue
			normalized_limits[normalized_role] = max(0, int(raw_limits[role_id]))
	return normalized_limits


func get_base_role_limit(role_id: String) -> int:
	var limits: Dictionary = get_base_role_limits()
	var normalized_role := NPC_ROLE_CATALOG_SCRIPT.normalize_role_id(role_id)
	return int(limits.get(normalized_role, 0))


func get_base_role_counts() -> Dictionary:
	return {
		"transporter": get_crew_count("transporter"),
		"muscle": get_crew_count("muscle"),
		"production": get_crew_count("production"),
	}


func can_base_accept_role(role_id: String) -> bool:
	var normalized_role := NPC_ROLE_CATALOG_SCRIPT.normalize_role_id(role_id)
	return get_crew_count(normalized_role) < get_base_role_limit(normalized_role)


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
	for trip in trade_state.get_trips():
		if trip is Dictionary and str(trip.get("crew_id", "")) == crew_id:
			trip_ids_to_cancel.append(str(trip.get("id", "")))
	for trip_id in trip_ids_to_cancel:
		trade_state.cancel_trip(_trade_context(), str(trip_id))

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


func get_base_production_rows() -> Array:
	_ensure_base_production()
	return base_production.get_recipe_rows(_base_production_context())


func get_base_production_jobs() -> Array:
	_ensure_base_production()
	return base_production.get_jobs()


func start_base_production(facility_id: String, recipe_id: String) -> Dictionary:
	_ensure_base_production()
	var result: Dictionary = base_production.start_job(_base_production_context(), facility_id, recipe_id)
	if bool(result.get("ok", false)):
		state_changed.emit()
	return result


func cancel_base_production(facility_id: String) -> Dictionary:
	_ensure_base_production()
	var result: Dictionary = base_production.cancel_job(_base_production_context(), facility_id)
	if bool(result.get("ok", false)):
		state_changed.emit()
	return result


func advance_base_production(delta_seconds: float) -> Array:
	_ensure_base_production()
	var completed: Array = base_production.advance(_base_production_context(), delta_seconds)
	for batch in completed:
		if batch is Dictionary:
			record_progression_event("crafted", {
				"item_id": str(batch.get("good_id", "")),
				"quantity": int(batch.get("quantity", 0)),
				"facility_id": str(batch.get("facility_id", "")),
			})
	if not completed.is_empty():
		state_changed.emit()
	return completed


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


func send_raid(target_id: String, crew_ids: Array) -> Dictionary:
	if not active_raid_target.is_empty():
		return _result(false, "A raid is already active.")

	var target: Dictionary = resolve_raid_target(target_id)
	if target.is_empty():
		return _result(false, "Raid target is not available.")

	var selected_ids: Array = []
	for value in crew_ids:
		var crew_id := str(value)
		if crew_id != "" and not selected_ids.has(crew_id):
			selected_ids.append(crew_id)

	var crew_required: int = int(target.get("crew_required", 1))
	if selected_ids.size() < crew_required:
		return _result(false, "Select at least %d crew." % crew_required)

	for crew_id in selected_ids:
		var crew_index := _find_crew_index(crew_id)
		if crew_index < 0:
			return _result(false, "Crew member is not available.")
		var crew_member: Dictionary = crew_roster[crew_index]
		if not _is_crew_member_alive(crew_member):
			return _result(false, "%s cannot raid." % str(crew_member.get("name", "Crew")))
		if str(crew_member.get("status", "Ready")) != "Ready":
			return _result(false, "%s is busy." % str(crew_member.get("name", "Crew")))

	target["mode"] = "departing"
	target["crew_ids"] = selected_ids
	target["crew_names"] = _get_crew_names_for_ids(selected_ids)
	active_raid_target = target
	last_raid_report = {}
	for crew_id in selected_ids:
		var crew_index := _find_crew_index(crew_id)
		if crew_index >= 0:
			crew_roster[crew_index]["status"] = "Leaving"
			crew_roster[crew_index]["assigned_task"] = "raid:%s" % target_id
	state_changed.emit()

	return _result(true, "%s is heading for the exit." % ", ".join(PackedStringArray(target.get("crew_names", []))))


func begin_sent_raid(departed_crew_ids: Array) -> Dictionary:
	if active_raid_target.is_empty() or str(active_raid_target.get("mode", "")) != "departing":
		return _result(false, "No raid party is leaving.")

	var target := active_raid_target.duplicate(true)
	var selected_ids: Array = target.get("crew_ids", [])
	var participant_ids: Array = []
	var selected_crew: Array = []
	for value in departed_crew_ids:
		var crew_id := str(value)
		if crew_id == "" or participant_ids.has(crew_id) or not selected_ids.has(crew_id):
			continue
		var crew_index := _find_crew_index(crew_id)
		if crew_index < 0:
			continue
		var crew_member: Dictionary = crew_roster[crew_index]
		if not _is_crew_member_alive(crew_member):
			continue
		participant_ids.append(crew_id)
		selected_crew.append(crew_member.duplicate(true))

	if participant_ids.is_empty():
		active_raid_target = {}
		state_changed.emit()
		return _result(false, "No crew made it out for the raid.")

	target["mode"] = "sent"
	target["crew_ids"] = participant_ids
	target["crew_names"] = _get_crew_names_for_ids(participant_ids)
	active_raid_target = target
	for crew_id in participant_ids:
		var crew_index := _find_crew_index(crew_id)
		if crew_index >= 0:
			crew_roster[crew_index]["status"] = "Raiding"
			crew_roster[crew_index]["assigned_task"] = "raid:%s" % str(target.get("id", ""))
	raid_stats["launched"] = int(raid_stats.get("launched", 0)) + 1
	record_progression_event("raid_started", {
		"target_id": str(target.get("id", "")),
		"metrics": {"raids_started": 1},
	})
	state_changed.emit()

	var result := _result(true, "%s left for %s." % [
		", ".join(PackedStringArray(target.get("crew_names", []))),
		str(target.get("name", target.get("id", "raid"))),
	])
	result["duration_seconds"] = _get_sent_raid_duration(target, selected_crew)
	return result


func complete_active_raid(success: bool = true) -> Dictionary:
	if active_raid_target.is_empty():
		return _result(false, "No active raid.")
	var target_name: String = str(active_raid_target.get("name", "Raid"))
	var active_target := active_raid_target.duplicate(true)
	var is_sent_raid := str(active_target.get("mode", "")) == "sent"
	var report: Dictionary = {}
	if is_sent_raid:
		report = _resolve_sent_raid_report(active_target, success)
		success = bool(report.get("success", success))
	if success:
		raid_stats["completed"] = int(raid_stats.get("completed", 0)) + 1
		cash += 35
		inventory[GOOD_KEY] = get_stock(GOOD_KEY) + 2
		storage_inventory[GOOD_KEY] = get_stock(GOOD_KEY)
		record_progression_event("raid_completed", {
			"target_id": str(active_raid_target.get("id", "")),
			"metrics": {"raids_completed": 1},
		})
		record_intro_mission_event("raid_completed", {
			"target_id": str(active_target.get("id", "")),
		})
	if is_sent_raid:
		_apply_sent_raid_report(report)
		last_raid_report = report
	else:
		var report_loot: Dictionary = {}
		if success:
			report_loot[GOOD_KEY] = 2
		last_raid_report = {
			"target_id": str(active_target.get("id", "")),
			"target_name": target_name,
			"success": success,
			"message": "%s complete." % target_name,
			"reward_cash": 35 if success else 0,
			"loot": report_loot,
		}
	active_raid_target = {}
	state_changed.emit()
	var message := str(last_raid_report.get("message", "%s complete." % target_name))
	return _result(success, message)


func get_active_raid_target() -> Dictionary:
	return active_raid_target.duplicate(true)


func get_last_raid_report() -> Dictionary:
	return last_raid_report.duplicate(true)


func get_raid_stats() -> Dictionary:
	return raid_stats.duplicate(true)


func get_stock(good_id: String = GOOD_KEY) -> int:
	return int(inventory.get(good_id, 0))

func get_current_buy_price(good_id: String = GOOD_KEY, market_id: String = "") -> int:
	return trade_state.get_current_buy_price(_trade_context(), good_id, market_id)


func get_current_sell_price(good_id: String = GOOD_KEY, market_id: String = "") -> int:
	return trade_state.get_current_sell_price(_trade_context(), good_id, market_id)


func get_market_snapshot(market_id: String = "") -> Array:
	_ensure_market()
	return market.get_market_snapshot(_resolve_market_id(market_id))


func get_available_trade_goods() -> Array:
	return trade_state.get_available_goods(_trade_context())


func get_remote_inventory_for_good(good_id: String) -> int:
	return trade_state.get_remote_inventory(_trade_context(), good_id)


func get_remote_inventory_label(good_id: String) -> String:
	return trade_state.get_remote_inventory_label(_trade_context(), good_id)


func get_trade_distance_label(good_id: String) -> String:
	return trade_state.get_distance_label(good_id)




func advance_market(days: int = 1) -> void:
	_ensure_market()
	_ensure_progression()
	market.advance_day(days)
	_apply_weekly_finances(days)
	_heal_roster(days)
	_heal_player(days)
	_advance_hire_candidates(days)
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


func record_intro_mission_event(event_type: String, payload: Dictionary = {}) -> Dictionary:
	_ensure_intro_missions()
	var transition: Dictionary = intro_missions.record_event(event_type, payload)
	if not bool(transition.get("changed", false)):
		return transition
	if bool(transition.get("intro_complete", false)):
		for good_id in PRODUCTION_TRADE_GOODS:
			trade_state.unlock_good(str(good_id))
	var snapshot: Dictionary = intro_missions.get_snapshot()
	intro_mission_changed.emit(snapshot, transition)
	state_changed.emit()
	return transition


func get_intro_mission_snapshot() -> Dictionary:
	_ensure_intro_missions()
	return intro_missions.get_snapshot()


func record_kill(target_type: String = "npc") -> Array:
	return record_progression_event("kill", {
		"target_type": target_type,
	})


func is_unlocked(unlock_id: String) -> bool:
	_ensure_progression()
	return progression.is_unlocked(unlock_id)


func unlock_trade_good(good_id: String) -> bool:
	return trade_state.unlock_good(good_id)


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


func _ensure_intro_missions() -> void:
	if intro_missions != null:
		return
	intro_missions = INTRO_MISSION_TRACKER_SCRIPT.new()
	intro_missions.load_missions(INTRO_MISSION_DATA_PATH)


func _ensure_base_production() -> void:
	if base_production != null:
		return
	base_production = BASE_PRODUCTION_STATE_SCRIPT.new()
	base_production.load_recipes(BASE_PRODUCTION_DATA_PATH)


func _ensure_hire_candidates() -> void:
	if hire_candidates_initialized:
		return
	while hire_candidates.size() < STARTING_HIRE_CANDIDATE_LIMIT and hire_candidates.size() < _get_hire_candidate_limit():
		_add_hire_candidate()
	hire_candidates_initialized = true


func _advance_hire_candidates(days: int) -> void:
	hire_candidate_progress_days += max(0, days)
	while hire_candidate_progress_days >= HIRE_CANDIDATE_REFRESH_DAYS and hire_candidates.size() < _get_hire_candidate_limit():
		hire_candidate_progress_days -= HIRE_CANDIDATE_REFRESH_DAYS
		_add_hire_candidate()
	if hire_candidates.size() >= _get_hire_candidate_limit():
		hire_candidate_progress_days = 0


func _get_hire_candidate_limit() -> int:
	return min(MAX_HIRE_CANDIDATE_LIMIT, STARTING_HIRE_CANDIDATE_LIMIT + int(day_count / DAYS_PER_WEEK))


func _add_hire_candidate() -> void:
	var archetype_id := str(HIRE_ARCHETYPE_SEQUENCE[(next_hire_candidate_id - 1) % HIRE_ARCHETYPE_SEQUENCE.size()])
	var staff_profile := NPC_ROLE_CATALOG_SCRIPT.build_staff_profile({"archetype": archetype_id}, {})
	var candidate := {
		"id": "hire_candidate_%d" % next_hire_candidate_id,
		"name": _generate_hire_name(),
		"price": int(HIRE_ARCHETYPE_PRICES.get(archetype_id, 50)),
		"role": str(staff_profile.get("role", "")),
		"role_name": str(staff_profile.get("role_name", "Crew")),
		"archetype": str(staff_profile.get("archetype", archetype_id)),
		"archetype_name": str(staff_profile.get("archetype_name", archetype_id.capitalize())),
		"job": str(staff_profile.get("job", archetype_id.capitalize())),
		"task_types": staff_profile.get("task_types", []),
		"carry_capacity_kg": int(staff_profile.get("carry_capacity_kg", 0)),
		"upkeep": int(staff_profile.get("upkeep", 0)),
		"status": "Ready",
		"assigned_task": "",
		"health": 60,
		"max_health": 60,
		"available_day": day_count,
	}
	_apply_default_hire_loadout(candidate)
	hire_candidates.append(candidate)
	next_hire_candidate_id += 1


func _generate_hire_name() -> String:
	for _attempt in range(24):
		var candidate_name := hire_name_generator.generate_npc_name({"include_surname": false})
		if not _is_crew_or_candidate_name_used(candidate_name):
			return candidate_name
	return hire_name_generator.generate_npc_name({"include_surname": true})


func _is_crew_or_candidate_name_used(candidate_name: String) -> bool:
	for crew_member in crew_roster:
		if crew_member is Dictionary and str(crew_member.get("name", "")) == candidate_name:
			return true
	for candidate in hire_candidates:
		if candidate is Dictionary and str(candidate.get("name", "")) == candidate_name:
			return true
	return false


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
		var staff_profile: Dictionary = NPC_ROLE_CATALOG_SCRIPT.build_staff_profile(staff_data, npc)
		roster.append({
			"id": str(npc.get("id", "")),
			"name": str(npc.get("name", "Crew")),
			"role": str(staff_profile.get("role", "")),
			"role_name": str(staff_profile.get("role_name", "Crew")),
			"archetype": str(staff_profile.get("archetype", "")),
			"archetype_name": str(staff_profile.get("archetype_name", "Crew")),
			"job": str(staff_profile.get("job", "Crew")),
			"status": str(staff_profile.get("status", "Ready")),
			"assigned_task": str(staff_profile.get("assigned_task", "")),
			"task_types": staff_profile.get("task_types", []),
			"carry_capacity_kg": int(staff_profile.get("carry_capacity_kg", RUNNER_CARRY_CAPACITY_KG)),
			"upkeep": int(staff_profile.get("upkeep", 0)),
			"health": int(npc.get("health", 60)),
			"max_health": int(npc.get("max_health", npc.get("health", 60))),
			"color": npc.get("color", []),
			"visual_id": str(npc.get("visual_id", "crew_jacket")),
			"faction": str(npc.get("faction", "player_crew")),
			"home_position": npc.get("position", []),
		})
	return roster


func _get_hire_visual_id(archetype_id: String) -> String:
	match archetype_id:
		"thug", "mercenary":
			return "crew_muscle"
		"workshop_hand":
			return "crew_worker"
	return "crew_jacket"


func _get_hire_color(role_id: String, archetype_id: String) -> Array:
	match role_id:
		"muscle":
			return [0.58, 0.36, 0.30]
		"production":
			return [0.72, 0.58, 0.30]
	match archetype_id:
		"runner":
			return [0.36, 0.58, 0.72]
	return [0.28, 0.68, 0.62]


func _apply_default_hire_loadout(crew_member: Dictionary) -> void:
	match str(crew_member.get("archetype", "")):
		"thug":
			crew_member["ranged_weapon"] = false
			crew_member["weapon"] = null
			crew_member["melee_weapon"] = _get_bat_weapon()


func _get_bat_weapon() -> Dictionary:
	return {
		"name": "Baseball Bat",
		"weapon_type": "bat",
		"damage": 18,
		"range": 72,
		"arc_degrees": 95,
		"swing_cooldown": 0.6,
		"swing_duration": 0.16,
		"knockback": 90,
	}


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


func _heal_roster(days: int) -> void:
	var heal_amount: int = max(0, days) * DAILY_CREW_HEAL
	if heal_amount <= 0:
		return
	for index in range(crew_roster.size()):
		var crew_member: Variant = crew_roster[index]
		if not (crew_member is Dictionary):
			continue
		if not _is_crew_member_alive(crew_member):
			continue
		var max_health: int = int(crew_member.get("max_health", crew_member.get("health", 60)))
		var current_health: int = int(crew_member.get("health", max_health))
		crew_member["max_health"] = max_health
		crew_member["health"] = min(max_health, current_health + heal_amount)
		crew_roster[index] = crew_member


func _heal_player(days: int) -> void:
	var heal_amount: int = max(0, days) * DAILY_PLAYER_HEAL
	if heal_amount <= 0 or player_health <= 0:
		return
	player_health = min(player_max_health, player_health + heal_amount)


func _get_clock_minute_of_day() -> int:
	if DAY_LENGTH_SECONDS <= 0.0:
		return 0
	var progress: float = clampf(day_time_seconds / DAY_LENGTH_SECONDS, 0.0, 0.99999)
	return int(floor(progress * 1440.0))


func _get_calendar_date(days_elapsed: int) -> Dictionary:
	var start_date: Dictionary = CALENDAR_START.duplicate(true)
	var start_unix: int = int(Time.get_unix_time_from_datetime_dict(start_date))
	var date_unix: int = start_unix + max(0, days_elapsed) * 86400
	return Time.get_datetime_dict_from_unix_time(date_unix)


func _get_month_name(month: int) -> String:
	var month_names := PackedStringArray(["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"])
	if month < 1 or month > month_names.size():
		return "???"
	return month_names[month - 1]


func _get_weekday_name(weekday: int) -> String:
	var weekday_names := PackedStringArray(["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"])
	if weekday < 0 or weekday >= weekday_names.size():
		return "???"
	return weekday_names[weekday]


func _find_crew_index(crew_id: String) -> int:
	for index in range(crew_roster.size()):
		var crew_member: Variant = crew_roster[index]
		if crew_member is Dictionary and str(crew_member.get("id", "")) == crew_id:
			return index
	return -1


func _get_crew_names_for_ids(crew_ids: Array) -> Array:
	var names: Array = []
	for value in crew_ids:
		var crew_index := _find_crew_index(str(value))
		if crew_index < 0:
			continue
		var crew_member: Dictionary = crew_roster[crew_index]
		names.append(str(crew_member.get("name", "Crew")))
	return names


func _get_sent_raid_duration(target: Dictionary, selected_crew: Array) -> float:
	var difficulty: int = max(1, int(target.get("difficulty", 1)))
	var crew_count: int = max(1, selected_crew.size())
	return float(clamp(2.5 + float(difficulty) - float(crew_count) * 0.25, 2.0, 6.0))


func _resolve_sent_raid_report(target: Dictionary, requested_success: bool) -> Dictionary:
	var crew_ids: Array = target.get("crew_ids", [])
	var crew_names: Array = target.get("crew_names", _get_crew_names_for_ids(crew_ids))
	var enemy_names: Array = _get_raid_enemy_names(target)
	var difficulty: int = max(1, int(target.get("difficulty", 1)))
	var crew_required: int = max(1, int(target.get("crew_required", 1)))
	var crew_count: int = crew_ids.size()
	var success: bool = requested_success and crew_count >= crew_required and crew_count >= difficulty
	var casualty_count: int = 0
	if crew_count > 0:
		if success:
			casualty_count = max(0, difficulty - crew_count - 1)
		else:
			casualty_count = clamp(difficulty - crew_count + 1, 1, crew_count)

	var casualty_ids: Array = []
	var casualty_names: Array = []
	var survivor_ids: Array = []
	var survivor_names: Array = []
	var survivor_health_after: Dictionary = {}
	for index in range(crew_ids.size()):
		var crew_id := str(crew_ids[index])
		var crew_name := str(crew_names[index]) if index < crew_names.size() else crew_id
		if index < casualty_count:
			casualty_ids.append(crew_id)
			casualty_names.append(crew_name)
		else:
			survivor_ids.append(crew_id)
			survivor_names.append(crew_name)
			var crew_index := _find_crew_index(crew_id)
			if crew_index >= 0:
				var crew_member: Dictionary = crew_roster[crew_index]
				var current_health := int(crew_member.get("health", crew_member.get("max_health", 60)))
				var wound_damage := difficulty * (6 if success else 12)
				survivor_health_after[crew_id] = max(1, current_health - wound_damage)

	var enemy_casualty_count: int = enemy_names.size() if success else min(enemy_names.size(), max(0, crew_count - casualty_count))
	var enemy_casualties: Array = []
	var enemy_survivors: Array = []
	for index in range(enemy_names.size()):
		if index < enemy_casualty_count:
			enemy_casualties.append(enemy_names[index])
		else:
			enemy_survivors.append(enemy_names[index])

	var target_name: String = str(target.get("name", "Raid"))
	var message: String = ""
	if success:
		message = "%s hit %s and came back with supplies." % [_format_names_for_report(survivor_names), target_name]
		if not casualty_names.is_empty():
			message += " Lost: %s." % _format_names_for_report(casualty_names)
		if not enemy_casualties.is_empty():
			message += " Enemy losses: %s." % _format_names_for_report(enemy_casualties)
	else:
		message = "%s failed at %s." % [_format_names_for_report(crew_names), target_name]
		if not casualty_names.is_empty():
			message += " Lost: %s." % _format_names_for_report(casualty_names)
		if not enemy_casualties.is_empty():
			message += " Enemy losses: %s." % _format_names_for_report(enemy_casualties)

	var loot: Dictionary = {}
	if success:
		loot[GOOD_KEY] = 2
	return {
		"target_id": str(target.get("id", "")),
		"target_name": target_name,
		"success": success,
		"crew_sent": crew_names,
		"survivors": survivor_names,
		"casualties": casualty_names,
		"enemy_casualties": enemy_casualties,
		"enemy_survivors": enemy_survivors,
		"survivor_ids": survivor_ids,
		"survivor_health_after": survivor_health_after,
		"casualty_ids": casualty_ids,
		"reward_cash": 35 if success else 0,
		"loot": loot,
		"message": message,
	}


func _get_raid_enemy_names(target: Dictionary) -> Array:
	var enemy_names: Array = []
	var path := str(target.get("path", ""))
	if path != "" and FileAccess.file_exists(path):
		var source := FileAccess.get_file_as_string(path)
		var parsed: Variant = JSON.parse_string(source)
		if parsed is Dictionary:
			for npc in parsed.get("npcs", []):
				if not (npc is Dictionary):
					continue
				var faction := str(npc.get("faction", ""))
				if faction == "player" or faction == "player_crew":
					continue
				enemy_names.append(str(npc.get("name", npc.get("id", "Enemy"))))
	if enemy_names.is_empty():
		for index in range(max(1, int(target.get("difficulty", 1)))):
			enemy_names.append("Rival %d" % (index + 1))
	return enemy_names


func _format_names_for_report(names: Array) -> String:
	if names.is_empty():
		return "None"
	return ", ".join(PackedStringArray(names))


func _apply_sent_raid_report(report: Dictionary) -> void:
	for value in report.get("survivor_ids", []):
		var crew_index := _find_crew_index(str(value))
		if crew_index < 0:
			continue
		var survivor_health_after: Dictionary = report.get("survivor_health_after", {})
		if survivor_health_after.has(str(value)):
			crew_roster[crew_index]["health"] = clamp(int(survivor_health_after[str(value)]), 1, int(crew_roster[crew_index].get("max_health", crew_roster[crew_index].get("health", 60))))
		crew_roster[crew_index]["status"] = "Ready"
		crew_roster[crew_index]["assigned_task"] = ""
	for value in report.get("casualty_ids", []):
		var crew_index := _find_crew_index(str(value))
		if crew_index < 0:
			continue
		crew_roster[crew_index]["health"] = 0
		crew_roster[crew_index]["status"] = "Lost"
		crew_roster[crew_index]["assigned_task"] = ""


func _find_hire_candidate_index(candidate_id: String) -> int:
	for index in range(hire_candidates.size()):
		var candidate: Variant = hire_candidates[index]
		if candidate is Dictionary and str(candidate.get("id", "")) == candidate_id:
			return index
	return -1


func _is_crew_member_alive(crew_member: Dictionary) -> bool:
	return int(crew_member.get("health", 1)) > 0




func _find_transport_task(task_id: String) -> Dictionary:
	for task in transport_tasks:
		if task is Dictionary and str(task.get("id", "")) == task_id:
			return task.duplicate(true)
	return {}


func _crew_can_do_task(crew_member: Dictionary, task: Dictionary) -> bool:
	var required_role: String = str(task.get("required_role", ""))
	if required_role != "" and not NPC_ROLE_CATALOG_SCRIPT.has_role(crew_member, required_role):
		return false
	var required_job: String = str(task.get("required_job", ""))
	if required_job != "" and str(crew_member.get("job", "")) != required_job:
		return false
	return NPC_ROLE_CATALOG_SCRIPT.can_do_task_type(crew_member, "transport")


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
			_apply_progression_event_effects(event)
			progression_event_triggered.emit(event)


func _apply_progression_event_effects(event: Dictionary) -> void:
	match str(event.get("type", "")):
		"market_unlock":
			unlock_trade_good(str(event.get("id", "")))


func _resolve_market_id(market_id: String) -> String:
	return active_market_id if market_id == "" else market_id


func _trade_context() -> Dictionary:
	_ensure_market()
	return {
		"cash": cash,
		"heat": heat,
		"inventory": inventory,
		"storage_inventory": storage_inventory,
		"storage_capacity": storage_capacity,
		"crew_roster": crew_roster,
		"market": market,
		"active_market_id": active_market_id,
	}


func _base_production_context() -> Dictionary:
	_ensure_market()
	var unit_weights: Dictionary = {}
	var good_names: Dictionary = {}
	for value in market.goods.keys():
		var good_id := str(value)
		unit_weights[good_id] = trade_state.get_unit_weight_kg(good_id)
		good_names[good_id] = trade_state.get_good_name(_trade_context(), good_id)
	return {
		"inventory": inventory,
		"storage_inventory": storage_inventory,
		"storage_capacity": storage_capacity,
		"facilities": base_facilities,
		"ready_production_workers": get_ready_crew_count("production"),
		"unit_weights": unit_weights,
		"good_names": good_names,
	}


func _complete_trade_action(context: Dictionary, action_result: Dictionary, upgrade_scope: bool = false) -> Dictionary:
	cash = int(context.get("cash", cash))
	heat = int(context.get("heat", heat))
	var result := action_result.duplicate(true)
	var progression_events: Array = result.get("progression_events", [])
	result.erase("progression_events")
	for event in progression_events:
		if event is Dictionary:
			record_progression_event(str(event.get("type", "")), event.get("payload", {}))
	if bool(result.get("ok", false)):
		if upgrade_scope:
			_maybe_upgrade_scope()
		state_changed.emit()
	return result


func _result(ok: bool, message: String) -> Dictionary:
	return {
		"ok": ok,
		"message": message,
	}
