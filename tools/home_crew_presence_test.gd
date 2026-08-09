extends SceneTree

const MAIN_SCENE := preload("res://scenes/main/Main.tscn")

var _failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var main = MAIN_SCENE.instantiate()
	get_root().add_child(main)
	await process_frame
	await process_frame

	await _test_sent_raid_waits_for_crew_to_leave(main)
	await _test_hired_crew_walks_onto_home_map(main)
	await _test_two_hired_thugs_enable_enemy_thug_attack(main)

	main.queue_free()
	await process_frame
	if _failures == 0:
		print("Home crew presence tests passed.")
	else:
		push_error("Home crew presence tests failed: %d failure(s)." % _failures)
	quit(_failures)


func _test_sent_raid_waits_for_crew_to_leave(main) -> void:
	var state = main.game_state
	var benji = main._find_spawned_npc_by_id("benji_runner")
	_expect(benji != null, "starter crew is present before sent raid")
	if benji == null:
		return
	benji.apply_damage(10)
	var wounded_benji: Dictionary = _find_crew_member(state.get_crew_roster(), "benji_runner")
	_expect(int(wounded_benji.get("health", 0)) == int(wounded_benji.get("max_health", 0)) - 10, "home crew damage persists to roster health")

	main._on_raid_send_requested("abandoned_depot", ["benji_runner"])
	_expect(str(state.get_active_raid_target().get("mode", "")) == "departing", "sent raid starts as a departure")
	_expect(main.active_raid_departures.has("benji_runner"), "sent raid tracks crew walking to exit")
	_expect(main.active_sent_raid_seconds <= 0.0, "sent raid timer waits for crew to leave map")

	for _index in range(240):
		main._process(0.1)
		await process_frame
		if str(state.get_active_raid_target().get("mode", "")) == "sent":
			break

	_expect(str(state.get_active_raid_target().get("mode", "")) == "sent", "sent raid starts after crew leaves map")
	_expect(main._find_spawned_npc_by_id("benji_runner") == null, "departed crew is removed from the home map")
	_expect(main.active_sent_raid_seconds > 0.0, "sent raid timer starts after departure")

	for _index in range(80):
		main._process(0.1)
		await process_frame
		if state.get_active_raid_target().is_empty():
			break
	await process_frame

	_expect(state.get_active_raid_target().is_empty(), "sent raid completes after departure")
	_expect(state.get_ready_crew_count() == 1, "sent raid survivor returns to ready crew")
	_expect(main._find_spawned_npc_by_id("benji_runner") != null, "sent raid survivor returns to the home map")


func _test_hired_crew_walks_onto_home_map(main) -> void:
	var state = main.game_state
	var hires: Array = state.get_available_hires()
	_expect(not hires.is_empty(), "hire candidates are available")
	if hires.is_empty():
		return

	var hire_result: Dictionary = state.hire_employee(str(hires[0].get("id", "")))
	_expect(bool(hire_result.get("ok", false)), "hire succeeds from the home map")
	var hired_member: Dictionary = hire_result.get("crew_member", {})
	var hired_id := str(hired_member.get("id", ""))
	var npc = main._find_spawned_npc_by_id(hired_id)
	_expect(npc != null, "hired crew spawns as a home map NPC")
	_expect(npc != null and npc.get("gun") == null, "hired thug has no gun on the map")
	_expect(npc != null and npc.get("melee_weapon") != null, "hired thug has a melee weapon on the map")
	_expect(main.active_crew_arrivals.has(hired_id), "hired crew starts with an arrival walk")
	_expect(npc != null and npc.get("combat_ai") != null and not bool(npc.get("combat_ai").get("enabled")), "arrival walk owns movement instead of fighting follow AI")
	if npc == null or not main.active_crew_arrivals.has(hired_id):
		return

	var arrival: Dictionary = main.active_crew_arrivals[hired_id]
	var target: Vector2 = arrival.get("target", npc.position)
	var starting_distance: float = npc.position.distance_to(target)
	for _index in range(180):
		main._process(0.1)
		if not main.active_crew_arrivals.has(hired_id):
			break

	_expect(npc.position.distance_to(target) < starting_distance, "hired crew moves toward their base spot")
	_expect(not main.active_crew_arrivals.has(hired_id), "hired crew finishes arrival and stays at base")
	_expect(main._find_spawned_npc_by_id(hired_id) == npc, "hired crew remains present after arriving")
	_expect(bool(npc.get("combat_ai").get("enabled")), "finishing arrival restores squad AI")
	main._begin_crew_arrival(hired_id, npc, npc.position + Vector2(12.0, 0.0))
	main._update_crew_arrivals(0.1)
	_expect(not main.active_crew_arrivals.has(hired_id), "arrival clears as soon as crew is within the settle distance")
	_expect(bool(npc.get("combat_ai").get("enabled")), "early arrival settlement restores squad AI")

	# Recreate the real onboarding timing: the player can send a recent hire while
	# its arrival walk is still active.
	main._begin_crew_arrival(hired_id, npc, main.player.position)
	main._on_raid_send_requested("abandoned_depot", [hired_id])
	_expect(npc.get("combat_ai") != null, "hired raid crew has follow AI")
	_expect(not bool(npc.get("combat_ai").get("enabled")), "raid departure suspends the follow AI")
	_expect(not main.active_crew_arrivals.has(hired_id), "raid departure cancels a pending hire arrival walk")
	for _index in range(240):
		main._process(0.1)
		await process_frame
		if str(state.get_active_raid_target().get("mode", "")) == "sent":
			break
	_expect(str(state.get_active_raid_target().get("mode", "")) == "sent", "AI-controlled crew reaches the exit instead of following the player")
	for _index in range(80):
		main._process(0.1)
		await process_frame
		if state.get_active_raid_target().is_empty():
			break
	await process_frame


func _test_two_hired_thugs_enable_enemy_thug_attack(main) -> void:
	var state = main.game_state
	var hires: Array = state.get_available_hires()
	if hires.size() < 1:
		_expect(false, "second starter thug is still available")
		return
	var second_hire: Dictionary = state.hire_employee(str(hires[0].get("id", "")))
	_expect(bool(second_hire.get("ok", false)), "second starter thug can be hired")
	await process_frame
	await process_frame

	_expect(state.get_ready_crew_count("muscle") == 2, "two hired thugs are ready at the base")
	var enemy = _find_first_rival(main)
	_expect(enemy != null, "enemy thug attack auto-spawns after hiring two thugs")
	if enemy == null:
		return
	_expect(enemy.has_method("get_faction") and str(enemy.get_faction()) == "rival", "enemy thug is a rival")
	_expect(enemy.get("gun") == null, "enemy thug has no ranged weapon")
	_expect(enemy.get("melee_weapon") != null, "enemy thug starts with a bat")
	_expect(enemy.get("combat_ai") != null, "enemy thug has attack AI")
	var ai = enemy.get("combat_ai")
	_expect(ai != null and ai.is_hostile(main.player), "enemy thug treats the player as hostile")
	_expect(ai != null and ai.current_target == main.player, "enemy thug is forced to attack into the base")
	var starting_distance: float = enemy.global_position.distance_to(main.player.global_position)
	for _index in range(80):
		if ai != null:
			ai.tick_ai(0.1)
		await process_frame
		if enemy.global_position.distance_to(main.player.global_position) < starting_distance - 24.0:
			break
	_expect(enemy.global_position.distance_to(main.player.global_position) < starting_distance, "enemy thug walks toward the player after spawning")


func _find_first_rival(main):
	for npc in main.spawned_npcs:
		if is_instance_valid(npc) and npc.has_method("get_faction") and str(npc.get_faction()) == "rival":
			return npc
	return null


func _find_crew_member(roster: Array, crew_id: String) -> Dictionary:
	for crew_member in roster:
		if crew_member is Dictionary and str(crew_member.get("id", "")) == crew_id:
			return crew_member
	return {}


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		_failures += 1
		push_error("FAIL: %s" % label)
