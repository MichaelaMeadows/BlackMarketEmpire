extends SceneTree

const NAME_GENERATOR_SCRIPT := preload("res://scripts/name_generator.gd")

var _failures: int = 0


func _init() -> void:
	_test_seeded_names_are_deterministic()
	_test_generated_names_are_unique_by_default()
	_test_surname_option_generates_full_names()
	_test_unique_pool_falls_back_when_exhausted()

	if _failures == 0:
		print("Name generator tests passed.")
	else:
		push_error("Name generator tests failed: %d failure(s)." % _failures)
	quit(_failures)


func _test_seeded_names_are_deterministic() -> void:
	var first = NAME_GENERATOR_SCRIPT.new(123)
	var second = NAME_GENERATOR_SCRIPT.new(123)
	_expect(first.generate_many(12) == second.generate_many(12), "seeded NPC names are deterministic")


func _test_generated_names_are_unique_by_default() -> void:
	var generator = NAME_GENERATOR_SCRIPT.new(44)
	var names: Array = generator.generate_many(24)
	var seen := {}
	for name in names:
		_expect(str(name) != "", "generated NPC name is not empty")
		_expect(not seen.has(str(name)), "generated NPC names are unique by default")
		seen[str(name)] = true


func _test_surname_option_generates_full_names() -> void:
	var generator = NAME_GENERATOR_SCRIPT.new(7)
	var name: String = generator.generate_npc_name({"include_surname": true, "allow_nickname": false})
	_expect(name.split(" ").size() == 2, "surname option generates first and last name")


func _test_unique_pool_falls_back_when_exhausted() -> void:
	var generator = NAME_GENERATOR_SCRIPT.new(91)
	var names: Array = generator.generate_many(70, {"allow_nickname": false})
	var seen := {}
	for name in names:
		_expect(not seen.has(str(name)), "exhausted short-name pool still returns unique fallback names")
		seen[str(name)] = true


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		_failures += 1
		push_error("FAIL: %s" % label)
