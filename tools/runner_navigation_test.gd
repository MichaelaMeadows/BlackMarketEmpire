extends SceneTree

const MAP_NAVIGATION_SCRIPT := preload("res://scripts/map_navigation.gd")
const NAVIGATION_MOVER_SCRIPT := preload("res://scripts/navigation_mover.gd")


var _failures: int = 0


func _init() -> void:
	_test_runner_uses_navigation_waypoints()

	if _failures == 0:
		print("Runner navigation tests passed.")
	else:
		push_error("Runner navigation tests failed: %d failure(s)." % _failures)
	quit(_failures)


func _test_runner_uses_navigation_waypoints() -> void:
	var navigation = MAP_NAVIGATION_SCRIPT.new()
	navigation.setup({
		"bounds": [0, 0, 320, 224],
		"player_start": [64, 64],
		"walls": [
			{"id": "divider", "rect": [128, 0, 32, 128], "collides": true},
		],
	})
	var npc := CharacterBody2D.new()
	npc.position = Vector2(64.0, 64.0)
	var target := Vector2(224.0, 64.0)
	var max_y := npc.position.y
	var completed := false
	for index in range(80):
		completed = NAVIGATION_MOVER_SCRIPT.move_towards(npc, target, 120.0, 0.1, navigation)
		max_y = max(max_y, npc.position.y)
		if completed:
			break

	_expect(completed, "runner completes navigation movement")
	_expect(max_y > 128.0, "runner follows waypoint path through wall gap")
	_expect(npc.position.distance_to(target) <= 8.0, "runner finishes near target")
	npc.free()


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		_failures += 1
		push_error("FAIL: %s" % label)
