extends Node2D

const PLAYER_SCENE := preload("res://scenes/player/Player.tscn")
const CONTACT_SCENE := preload("res://scenes/market/MarketContact.tscn")
const NPC_SCENE := preload("res://scenes/npc/BasicNpc.tscn")
const MAP_LOADER_SCRIPT := preload("res://scripts/map_loader.gd")
const NAVIGATION_MOVER_SCRIPT := preload("res://scripts/navigation_mover.gd")
const PHONE_UI_SCRIPT := preload("res://scripts/phone_ui.gd")
const GAME_STATE_SCRIPT := preload("res://scripts/autoload/game_state.gd")
const UI_TOKENS := preload("res://scripts/ui/ui_tokens.gd")
const UI_THEME := preload("res://scripts/ui/ui_theme.gd")
const UI := preload("res://scripts/ui/ui_factory.gd")
const HOME_MAP_PATH := "res://maps/starter_house.json"
const DEFAULT_MAP_PATH := HOME_MAP_PATH
const RUNNER_TRAVEL_SPEED := 120.0
const RUNNER_AWAY_SECONDS := 4.0
const SENT_RAID_FALLBACK_SECONDS := 3.0
const RAID_DEPARTURE_SPEED := 125.0
const CREW_ARRIVAL_SPEED := 105.0
const ENEMY_THUG_NAMES := ["Rook", "Mack", "Vince", "Doyle", "Kane", "Rafe"]

var player: CharacterBody2D
var active_contact: Area2D
var map_loader
var phone_ui
var game_state
var hud_label: Label
var clock_label: Label
var ammo_label: Label
var reload_button: Button
var prompt_label: Label
var status_label: Label
var scope_label: Label
var progression_dialog: AcceptDialog
var spawned_npcs: Array = []
var spawned_contacts: Array = []
var active_runner_jobs: Dictionary = {}
var active_crew_arrivals: Dictionary = {}
var active_raid_departure: Dictionary = {}
var active_raid_departures: Dictionary = {}
var active_sent_raid_seconds := 0.0
var active_map_path := ""
var home_map_path := HOME_MAP_PATH
var next_enemy_attack_id := 1
var starter_thug_attack_triggered := false

func _ready() -> void:
	game_state = _resolve_game_state()
	_ensure_input_map()
	_load_gameplay_map(DEFAULT_MAP_PATH)
	_build_hud()
	_build_phone()
	game_state.state_changed.connect(_on_game_state_changed)
	game_state.crew_hired.connect(_on_crew_hired)
	game_state.progression_event_triggered.connect(_on_progression_event_triggered)
	_refresh_hud()
	_set_status("%s is yours. Open the phone to manage the base or plan a raid." % game_state.get_base_summary().get("name", map_loader.get_title()))


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("phone"):
		phone_ui.toggle()
		get_viewport().set_input_as_handled()
		return


func _unhandled_input(event: InputEvent) -> void:
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
	var time_result: Dictionary = game_state.advance_game_time(delta)
	if bool(time_result.get("clock_changed", false)):
		_refresh_hud()
	if map_loader != null and player != null:
		map_loader.set_player_position(player.position)
		_refresh_occluded_actor_visibility()
	_update_raid_departures(delta)
	_update_sent_raid(delta)
	_update_crew_arrivals(delta)
	_update_runner_jobs(delta)
	_refresh_ammo_hud()


func _resolve_game_state():
	var state = get_node_or_null("/root/GameState")
	if state != null:
		return state
	state = GAME_STATE_SCRIPT.new()
	state.name = "GameState"
	get_tree().root.add_child(state)
	return state


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
		game_state.initialize_base_from_map(map_loader.get_map_data())
	_spawn_player()
	_spawn_npcs()
	if _is_home_map():
		_sync_home_crew_visuals()
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
	active_crew_arrivals.clear()
	active_raid_departures.clear()
	active_raid_departure.clear()

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
	var player_health: Dictionary = game_state.get_player_health()
	if player.has_method("set_health_values"):
		player.set_health_values(int(player_health.get("health", 100)), int(player_health.get("max_health", 100)))
	player.health_changed.connect(_on_player_health_changed)

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
	if npc.has_signal("health_changed"):
		npc.health_changed.connect(_on_npc_health_changed)
	npc.died.connect(_on_npc_died)
	_configure_npc_navigation(npc)
	_configure_player_crew_follow(npc)
	return npc


func _spawn_home_crew_member(crew_member: Dictionary, position: Vector2):
	return _spawn_npc_from_data(_crew_member_to_npc_data(crew_member, position), position)


func _crew_member_to_npc_data(crew_member: Dictionary, position: Vector2) -> Dictionary:
	var crew_id := str(crew_member.get("id", ""))
	var npc_data := {
		"id": crew_id,
		"crew_id": crew_id,
		"name": str(crew_member.get("name", "Crew")),
		"role": "crew",
		"faction": "player_crew",
		"visual_id": str(crew_member.get("visual_id", "crew_jacket")),
		"position": [position.x, position.y],
		"health": int(crew_member.get("health", 60)),
		"max_health": int(crew_member.get("max_health", crew_member.get("health", 60))),
		"color": crew_member.get("color", [0.28, 0.68, 0.62]),
	}
	if crew_member.has("ranged_weapon"):
		npc_data["ranged_weapon"] = bool(crew_member.get("ranged_weapon", true))
	if crew_member.has("weapon"):
		npc_data["weapon"] = crew_member.get("weapon")
	if crew_member.has("melee_weapon"):
		npc_data["melee_weapon"] = crew_member.get("melee_weapon")
	if str(crew_member.get("role", "")) == "muscle":
		npc_data["ai"] = {
			"enabled": true,
			"faction": "player_crew",
			"hostile_factions": ["rival", "law"],
			"role": "assault",
			"detection_radius": 360,
			"attack_range": _get_melee_attack_range(npc_data, 72.0),
			"preferred_range": 52,
			"chase_speed": 165,
			"reaction_time": 0.12,
			"target_memory_seconds": 2.0,
			"squad_id": "home_guard",
		}
	return npc_data


func _spawn_raid_crew() -> void:
	var roster: Array = game_state.get_crew_roster()
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
			"visual_id": str(crew_member.get("visual_id", "crew_jacket")),
			"health": int(crew_member.get("health", 80)),
			"max_health": int(crew_member.get("max_health", crew_member.get("health", 80))),
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
			"melee_weapon": crew_member.get("melee_weapon", _get_bat_weapon(16)),
		}
		if crew_member.has("ranged_weapon"):
			crew_data["ranged_weapon"] = bool(crew_member.get("ranged_weapon", true))
		if crew_member.has("weapon"):
			crew_data["weapon"] = crew_member.get("weapon")
		var offset: Vector2 = offsets[index % offsets.size()]
		_spawn_npc_from_data(crew_data, player.position + offset)


func _build_phone() -> void:
	phone_ui = PHONE_UI_SCRIPT.new()
	add_child(phone_ui)
	phone_ui.setup(map_loader, player)
	phone_ui.phone_visibility_changed.connect(_on_phone_visibility_changed)
	phone_ui.raid_join_requested.connect(_on_raid_join_requested)
	phone_ui.raid_send_requested.connect(_on_raid_send_requested)
	phone_ui.return_home_requested.connect(_on_return_home_requested)
	phone_ui.trade_order_requested.connect(_on_trade_order_requested)


func _build_hud() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)

	clock_label = Label.new()
	clock_label.anchor_left = 1.0
	clock_label.anchor_top = 0.0
	clock_label.anchor_right = 1.0
	clock_label.anchor_bottom = 0.0
	clock_label.offset_left = -180.0
	clock_label.offset_top = 16.0
	clock_label.offset_right = -18.0
	clock_label.offset_bottom = 42.0
	clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	clock_label.add_theme_font_size_override("font_size", 15)
	clock_label.modulate = Color(0.88, 0.93, 0.90, 0.86)
	canvas.add_child(clock_label)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.theme = UI_THEME.create()
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

	reload_button = UI.button("Reload", "Reload equipped weapon")
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
	status_label.modulate = UI_TOKENS.DUST
	layout.add_child(status_label)

	progression_dialog = AcceptDialog.new()
	progression_dialog.title = "New Lead"
	progression_dialog.min_size = Vector2i(420, 0)
	canvas.add_child(progression_dialog)


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
			result = game_state.pay_fixer()
		_:
			result = _place_trade_order("buy")

	_set_status(result["message"])


func _place_trade_order(order_type: String, good_id: String = "", quantity: int = -1) -> Dictionary:
	if not _is_home_map():
		return _result(false, "Transporters can only be sent from home.")
	if good_id == "":
		good_id = str(game_state.GOOD_KEY)
	var result: Dictionary
	if order_type == "sell":
		result = game_state.place_sell_order(quantity, -1, good_id)
	else:
		result = game_state.place_buy_order(quantity, -1, good_id)
	if bool(result.get("ok", false)):
		_start_runner_trips(result.get("trips", []))
	return result


func _refresh_hud() -> void:
	if hud_label == null or scope_label == null:
		return
	if clock_label != null:
		clock_label.text = game_state.get_clock_label()
	var base_summary: Dictionary = game_state.get_base_summary()
	var player_health: Dictionary = game_state.get_player_health()
	hud_label.text = "Base: %s    Cash: $%d    Inventory: %d/%d KG    Heat: %d%%    Crew: %d    HP: %d/%d" % [
		str(base_summary.get("name", "No Base")),
		game_state.cash,
		game_state.get_storage_used(),
		game_state.get_storage_capacity(),
		game_state.heat,
		game_state.get_ready_crew_count(),
		int(player_health.get("health", 100)),
		int(player_health.get("max_health", 100)),
	]
	if _is_home_map():
		scope_label.text = "%s tier. Next base: %s." % [
			str(base_summary.get("tier", "Base")).capitalize(),
			str(base_summary.get("next_base_hint", "Unknown")),
		]
	else:
		var active_raid: Dictionary = game_state.get_active_raid_target()
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


func _on_player_health_changed(current_health: int, max_health: int) -> void:
	game_state.set_player_health(current_health, max_health)
	_refresh_hud()


func _on_npc_health_changed(npc: CharacterBody2D, current_health: int, max_health: int) -> void:
	if npc == null or not npc.has_method("get_faction") or str(npc.get_faction()) != "player_crew":
		return
	var crew_id := str(npc.get_meta("crew_id", npc.get_meta("npc_id", "")))
	if crew_id == "":
		return
	game_state.set_crew_health(crew_id, current_health, max_health)


func _on_npc_died(npc: CharacterBody2D) -> void:
	var faction := ""
	if npc != null and npc.has_method("get_faction"):
		faction = str(npc.get_faction())
	if faction == "player_crew":
		var crew_id := str(npc.get_meta("crew_id", npc.get_meta("npc_id", "")))
		active_runner_jobs.erase(crew_id)
		active_runner_jobs.erase(str(npc.get_meta("npc_id", "")))
		active_raid_departures.erase(crew_id)
		var result: Dictionary = game_state.remove_crew_member(crew_id)
		_set_status(str(result.get("message", "Crew member died.")))
		_refresh_hud()
		_complete_raid_departure_if_ready()
		return
	game_state.record_kill("npc")


func _on_game_state_changed() -> void:
	_refresh_hud()
	_sync_player_health_from_state()
	if _is_home_map():
		call_deferred("_sync_home_crew_visuals")


func _on_crew_hired(crew_member: Dictionary) -> void:
	if not _is_home_map():
		return
	var crew_id := str(crew_member.get("id", ""))
	if crew_id == "" or _find_spawned_npc_by_id(crew_id) != null:
		_maybe_trigger_starter_thug_attack()
		return
	var roster_index := _get_roster_index(crew_id)
	var target := _get_crew_idle_position(crew_member, roster_index)
	var entry_position := _get_crew_entry_position(target)
	_spawn_home_crew_member(crew_member, entry_position)
	active_crew_arrivals[crew_id] = {"target": target}
	_maybe_trigger_starter_thug_attack()


func _on_progression_event_triggered(event: Dictionary) -> void:
	var message: String = str(event.get("message", ""))
	if message != "":
		_set_status(message)
		if str(event.get("type", "")) == "event":
			_show_progression_popup(message)


func _show_progression_popup(message: String) -> void:
	if progression_dialog == null:
		return
	progression_dialog.dialog_text = message
	progression_dialog.popup_centered(Vector2i(460, 180))


func _sync_home_crew_visuals() -> void:
	if not _is_home_map() or map_loader == null:
		return
	var roster: Array = game_state.get_crew_roster()
	var crew_by_id: Dictionary = {}
	for crew_member in roster:
		if crew_member is Dictionary:
			crew_by_id[str(crew_member.get("id", ""))] = crew_member

	for index in range(spawned_npcs.size() - 1, -1, -1):
		var npc = spawned_npcs[index]
		if not is_instance_valid(npc):
			spawned_npcs.remove_at(index)
			continue
		if not npc.has_method("get_faction") or str(npc.get_faction()) != "player_crew":
			continue
		var crew_id := str(npc.get_meta("crew_id", npc.get_meta("npc_id", "")))
		var crew_member: Dictionary = crew_by_id.get(crew_id, {})
		if crew_member.is_empty() or (not _should_show_home_crew(crew_member) and not active_runner_jobs.has(crew_id) and not active_raid_departures.has(crew_id)):
			active_crew_arrivals.erase(crew_id)
			npc.queue_free()
			spawned_npcs.remove_at(index)
			continue
		if npc.has_method("set_health_values"):
			npc.set_health_values(int(crew_member.get("health", 60)), int(crew_member.get("max_health", crew_member.get("health", 60))))

	for roster_index in range(roster.size()):
		var crew_member: Variant = roster[roster_index]
		if not (crew_member is Dictionary):
			continue
		if not _should_show_home_crew(crew_member):
			continue
		var crew_id := str(crew_member.get("id", ""))
		if crew_id == "" or _find_spawned_npc_by_id(crew_id) != null:
			continue
		_spawn_home_crew_member(crew_member, _get_crew_idle_position(crew_member, roster_index))


func _sync_player_health_from_state() -> void:
	if player == null or not player.has_method("set_health_values") or player.get("health") == null:
		return
	var player_health: Dictionary = game_state.get_player_health()
	var health_component = player.get("health")
	var current_health := int(player_health.get("health", 100))
	var max_health := int(player_health.get("max_health", 100))
	if int(health_component.get("current_health")) == current_health and int(health_component.get("max_health")) == max_health:
		return
	player.set_health_values(current_health, max_health)


func _should_show_home_crew(crew_member: Dictionary) -> bool:
	return str(crew_member.get("status", "Ready")) == "Ready"


func _update_crew_arrivals(delta: float) -> void:
	if active_crew_arrivals.is_empty():
		return
	for crew_id in active_crew_arrivals.keys():
		if not active_crew_arrivals.has(crew_id):
			continue
		var npc = _find_spawned_npc_by_id(str(crew_id))
		if npc == null:
			active_crew_arrivals.erase(crew_id)
			continue
		var arrival: Dictionary = active_crew_arrivals[crew_id]
		var target: Vector2 = arrival.get("target", npc.position)
		if NAVIGATION_MOVER_SCRIPT.move_towards(npc, target, CREW_ARRIVAL_SPEED, delta, _get_navigation()):
			active_crew_arrivals.erase(crew_id)


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
	var result: Dictionary = game_state.start_raid(target_id, true)
	if not bool(result.get("ok", false)):
		_set_status(str(result.get("message", "Could not start raid.")))
		return result

	var target: Dictionary = game_state.resolve_raid_target(target_id)
	var path := str(target.get("path", ""))
	if path == "":
		_set_status("Raid target has no map.")
		return _result(false, "Raid target has no map.")
	_load_gameplay_map(path)
	_set_status(str(result.get("message", "")))
	return result


func return_home() -> void:
	if not _is_home_map() and not game_state.get_active_raid_target().is_empty():
		var result: Dictionary = game_state.complete_active_raid(true)
		_set_status(str(result.get("message", "Returned home.")))
	_load_gameplay_map(home_map_path)


func _start_raid_departure(target_id: String, crew_ids: Array) -> void:
	active_raid_departure = {
		"target_id": target_id,
		"crew_ids": crew_ids.duplicate(),
		"departed_ids": [],
	}
	active_raid_departures.clear()
	for value in crew_ids:
		var crew_id := str(value)
		var npc = _find_spawned_npc_by_id(crew_id)
		if npc == null:
			continue
		active_raid_departures[crew_id] = {
			"exit_position": _get_exit_position(npc.position),
		}
	_complete_raid_departure_if_ready()


func _update_raid_departures(delta: float) -> void:
	if active_raid_departures.is_empty():
		return
	for crew_id in active_raid_departures.keys():
		if not active_raid_departures.has(crew_id):
			continue
		var job: Dictionary = active_raid_departures[crew_id]
		var npc = _find_spawned_npc_by_id(str(crew_id))
		if npc == null:
			active_raid_departures.erase(crew_id)
			continue
		var exit_position: Vector2 = job.get("exit_position", npc.position)
		if NAVIGATION_MOVER_SCRIPT.move_towards(npc, exit_position, RAID_DEPARTURE_SPEED, delta, _get_navigation()):
			var departed_ids: Array = active_raid_departure.get("departed_ids", [])
			departed_ids.append(str(crew_id))
			active_raid_departure["departed_ids"] = departed_ids
			active_raid_departures.erase(crew_id)
			_remove_spawned_npc(npc)
	_complete_raid_departure_if_ready()


func _complete_raid_departure_if_ready() -> void:
	if active_raid_departure.is_empty() or not active_raid_departures.is_empty():
		return
	var departed_ids: Array = active_raid_departure.get("departed_ids", [])
	active_raid_departure.clear()
	var result: Dictionary = game_state.begin_sent_raid(departed_ids)
	_set_status(str(result.get("message", "Raid party departed.")))
	if bool(result.get("ok", false)):
		active_sent_raid_seconds = float(result.get("duration_seconds", SENT_RAID_FALLBACK_SECONDS))


func _update_sent_raid(delta: float) -> void:
	if active_sent_raid_seconds <= 0.0:
		return
	active_sent_raid_seconds -= delta
	if active_sent_raid_seconds > 0.0:
		return
	active_sent_raid_seconds = 0.0
	var active_raid: Dictionary = game_state.get_active_raid_target()
	if active_raid.is_empty() or str(active_raid.get("mode", "")) != "sent":
		return
	var result: Dictionary = game_state.complete_active_raid(true)
	_set_status(str(result.get("message", "Raid complete.")))


func trigger_random_enemy_thug_attack(seed: int = -1) -> Dictionary:
	if not _is_home_map():
		return _result(false, "Base attacks can only trigger at home.")
	var rng := RandomNumberGenerator.new()
	if seed >= 0:
		rng.seed = seed
	else:
		rng.randomize()
	var entry_positions := [
		Vector2(0.0, 560.0),
		Vector2(-520.0, 520.0),
		Vector2(520.0, 520.0),
		Vector2(-640.0, -450.0),
		Vector2(640.0, -450.0),
	]
	var entry_position: Vector2 = _get_navigable_position(entry_positions[rng.randi_range(0, entry_positions.size() - 1)])
	var enemy_id := "enemy_thug_attack_%d" % next_enemy_attack_id
	next_enemy_attack_id += 1
	var enemy_data := {
		"id": enemy_id,
		"name": "%s the Thug" % ENEMY_THUG_NAMES[rng.randi_range(0, ENEMY_THUG_NAMES.size() - 1)],
		"role": "thug",
		"faction": "rival",
		"visual_id": "rival_thug",
		"position": [entry_position.x, entry_position.y],
		"health": 70,
		"color": [0.66, 0.24, 0.20],
		"ranged_weapon": false,
		"weapon": null,
		"melee_weapon": _get_bat_weapon(16),
		"ai": {
			"enabled": true,
			"faction": "rival",
			"hostile_factions": ["player", "player_crew"],
			"role": "assault",
			"detection_radius": 620,
			"attack_range": 72,
			"preferred_range": 52,
			"chase_speed": 175,
			"reaction_time": 0.10,
			"target_memory_seconds": 3.0,
			"squad_id": "base_attack_%d" % next_enemy_attack_id,
		},
	}
	var enemy = _spawn_npc_from_data(enemy_data, entry_position)
	_force_npc_target(enemy, _get_base_attack_target())
	_set_status("An enemy thug is coming at the house.")
	return {
		"ok": enemy != null,
		"message": "Enemy thug attack triggered.",
		"enemy_id": enemy_id,
		"enemy": enemy,
	}


func _maybe_trigger_starter_thug_attack() -> void:
	if starter_thug_attack_triggered or not _is_home_map():
		return
	if game_state.get_ready_crew_count("muscle") < 2:
		return
	starter_thug_attack_triggered = true
	call_deferred("trigger_random_enemy_thug_attack")


func _get_base_attack_target() -> Node2D:
	return player


func _force_npc_target(npc: Node, target: Node2D) -> void:
	if npc == null or target == null:
		return
	var combat_ai = npc.get("combat_ai")
	if combat_ai != null and combat_ai.has_method("force_target"):
		combat_ai.force_target(target, 1.0)


func _on_raid_join_requested(target_id: String) -> void:
	join_raid(target_id)
	if phone_ui != null and phone_ui.is_open():
		phone_ui.toggle()


func _on_raid_send_requested(target_id: String, crew_ids: Array) -> void:
	var result: Dictionary = game_state.send_raid(target_id, crew_ids)
	_set_status(str(result.get("message", "Raid order updated.")))
	if bool(result.get("ok", false)):
		active_sent_raid_seconds = 0.0
		_start_raid_departure(target_id, crew_ids)


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


func _configure_npc_navigation(npc: Node) -> void:
	if npc == null:
		return
	var combat_ai = npc.get("combat_ai")
	if combat_ai != null and combat_ai.has_method("set_navigation"):
		combat_ai.set_navigation(_get_navigation())


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
						var pickup_result: Dictionary = game_state.pick_up_sell_order(str(job.get("trip_id", "")))
						if not bool(pickup_result.get("ok", false)):
							_finish_runner_job(str(crew_id), npc)
							_set_status(str(pickup_result.get("message", "Sell order canceled.")))
							_start_runner_trips(game_state.dispatch_queued_trade_trips())
							continue
						job["phase"] = "to_exit"
						_set_status(str(pickup_result.get("message", "")))
					else:
						var deposit_result: Dictionary = game_state.deposit_buy_order(str(job.get("trip_id", "")))
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
					var retry_result: Dictionary = game_state.deposit_buy_order(str(job.get("trip_id", "")))
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
					var sell_result: Dictionary = game_state.complete_sell_order(str(job.get("trip_id", "")))
					_finish_runner_job(str(crew_id), npc)
					_set_status(str(sell_result.get("message", "")))
					_start_runner_trips(sell_result.get("trips", []))
					continue
		game_state.update_trade_trip_progress(str(job.get("trip_id", "")), str(job.get("phase", "")), _estimate_runner_job_eta(job, npc))
		active_runner_jobs[crew_id] = job


func _move_runner_towards(npc: CharacterBody2D, target: Vector2, delta: float) -> bool:
	return NAVIGATION_MOVER_SCRIPT.move_towards(npc, target, RUNNER_TRAVEL_SPEED, delta, _get_navigation())


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
	return _estimate_navigation_distance(from_position, to_position) / RUNNER_TRAVEL_SPEED


func _finish_runner_job(crew_id: String, npc: CharacterBody2D) -> void:
	active_runner_jobs.erase(crew_id)
	if npc != null:
		npc.velocity = Vector2.ZERO
		npc.visible = true


func _find_spawned_npc_by_id(npc_id: String):
	for npc in spawned_npcs:
		if not is_instance_valid(npc):
			continue
		if str(npc.get_meta("npc_id", "")) == npc_id or str(npc.get_meta("crew_id", "")) == npc_id:
			return npc
	return null


func _remove_spawned_npc(npc: Node) -> void:
	if npc == null:
		return
	for index in range(spawned_npcs.size() - 1, -1, -1):
		if spawned_npcs[index] == npc:
			spawned_npcs.remove_at(index)
			break
	if is_instance_valid(npc):
		npc.queue_free()


func _get_roster_index(crew_id: String) -> int:
	var roster: Array = game_state.get_crew_roster()
	for index in range(roster.size()):
		var crew_member: Variant = roster[index]
		if crew_member is Dictionary and str(crew_member.get("id", "")) == crew_id:
			return index
	return max(0, roster.size() - 1)


func _get_crew_idle_position(crew_member: Dictionary, roster_index: int) -> Vector2:
	var home_position := _read_vector2(crew_member.get("home_position", []))
	if home_position != Vector2.ZERO:
		return _get_navigable_position(home_position)

	var transporter_positions: Array[Vector2] = [
		Vector2(-252.0, -108.0),
		Vector2(-382.0, -108.0),
		Vector2(-312.0, 104.0),
		Vector2(206.0, 104.0),
		Vector2(338.0, 244.0),
	]
	var muscle_positions: Array[Vector2] = [
		Vector2(-186.0, -244.0),
		Vector2(-186.0, -132.0),
		Vector2(420.0, 128.0),
	]
	var production_positions: Array[Vector2] = [
		Vector2(270.0, -160.0),
		Vector2(170.0, -238.0),
	]
	var positions: Array[Vector2] = transporter_positions
	match str(crew_member.get("role", "")):
		"muscle":
			positions = muscle_positions
		"production":
			positions = production_positions
	var index: int = max(0, roster_index) % positions.size()
	return _get_navigable_position(positions[index])


func _get_crew_entry_position(target: Vector2) -> Vector2:
	var preferred_entry := Vector2(0.0, 672.0)
	if map_loader == null:
		return preferred_entry
	return _get_navigable_position(preferred_entry)


func _get_navigable_position(position: Vector2) -> Vector2:
	var navigation = _get_navigation()
	if navigation != null and navigation.has_method("find_nearest_walkable"):
		return navigation.find_nearest_walkable(position)
	return position


func _get_bat_weapon(damage: int = 18) -> Dictionary:
	return {
		"name": "Baseball Bat",
		"weapon_type": "bat",
		"damage": damage,
		"range": 72,
		"arc_degrees": 95,
		"swing_cooldown": 0.6,
		"swing_duration": 0.16,
		"knockback": 90,
	}


func _get_melee_attack_range(npc_data: Dictionary, fallback: float) -> float:
	var melee_data: Variant = npc_data.get("melee_weapon", {})
	if melee_data is Dictionary:
		return float(melee_data.get("range", fallback))
	return fallback


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


func _get_navigation():
	if map_loader != null and map_loader.has_method("get_navigation"):
		return map_loader.get_navigation()
	return null


func _estimate_navigation_distance(from_position: Vector2, to_position: Vector2) -> float:
	var navigation = _get_navigation()
	if navigation == null or not navigation.has_method("find_path"):
		return from_position.distance_to(to_position)
	var path: PackedVector2Array = navigation.find_path(from_position, to_position)
	if path.is_empty():
		return from_position.distance_to(to_position)
	var distance := 0.0
	var cursor := from_position
	for waypoint in path:
		distance += cursor.distance_to(waypoint)
		cursor = waypoint
	return distance


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
