extends CanvasLayer

signal phone_visibility_changed(is_open: bool)
signal raid_join_requested(target_id: String)
signal raid_send_requested(target_id: String, crew_ids: Array)
signal return_home_requested
signal trade_order_requested(order_type: String, good_id: String, quantity: int)

const PHONE_MAP_VIEW_SCRIPT := preload("res://scripts/phone_map_view.gd")
const UI_TOKENS := preload("res://scripts/ui/ui_tokens.gd")
const UI_THEME := preload("res://scripts/ui/ui_theme.gd")
const UI := preload("res://scripts/ui/ui_factory.gd")
const VISUAL_ASSETS := preload("res://scripts/ui/visual_asset_catalog.gd")
const PHONE_BG := UI_TOKENS.ASPHALT
const PHONE_PANEL_BG := UI_TOKENS.STEEL
const PHONE_PANEL_BORDER := UI_TOKENS.RULE
const PHONE_TEXT_MUTED := UI_TOKENS.DUST
const APP_ICONS := {
	"base": preload("res://assets/ui/icons/nav_base.png"),
	"crew": preload("res://assets/ui/icons/nav_crew.png"),
	"raids": preload("res://assets/ui/icons/nav_raids.png"),
	"map": preload("res://assets/ui/icons/nav_map.png"),
	"bank": preload("res://assets/ui/icons/nav_bank.png"),
	"market": preload("res://assets/ui/icons/nav_market.png"),
	"orders": preload("res://assets/ui/icons/nav_orders.png"),
	"hire": preload("res://assets/ui/icons/nav_hire.png"),
}

var map_loader
var player
var current_app := "base"
var app_buttons: Dictionary = {}
var phone_root: Control
var title_label: Label
var app_content: VBoxContainer
var map_view
var bank_label: Label
var market_title: Label
var market_list: GridContainer
var market_quantity_inputs: Dictionary = {}
var market_mode := "buy"
var orders_list: GridContainer
var order_details_dialog: AcceptDialog
var orders_refresh_timer := 0.0
var hire_list: GridContainer
var hire_status_label: Label
var hire_message := ""
var hire_role_filter := "all"
var raid_status_label: Label
var selected_raid_target_id := ""
var selected_raid_crew_ids: Dictionary = {}
var game_state

func _ready() -> void:
	visible = false
	game_state = get_node("/root/GameState")
	_build_ui()
	game_state.state_changed.connect(_refresh_bank)
	game_state.state_changed.connect(_refresh_market)
	game_state.state_changed.connect(_refresh_current_base_app)
	set_process(false)


func setup(new_map_loader, new_player) -> void:
	map_loader = new_map_loader
	player = new_player
	if map_view != null and map_loader != null:
		map_view.set_map_data(map_loader.get_map_data())


func toggle() -> void:
	visible = not visible
	set_process(visible)
	if visible:
		_show_app(current_app)
	phone_visibility_changed.emit(visible)


func is_open() -> bool:
	return visible


func _process(delta: float) -> void:
	if visible and current_app == "map" and player != null:
		map_view.set_player_position(player.position)
	if visible and current_app == "orders":
		orders_refresh_timer -= delta
		if orders_refresh_timer <= 0.0:
			_refresh_orders()
			orders_refresh_timer = 0.25


func _build_ui() -> void:
	phone_root = Control.new()
	phone_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	phone_root.theme = UI_THEME.create()
	add_child(phone_root)

	var shade := ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(UI_TOKENS.INK, 0.82)
	phone_root.add_child(shade)

	var phone := PanelContainer.new()
	phone.anchor_left = 0.03
	phone.anchor_top = 0.04
	phone.anchor_right = 0.97
	phone.anchor_bottom = 0.96
	phone.add_theme_stylebox_override("panel", UI_THEME.panel_style(PHONE_BG, UI_TOKENS.RULE, 2, UI_TOKENS.CORNER_MODAL, 0))
	phone_root.add_child(phone)

	var phone_margin := MarginContainer.new()
	phone_margin.add_theme_constant_override("margin_left", 18)
	phone_margin.add_theme_constant_override("margin_top", 16)
	phone_margin.add_theme_constant_override("margin_right", 18)
	phone_margin.add_theme_constant_override("margin_bottom", 16)
	phone.add_child(phone_margin)

	var layout := VBoxContainer.new()
	layout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_theme_constant_override("separation", 12)
	phone_margin.add_child(layout)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	layout.add_child(header)

	title_label = Label.new()
	title_label.text = "Phone"
	title_label.add_theme_font_size_override("font_size", 22)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_label)

	var close_button := UI.button("Tab", "Close phone")
	close_button.pressed.connect(toggle)
	header.add_child(close_button)

	var app_bar := HBoxContainer.new()
	app_bar.add_theme_constant_override("separation", 8)
	layout.add_child(app_bar)

	_add_app_button(app_bar, "Base", "base")
	_add_app_button(app_bar, "Crew", "crew")
	_add_app_button(app_bar, "Raids", "raids")
	_add_app_button(app_bar, "Map", "map")
	_add_app_button(app_bar, "Bank", "bank")
	_add_app_button(app_bar, "Market", "market")
	_add_app_button(app_bar, "Orders", "orders")
	_add_app_button(app_bar, "Hire", "hire")

	app_content = VBoxContainer.new()
	app_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	app_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	app_content.add_theme_constant_override("separation", 10)
	layout.add_child(app_content)

	_build_home_app()


func _add_app_button(parent: HBoxContainer, label: String, app_id: String) -> void:
	var button := UI.button(label, "Open %s" % label)
	button.icon = APP_ICONS.get(app_id)
	button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	button.toggle_mode = true
	button.button_pressed = app_id == current_app
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(_show_app.bind(app_id))
	parent.add_child(button)
	app_buttons[app_id] = button


func _show_app(app_id: String) -> void:
	current_app = app_id
	for button_id in app_buttons:
		var app_button: Button = app_buttons[button_id]
		app_button.set_pressed_no_signal(button_id == app_id)
	if app_id != "raids":
		selected_raid_target_id = ""
		selected_raid_crew_ids.clear()
	bank_label = null
	market_title = null
	market_list = null
	market_quantity_inputs.clear()
	orders_list = null
	orders_refresh_timer = 0.0
	hire_list = null
	hire_status_label = null
	raid_status_label = null
	for child in app_content.get_children():
		child.queue_free()

	match app_id:
		"base":
			_build_base_app()
		"crew":
			_build_crew_app()
		"raids":
			_build_raids_app()
		"map":
			_build_map_app()
		"bank":
			_build_bank_app()
		"market":
			_build_market_app()
		"orders":
			_build_orders_app()
		"hire":
			_build_hire_app()
		_:
			_build_home_app()


func _build_home_app() -> void:
	title_label.text = "Phone"
	var label := Label.new()
	label.text = "Choose an app."
	label.add_theme_font_size_override("font_size", 18)
	app_content.add_child(label)


func _build_messages_app() -> void:
	title_label.text = "Messages"
	var label := Label.new()
	label.text = "No new messages."
	label.add_theme_font_size_override("font_size", 18)
	app_content.add_child(label)


func _build_base_app() -> void:
	title_label.text = "Base"
	var summary: Dictionary = game_state.get_base_summary()
	var role_counts: Dictionary = summary.get("role_counts", {})
	var role_limits: Dictionary = summary.get("role_limits", {})
	_add_info_label("%s\nTier: %s\nCrew: T %d/%d, M %d/%d, P %d/%d\nInventory: %d/%d KG\nWeekly: +$%d benefits, -$%d payroll, net $%d\nNext: %s" % [
		str(summary.get("name", "No Base")),
		str(summary.get("tier", "none")).capitalize(),
		int(role_counts.get("transporter", 0)),
		int(role_limits.get("transporter", 0)),
		int(role_counts.get("muscle", 0)),
		int(role_limits.get("muscle", 0)),
		int(role_counts.get("production", 0)),
		int(role_limits.get("production", 0)),
		int(summary.get("storage_used", 0)),
		int(summary.get("storage_capacity", 0)),
		int(summary.get("weekly_income", 0)),
		int(summary.get("weekly_payroll", 0)),
		int(summary.get("weekly_net", 0)),
		str(summary.get("next_base_hint", "Unknown")),
	], 18)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	app_content.add_child(scroll)

	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)

	for room in game_state.get_base_rooms():
		if not (room is Dictionary):
			continue
		var room_label := Label.new()
		var slot_text := _format_slot_list(room.get("slot_ids", []))
		room_label.text = "%s  |  Slots: %s" % [
			str(room.get("name", room.get("id", "Room"))),
			slot_text,
		]
		room_label.add_theme_font_size_override("font_size", 16)
		list.add_child(room_label)

		for slot_id in room.get("slot_ids", []):
			var facility: Dictionary = game_state.get_owned_facility_for_slot(str(slot_id))
			if facility.is_empty():
				continue
			var facility_label := Label.new()
			facility_label.text = "  %s: %s" % [
				str(facility.get("type", "facility")).capitalize(),
				str(facility.get("name", "Facility")),
			]
			facility_label.modulate = Color(0.78, 0.84, 0.82, 0.78)
			list.add_child(facility_label)


func _build_crew_app() -> void:
	title_label.text = "Crew"
	var roster: Array = game_state.get_crew_roster()
	if roster.is_empty():
		_add_info_label("No crew hired.", 18)
		return

	for crew_member in roster:
		if not (crew_member is Dictionary):
			continue
		_add_info_label("%s\n%s | %s | Health %s | $%d/week\nCan: %s\nTask: %s" % [
			str(crew_member.get("name", "Crew")),
			"%s %s" % [
				str(crew_member.get("archetype_name", crew_member.get("job", "Hireling"))),
				str(crew_member.get("role_name", "Crew")),
			],
			str(crew_member.get("status", "Ready")),
			_format_health(crew_member),
			int(crew_member.get("upkeep", 0)),
			_format_slot_list(crew_member.get("task_types", [])),
			_format_assignment(crew_member),
		], 17)


func _build_hire_app() -> void:
	title_label.text = "Hire"
	var summary: Dictionary = game_state.get_base_summary()
	var role_counts: Dictionary = summary.get("role_counts", {})
	var role_limits: Dictionary = summary.get("role_limits", {})

	var summary_row := HBoxContainer.new()
	summary_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	summary_row.add_theme_constant_override("separation", 10)
	app_content.add_child(summary_row)
	_add_market_stat(summary_row, "Cash", "$%d" % game_state.cash)
	_add_market_stat(summary_row, "Transporters", "%d/%d" % [int(role_counts.get("transporter", 0)), int(role_limits.get("transporter", 0))])
	_add_market_stat(summary_row, "Muscle", "%d/%d" % [int(role_counts.get("muscle", 0)), int(role_limits.get("muscle", 0))])
	_add_market_stat(summary_row, "Production", "%d/%d" % [int(role_counts.get("production", 0)), int(role_limits.get("production", 0))])

	if hire_message != "":
		hire_status_label = _add_info_label(hire_message, 16)
		hire_status_label.modulate = PHONE_TEXT_MUTED

	var filter_row := HBoxContainer.new()
	filter_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	filter_row.add_theme_constant_override("separation", 10)
	app_content.add_child(filter_row)

	var filter_label := Label.new()
	filter_label.text = "Role"
	filter_label.custom_minimum_size = Vector2(54.0, 38.0)
	filter_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	filter_label.add_theme_font_size_override("font_size", 15)
	filter_label.modulate = PHONE_TEXT_MUTED
	filter_row.add_child(filter_label)

	var role_filter := OptionButton.new()
	role_filter.custom_minimum_size = Vector2(190.0, 38.0)
	role_filter.tooltip_text = "Filter hire candidates by role"
	_add_hire_role_filter_option(role_filter, "All Roles", "all")
	_add_hire_role_filter_option(role_filter, "Transporter", "transporter")
	_add_hire_role_filter_option(role_filter, "Muscle", "muscle")
	_add_hire_role_filter_option(role_filter, "Production", "production")
	role_filter.selected = _get_hire_role_filter_index(role_filter, hire_role_filter)
	role_filter.item_selected.connect(_on_hire_role_filter_selected.bind(role_filter))
	filter_row.add_child(role_filter)

	var filter_spacer := Control.new()
	filter_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	filter_row.add_child(filter_spacer)

	var hire_panel := PanelContainer.new()
	hire_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hire_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hire_panel.add_theme_stylebox_override("panel", _make_panel_style(PHONE_PANEL_BG, PHONE_PANEL_BORDER, 1, 0))
	app_content.add_child(hire_panel)

	var panel_margin := MarginContainer.new()
	panel_margin.add_theme_constant_override("margin_left", 14)
	panel_margin.add_theme_constant_override("margin_top", 12)
	panel_margin.add_theme_constant_override("margin_right", 14)
	panel_margin.add_theme_constant_override("margin_bottom", 12)
	hire_panel.add_child(panel_margin)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel_margin.add_child(scroll)

	hire_list = GridContainer.new()
	hire_list.columns = 5
	hire_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hire_list.add_theme_constant_override("h_separation", 12)
	hire_list.add_theme_constant_override("v_separation", 8)
	scroll.add_child(hire_list)
	_refresh_hires()


func _build_raids_app() -> void:
	title_label.text = "Raids"
	var active_raid: Dictionary = game_state.get_active_raid_target()
	if not active_raid.is_empty():
		raid_status_label = Label.new()
		var active_mode := str(active_raid.get("mode", ""))
		if active_mode == "departing":
			raid_status_label.text = "Raid party leaving: %s\nSent: %s" % [
				str(active_raid.get("name", "Raid")),
				", ".join(PackedStringArray(active_raid.get("crew_names", []))),
			]
		elif active_mode == "sent":
			raid_status_label.text = "Raid in progress: %s\nSent: %s" % [
				str(active_raid.get("name", "Raid")),
				", ".join(PackedStringArray(active_raid.get("crew_names", []))),
			]
		else:
			raid_status_label.text = "Active raid: %s" % str(active_raid.get("name", "Raid"))
		raid_status_label.add_theme_font_size_override("font_size", 17)
		raid_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		app_content.add_child(raid_status_label)

		if active_mode != "sent" and active_mode != "departing":
			var return_button := Button.new()
			return_button.text = "Return Home"
			return_button.pressed.connect(func(): return_home_requested.emit())
			app_content.add_child(return_button)
		return

	if selected_raid_target_id != "":
		_build_raid_crew_picker(selected_raid_target_id)
		return

	var targets: Array = game_state.get_raid_targets()
	if targets.is_empty():
		_add_info_label("No raid targets available.", 18)
		return

	var report: Dictionary = game_state.get_last_raid_report()
	if not report.is_empty():
		_add_raid_report_card(report)

	raid_status_label = Label.new()
	raid_status_label.text = "Ready crew: %d" % game_state.get_ready_crew_count()
	raid_status_label.add_theme_font_size_override("font_size", 17)
	app_content.add_child(raid_status_label)

	for target in targets:
		if not (target is Dictionary):
			continue
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_theme_constant_override("separation", 8)
		app_content.add_child(row)

		var target_label := Label.new()
		target_label.text = "%s | Difficulty %d | %s" % [
			str(target.get("name", "Target")),
			int(target.get("difficulty", 1)),
			str(target.get("reward_hint", "")),
		]
		target_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		target_label.add_theme_font_size_override("font_size", 16)
		row.add_child(target_label)

		var send_button := Button.new()
		send_button.text = "Send"
		send_button.pressed.connect(_on_send_raid_pressed.bind(str(target.get("id", ""))))
		row.add_child(send_button)

		var join_button := Button.new()
		join_button.text = "Join"
		join_button.pressed.connect(func(): raid_join_requested.emit(str(target.get("id", ""))))
		row.add_child(join_button)


func _build_raid_crew_picker(target_id: String) -> void:
	var target: Dictionary = game_state.resolve_raid_target(target_id)
	if target.is_empty():
		selected_raid_target_id = ""
		selected_raid_crew_ids.clear()
		_add_info_label("That raid target is no longer available.", 18)
		return

	title_label.text = "Send Crew"
	var crew_required := int(target.get("crew_required", 1))
	raid_status_label = _add_info_label("%s | Difficulty %d | Select %d+ crew" % [
		str(target.get("name", "Target")),
		int(target.get("difficulty", 1)),
		crew_required,
	], 17)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	app_content.add_child(scroll)

	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 8)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	var roster: Array = game_state.get_crew_roster()
	for crew_member in roster:
		if not (crew_member is Dictionary):
			continue
		var crew_id := str(crew_member.get("id", ""))
		if crew_id == "":
			continue
		var is_ready := str(crew_member.get("status", "Ready")) == "Ready"
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		list.add_child(row)

		var check_box := CheckBox.new()
		check_box.button_pressed = bool(selected_raid_crew_ids.get(crew_id, false))
		check_box.disabled = not is_ready
		check_box.toggled.connect(_on_raid_crew_toggled.bind(crew_id))
		row.add_child(check_box)

		var label := Label.new()
		label.text = "%s | %s | %s | Health %s" % [
			str(crew_member.get("name", "Crew")),
			str(crew_member.get("role_name", crew_member.get("role", "Crew"))),
			str(crew_member.get("status", "Ready")),
			_format_health(crew_member),
		]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(label)

	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 8)
	app_content.add_child(action_row)

	var launch_button := Button.new()
	launch_button.text = "Launch Raid"
	launch_button.pressed.connect(_on_confirm_send_raid_pressed.bind(target_id))
	action_row.add_child(launch_button)

	var cancel_button := Button.new()
	cancel_button.text = "Cancel"
	cancel_button.pressed.connect(_on_cancel_send_raid_pressed)
	action_row.add_child(cancel_button)


func _build_map_app() -> void:
	title_label.text = "Map"
	var map_name := Label.new()
	map_name.text = map_loader.get_title() if map_loader != null else "Unknown Map"
	map_name.add_theme_font_size_override("font_size", 17)
	app_content.add_child(map_name)

	map_view = PHONE_MAP_VIEW_SCRIPT.new()
	map_view.custom_minimum_size = Vector2(320.0, 0.0)
	map_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if map_loader != null:
		map_view.set_map_data(map_loader.get_map_data())
	if player != null:
		map_view.set_player_position(player.position)
	app_content.add_child(map_view)


func _build_bank_app() -> void:
	title_label.text = "Bank"
	bank_label = Label.new()
	bank_label.add_theme_font_size_override("font_size", 18)
	app_content.add_child(bank_label)
	_refresh_bank()


func _build_market_app() -> void:
	title_label.text = "Market"
	market_title = Label.new()
	market_title.add_theme_font_size_override("font_size", 21)
	app_content.add_child(market_title)

	var summary_row := HBoxContainer.new()
	summary_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	summary_row.add_theme_constant_override("separation", 10)
	app_content.add_child(summary_row)
	_add_market_stat(summary_row, "Cash", "$%d" % game_state.cash)
	_add_market_stat(summary_row, "Storage", "%d/%d KG" % [game_state.get_storage_used(), game_state.get_storage_capacity()])
	_add_market_stat(summary_row, "Transporters", "%d ready" % game_state.get_ready_crew_count("transporter"))
	_add_market_stat(summary_row, "Active Orders", "%d" % game_state.get_trade_orders().size())
	_add_market_stat(summary_row, "In Flight", "%d" % game_state.get_trade_trips().size())

	var controls_row := HBoxContainer.new()
	controls_row.add_theme_constant_override("separation", 12)
	app_content.add_child(controls_row)

	var mode_row := HBoxContainer.new()
	mode_row.custom_minimum_size = Vector2(260.0, 38.0)
	mode_row.add_theme_constant_override("separation", 0)
	controls_row.add_child(mode_row)

	var buy_screen_button := Button.new()
	buy_screen_button.text = "Buy"
	buy_screen_button.toggle_mode = true
	buy_screen_button.button_pressed = market_mode == "buy"
	buy_screen_button.custom_minimum_size = Vector2(130.0, 38.0)
	buy_screen_button.pressed.connect(_on_market_mode_pressed.bind("buy"))
	mode_row.add_child(buy_screen_button)

	var sell_screen_button := Button.new()
	sell_screen_button.text = "Sell"
	sell_screen_button.toggle_mode = true
	sell_screen_button.button_pressed = market_mode == "sell"
	sell_screen_button.custom_minimum_size = Vector2(130.0, 38.0)
	sell_screen_button.pressed.connect(_on_market_mode_pressed.bind("sell"))
	mode_row.add_child(sell_screen_button)

	var hint := Label.new()
	hint.text = "Legal starter route. Buy from nearby shops, store at base, then sell for a margin."
	hint.modulate = PHONE_TEXT_MUTED
	hint.add_theme_font_size_override("font_size", 14)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls_row.add_child(hint)

	var queue_selected_button := Button.new()
	queue_selected_button.text = "Queue Selected"
	queue_selected_button.custom_minimum_size = Vector2(150.0, 38.0)
	queue_selected_button.pressed.connect(_queue_selected_market_orders)
	controls_row.add_child(queue_selected_button)

	var market_panel := PanelContainer.new()
	market_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	market_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	market_panel.add_theme_stylebox_override("panel", _make_panel_style(PHONE_PANEL_BG, PHONE_PANEL_BORDER, 1, 0))
	app_content.add_child(market_panel)

	var panel_margin := MarginContainer.new()
	panel_margin.add_theme_constant_override("margin_left", 14)
	panel_margin.add_theme_constant_override("margin_top", 12)
	panel_margin.add_theme_constant_override("margin_right", 14)
	panel_margin.add_theme_constant_override("margin_bottom", 12)
	market_panel.add_child(panel_margin)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel_margin.add_child(scroll)

	market_list = GridContainer.new()
	market_list.columns = 9
	market_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	market_list.add_theme_constant_override("h_separation", 12)
	market_list.add_theme_constant_override("v_separation", 8)
	scroll.add_child(market_list)
	_refresh_market()


func _build_orders_app() -> void:
	title_label.text = "Orders"
	var order_rows: Array = game_state.get_trade_order_rows()
	var holding_weight: int = 0
	var queued_count: int = 0
	for row in order_rows:
		if not (row is Dictionary):
			continue
		holding_weight += int(row.get("holding_weight_kg", 0))
		if str(row.get("row_type", "")) == "order":
			queued_count += 1

	var summary_row := HBoxContainer.new()
	summary_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	summary_row.add_theme_constant_override("separation", 10)
	app_content.add_child(summary_row)
	_add_market_stat(summary_row, "Active Orders", "%d" % game_state.get_trade_orders().size())
	_add_market_stat(summary_row, "In Flight", "%d" % game_state.get_trade_trips().size())
	_add_market_stat(summary_row, "Queued", "%d" % queued_count)
	_add_market_stat(summary_row, "Holding", "%d KG" % holding_weight)

	var orders_panel := PanelContainer.new()
	orders_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	orders_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	orders_panel.add_theme_stylebox_override("panel", _make_panel_style(PHONE_PANEL_BG, PHONE_PANEL_BORDER, 1, 0))
	app_content.add_child(orders_panel)

	var panel_margin := MarginContainer.new()
	panel_margin.add_theme_constant_override("margin_left", 14)
	panel_margin.add_theme_constant_override("margin_top", 12)
	panel_margin.add_theme_constant_override("margin_right", 14)
	panel_margin.add_theme_constant_override("margin_bottom", 12)
	orders_panel.add_child(panel_margin)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel_margin.add_child(scroll)

	orders_list = GridContainer.new()
	orders_list.columns = 9
	orders_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	orders_list.add_theme_constant_override("h_separation", 12)
	orders_list.add_theme_constant_override("v_separation", 8)
	scroll.add_child(orders_list)
	_refresh_orders()


func _refresh_bank() -> void:
	if bank_label == null:
		return

	bank_label.text = "Cash: $%d\nHeat: %d%%\nStorage: %d/%d KG\nActive orders: %d\nBenefits: +$%d/week\nPayroll: -$%d/week\nNet: $%d/week\nBuy: $%d\nSell: $%d" % [
		game_state.cash,
		game_state.heat,
		game_state.get_storage_used(),
		game_state.get_storage_capacity(),
		game_state.get_trade_orders().size(),
		game_state.get_weekly_income_total(),
		game_state.get_weekly_payroll_total(),
		game_state.get_weekly_net_income(),
		game_state.get_current_buy_price(),
		game_state.get_current_sell_price(),
	]


func _refresh_market() -> void:
	if market_list == null:
		return
	if market_title != null:
		market_title.text = "%s Orders" % market_mode.capitalize()

	for child in market_list.get_children():
		child.queue_free()
	market_quantity_inputs.clear()

	_add_market_grid_header("Product", 180.0)
	_add_market_grid_header("Legality", 100.0)
	_add_market_grid_header("%s Price" % market_mode.capitalize(), 90.0)
	_add_market_grid_header("Weight", 90.0)
	_add_market_grid_header("Distance", 110.0)
	_add_market_grid_header("Base Stock", 140.0)
	_add_market_grid_header("Remote Source", 160.0)
	_add_market_grid_header("Qty", 90.0)
	_add_market_grid_header("Action", 130.0)

	for item in game_state.get_available_trade_goods():
		_add_trade_row(item)


func _refresh_orders() -> void:
	if orders_list == null:
		return

	for child in orders_list.get_children():
		child.queue_free()

	var order_rows: Array = game_state.get_trade_order_rows()
	if order_rows.is_empty():
		orders_list.columns = 1
		var empty_label := Label.new()
		empty_label.text = "No incoming or outgoing orders."
		empty_label.add_theme_font_size_override("font_size", 17)
		empty_label.modulate = PHONE_TEXT_MUTED
		orders_list.add_child(empty_label)
		return

	orders_list.columns = 9
	_add_order_grid_header("Flow", 90.0)
	_add_order_grid_header("Product", 160.0)
	_add_order_grid_header("Status", 160.0)
	_add_order_grid_header("Qty", 90.0)
	_add_order_grid_header("Holding", 110.0)
	_add_order_grid_header("Transporter", 120.0)
	_add_order_grid_header("ETA", 95.0)
	_add_order_grid_header("Risk", 80.0)
	_add_order_grid_header("Details", 100.0)

	for row in order_rows:
		if row is Dictionary:
			_add_order_row(row)


func _refresh_hires() -> void:
	if hire_list == null:
		return

	for child in hire_list.get_children():
		child.queue_free()

	var hires: Array = _filter_hires_by_role(game_state.get_available_hires())
	if hires.is_empty():
		hire_list.columns = 1
		var empty_label := Label.new()
		empty_label.text = "No one matches that role right now." if hire_role_filter != "all" else "No one is looking for work right now."
		empty_label.add_theme_font_size_override("font_size", 17)
		empty_label.modulate = PHONE_TEXT_MUTED
		hire_list.add_child(empty_label)
		return

	hire_list.columns = 5
	_add_hire_grid_header("Name", 170.0)
	_add_hire_grid_header("Price", 90.0)
	_add_hire_grid_header("Job", 150.0)
	_add_hire_grid_header("Role", 120.0)
	_add_hire_grid_header("Buy", 110.0)

	for candidate in hires:
		if candidate is Dictionary:
			_add_hire_row(candidate)


func _filter_hires_by_role(hires: Array) -> Array:
	if hire_role_filter == "all":
		return hires
	var filtered: Array = []
	for candidate in hires:
		if candidate is Dictionary and str(candidate.get("role", "")) == hire_role_filter:
			filtered.append(candidate)
	return filtered


func _add_hire_role_filter_option(role_filter: OptionButton, label: String, role_id: String) -> void:
	role_filter.add_item(label)
	role_filter.set_item_metadata(role_filter.item_count - 1, role_id)


func _get_hire_role_filter_index(role_filter: OptionButton, role_id: String) -> int:
	for index in range(role_filter.item_count):
		if str(role_filter.get_item_metadata(index)) == role_id:
			return index
	return 0


func _on_hire_role_filter_selected(index: int, role_filter: OptionButton) -> void:
	hire_role_filter = str(role_filter.get_item_metadata(index))
	_refresh_hires()


func _add_order_row(row: Dictionary) -> void:
	_add_order_grid_cell(str(row.get("direction", "Order")), 90.0, true)
	_add_good_grid_cell(orders_list, str(row.get("good_id", "")), str(row.get("good_name", "Product")), 160.0)
	_add_order_grid_cell(str(row.get("status", "Queued")), 160.0)
	_add_order_grid_cell("%d units\n%d KG trip" % [
		int(row.get("quantity", 0)),
		int(row.get("load_weight_kg", 0)),
	], 90.0)
	_add_order_grid_cell("%d KG" % int(row.get("holding_weight_kg", 0)), 110.0)
	_add_order_grid_cell(str(row.get("runner", "Waiting")), 120.0)
	_add_order_grid_cell(str(row.get("eta_label", "Queued")), 95.0)
	_add_order_grid_cell(str(row.get("risk_label", "Low")), 80.0)
	var details_button := Button.new()
	details_button.text = "Details"
	details_button.custom_minimum_size = Vector2(100.0, 44.0)
	details_button.focus_mode = Control.FOCUS_NONE
	details_button.tooltip_text = "Show order details"
	details_button.pressed.connect(_show_order_details.bind(row.duplicate(true)))
	orders_list.add_child(details_button)


func _show_order_details(row: Dictionary) -> void:
	if order_details_dialog == null:
		order_details_dialog = AcceptDialog.new()
		order_details_dialog.title = "Order Details"
		order_details_dialog.min_size = Vector2i(440, 0)
		add_child(order_details_dialog)
	order_details_dialog.dialog_text = _format_order_details(row)
	order_details_dialog.popup_centered(Vector2i(480, 380))


func _format_order_details(row: Dictionary) -> String:
	var lines := PackedStringArray()
	lines.append("%s %s" % [
		str(row.get("direction", "Order")),
		str(row.get("good_name", "Product")),
	])
	lines.append("Status: %s" % str(row.get("status", "Queued")))
	lines.append("Goods: %d units, %d KG total load" % [
		int(row.get("quantity", 0)),
		int(row.get("load_weight_kg", 0)),
	])
	lines.append("Unit weight: %d KG" % int(row.get("unit_weight_kg", 0)))
	lines.append("Holding now: %d KG" % int(row.get("holding_weight_kg", 0)))
	lines.append("Transporter: %s" % str(row.get("runner", "Waiting")))
	lines.append("ETA: %s" % str(row.get("eta_label", "Queued")))
	lines.append("Risk: %s" % str(row.get("risk_label", "Low")))
	lines.append("Legality: %s" % str(row.get("legality_label", "Unknown")))
	lines.append("Unit price: $%d" % int(row.get("unit_price", 0)))
	lines.append("Value: $%d" % int(row.get("value", 0)))

	var order_id := str(row.get("order_id", row.get("id", "")))
	if order_id != "":
		lines.append("Order ID: %s" % order_id)
	var trip_id := str(row.get("trip_id", ""))
	if trip_id != "":
		lines.append("Trip ID: %s" % trip_id)
	var market_id := str(row.get("market_id", ""))
	if market_id != "":
		lines.append("Market: %s" % market_id.capitalize().replace("_", " "))
	var phase := str(row.get("phase", ""))
	if phase != "":
		lines.append("Phase: %s" % phase.capitalize().replace("_", " "))
	if row.has("picked_up"):
		lines.append("Picked up: %s" % ("Yes" if bool(row.get("picked_up", false)) else "No"))
	if str(row.get("row_type", "")) == "order":
		lines.append("Progress: %d pending, %d in flight, %d complete of %d" % [
			int(row.get("pending_quantity", 0)),
			int(row.get("in_flight_quantity", 0)),
			int(row.get("completed_quantity", 0)),
			int(row.get("total_quantity", 0)),
		])
	return "\n".join(lines)


func _add_hire_row(candidate: Dictionary) -> void:
	_add_hire_grid_cell(str(candidate.get("name", "Unknown")), 170.0, true)
	_add_hire_grid_cell("$%d" % int(candidate.get("price", 0)), 90.0)
	_add_hire_grid_cell(str(candidate.get("job", "Hireling")), 150.0)
	_add_hire_grid_cell(str(candidate.get("role_name", "Crew")), 120.0)
	var hire_button := Button.new()
	hire_button.text = "Buy"
	hire_button.custom_minimum_size = Vector2(110.0, 44.0)
	hire_button.focus_mode = Control.FOCUS_NONE
	hire_button.disabled = not bool(candidate.get("can_hire", false))
	hire_button.tooltip_text = str(candidate.get("block_reason", "")) if hire_button.disabled else "Hire %s" % str(candidate.get("name", "candidate"))
	hire_button.pressed.connect(_on_hire_pressed.bind(str(candidate.get("id", ""))))
	hire_list.add_child(hire_button)


func _add_hire_grid_header(text: String, width: float) -> void:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(width, 28.0)
	label.add_theme_font_size_override("font_size", 14)
	label.modulate = PHONE_TEXT_MUTED
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hire_list.add_child(label)


func _add_hire_grid_cell(text: String, width: float, primary: bool = false) -> void:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(width, 44.0)
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.add_theme_font_size_override("font_size", 16 if primary else 15)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if not primary:
		label.modulate = Color(0.88, 0.92, 0.88, 1.0)
	hire_list.add_child(label)


func _add_order_grid_header(text: String, width: float) -> void:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(width, 28.0)
	label.add_theme_font_size_override("font_size", 14)
	label.modulate = PHONE_TEXT_MUTED
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	orders_list.add_child(label)


func _add_order_grid_cell(text: String, width: float, primary: bool = false) -> void:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(width, 44.0)
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.add_theme_font_size_override("font_size", 16 if primary else 15)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if not primary:
		label.modulate = Color(0.88, 0.92, 0.88, 1.0)
	orders_list.add_child(label)


func _add_market_header(parent: HBoxContainer, text: String, width: float) -> void:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(width, 24.0)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL if text == "Good" else Control.SIZE_SHRINK_BEGIN
	label.add_theme_font_size_override("font_size", 14)
	label.modulate = Color(0.78, 0.84, 0.82, 0.78)
	parent.add_child(label)


func _add_market_row(item_name: Variant, price: int, trend: String, scarcity: String, route_pressure: String) -> void:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 10)
	market_list.add_child(row)

	_add_market_cell(row, str(item_name), 260.0, true)
	_add_market_cell(row, "$%d" % price, 72.0)
	_add_market_cell(row, trend, 110.0)
	_add_market_cell(row, scarcity, 130.0)
	_add_market_cell(row, route_pressure, 140.0)


func _add_market_cell(parent: HBoxContainer, text: String, width: float, expands: bool = false) -> void:
	var label := Label.new()
	label.text = text.capitalize().replace("_", " ")
	label.custom_minimum_size = Vector2(width, 26.0)
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.add_theme_font_size_override("font_size", 15)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL if expands else Control.SIZE_SHRINK_BEGIN
	parent.add_child(label)


func _add_trade_row(item: Dictionary) -> void:
	var good_id := str(item.get("id", ""))
	var price: int = int(item.get("buy_price", 0)) if market_mode == "buy" else int(item.get("sell_price", 0))
	var unit_weight: int = int(item.get("unit_weight_kg", 1))
	_add_good_grid_cell(market_list, good_id, str(item.get("name", "Product")), 180.0)
	_add_market_grid_cell(str(item.get("legality_label", "Unknown")), 100.0)
	_add_market_grid_cell("$%d" % price, 90.0)
	_add_market_grid_cell("%d KG/unit" % unit_weight, 90.0)
	_add_market_grid_cell(str(item.get("distance_label", "Local")), 110.0)
	var base_stock_text := "%d units\n%d KG" % [
		int(item.get("base_inventory", 0)),
		int(item.get("base_inventory", 0)) * unit_weight,
	]
	if market_mode == "sell":
		base_stock_text = "%d units\n%d available" % [
			int(item.get("base_inventory", 0)),
			int(item.get("available_sell_inventory", 0)),
		]
	_add_market_grid_cell(base_stock_text, 140.0)
	_add_market_grid_cell("%s\n%s" % [str(item.get("source_name", "Source")), str(item.get("remote_inventory_label", "Unknown"))], 160.0)

	var quantity_input := LineEdit.new()
	quantity_input.text = "0"
	quantity_input.placeholder_text = "Units"
	quantity_input.custom_minimum_size = Vector2(90.0, 36.0)
	quantity_input.select_all_on_focus = true
	quantity_input.tooltip_text = "Units to queue for this product"
	quantity_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	market_quantity_inputs[good_id] = quantity_input
	market_list.add_child(quantity_input)

	var order_button := Button.new()
	order_button.text = "Queue"
	order_button.custom_minimum_size = Vector2(130.0, 42.0)
	order_button.disabled = _is_trade_row_disabled(item)
	order_button.pressed.connect(func(): _queue_market_order(good_id))
	market_list.add_child(order_button)


func _is_trade_row_disabled(item: Dictionary) -> bool:
	if market_mode == "sell":
		return int(item.get("available_sell_inventory", 0)) <= 0
	var remote_inventory: int = int(item.get("remote_inventory", 0))
	return remote_inventory != game_state.TRADE_SOURCE_INFINITE and remote_inventory <= 0


func _on_market_mode_pressed(new_mode: String) -> void:
	market_mode = new_mode
	_show_app("market")


func _queue_market_order(good_id: String) -> void:
	var quantity: int = _get_market_order_quantity(good_id, 1)
	if quantity <= 0:
		return
	trade_order_requested.emit(market_mode, good_id, quantity)


func _queue_selected_market_orders() -> void:
	var selected_orders: Array = []
	for good_id in market_quantity_inputs:
		var quantity: int = _get_market_order_quantity(str(good_id), 0)
		if quantity > 0:
			selected_orders.append({"good_id": str(good_id), "quantity": quantity})
	for order in selected_orders:
		if order is Dictionary:
			trade_order_requested.emit(market_mode, str(order.get("good_id", "")), int(order.get("quantity", 0)))


func _get_market_order_quantity(good_id: String, fallback_quantity: int = 0) -> int:
	var input: Variant = market_quantity_inputs.get(good_id)
	if not (input is LineEdit):
		return fallback_quantity
	var quantity: int = int(input.text)
	if quantity <= 0:
		return fallback_quantity
	return quantity


func _add_market_grid_header(text: String, width: float) -> void:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(width, 28.0)
	label.add_theme_font_size_override("font_size", 14)
	label.modulate = PHONE_TEXT_MUTED
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	market_list.add_child(label)


func _add_market_grid_cell(text: String, width: float, primary: bool = false) -> void:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(width, 44.0)
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.add_theme_font_size_override("font_size", 16 if primary else 15)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if not primary:
		label.modulate = Color(0.88, 0.92, 0.88, 1.0)
	market_list.add_child(label)


func _add_good_grid_cell(grid: GridContainer, good_id: String, good_name: String, width: float) -> void:
	var cell := HBoxContainer.new()
	cell.custom_minimum_size = Vector2(width, 44.0)
	cell.add_theme_constant_override("separation", UI_TOKENS.SPACE_2)
	grid.add_child(cell)

	var icon := TextureRect.new()
	icon.texture = VISUAL_ASSETS.get_good_icon(good_id)
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.custom_minimum_size = Vector2(32.0, 32.0)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.tooltip_text = "%s icon" % good_name
	cell.add_child(icon)

	var label := Label.new()
	label.text = good_name
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.add_theme_font_size_override("font_size", 16)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cell.add_child(label)


func _add_market_stat(parent: HBoxContainer, label_text: String, value_text: String) -> void:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _make_panel_style(PHONE_PANEL_BG, PHONE_PANEL_BORDER, 1, 0))
	parent.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)

	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 2)
	margin.add_child(stack)

	var label := Label.new()
	label.text = label_text
	label.modulate = PHONE_TEXT_MUTED
	label.add_theme_font_size_override("font_size", 13)
	stack.add_child(label)

	var value := Label.new()
	value.text = value_text
	value.add_theme_font_size_override("font_size", 17)
	stack.add_child(value)


func _make_panel_style(bg_color: Color, border_color: Color, border_width: int = 1, corner_radius: int = 0) -> StyleBoxFlat:
	return UI_THEME.panel_style(bg_color, border_color, border_width, corner_radius, 0)


func _refresh_current_base_app() -> void:
	if not visible:
		return
	if ["base", "crew", "raids", "market", "orders", "hire"].has(current_app):
		_show_app(current_app)


func _on_hire_pressed(candidate_id: String) -> void:
	var result: Dictionary = game_state.hire_employee(candidate_id)
	hire_message = str(result.get("message", "Hire updated."))
	_show_app("hire")


func _on_send_raid_pressed(target_id: String) -> void:
	selected_raid_target_id = target_id
	selected_raid_crew_ids.clear()
	_show_app("raids")


func _on_raid_crew_toggled(is_selected: bool, crew_id: String) -> void:
	if is_selected:
		selected_raid_crew_ids[crew_id] = true
	else:
		selected_raid_crew_ids.erase(crew_id)


func _on_confirm_send_raid_pressed(target_id: String) -> void:
	var target: Dictionary = game_state.resolve_raid_target(target_id)
	var crew_required := int(target.get("crew_required", 1))
	var crew_ids: Array = selected_raid_crew_ids.keys()
	if crew_ids.size() < crew_required:
		if raid_status_label != null:
			raid_status_label.text = "Select at least %d crew." % crew_required
		return
	selected_raid_target_id = ""
	selected_raid_crew_ids.clear()
	raid_send_requested.emit(target_id, crew_ids)


func _on_cancel_send_raid_pressed() -> void:
	selected_raid_target_id = ""
	selected_raid_crew_ids.clear()
	_show_app("raids")


func _add_raid_report_card(report: Dictionary) -> void:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _make_panel_style(PHONE_PANEL_BG, PHONE_PANEL_BORDER, 1, 0))
	app_content.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)

	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 5)
	margin.add_child(stack)

	var title := Label.new()
	title.text = "Battle Summary"
	title.add_theme_font_size_override("font_size", 18)
	stack.add_child(title)

	var outcome := "Success" if bool(report.get("success", false)) else "Failed"
	_add_raid_report_line(stack, "Target", "%s | %s" % [str(report.get("target_name", "Raid")), outcome])
	_add_raid_report_line(stack, "Sent", _format_raid_report_names(report.get("crew_sent", [])))
	_add_raid_report_line(stack, "Returned", _format_raid_report_names(report.get("survivors", [])))
	_add_raid_report_line(stack, "Your losses", _format_raid_report_names(report.get("casualties", [])))
	_add_raid_report_line(stack, "Enemy killed", _format_raid_report_names(report.get("enemy_casualties", [])))
	_add_raid_report_line(stack, "Enemy left", _format_raid_report_names(report.get("enemy_survivors", [])))

	var reward_cash := int(report.get("reward_cash", 0))
	var loot: Dictionary = report.get("loot", {})
	_add_raid_report_line(stack, "Recovered", "$%d, %d goods" % [reward_cash, int(loot.get(game_state.GOOD_KEY, 0))])


func _add_raid_report_line(parent: VBoxContainer, label_text: String, value_text: String) -> void:
	var label := Label.new()
	label.text = "%s: %s" % [label_text, value_text]
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 15)
	if value_text == "None":
		label.modulate = PHONE_TEXT_MUTED
	parent.add_child(label)


func _format_raid_report_names(value: Variant) -> String:
	if not (value is Array):
		return "None"
	if value.is_empty():
		return "None"
	return ", ".join(PackedStringArray(value))


func _format_slot_list(value: Variant) -> String:
	if not (value is Array):
		return "None"
	if value.is_empty():
		return "None"
	var names := PackedStringArray()
	for item in value:
		names.append(str(item).capitalize().replace("_", " "))
	return ", ".join(names)


func _format_assignment(crew_member: Dictionary) -> String:
	var assigned_task := str(crew_member.get("assigned_task", ""))
	if assigned_task == "":
		return "Unassigned"
	for task in game_state.get_transport_tasks():
		if task is Dictionary and str(task.get("id", "")) == assigned_task:
			return str(task.get("name", assigned_task))
	return assigned_task.capitalize().replace("_", " ")


func _format_health(crew_member: Dictionary) -> String:
	var max_health: int = int(crew_member.get("max_health", crew_member.get("health", 0)))
	var current_health: int = clamp(int(crew_member.get("health", max_health)), 0, max_health)
	return "%d/%d" % [current_health, max_health]


func _add_info_label(text: String, font_size: int = 16) -> Label:
	var label := UI.label(text)
	label.add_theme_font_size_override("font_size", font_size)
	app_content.add_child(label)
	return label
