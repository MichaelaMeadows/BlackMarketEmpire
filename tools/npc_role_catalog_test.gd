extends SceneTree

const NPC_ROLE_CATALOG_SCRIPT := preload("res://scripts/npc_role_catalog.gd")

var _failures: int = 0


func _init() -> void:
	_test_basic_roles_exist()
	_test_dealer_is_transporter()
	_test_muscle_archetypes_are_extensible()
	_test_production_archetype_exists()
	_test_legacy_runner_job_maps_to_transporter()

	if _failures == 0:
		print("NPC role catalog tests passed.")
	else:
		push_error("NPC role catalog tests failed: %d failure(s)." % _failures)
	quit(_failures)


func _test_basic_roles_exist() -> void:
	_expect(NPC_ROLE_CATALOG_SCRIPT.get_role("transporter").get("name") == "Transporter", "transporter role exists")
	_expect(NPC_ROLE_CATALOG_SCRIPT.get_role("muscle").get("name") == "Muscle", "muscle role exists")
	_expect(NPC_ROLE_CATALOG_SCRIPT.get_role("production").get("name") == "Production", "production role exists")


func _test_dealer_is_transporter() -> void:
	var profile: Dictionary = NPC_ROLE_CATALOG_SCRIPT.build_staff_profile({"archetype": "dealer"})
	_expect(profile.get("role") == "transporter", "dealer archetype resolves to transporter")
	_expect(profile.get("archetype_name") == "Dealer", "dealer archetype has display name")
	_expect(profile.get("task_types", []).has("transport"), "dealer can transport")
	_expect(int(profile.get("carry_capacity_kg", 0)) == 5, "dealer has starter carry capacity")


func _test_muscle_archetypes_are_extensible() -> void:
	var thug: Dictionary = NPC_ROLE_CATALOG_SCRIPT.build_staff_profile({"archetype": "thug"})
	var mercenary: Dictionary = NPC_ROLE_CATALOG_SCRIPT.build_staff_profile({"archetype": "mercenary"})
	_expect(thug.get("role") == "muscle", "thug archetype resolves to muscle")
	_expect(mercenary.get("role") == "muscle", "mercenary archetype resolves to muscle")
	_expect(int(mercenary.get("upkeep", 0)) > int(thug.get("upkeep", 0)), "muscle archetypes can carry different tuning")


func _test_production_archetype_exists() -> void:
	var worker: Dictionary = NPC_ROLE_CATALOG_SCRIPT.build_staff_profile({"archetype": "workshop_hand"})
	_expect(worker.get("role") == "production", "workshop hand archetype resolves to production")
	_expect(worker.get("task_types", []).has("production"), "production archetype can make items")


func _test_legacy_runner_job_maps_to_transporter() -> void:
	var profile: Dictionary = NPC_ROLE_CATALOG_SCRIPT.build_staff_profile({"job": "Runner", "status": "Ready"})
	_expect(profile.get("role") == "transporter", "legacy runner job maps to transporter")
	_expect(profile.get("task_types", []).has("transport"), "legacy runner keeps transport task")


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		_failures += 1
		push_error("FAIL: %s" % label)
