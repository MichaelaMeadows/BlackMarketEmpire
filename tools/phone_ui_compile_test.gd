extends SceneTree

const PHONE_UI_SCRIPT := preload("res://scripts/phone_ui.gd")

var _failures: int = 0


func _init() -> void:
	_expect(PHONE_UI_SCRIPT != null, "phone UI script compiles")
	_test_tab_closes_open_phone()
	_test_corner_clock_exists()
	_test_hire_role_filter_exists()
	_test_raid_send_picker_exists()
	_test_squad_command_controls_exist()
	_test_intro_mission_hud_exists()
	_test_production_app_exists()

	if _failures == 0:
		print("Phone UI compile tests passed.")
	else:
		push_error("Phone UI compile tests failed: %d failure(s)." % _failures)
	quit(_failures)


func _test_tab_closes_open_phone() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/main.gd")
	_expect(source.contains("func _input(event: InputEvent)"), "main handles phone input before GUI focus")
	_expect(source.contains("event.is_action_pressed(\"phone\")"), "main listens for the phone action")
	_expect(source.contains("phone_ui.toggle()"), "phone action toggles an already-open phone UI")


func _test_corner_clock_exists() -> void:
	var main_source := FileAccess.get_file_as_string("res://scripts/main.gd")
	var state_source := FileAccess.get_file_as_string("res://scripts/autoload/game_state.gd")
	_expect(state_source.contains("const DAY_LENGTH_SECONDS := 360.0"), "day length is configured in one GameState constant")
	_expect(state_source.contains("const CALENDAR_START"), "calendar start is configured in GameState")
	_expect(state_source.contains("\"year\": 2025"), "calendar starts in 2025")
	_expect(state_source.contains("\"month\": 4"), "calendar starts in April")
	_expect(state_source.contains("\"day\": 20"), "calendar starts on day 20")
	_expect(state_source.contains("func advance_game_time"), "GameState owns clock advancement")
	_expect(main_source.contains("var clock_label"), "main HUD has a clock label")
	_expect(main_source.contains("clock_label.anchor_left = 1.0"), "clock is anchored to the top corner")
	_expect(main_source.contains("game_state.get_clock_label()"), "main HUD displays formatted game time")


func _test_hire_role_filter_exists() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/phone_ui.gd")
	_expect(source.contains("var hire_role_filter"), "hire screen stores selected role filter")
	_expect(source.contains("OptionButton.new()"), "hire screen exposes a role filter selector")
	_expect(source.contains("_filter_hires_by_role"), "hire screen filters candidates by role")
	_expect(source.contains("_on_hire_role_filter_selected"), "hire screen refreshes when role filter changes")


func _test_raid_send_picker_exists() -> void:
	var phone_source := FileAccess.get_file_as_string("res://scripts/phone_ui.gd")
	var main_source := FileAccess.get_file_as_string("res://scripts/main.gd")
	_expect(phone_source.contains("signal raid_send_requested"), "raids screen emits selected crew for sent raids")
	_expect(phone_source.contains("_build_raid_crew_picker"), "raids screen has a crew picker")
	_expect(phone_source.contains("CheckBox.new()"), "raids screen lets the player select NPCs")
	_expect(phone_source.contains("_format_health"), "phone UI formats crew health as current and max")
	_expect(phone_source.contains("Health %s"), "crew and raid screens show health values")
	_expect(phone_source.contains("_add_raid_report_card"), "raids screen renders the last raid report as a card")
	_expect(phone_source.contains("Battle Summary"), "raids screen labels the battle summary card")
	_expect(phone_source.contains("Enemy killed"), "raids screen shows opponent losses")
	_expect(main_source.contains("raid_send_requested.connect(_on_raid_send_requested)"), "main handles sent raid requests")
	_expect(main_source.contains("_update_sent_raid"), "main resolves sent raids after travel time")


func _test_squad_command_controls_exist() -> void:
	var main_source := FileAccess.get_file_as_string("res://scripts/main.gd")
	var ai_source := FileAccess.get_file_as_string("res://scripts/combat_ai_controller.gd")
	_expect(main_source.contains("[1] Follow"), "HUD exposes a squad follow button and key")
	_expect(main_source.contains("[2] Attack"), "HUD exposes a squad attack button and key")
	_expect(main_source.contains("[3] Hold"), "HUD exposes a squad hold button and key")
	_expect(main_source.contains("_try_issue_squad_attack_at"), "main supports click-targeted squad attacks")
	_expect(ai_source.contains("func issue_follow_order"), "combat AI accepts follow orders")
	_expect(ai_source.contains("func issue_attack_order"), "combat AI accepts attack orders")
	_expect(ai_source.contains("func issue_hold_order"), "combat AI accepts hold orders")


func _test_intro_mission_hud_exists() -> void:
	var main_source := FileAccess.get_file_as_string("res://scripts/main.gd")
	var state_source := FileAccess.get_file_as_string("res://scripts/autoload/game_state.gd")
	_expect(main_source.contains("mission_title_label"), "HUD exposes the current intro mission")
	_expect(main_source.contains("_refresh_intro_mission"), "HUD refreshes mission progress")
	_expect(state_source.contains("INTRO_MISSION_DATA_PATH"), "GameState loads data-driven intro missions")
	_expect(state_source.contains("record_intro_mission_event"), "GameState accepts gameplay events for intro missions")


func _test_production_app_exists() -> void:
	var phone_source := FileAccess.get_file_as_string("res://scripts/phone_ui.gd")
	var state_source := FileAccess.get_file_as_string("res://scripts/autoload/game_state.gd")
	_expect(phone_source.contains("_build_production_app"), "phone exposes production management")
	_expect(phone_source.contains("Start Batch"), "production app can start a batch")
	_expect(state_source.contains("start_base_production"), "GameState exposes base production commands")
	_expect(state_source.contains("advance_base_production"), "base production advances with game time")


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("PASS: %s" % message)
	else:
		_failures += 1
		push_error("FAIL: %s" % message)
