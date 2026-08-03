extends SceneTree

const MAP_LOADER_SCRIPT := preload("res://scripts/map_loader.gd")
const GAME_STATE_SCRIPT := preload("res://scripts/autoload/game_state.gd")
const HOME_MAP_PATH := "res://maps/starter_house.json"

var _failures: int = 0


func _init() -> void:
	_test_home_to_raid_to_home_data_flow()

	if _failures == 0:
		print("Map switch tests passed.")
	else:
		push_error("Map switch tests failed: %d failure(s)." % _failures)
	quit(_failures)


func _test_home_to_raid_to_home_data_flow() -> void:
	var state = GAME_STATE_SCRIPT.new()
	state._ready()

	var map_loader = MAP_LOADER_SCRIPT.new()
	get_root().add_child(map_loader)
	_expect(map_loader.load_map(HOME_MAP_PATH), "home map loads")
	state.initialize_base_from_map(map_loader.get_map_data())
	_expect(map_loader.get_title() == "Cypress House", "home map title resolves")
	var home_start := map_loader.get_player_start()
	_expect(map_loader.get_navigation().is_walkable(home_start), "home player start is walkable")
	_expect(map_loader.get_navigation().get_room_id_at(home_start) == "bedroom", "home player starts in the bedroom")
	_expect(state.get_base_summary().get("id") == "cypress_house", "home map initializes base state")

	var join_result: Dictionary = state.start_raid("abandoned_depot", true)
	_expect(bool(join_result.get("ok", false)), "joined raid can start")

	var target: Dictionary = state.resolve_raid_target("abandoned_depot")
	_expect(map_loader.load_map(str(target.get("path", ""))), "raid target map loads")
	_expect(map_loader.get_title() == "Abandoned Depot", "raid map title resolves")
	_expect(map_loader.get_player_start() == Vector2(-740.0, 380.0), "raid player start resolves")

	var complete_result: Dictionary = state.complete_active_raid(true)
	_expect(bool(complete_result.get("ok", false)), "active raid completes")
	_expect(state.get_active_raid_target().is_empty(), "active raid clears after completion")
	_expect(map_loader.load_map(HOME_MAP_PATH), "home map reloads after raid")
	_expect(map_loader.get_title() == "Cypress House", "home title restores")

	map_loader.free()
	state.free()


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		_failures += 1
		push_error("FAIL: %s" % label)
