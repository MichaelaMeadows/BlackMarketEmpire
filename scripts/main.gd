extends Node2D

const PLAYER_SCENE := preload("res://scenes/player/Player.tscn")
const CONTACT_SCENE := preload("res://scenes/market/MarketContact.tscn")
const NPC_SCENE := preload("res://scenes/npc/BasicNpc.tscn")
const MAP_LOADER_SCRIPT := preload("res://scripts/map_loader.gd")
const PHONE_UI_SCRIPT := preload("res://scripts/phone_ui.gd")
const HOME_MAP_PATH := "res://maps/starter_house.json"
const DEFAULT_MAP_PATH := HOME_MAP_PATH
const RUNNER_TRAVEL_SPEED := 120.0
const RUNNER_AWAY_SECONDS := 4.0

var player: CharacterBody2D
var active_contact: Area2D
var map_loader
var phone_ui
var hud_label: Label
var ammo_label: Label
var reload_button: Button
var prompt_label: Label
var status_label: Label
var scope_label: Label
var spawned_npcs: Array = []
var spawned_contacts: Array = []
var active_runner_jobs: Dictionary = {}
var active_map_path := ""
var home_map_path := HOME_MAP_PATH

func _ready() -> void:
	_ensure_input_map()
	_load_gameplay_map(DEFAULT_MAP_PATH)
	_build_hud()
	_build_phone()
	GameState.state_changed.connect(_refresh_hud)
	GameState.progression_event_triggered.connect(_on_progression_event_triggered)
	_refresh_hud()
	_set_status("%s is yours. Open the phone to manage the base or plan a raid." % GameState.get_base_summary().get("name", map_loader.get_title()))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("phone"):
		phone_ui.toggle()
		get_viewport().set_input_as_handled()
		return

	if phone_ui != null and phone_ui.is_open():
		return

	if active_contact == null:
		return

	if event.is_action_pressed("trade_buy"):
		_try_contact_action("supplier")
	elif event.is_action_pressed("trade_sell"):
		_try_contact_action("buyer")
	elif event.is_action_pressed("reduce_heat"):
		_try_contact_action("fixer")


func _process(delta: float) -> void:
	if map_loader != null and player != null:
		map_loader.set_player_position(player.position)
		_refresh_occluded_actor_visibility()
	_update_runner_jobs(delta)
	_refresh_ammo_hud()


func _load_map(path: String) -> void:
	map_loader = MAP_LOADER_SCRIPT.new()
	add_child(map_loader)
	map_loader.load_map(path)


func _load_gameplay_map(path: String) -> void:
	_clear_gameplay_map()
	active_map_path = path
	_load_map(path)
	if map_loader.get_base_data().has("id"):
		home_map_path = path
		GameState.initialize_base_from_map(map_loader.get_map_data())
	_spawn_player()
	_spawn_npcs()
	if not _is_home_map():
		_spawn_raid_crew()
	_spawn_contacts()
	if phone_ui != null:
		phone_ui.setup(map_loader, player)
	_refresh_hud()


func _clear_gameplay_map() -> void:
	active_contact = null
	for contact in spawned_contacts:
		if is_instance_valid(contact):
			contact.queue_free()
	spawned_contacts.clear()

	for npc in spawned_npcs:
		if is_instance_valid(npc):
			npc.queue_free()
	spawned_npcs.clear()
	active_runner_jobs.clear()

	if player != null and is_instance_valid(player):
		player.queue_free()
	player = null

	if map_loader != null and is_instance_valid(map_loader):
		map_loader.queue_free()
	map_loader = null


func _spawn_player() -> void:
	player = PLAYER_SCENE.instantiate()
	player.position = map_loader.get_player_start()
	add_child(player)

	var camera := Camera2D.new()
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 8.0
	player.add_child(camera)
	camera.make_current()


func _spawn_contacts() -> void:
	for data in map_loader.get_contacts():
		var contact: Area2D = CONTACT_SCENE.instantiate()
		contact.position = _read_vector2(data.get("position", [0.0, 0.0]))
		contact.set_contact_data(
			str(data.get("name", "Contact")),
			str(data.get("type", "supplier")),
			_read_color(data.get("color", []), Color(0.93, 0.72, 0.25))
		)
		add_child(contact)
		spawned_contacts.append(contact)
		contact.contacted.connect(_on_contacted)
		contact.player_presence_changed.connect(_on_contact_presence_changed)


func _spawn_npcs() -> void:
	for data in map_loader.get_npcs():
		_spawn_npc_from_data(data)


func _spawn_npc_from_data(data: Dictionary, position_override: Variant = null):
	var npc = NPC_SCENE.instantiate()
	npc.position = _read_vector2(data.get("position", [0.0, 0.0])) if position_override == null else position_override
	npc.setup(data)
	npc.set_meta("npc_id", str(data.get("id", "")))
	npc.set_meta("crew_id", str(data.get("crew_id", data.get("id", ""))))
	add_child(npc)
	spawned_npcs.append(npc)
	npc.died.connect(_on_npc_died)
	_configure_player_crew_follow(npc)
	return npc


func _spawn_raid_crew() -> void:
	var roster: Array = GameState.get_crew_roster()
	var offsets := [
		Vector2(-58.0, 36.0),
		Vector2(-92.0, 78.0),
		Vector2(-126.0, 26.0),
	]
	for index in range(roster.size()):
		var crew_member: Dictionary = roster[index]
		var crew_data := {
			"id": "raid_%s" % str(crew_member.get("id", index)),
			"crew_id": str(crew_member.get("id", index)),
			"name": str(crew_member.get("name", "Crew")),
			"role": "crew",
			"faction": "player_crew",
			"visual_id": "crew_jacket",
			"health": int(crew_member.get("health", 80)),
			"color": crew_member.get("color", [0.28, 0.68, 0.62]),
			"ai": {
				"enabled": true,
				"faction": "player_crew",
				"hostile_factions": ["rival", "law"],
				"role": "assault",
				"detection_radius": 340,
				"follow_speed": 175,
				"desired_follow_distance": 88,
				"combat_follow_leash": 260,
				"reaction_time": 0.25,
				"target_memory_seconds": 1.8,
				"squad_id": "player_raid",
			},
			"melee_weapon": {
				"name": "Short Bat",
				"weapon_type": "bat",
				"damage": 16,
				"range": 68,
				"arc_degrees": 90,
				"swing_cooldown": 0.7,
				"swing_duration": 0.16,
				"knockback": 90,
			},
		}
		var offset: Vector2 = offsets[index % offsets.size()]
		_spawn_npc_from_data(crew_data, player.position + offset)


func _build_phone() -> void:
	phone_ui = PHONE_UI_SCRIPT.new()
	add_child(phone_ui)
	phone_ui.setup(map_loader, player)
	phone_ui.phone_visibility_changed.connect(_on_phone_visibility_changed)
	phone_ui.raid_join_requested.connect(_on_raid_join_requested)
	phone_ui.return_home_requested.connect(_on_return_home_requested)
	phone_ui.trade_order_requested.connect(_on_trade_order_requested)


func _build_hud() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	canvas.add_child(margin)

	var layout := VBoxContainer.new()
	layout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(layout)

	hud_label = Label.new()
	hud_label.add_theme_font_size_override("font_size", 18)
	layout.add_child(hud_label)

	scope_label = Label.new()
	scope_label.add_theme_font_size_override("font_size", 15)
	scope_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(scope_label)

	var combat_row := HBoxContainer.new()
	combat_row.add_theme_constant_override("separation", 10)
	layout.add_child(combat_row)

	ammo_label = Label.new()
	ammo_label.add_theme_font_size_override("font_size", 16)
	combat_row.add_child(ammo_label)

	reload_button = Button.new()
	reload_button.text = "Reload"
	reload_button.focus_mode = Control.FOCUS_NONE
	reload_button.pressed.connect(_on_reload_pressed)
	combat_row.add_child(reload_button)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(spacer)

	prompt_label = Label.new()
	prompt_label.add_theme_font_size_override("font_size", 18)
	layout.add_child(prompt_label)

	status_label = Label.new()
	status_label.add_theme_font_size_override("font_size", 16)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(status_label)


func _on_contact_presence_changed(contact: Area2D, is_near: bool) -> void:
	if is_near:
		active_contact = contact
	else:
		if active_contact == contact:
			active_contact = null
	_refresh_prompt()


func _on_contacted(contact: Area2D) -> void:
	active_contact = contact
	_try_contact_action(contact.contact_type)


func _try_contact_action(required_type: String) -> void:
	if active_contact == null:
		return
	if active_contact.contact_type != required_type:
		_set_status("%s does not handle that." % active_contact.contact_name)
		return

	var result: Dictionary
	match active_contact.contact_type:
		"buyer":
			result = _place_trade_order("sell")
		"fixer":
			result = GameState.pay_fixer()
		_:
			result = _place_trade_order("buy")

	_set_status(result["message"])


func _place_trade_order(order_type: String, good_id: String = GameState.GOOD_KEY, quantity: int = -1) -> Dictionary:
	if not _is_home_map():
		return _result(false, "Trade runners can only be sent from home.")
	var result: Dictionary
	if order_type == "sell":
		result = GameState.place_sell_order(quantity, -1, good_id)
	else:
		result = GameState.place_buy_order(quantity, -1, good_id)
	if bool(result.get("ok", false)):
		_start_runner_trips(result.get("trips", []))
	return result


func _refresh_hud() -> void:
	if hud_label == null or scope_label == null:
		return
	var base_summary: Dictionary = GameState.get_base_summary()
	hud_label.text = "Base: %s    Cash: $%d    Inventory: %d/%d KG    Heat: %d%%    Crew: %d" % [
		str(base_summary.get("name", "No Base")),
		GameState.cash,
		GameState.get_storage_used(),
		GameState.get_storage_capacity(),
		GameState.heat,
		GameState.get_ready_crew_count(),
	]
	if _is_home_map():
		scope_label.text = "%s tier. Next base: %s." % [
			str(base_summary.get("tier", "Base")).capitalize(),
			str(base_summary.get("next_base_hint", "Unknown")),
		]
	else:
		var active_raid: Dictionary = GameState.get_active_raid_target()
		scope_label.text = "Raid: %s. Use the phone's Raids app to return home." % str(active_raid.get("name", map_loader.get_title()))
	_refresh_prompt()


func _refresh_prompt() -> void:
	if prompt_label == null:
		return

	if active_contact == null:
		prompt_label.text = "Move: WASD / Arrows    Mouse Aim    Space Fire    Q Melee    R Reload    Tab Phone"
	else:
		prompt_label.text = "%s: E %s    B Buy    X Sell    F Fixer    Mouse Aim    Space Fire    Q Melee    R Reload    Tab Phone" % [
			active_contact.contact_name,
			active_contact.get_action_label(),
		]


func _set_status(message: String) -> void:
	if status_label != null:
		status_label.text = message


func _on_npc_died(npc: CharacterBody2D) -> void:
	var faction := ""
	if npc != null and npc.has_method("get_faction"):
		faction = str(npc.get_faction())
	if faction == "player_crew":
		var crew_id := str(npc.get_meta("crew_id", npc.get_meta("npc_id", "")))
		active_runner_jobs.erase(crew_id)
		active_runner_jobs.erase(str(npc.get_meta("npc_id", "")))
		var result: Dictionary = GameState.remove_crew_member(crew_id)
		_set_status(str(result.get("message", "Crew member died.")))
		_refresh_hud()
		return
	GameState.record_kill("npc")


func _on_progression_event_triggered(event: Dictionary) -> void:
	var message: String = str(event.get("message", ""))
	if message != "":
		_set_status(message)


func _refresh_occluded_actor_visibility() -> void:
	for index in range(spawned_npcs.size() - 1, -1, -1):
		var npc = spawned_npcs[index]
		if not is_instance_valid(npc):
			spawned_npcs.remove_at(index)
			continue
		if active_runner_jobs.has(str(npc.get_meta("npc_id", ""))) and not bool(active_runner_jobs[str(npc.get_meta("npc_id", ""))].get("visible", true)):
			npc.visible = false
			continue
		npc.visible = map_loader.is_position_visible(npc.position)

	for index in range(spawned_contacts.size() - 1, -1, -1):
		var contact = spawned_contacts[index]
		if not is_instance_valid(contact):
			spawned_contacts.remove_at(index)
			continue
		contact.visible = map_loader.is_position_visible(contact.position)


func join_raid(target_id: String) -> Dictionary:
	var result: Dictionary = GameState.start_raid(target_id, true)
	if not bool(result.get("ok", false)):
		_set_status(str(result.get("message", "Could not start raid.")))
		return result

	var target: Dictionary = GameState.resolve_raid_target(target_id)
	var path := str(target.get("path", ""))
	if path == "":
		_set_status("Raid target has no map.")
		return _result(false, "Raid target has no map.")
	_load_gameplay_map(path)
	_set_status(str(result.get("message", "")))
	return result


func return_home() -> void:
	if not _is_home_map() and not GameState.get_active_raid_target().is_empty():
		var result: Dictionary = GameState.complete_active_raid(true)
		_set_status(str(result.get("message", "Returned home.")))
	_load_gameplay_map(home_map_path)


func _on_raid_join_requested(target_id: String) -> void:
	join_raid(target_id)
	if phone_ui != null and phone_ui.is_open():
		phone_ui.toggle()


func _on_return_home_requested() -> void:
	return_home()
	if phone_ui != null and phone_ui.is_open():
		phone_ui.toggle()


func _on_trade_order_requested(order_type: String, good_id: String, quantity: int) -> void:
	var result: Dictionary = _place_trade_order(order_type, good_id, quantity)
	_set_status(str(result.get("message", "Order updated.")))


func _configure_player_crew_follow(npc: Node) -> void:
	if player == null or npc == null:
		return
	if not npc.has_method("get_faction") or str(npc.get_faction()) != "player_crew":
		return
	var combat_ai = npc.get("combat_ai")
	if combat_ai != null and combat_ai.has_method("set_follow_target"):
		combat_ai.set_follow_target(player, 88.0, 260.0)


func _start_runner_trips(trips: Array) -> void:
	for trip in trips:
		if trip is Dictionary:
			_start_runner_job(trip)


func _start_runner_job(trip: Dictionary) -> void:
	if trip.is_empty() or not _is_home_map():
		return
	var crew_id := str(trip.get("crew_id", ""))
	var npc = _find_spawned_npc_by_id(crew_id)
	if npc == null:
		return

	var storage_position := _get_storage_position()
	var exit_position := _get_exit_position(npc.position)
	var idle_position: Vector2 = npc.position
	active_runner_jobs[crew_id] = {
		"trip_id": str(trip.get("id", "")),
		"type": str(trip.get("type", "")),
		"phase": "to_exit" if str(trip.get("type", "")) == "buy" else "to_storage",
		"storage_position": storage_position,
		"exit_position": exit_position,
		"idle_position": idle_position,
		"away_timer": 0.0,
		"retry_timer": 0.0,
		"visible": true,
	}


func _update_runner_jobs(delta: float) -> void:
	if active_runner_jobs.is_empty():
		return
	for crew_id in active_runner_jobs.keys():
		if not active_runner_jobs.has(crew_id):
			continue
		var job: Dictionary = active_runner_jobs[crew_id]
		var npc = _find_spawned_npc_by_id(str(crew_id))
		if npc == null:
			active_runner_jobs.erase(crew_id)
			continue
		match str(job.get("phase", "")):
			"to_exit":
				if _move_runner_towards(npc, job.get("exit_position", Vector2.ZERO), delta):
					job["phase"] = "away_buy" if str(job.get("type", "")) == "buy" else "away_sell"
					job["away_timer"] = RUNNER_AWAY_SECONDS
					job["visible"] = false
					npc.visible = false
			"away_buy":
				job["away_timer"] = max(0.0, float(job.get("away_timer", 0.0)) - delta)
				if float(job.get("away_timer", 0.0)) <= 0.0:
					npc.position = job.get("exit_position", npc.position)
					npc.visible = true
					job["visible"] = true
					job["phase"] = "to_storage"
			"to_storage":
				if _move_runner_towards(npc, job.get("storage_position", Vector2.ZERO), delta):
					if str(job.get("type", "")) == "sell":
						var pickup_result: Dictionary = GameState.pick_up_sell_order(str(job.get("trip_id", "")))
						if not bool(pickup_result.get("ok", false)):
							_finish_runner_job(str(crew_id), npc)
							_set_status(str(pickup_result.get("message", "Sell order canceled.")))
							_start_runner_trips(GameState.dispatch_queued_trade_trips())
							continue
						job["phase"] = "to_exit"
						_set_status(str(pickup_result.get("message", "")))
					else:
						var deposit_result: Dictionary = GameState.deposit_buy_order(str(job.get("trip_id", "")))
						if bool(deposit_result.get("ok", false)):
							_finish_runner_job(str(crew_id), npc)
							_set_status(str(deposit_result.get("message", "")))
							_start_runner_trips(deposit_result.get("trips", []))
							continue
						job["phase"] = "waiting_storage"
						job["retry_timer"] = 0.75
						_set_status(str(deposit_result.get("message", "")))
			"waiting_storage":
				job["retry_timer"] = max(0.0, float(job.get("retry_timer", 0.0)) - delta)
				if float(job.get("retry_timer", 0.0)) <= 0.0:
					var retry_result: Dictionary = GameState.deposit_buy_order(str(job.get("trip_id", "")))
					if bool(retry_result.get("ok", false)):
						_finish_runner_job(str(crew_id), npc)
						_set_status(str(retry_result.get("message", "")))
						_start_runner_trips(retry_result.get("trips", []))
						continue
					job["retry_timer"] = 1.0
			"away_sell":
				job["away_timer"] = max(0.0, float(job.get("away_timer", 0.0)) - delta)
				if float(job.get("away_timer", 0.0)) <= 0.0:
					npc.position = job.get("exit_position", npc.position)
					npc.visible = true
					job["visible"] = true
					job["phase"] = "return_idle"
			"return_idle":
				if _move_runner_towards(npc, job.get("idle_position", Vector2.ZERO), delta):
					var sell_result: Dictionary = GameState.complete_sell_order(str(job.get("trip_id", "")))
					_finish_runner_job(str(crew_id), npc)
					_set_status(str(sell_result.get("message", "")))
					_start_runner_trips(sell_result.get("trips", []))
					continue
		GameState.update_trade_trip_progress(str(job.get("trip_id", "")), str(job.get("phase", "")), _estimate_runner_job_eta(job, npc))
		active_runner_jobs[crew_id] = job


func _move_runner_towards(npc: CharacterBody2D, target: Vector2, delta: float) -> bool:
	var offset: Vector2 = target - npc.position
	if offset.length() <= 8.0:
		npc.position = target
		npc.velocity = Vector2.ZERO
		return true
	var direction: Vector2 = offset.normalized()
	npc.velocity = direction * RUNNER_TRAVEL_SPEED
	npc.position += npc.velocity * delta
	if npc.has_method("set_facing_direction"):
		npc.set_facing_direction(direction)
	return false


func _estimate_runner_job_eta(job: Dictionary, npc: CharacterBody2D) -> float:
	if npc == null:
		return -1.0
	var phase := str(job.get("phase", ""))
	var order_type := str(job.get("type", ""))
	var storage_position: Vector2 = job.get("storage_position", Vector2.ZERO)
	var exit_position: Vector2 = job.get("exit_position", Vector2.ZERO)
	var idle_position: Vector2 = job.get("idle_position", Vector2.ZERO)
	match phase:
		"to_exit":
			if order_type == "buy":
				return _travel_seconds(npc.position, exit_position) + RUNNER_AWAY_SECONDS + _travel_seconds(exit_position, storage_position)
			return _travel_seconds(npc.position, exit_position) + RUNNER_AWAY_SECONDS + _travel_seconds(exit_position, idle_position)
		"away_buy":
			return float(job.get("away_timer", 0.0)) + _travel_seconds(exit_position, storage_position)
		"to_storage":
			if order_type == "sell":
				return _travel_seconds(npc.position, storage_position) + _travel_seconds(storage_position, exit_position) + RUNNER_AWAY_SECONDS + _travel_seconds(exit_position, idle_position)
			return _travel_seconds(npc.position, storage_position)
		"waiting_storage":
			return -1.0
		"away_sell":
			return float(job.get("away_timer", 0.0)) + _travel_seconds(exit_position, idle_position)
		"return_idle":
			return _travel_seconds(npc.position, idle_position)
	return -1.0


func _travel_seconds(from_position: Vector2, to_position: Vector2) -> float:
	return from_position.distance_to(to_position) / RUNNER_TRAVEL_SPEED


func _finish_runner_job(crew_id: String, npc: CharacterBody2D) -> void:
	active_runner_jobs.erase(crew_id)
	if npc != null:
		npc.velocity = Vector2.ZERO
		npc.visible = true


func _find_spawned_npc_by_id(npc_id: String):
	for npc in spawned_npcs:
		if is_instance_valid(npc) and str(npc.get_meta("npc_id", "")) == npc_id:
			return npc
	return null


func _get_storage_position() -> Vector2:
	if map_loader == null:
		return Vector2.ZERO
	for facility in map_loader.get_facilities():
		if facility is Dictionary and str(facility.get("type", "")) == "storage":
			return _read_vector2(facility.get("position", [0.0, 0.0])) + Vector2(34.0, 34.0)
	return map_loader.get_player_start()


func _get_exit_position(from_position: Vector2) -> Vector2:
	if map_loader == null:
		return from_position
	var bounds: Rect2 = _read_rect(map_loader.get_map_data().get("bounds", [-900.0, -700.0, 1800.0, 1400.0]))
	var candidates := [
		Vector2(bounds.get_center().x, bounds.position.y - 80.0),
		Vector2(bounds.get_center().x, bounds.end.y + 80.0),
		Vector2(bounds.position.x - 80.0, bounds.get_center().y),
		Vector2(bounds.end.x + 80.0, bounds.get_center().y),
	]
	var best: Vector2 = candidates[0]
	var best_distance := INF
	for candidate in candidates:
		var distance := from_position.distance_to(candidate)
		if distance < best_distance:
			best_distance = distance
			best = candidate
	return best


func _is_home_map() -> bool:
	return active_map_path == home_map_path


func _ensure_input_map() -> void:
	_bind_key("move_left", KEY_A)
	_bind_key("move_left", KEY_LEFT)
	_bind_key("move_right", KEY_D)
	_bind_key("move_right", KEY_RIGHT)
	_bind_key("move_up", KEY_W)
	_bind_key("move_up", KEY_UP)
	_bind_key("move_down", KEY_S)
	_bind_key("move_down", KEY_DOWN)
	_bind_key("interact", KEY_E)
	_bind_key("trade_buy", KEY_B)
	_bind_key("trade_sell", KEY_X)
	_bind_key("reduce_heat", KEY_F)
	_bind_key("phone", KEY_TAB)
	_bind_key("fire", KEY_SPACE)
	_bind_key("melee", KEY_Q)
	_bind_key("reload", KEY_R)


func _bind_key(action_name: StringName, physical_keycode: Key) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)

	for event in InputMap.action_get_events(action_name):
		if event is InputEventKey and event.physical_keycode == physical_keycode:
			return

	var input_event := InputEventKey.new()
	input_event.physical_keycode = physical_keycode
	InputMap.action_add_event(action_name, input_event)


func _read_vector2(value: Variant) -> Vector2:
	if value is Array and value.size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	return Vector2.ZERO


func _read_rect(value: Variant) -> Rect2:
	if value is Array and value.size() >= 4:
		return Rect2(float(value[0]), float(value[1]), float(value[2]), float(value[3]))
	return Rect2()


func _read_color(value: Variant, fallback: Color) -> Color:
	if value is Array and value.size() >= 3:
		var alpha: float = float(value[3]) if value.size() >= 4 else 1.0
		return Color(float(value[0]), float(value[1]), float(value[2]), alpha)
	return fallback


func _on_phone_visibility_changed(is_open: bool) -> void:
	if player != null:
		player.set("controls_enabled", not is_open)


func _on_reload_pressed() -> void:
	if player != null and player.has_method("reload_weapon"):
		player.reload_weapon()
	_refresh_ammo_hud()


func _refresh_ammo_hud() -> void:
	if ammo_label == null or reload_button == null:
		return

	var gun = null
	if player != null:
		gun = player.get("gun")
	var has_gun := gun != null
	ammo_label.visible = has_gun
	reload_button.visible = has_gun
	if not has_gun:
		return

	var ammo := int(gun.get("ammo_in_magazine"))
	var magazine_size := int(gun.get("magazine_size"))
	var weapon_name := str(gun.get("weapon_name"))
	var is_reloading := false
	if gun.has_method("is_reloading"):
		is_reloading = gun.is_reloading()
	ammo_label.text = "%s Ammo: %d/%d%s" % [
		weapon_name,
		ammo,
		magazine_size,
		" (Reloading)" if is_reloading else "",
	]
	reload_button.disabled = is_reloading or ammo >= magazine_size


func _result(ok: bool, message: String) -> Dictionary:
	return {
		"ok": ok,
		"message": message,
	}
