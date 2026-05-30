extends Node2D

const PLAYER_SCENE := preload("res://scenes/player/Player.tscn")
const CONTACT_SCENE := preload("res://scenes/market/MarketContact.tscn")
const NPC_SCENE := preload("res://scenes/npc/BasicNpc.tscn")
const MAP_LOADER_SCRIPT := preload("res://scripts/map_loader.gd")
const PHONE_UI_SCRIPT := preload("res://scripts/phone_ui.gd")
const DEFAULT_MAP_PATH := "res://maps/neighborhood_basic.json"

var player: CharacterBody2D
var active_contact: Area2D
var map_loader
var phone_ui
var hud_label: Label
var prompt_label: Label
var status_label: Label
var scope_label: Label

func _ready() -> void:
	_ensure_input_map()
	_load_map(DEFAULT_MAP_PATH)
	_spawn_player()
	_spawn_npcs()
	_spawn_contacts()
	_build_hud()
	_build_phone()
	GameState.state_changed.connect(_refresh_hud)
	GameState.progression_event_triggered.connect(_on_progression_event_triggered)
	_refresh_hud()
	_set_status("Find a contact in %s. Build the first neighborhood route." % map_loader.get_title())


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


func _load_map(path: String) -> void:
	map_loader = MAP_LOADER_SCRIPT.new()
	add_child(map_loader)
	map_loader.load_map(path)


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
		contact.contacted.connect(_on_contacted)
		contact.player_presence_changed.connect(_on_contact_presence_changed)


func _spawn_npcs() -> void:
	for data in map_loader.get_npcs():
		var npc = NPC_SCENE.instantiate()
		npc.position = _read_vector2(data.get("position", [0.0, 0.0]))
		npc.setup(data)
		add_child(npc)
		npc.died.connect(_on_npc_died)


func _build_phone() -> void:
	phone_ui = PHONE_UI_SCRIPT.new()
	add_child(phone_ui)
	phone_ui.setup(map_loader, player)
	phone_ui.phone_visibility_changed.connect(_on_phone_visibility_changed)


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
			result = GameState.sell_to_buyer()
		"fixer":
			result = GameState.pay_fixer()
		_:
			result = GameState.buy_from_supplier()

	_set_status(result["message"])


func _refresh_hud() -> void:
	hud_label.text = "Cash: $%d    Stock: %d %s    Buy: $%d    Sell: $%d    Heat: %d%%    Scope: %s" % [
		GameState.cash,
		GameState.get_stock(),
		GameState.product_name,
		GameState.get_current_buy_price(),
		GameState.get_current_sell_price(),
		GameState.heat,
		GameState.get_scope_label(),
	]
	scope_label.text = GameState.get_scope_description()
	_refresh_prompt()


func _refresh_prompt() -> void:
	if prompt_label == null:
		return

	if active_contact == null:
		prompt_label.text = "Move: WASD / Arrows    Mouse Aim    Space Fire    Tab Phone"
	else:
		prompt_label.text = "%s: E %s    B Buy    X Sell    F Fixer    Mouse Aim    Space Fire    Tab Phone" % [
			active_contact.contact_name,
			active_contact.get_action_label(),
		]


func _set_status(message: String) -> void:
	if status_label != null:
		status_label.text = message


func _on_npc_died(_npc: CharacterBody2D) -> void:
	GameState.record_kill("npc")


func _on_progression_event_triggered(event: Dictionary) -> void:
	var message: String = str(event.get("message", ""))
	if message != "":
		_set_status(message)


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


func _read_color(value: Variant, fallback: Color) -> Color:
	if value is Array and value.size() >= 3:
		var alpha: float = float(value[3]) if value.size() >= 4 else 1.0
		return Color(float(value[0]), float(value[1]), float(value[2]), alpha)
	return fallback


func _on_phone_visibility_changed(is_open: bool) -> void:
	if player != null:
		player.set("controls_enabled", not is_open)
