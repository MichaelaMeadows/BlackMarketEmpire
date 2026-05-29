extends Node2D

const PLAYER_SCENE := preload("res://scenes/player/Player.tscn")
const CONTACT_SCENE := preload("res://scenes/market/MarketContact.tscn")

var player: PlayerController
var active_contact: MarketContact
var hud_label: Label
var prompt_label: Label
var status_label: Label
var scope_label: Label

func _ready() -> void:
	_ensure_input_map()
	_spawn_player()
	_spawn_contacts()
	_build_hud()
	GameState.state_changed.connect(_refresh_hud)
	_refresh_hud()
	_set_status("Find a contact. Build the first neighborhood route.")


func _unhandled_input(event: InputEvent) -> void:
	if active_contact == null:
		return

	if event.is_action_pressed("trade_buy"):
		_try_contact_action("supplier")
	elif event.is_action_pressed("trade_sell"):
		_try_contact_action("buyer")
	elif event.is_action_pressed("reduce_heat"):
		_try_contact_action("fixer")


func _draw() -> void:
	draw_rect(Rect2(Vector2(-2000.0, -2000.0), Vector2(4000.0, 4000.0)), Color(0.06, 0.07, 0.075))

	for x in range(-1000, 1001, 80):
		draw_line(Vector2(x, -800.0), Vector2(x, 800.0), Color(0.10, 0.11, 0.12), 1.0)
	for y in range(-800, 801, 80):
		draw_line(Vector2(-1000.0, y), Vector2(1000.0, y), Color(0.10, 0.11, 0.12), 1.0)

	var building_color := Color(0.16, 0.18, 0.19)
	var trim_color := Color(0.28, 0.32, 0.33)
	for block in [
		Rect2(-520.0, -260.0, 220.0, 150.0),
		Rect2(240.0, -310.0, 280.0, 190.0),
		Rect2(-160.0, 160.0, 340.0, 170.0),
		Rect2(410.0, 150.0, 180.0, 260.0),
	]:
		draw_rect(block, building_color)
		draw_rect(block, trim_color, false, 3.0)


func _spawn_player() -> void:
	player = PLAYER_SCENE.instantiate()
	player.position = Vector2.ZERO
	add_child(player)

	var camera := Camera2D.new()
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 8.0
	player.add_child(camera)
	camera.make_current()


func _spawn_contacts() -> void:
	var contact_data := [
		{
			"name": "Corner Supplier",
			"type": "supplier",
			"position": Vector2(-280.0, -160.0),
			"color": Color(0.95, 0.68, 0.20),
		},
		{
			"name": "Night Buyer",
			"type": "buyer",
			"position": Vector2(310.0, -80.0),
			"color": Color(0.42, 0.82, 0.48),
		},
		{
			"name": "Quiet Fixer",
			"type": "fixer",
			"position": Vector2(30.0, 260.0),
			"color": Color(0.58, 0.50, 0.92),
		},
	]

	for data in contact_data:
		var contact: MarketContact = CONTACT_SCENE.instantiate()
		contact.position = data["position"]
		contact.set_contact_data(data["name"], data["type"], data["color"])
		add_child(contact)
		contact.contacted.connect(_on_contacted)
		contact.player_presence_changed.connect(_on_contact_presence_changed)


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


func _on_contact_presence_changed(contact: MarketContact, is_near: bool) -> void:
	if is_near:
		active_contact = contact
	else:
		if active_contact == contact:
			active_contact = null
	_refresh_prompt()


func _on_contacted(contact: MarketContact) -> void:
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
	hud_label.text = "Cash: $%d    Stock: %d %s    Heat: %d%%    Scope: %s" % [
		GameState.cash,
		GameState.get_stock(),
		GameState.product_name,
		GameState.heat,
		GameState.get_scope_label(),
	]
	scope_label.text = GameState.get_scope_description()
	_refresh_prompt()


func _refresh_prompt() -> void:
	if prompt_label == null:
		return

	if active_contact == null:
		prompt_label.text = "Move: WASD / Arrows"
	else:
		prompt_label.text = "%s: E %s    B Buy    X Sell    F Fixer" % [
			active_contact.contact_name,
			active_contact.get_action_label(),
		]


func _set_status(message: String) -> void:
	if status_label != null:
		status_label.text = message


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


func _bind_key(action_name: StringName, physical_keycode: Key) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)

	for event in InputMap.action_get_events(action_name):
		if event is InputEventKey and event.physical_keycode == physical_keycode:
			return

	var input_event := InputEventKey.new()
	input_event.physical_keycode = physical_keycode
	InputMap.action_add_event(action_name, input_event)
