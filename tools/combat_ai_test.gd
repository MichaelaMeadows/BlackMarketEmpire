extends SceneTree

const BASIC_NPC_SCENE_PATH = "res://scenes/npc/BasicNpc.tscn"
const COMBAT_AI_SCENE_PATH = "res://scenes/combat/CombatAiController.tscn"
const GUN_COMPONENT_SCENE_PATH = "res://scenes/combat/GunComponent.tscn"
const MELEE_COMPONENT_SCENE_PATH = "res://scenes/combat/MeleeComponent.tscn"

var _failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_hostile_factions_are_explicit()
	_test_detects_visible_hostile()
	_test_attacks_target_in_range()
	_test_chases_target_out_of_range()
	_test_low_health_tries_to_take_cover()
	_test_follow_anchor_without_hostiles()
	_test_combat_follow_leash_keeps_units_together()
	_test_attacked_units_remember_attacker_faction()
	_test_accuracy_reduces_weapon_spread()
	_test_movement_penalty_depends_on_weapon_type()
	_test_recoil_increases_and_recovers()
	_test_reload_blocks_fire_and_refills_magazine()
	_test_melee_swing_hits_targets_inside_arc()
	_test_seeded_shot_variance_is_deterministic()
	_test_multi_projectile_weapon_fires_a_pattern()
	_test_burst_weapon_fires_followup_shots()
	_test_ai_waits_for_reaction_before_firing()
	_test_ai_forgets_stale_last_seen_targets()
	_test_ai_chases_last_seen_target_at_origin()
	_test_ai_defaults_to_weapon_effective_range()
	_test_ai_uses_updated_weapon_range_after_setup()
	_test_ai_prefers_cover_when_reloading_or_suppressed()
	_test_squad_shares_visible_targets()
	_test_squad_spacing_avoids_stacking()
	_test_cover_prefers_actual_line_blockers()
	_test_cover_search_respects_configured_radius()
	_test_cover_rejects_ally_occupied_positions()
	_test_squad_reports_respect_faction_and_confidence()

	if _failures == 0:
		print("Combat AI tests passed.")
	else:
		push_error("Combat AI tests failed: %d failure(s)." % _failures)
	quit(_failures)


func _test_hostile_factions_are_explicit() -> void:
	var owner: CharacterBody2D = _new_unit("guard", "crew", Vector2.ZERO, {"aim_time": 0.0})
	var ally: CharacterBody2D = _new_unit("ally", "crew", Vector2(80, 0))
	var bystander: CharacterBody2D = _new_unit("bystander", "neutral", Vector2(120, 0))
	var target: CharacterBody2D = _new_unit("target", "rival", Vector2(160, 0))
	var ai = _new_ai(owner, {"hostile_factions": ["rival"]})

	_expect(not ai.is_hostile(ally), "same faction is not hostile")
	_expect(not ai.is_hostile(bystander), "unlisted faction is not hostile")
	_expect(ai.is_hostile(target), "listed hostile faction is hostile")

	_free_nodes([owner, ally, bystander, target])


func _test_detects_visible_hostile() -> void:
	var owner: CharacterBody2D = _new_unit("guard", "crew", Vector2.ZERO)
	var target: CharacterBody2D = _new_unit("target", "rival", Vector2(180, 0))
	var ai = _new_ai(owner, {"hostile_factions": ["rival"], "detection_radius": 300.0})

	_expect(ai.find_visible_hostile() == target, "AI finds nearest visible hostile inside detection radius")

	_free_nodes([owner, target])


func _test_attacks_target_in_range() -> void:
	var owner: CharacterBody2D = _new_unit("guard", "crew", Vector2.ZERO)
	var target: CharacterBody2D = _new_unit("target", "rival", Vector2(180, 0))
	var ai = _new_ai(owner, {
		"hostile_factions": ["rival"],
		"detection_radius": 400.0,
		"attack_range": 240.0,
		"reaction_time": 0.0,
	})

	ai.tick_ai(0.1)
	_expect(ai.get_state_name() == "ATTACKING", "AI attacks visible target inside weapon range")
	_expect(_get_gun(owner).cooldown_remaining > 0.0, "AI fires its gun when attacking")

	_free_nodes([owner, target])


func _test_chases_target_out_of_range() -> void:
	var owner: CharacterBody2D = _new_unit("guard", "crew", Vector2.ZERO)
	var target: CharacterBody2D = _new_unit("target", "rival", Vector2(360, 0))
	var ai = _new_ai(owner, {
		"hostile_factions": ["rival"],
		"detection_radius": 500.0,
		"attack_range": 180.0,
		"chase_speed": 120.0,
	})

	ai.tick_ai(0.1)
	_expect(ai.get_state_name() == "CHASING", "AI chases visible target outside weapon range")
	_expect(owner.velocity.x > 0.0 and abs(owner.velocity.y) < 0.01, "AI chase velocity points toward target")

	_free_nodes([owner, target])


func _test_low_health_tries_to_take_cover() -> void:
	var owner: CharacterBody2D = _new_unit("guard", "crew", Vector2.ZERO)
	var target: CharacterBody2D = _new_unit("target", "rival", Vector2(180, 0))
	var ai = _new_ai(owner, {
		"hostile_factions": ["rival"],
		"detection_radius": 400.0,
		"attack_range": 260.0,
		"cover_health_fraction": 0.75,
		"cover_search_radius": 120.0,
	})
	_get_health(owner).apply_damage(40)

	ai.tick_ai(0.1)
	_expect(ai.get_state_name() == "TAKING_COVER", "wounded AI enters cover behavior")
	_expect(ai.cover_position.distance_to(target.global_position) > owner.global_position.distance_to(target.global_position), "cover fallback moves away from hostile")

	_free_nodes([owner, target])


func _test_follow_anchor_without_hostiles() -> void:
	var owner: CharacterBody2D = _new_unit("guard", "crew", Vector2.ZERO)
	var leader: CharacterBody2D = _new_unit("leader", "crew", Vector2(260, 0))
	var ai = _new_ai(owner, {"hostile_factions": ["rival"], "follow_speed": 90.0})
	ai.set_follow_target(leader, 80.0)

	ai.tick_ai(0.1)
	_expect(ai.get_state_name() == "FOLLOWING", "AI follows assigned anchor when idle")
	_expect(owner.velocity.x > 0.0, "AI follow velocity points toward anchor")

	_free_nodes([owner, leader])


func _test_combat_follow_leash_keeps_units_together() -> void:
	var owner: CharacterBody2D = _new_unit("guard", "crew", Vector2.ZERO)
	var leader: CharacterBody2D = _new_unit("leader", "crew", Vector2(-500, 0))
	var target: CharacterBody2D = _new_unit("target", "rival", Vector2(180, 0))
	var ai = _new_ai(owner, {
		"hostile_factions": ["rival"],
		"detection_radius": 400.0,
		"attack_range": 260.0,
		"combat_follow_leash": 200.0,
	})
	ai.set_follow_target(leader, 80.0, 200.0)

	ai.tick_ai(0.1)
	_expect(ai.get_state_name() == "FOLLOWING", "AI regroups with follow anchor when combat leash is exceeded")
	_expect(owner.velocity.x < 0.0, "AI regroup velocity points back toward anchor")

	_free_nodes([owner, leader, target])


func _test_attacked_units_remember_attacker_faction() -> void:
	var owner: CharacterBody2D = _new_unit("guard", "crew", Vector2.ZERO)
	var attacker: CharacterBody2D = _new_unit("attacker", "rival", Vector2(180, 0))
	var ai = _new_ai(owner, {"hostile_factions": []})

	ai.notify_attacked_by(attacker)
	_expect(ai.is_hostile(attacker), "AI treats a damaging attacker faction as hostile")
	_expect(ai.current_target == attacker, "AI targets the unit that attacked it")

	_free_nodes([owner, attacker])


func _test_accuracy_reduces_weapon_spread() -> void:
	var owner: CharacterBody2D = _new_unit("shooter", "crew", Vector2.ZERO)
	var accurate = _new_gun({
		"weapon_type": "rifle",
		"accuracy": 0.95,
		"base_spread_degrees": 20.0,
		"movement_spread_degrees": 0.0,
	})
	var loose = _new_gun({
		"weapon_type": "rifle",
		"accuracy": 0.35,
		"base_spread_degrees": 20.0,
		"movement_spread_degrees": 0.0,
	})

	_expect(accurate.get_effective_spread_degrees(owner) < loose.get_effective_spread_degrees(owner), "higher weapon accuracy produces less spread")

	_free_nodes([owner, accurate, loose])


func _test_movement_penalty_depends_on_weapon_type() -> void:
	var owner: CharacterBody2D = _new_unit("mover", "crew", Vector2.ZERO)
	owner.velocity = Vector2(220.0, 0.0)
	var pistol = _new_gun({
		"weapon_type": "pistol",
		"accuracy": 1.0,
		"base_spread_degrees": 0.0,
	})
	var rifle = _new_gun({
		"weapon_type": "rifle",
		"accuracy": 1.0,
		"base_spread_degrees": 0.0,
	})

	_expect(rifle.get_effective_spread_degrees(owner) > pistol.get_effective_spread_degrees(owner), "rifle has stronger movement spread penalty than pistol")

	_free_nodes([owner, pistol, rifle])


func _test_seeded_shot_variance_is_deterministic() -> void:
	var owner: CharacterBody2D = _new_unit("shooter", "crew", Vector2.ZERO)
	var gun_a = _new_gun({
		"accuracy": 0.5,
		"base_spread_degrees": 24.0,
		"movement_spread_degrees": 0.0,
	})
	var gun_b = _new_gun({
		"accuracy": 0.5,
		"base_spread_degrees": 24.0,
		"movement_spread_degrees": 0.0,
	})
	gun_a.set_seed(123)
	gun_b.set_seed(123)

	var direction_a: Vector2 = gun_a.calculate_shot_directions(owner, Vector2.RIGHT)[0]
	var direction_b: Vector2 = gun_b.calculate_shot_directions(owner, Vector2.RIGHT)[0]
	_expect(direction_a.distance_to(direction_b) < 0.0001, "seeded weapon spread is deterministic")

	_free_nodes([owner, gun_a, gun_b])


func _test_recoil_increases_and_recovers() -> void:
	var owner: CharacterBody2D = _new_unit("shooter", "crew", Vector2.ZERO)
	var gun = _new_gun({
		"accuracy": 1.0,
		"base_spread_degrees": 0.0,
		"movement_spread_degrees": 0.0,
		"recoil_per_shot": 2.0,
		"recoil_recovery_per_second": 4.0,
		"max_recoil_spread_degrees": 6.0,
		"fire_cooldown": 0.01,
	})

	_expect(gun.try_fire(owner, Vector2.RIGHT), "recoil test weapon fires")
	var after_shot: float = gun.get_effective_spread_degrees(owner)
	gun._process(0.5)
	var after_recovery: float = gun.get_effective_spread_degrees(owner)
	_expect(after_shot > 0.0, "recoil adds spread after firing")
	_expect(after_recovery < after_shot, "recoil spread recovers over time")

	_free_nodes([owner, gun])


func _test_reload_blocks_fire_and_refills_magazine() -> void:
	var owner: CharacterBody2D = _new_unit("shooter", "crew", Vector2.ZERO)
	var gun = _new_gun({
		"magazine_size": 2,
		"ammo_in_magazine": 1,
		"reload_time": 0.3,
		"fire_cooldown": 0.01,
	})

	_expect(gun.try_fire(owner, Vector2.RIGHT), "last round fires")
	_expect(not gun.try_fire(owner, Vector2.RIGHT), "empty weapon cannot fire")
	_expect(gun.start_reload(), "empty weapon starts reload")
	_expect(not gun.try_fire(owner, Vector2.RIGHT), "reloading weapon cannot fire")
	gun._process(0.31)
	_expect(gun.ammo_in_magazine == 2, "reload refills magazine")

	_free_nodes([owner, gun])


func _test_melee_swing_hits_targets_inside_arc() -> void:
	var owner: CharacterBody2D = _new_unit("batter", "crew", Vector2.ZERO)
	var target: CharacterBody2D = _new_unit("target", "rival", Vector2(55, 0))
	var bystander: CharacterBody2D = _new_unit("bystander", "rival", Vector2(-45, 0))
	var melee_weapon = _equip_melee_weapon(owner, {
		"name": "Test Bat",
		"damage": 20,
		"range": 70,
		"arc_degrees": 90,
		"swing_cooldown": 0.4,
		"swing_duration": 0.1,
	})
	if melee_weapon == null:
		_free_nodes([owner, target, bystander])
		return

	_expect(melee_weapon.try_swing(owner, Vector2.RIGHT), "melee weapon swings")
	_expect(_get_health(target).current_health == 80, "melee swing damages target inside front arc")
	_expect(_get_health(bystander).current_health == 100, "melee swing ignores target behind owner")
	_expect(not melee_weapon.try_swing(owner, Vector2.RIGHT), "melee cooldown blocks immediate second swing")
	melee_weapon._process(0.41)
	_expect(melee_weapon.try_swing(owner, Vector2.RIGHT), "melee weapon swings again after cooldown")

	_free_nodes([owner, target, bystander])


func _test_multi_projectile_weapon_fires_a_pattern() -> void:
	var owner: CharacterBody2D = _new_unit("shooter", "crew", Vector2.ZERO, {
		"weapon_type": "shotgun",
		"accuracy": 1.0,
		"base_spread_degrees": 0.0,
		"projectiles_per_shot": 5,
		"projectile_spread_degrees": 24.0,
		"fire_cooldown": 0.1,
	})

	var gun = _get_gun(owner)
	var fired: bool = gun.try_fire(owner, Vector2.RIGHT)
	_expect(fired, "multi-projectile weapon fires")
	_expect(gun.last_fired_directions.size() == 5, "shotgun-style weapon emits multiple projectiles")
	_expect(_angle_degrees(gun.last_fired_directions[0]) < _angle_degrees(gun.last_fired_directions[4]), "multi-projectile weapon spreads directions across an arc")

	_free_nodes([owner])


func _test_burst_weapon_fires_followup_shots() -> void:
	var owner: CharacterBody2D = _new_unit("burster", "crew", Vector2.ZERO, {
		"burst_count": 3,
		"burst_interval": 0.05,
		"magazine_size": 9,
		"ammo_in_magazine": 9,
		"fire_cooldown": 0.3,
	})
	var gun = _get_gun(owner)

	_expect(gun.try_fire(owner, Vector2.RIGHT), "burst weapon fires first shot")
	_expect(gun.ammo_in_magazine == 8, "burst consumes first round immediately")
	gun._process(0.05)
	gun._process(0.05)
	_expect(gun.ammo_in_magazine == 6, "burst follow-up shots consume remaining burst rounds")
	_expect(gun.last_fired_directions.size() == 3, "burst records all fired directions")

	_free_nodes([owner])


func _test_ai_waits_for_reaction_before_firing() -> void:
	var owner: CharacterBody2D = _new_unit("guard", "crew", Vector2.ZERO, {"aim_time": 0.2})
	var target: CharacterBody2D = _new_unit("target", "rival", Vector2(160, 0))
	var ai = _new_ai(owner, {
		"hostile_factions": ["rival"],
		"detection_radius": 400.0,
		"attack_range": 240.0,
		"reaction_time": 0.3,
	})

	ai.tick_ai(0.1)
	_expect(_get_gun(owner).cooldown_remaining == 0.0, "AI does not fire before reaction and aim time finish")
	ai.tick_ai(0.5)
	_expect(_get_gun(owner).cooldown_remaining > 0.0, "AI fires after reaction and aim time")

	_free_nodes([owner, target])


func _test_ai_forgets_stale_last_seen_targets() -> void:
	var owner: CharacterBody2D = _new_unit("guard", "crew", Vector2.ZERO)
	var target: CharacterBody2D = _new_unit("target", "rival", Vector2(160, 0))
	var ai = _new_ai(owner, {
		"hostile_factions": ["rival"],
		"detection_radius": 400.0,
		"attack_range": 120.0,
		"target_memory_seconds": 0.2,
	})

	ai.notify_attacked_by(target)
	target.global_position = Vector2(1000, 0)
	ai.tick_ai(0.25)
	_expect(ai.current_target == null, "AI forgets target after memory expires")

	_free_nodes([owner, target])


func _test_ai_chases_last_seen_target_at_origin() -> void:
	var owner: CharacterBody2D = _new_unit("guard", "crew", Vector2(100, 0))
	var target: CharacterBody2D = _new_unit("target", "rival", Vector2.ZERO)
	var ai = _new_ai(owner, {
		"hostile_factions": ["rival"],
		"detection_radius": 200.0,
		"attack_range": 80.0,
		"target_memory_seconds": 1.0,
	})

	ai.notify_attacked_by(target)
	target.global_position = Vector2(1000, 0)
	ai.tick_ai(0.1)
	_expect(ai.get_state_name() == "CHASING", "AI chases a last-seen target position at world origin")
	_expect(owner.velocity.x < 0.0, "AI moves toward the origin last-seen position")

	_free_nodes([owner, target])


func _test_ai_defaults_to_weapon_effective_range() -> void:
	var close_range: CharacterBody2D = _new_unit("shotgunner", "crew", Vector2.ZERO, {
		"weapon_type": "shotgun",
		"effective_range": 120.0,
		"preferred_range": 80.0,
	})
	var long_range: CharacterBody2D = _new_unit("rifleman", "crew", Vector2(0, 120), {
		"weapon_type": "rifle",
		"effective_range": 420.0,
		"preferred_range": 300.0,
	})
	var target: CharacterBody2D = _new_unit("target", "rival", Vector2(260, 0))
	var close_ai = _new_ai(close_range, {
		"hostile_factions": ["rival"],
		"detection_radius": 500.0,
	})
	var long_ai = _new_ai(long_range, {
		"hostile_factions": ["rival"],
		"detection_radius": 500.0,
	})

	close_ai.tick_ai(0.1)
	long_ai.tick_ai(0.1)
	_expect(close_ai.get_state_name() == "CHASING", "short-range weapon holder closes distance before firing")
	_expect(long_ai.get_state_name() == "ATTACKING", "long-range weapon holder attacks from farther away")

	_free_nodes([close_range, long_range, target])


func _test_ai_uses_updated_weapon_range_after_setup() -> void:
	var owner: CharacterBody2D = _new_unit("switcher", "crew", Vector2.ZERO, {
		"effective_range": 120.0,
		"preferred_range": 80.0,
	})
	var target: CharacterBody2D = _new_unit("target", "rival", Vector2(260, 0))
	var ai = _new_ai(owner, {
		"hostile_factions": ["rival"],
		"detection_radius": 500.0,
		"reaction_time": 0.0,
	})

	ai.tick_ai(0.1)
	_expect(ai.get_state_name() == "CHASING", "AI initially chases with short-range weapon")
	_get_gun(owner).effective_range = 420.0
	_get_gun(owner).preferred_range = 300.0
	ai.tick_ai(0.1)
	_expect(ai.get_state_name() == "ATTACKING", "AI uses updated weapon range without setup refresh")

	_free_nodes([owner, target])


func _test_ai_prefers_cover_when_reloading_or_suppressed() -> void:
	var owner: CharacterBody2D = _new_unit("guard", "crew", Vector2.ZERO, {
		"magazine_size": 4,
		"ammo_in_magazine": 0,
		"reload_time": 0.8,
	})
	var target: CharacterBody2D = _new_unit("target", "rival", Vector2(180, 0))
	var ai = _new_ai(owner, {
		"hostile_factions": ["rival"],
		"detection_radius": 400.0,
		"attack_range": 240.0,
		"reaction_time": 0.0,
		"suppression_cover_threshold": 0.5,
	})

	ai.tick_ai(0.1)
	_expect(["TAKING_COVER", "RELOADING_IN_COVER", "IN_COVER"].has(ai.get_state_name()), "AI seeks cover while empty/reloading")
	_get_gun(owner).ammo_in_magazine = 4
	_get_gun(owner).reload_remaining = 0.0
	ai.suppress(0.8)
	ai.tick_ai(0.1)
	_expect(["TAKING_COVER", "IN_COVER", "PEEKING"].has(ai.get_state_name()), "suppressed AI prefers cover")

	_free_nodes([owner, target])


func _test_squad_shares_visible_targets() -> void:
	var scout: CharacterBody2D = _new_unit("scout", "crew", Vector2.ZERO)
	var ally: CharacterBody2D = _new_unit("ally", "crew", Vector2(260, 120))
	var target: CharacterBody2D = _new_unit("target", "rival", Vector2(180, 0))
	var scout_ai = _new_ai(scout, {
		"hostile_factions": ["rival"],
		"detection_radius": 320.0,
		"attack_range": 80.0,
		"squad_id": "alpha",
		"ally_alert_radius": 500.0,
	})
	var ally_ai = _new_ai(ally, {
		"hostile_factions": ["rival"],
		"detection_radius": 40.0,
		"attack_range": 80.0,
		"squad_id": "alpha",
		"ally_alert_radius": 500.0,
	})

	scout_ai.tick_ai(0.1)
	_expect(ally_ai.current_target == target, "squadmate receives target from ally contact report")
	_expect(ally_ai.last_seen_position.distance_to(target.global_position) < 0.01, "squadmate receives shared target position")

	_free_nodes([scout, ally, target])


func _test_squad_spacing_avoids_stacking() -> void:
	var mover: CharacterBody2D = _new_unit("mover", "crew", Vector2.ZERO)
	var ally: CharacterBody2D = _new_unit("ally", "crew", Vector2(0, 10))
	var target: CharacterBody2D = _new_unit("target", "rival", Vector2(360, 0))
	var ai = _new_ai(mover, {
		"hostile_factions": ["rival"],
		"detection_radius": 500.0,
		"attack_range": 80.0,
		"chase_speed": 120.0,
		"preferred_spacing": 80.0,
	})
	_new_ai(ally, {
		"hostile_factions": ["rival"],
		"preferred_spacing": 80.0,
	})

	ai.tick_ai(0.1)
	_expect(abs(mover.velocity.y) > 0.01, "moving squad unit adds separation when stacked with an ally")

	_free_nodes([mover, ally, target])


func _test_cover_prefers_actual_line_blockers() -> void:
	var owner: CharacterBody2D = _new_unit("guard", "crew", Vector2.ZERO)
	var target: CharacterBody2D = _new_unit("target", "rival", Vector2(180, 0))
	var blocker := _new_wall(Vector2(-60, 0), Vector2(20, 220))
	var ai = _new_ai(owner, {
		"hostile_factions": ["rival"],
		"detection_radius": 320.0,
		"attack_range": 240.0,
		"cover_health_fraction": 0.9,
		"cover_search_radius": 120.0,
	})
	_get_health(owner).apply_damage(40)

	ai.tick_ai(0.1)
	_expect(ai.get_state_name() == "TAKING_COVER", "wounded AI enters cover behavior with map blocker present")
	_expect(ai.cover_position.x < owner.global_position.x, "cover candidate is on safer side away from hostile")

	_free_nodes([owner, target, blocker])


func _test_cover_search_respects_configured_radius() -> void:
	var owner: CharacterBody2D = _new_unit("guard", "crew", Vector2.ZERO)
	var target: CharacterBody2D = _new_unit("target", "rival", Vector2(180, 0))
	var ai = _new_ai(owner, {
		"hostile_factions": ["rival"],
		"detection_radius": 320.0,
		"attack_range": 240.0,
		"cover_health_fraction": 0.9,
		"cover_search_radius": 60.0,
	})
	_get_health(owner).apply_damage(40)

	ai.tick_ai(0.1)
	_expect(ai.cover_position.distance_to(Vector2.ZERO) <= 60.01, "cover search stays inside configured radius")

	_free_nodes([owner, target])


func _test_cover_rejects_ally_occupied_positions() -> void:
	var owner: CharacterBody2D = _new_unit("guard", "crew", Vector2.ZERO)
	var target: CharacterBody2D = _new_unit("target", "rival", Vector2(180, 0))
	var ally: CharacterBody2D = _new_unit("ally", "crew", Vector2(-80, 0))
	var blocker := _new_wall(Vector2(-60, 0), Vector2(20, 220))
	var ai = _new_ai(owner, {
		"hostile_factions": ["rival"],
		"detection_radius": 320.0,
		"attack_range": 240.0,
		"cover_health_fraction": 0.9,
		"preferred_spacing": 90.0,
	})
	_new_ai(ally, {"hostile_factions": ["rival"], "preferred_spacing": 90.0})
	_get_health(owner).apply_damage(40)

	ai.tick_ai(0.1)
	_expect(ai.cover_position.distance_to(ally.global_position) >= 90.0, "cover scoring avoids ally-occupied cover")

	_free_nodes([owner, target, ally, blocker])


func _test_squad_reports_respect_faction_and_confidence() -> void:
	var owner: CharacterBody2D = _new_unit("owner", "crew", Vector2.ZERO)
	var ally: CharacterBody2D = _new_unit("ally", "crew", Vector2(60, 0))
	var other_squad: CharacterBody2D = _new_unit("other_squad", "crew", Vector2(70, 40))
	var stranger: CharacterBody2D = _new_unit("stranger", "neutral", Vector2(70, 0))
	var visible_target: CharacterBody2D = _new_unit("visible", "rival", Vector2(160, 0))
	var reported_target: CharacterBody2D = _new_unit("reported", "rival", Vector2(220, 0))
	var ai = _new_ai(owner, {
		"hostile_factions": ["rival"],
		"detection_radius": 300.0,
		"squad_id": "alpha",
	})
	_new_ai(ally, {"hostile_factions": ["rival"], "squad_id": "alpha"})
	_new_ai(other_squad, {"hostile_factions": ["rival"], "squad_id": "beta"})

	ai.tick_ai(0.1)
	ai.receive_shared_target(reported_target, ally, 0.4)
	_expect(ai.current_target == visible_target, "direct visible target wins over lower-confidence report")
	ai.receive_shared_target(reported_target, other_squad, 1.0)
	_expect(ai.current_target == visible_target, "report from wrong squad is ignored")
	ai.receive_shared_target(reported_target, stranger, 1.0)
	_expect(ai.current_target == visible_target, "report from wrong faction is ignored")

	_free_nodes([owner, ally, other_squad, stranger, visible_target, reported_target])


func _new_unit(unit_name: String, faction: String, position: Vector2, weapon_data: Dictionary = {}) -> CharacterBody2D:
	var unit = _instantiate_scene(BASIC_NPC_SCENE_PATH)
	if unit == null:
		return null
	if not (unit is CharacterBody2D) or not unit.has_method("setup"):
		_expect(false, "BasicNpc scene provides CharacterBody2D setup unit")
		unit.free()
		return null
	var final_weapon_data := {
		"damage": 8,
		"projectile_speed": 500.0,
		"projectile_lifetime": 1.0,
		"fire_cooldown": 0.5,
	}
	for key in weapon_data:
		final_weapon_data[key] = weapon_data[key]

	unit.name = unit_name
	unit.call("setup", {
		"name": unit_name,
		"faction": faction,
		"health": 100,
		"weapon": final_weapon_data,
	})
	if not _unit_has_combat_components(unit):
		unit.free()
		return null
	unit.global_position = position
	root.add_child(unit)
	return unit


func _new_ai(owner: CharacterBody2D, config: Dictionary):
	if owner == null:
		_expect(false, "creates AI owner")
		return null
	var ai = _instantiate_scene(COMBAT_AI_SCENE_PATH)
	if ai == null:
		return null
	if not ai.has_method("setup") or not ai.has_method("tick_ai"):
		_expect(false, "Combat AI scene provides setup and tick_ai")
		ai.free()
		return null
	owner.add_child(ai)
	owner.set("combat_ai", ai)
	var ai_config := config.duplicate()
	ai_config["faction"] = str(owner.call("get_faction"))
	ai.setup(owner, ai_config)
	return ai


func _new_gun(weapon_data: Dictionary):
	var gun = _instantiate_scene(GUN_COMPONENT_SCENE_PATH)
	if gun == null:
		return null
	if not gun.has_method("setup") or not gun.has_method("try_fire") or not gun.has_method("is_reloading"):
		_expect(false, "Gun component scene provides weapon methods")
		gun.free()
		return null
	gun.setup(weapon_data)
	root.add_child(gun)
	return gun


func _equip_melee_weapon(owner: Node, weapon_data: Dictionary):
	var melee_weapon = _instantiate_scene(MELEE_COMPONENT_SCENE_PATH)
	if melee_weapon == null:
		return null
	if not melee_weapon.has_method("setup") or not melee_weapon.has_method("try_swing") or not melee_weapon.has_method("is_swinging"):
		_expect(false, "Melee component scene provides weapon methods")
		melee_weapon.free()
		return null
	melee_weapon.setup(weapon_data)
	owner.add_child(melee_weapon)
	owner.set("melee_weapon", melee_weapon)
	return melee_weapon


func _instantiate_scene(path: String):
	var scene = load(path)
	if scene == null:
		_expect(false, "loads scene: %s" % path)
		return null
	var instance = scene.instantiate()
	if instance == null:
		_expect(false, "instantiates scene: %s" % path)
		return null
	return instance


func _unit_has_combat_components(unit: Node) -> bool:
	var unit_health = unit.get("health")
	if unit_health == null or not unit_health.has_method("setup") or not unit_health.has_method("get_health_fraction"):
		_expect(false, "unit has scripted health component")
		return false

	var unit_gun = unit.get("gun")
	if unit_gun == null or not unit_gun.has_method("setup") or not unit_gun.has_method("try_fire") or not unit_gun.has_method("is_reloading"):
		_expect(false, "unit has scripted gun component")
		return false
	return true


func _new_wall(position: Vector2, size: Vector2) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.global_position = position
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = size
	shape.shape = rectangle
	body.add_child(shape)
	root.add_child(body)
	return body


func _angle_degrees(direction: Vector2) -> float:
	return rad_to_deg(direction.angle())


func _get_gun(unit: Node):
	return unit.get("gun")


func _get_melee_weapon(unit: Node):
	return unit.get("melee_weapon")


func _get_health(unit: Node):
	return unit.get("health")


func _free_nodes(nodes: Array) -> void:
	for node in nodes:
		if node != null and is_instance_valid(node):
			node.free()


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		_failures += 1
		push_error("FAIL: %s" % label)
