extends RefCounted
class_name NpcRoleCatalog

const ROLE_TRANSPORTER := "transporter"
const ROLE_MUSCLE := "muscle"
const ROLE_PRODUCTION := "production"

const ROLE_DEFINITIONS := {
	ROLE_TRANSPORTER: {
		"id": ROLE_TRANSPORTER,
		"name": "Transporter",
		"description": "Moves goods between the base and outside contacts.",
		"task_types": ["transport"],
	},
	ROLE_MUSCLE: {
		"id": ROLE_MUSCLE,
		"name": "Muscle",
		"description": "Fights, guards, and joins violent work.",
		"task_types": ["combat", "guard", "raid"],
	},
	ROLE_PRODUCTION: {
		"id": ROLE_PRODUCTION,
		"name": "Production",
		"description": "Makes things with items stored in the base.",
		"task_types": ["production"],
	},
}

const ARCHETYPE_DEFINITIONS := {
	"dealer": {
		"id": "dealer",
		"name": "Dealer",
		"role": ROLE_TRANSPORTER,
		"task_types": ["transport"],
		"carry_capacity_kg": 5,
		"upkeep": 10,
	},
	"runner": {
		"id": "runner",
		"name": "Runner",
		"role": ROLE_TRANSPORTER,
		"task_types": ["transport"],
		"carry_capacity_kg": 5,
		"upkeep": 10,
	},
	"thug": {
		"id": "thug",
		"name": "Thug",
		"role": ROLE_MUSCLE,
		"task_types": ["combat", "guard", "raid"],
		"upkeep": 18,
	},
	"mercenary": {
		"id": "mercenary",
		"name": "Mercenary",
		"role": ROLE_MUSCLE,
		"task_types": ["combat", "guard", "raid"],
		"upkeep": 35,
	},
	"workshop_hand": {
		"id": "workshop_hand",
		"name": "Workshop Hand",
		"role": ROLE_PRODUCTION,
		"task_types": ["production"],
		"upkeep": 14,
	},
}


static func get_role(role_id: String) -> Dictionary:
	var normalized_role_id := normalize_role_id(role_id)
	var role: Variant = ROLE_DEFINITIONS.get(normalized_role_id, {})
	if role is Dictionary:
		return role.duplicate(true)
	return {}


static func get_archetype(archetype_id: String) -> Dictionary:
	var archetype: Variant = ARCHETYPE_DEFINITIONS.get(archetype_id, {})
	if archetype is Dictionary:
		return archetype.duplicate(true)
	return {}


static func normalize_role_id(role_id: String) -> String:
	var normalized := role_id.strip_edges().to_lower()
	match normalized:
		"transport", "transporter", "runner", "dealer":
			return ROLE_TRANSPORTER
		"fighter", "combat", "guard", "muscle", "thug", "mercenary":
			return ROLE_MUSCLE
		"producer", "maker", "craft", "crafting", "production", "workshop_hand":
			return ROLE_PRODUCTION
	return normalized


static func normalize_archetype_id(archetype_id: String, role_id: String = "") -> String:
	var normalized := archetype_id.strip_edges().to_lower()
	if normalized != "":
		return normalized
	match normalize_role_id(role_id):
		ROLE_TRANSPORTER:
			return "dealer"
		ROLE_MUSCLE:
			return "thug"
		ROLE_PRODUCTION:
			return "workshop_hand"
	return ""


static func build_staff_profile(staff_data: Dictionary, npc_data: Dictionary = {}) -> Dictionary:
	var legacy_job := str(staff_data.get("job", ""))
	var role_id := normalize_role_id(str(staff_data.get("role", legacy_job)))
	var archetype_id := normalize_archetype_id(str(staff_data.get("archetype", "")), role_id)
	var archetype := get_archetype(archetype_id)
	if role_id == "" and not archetype.is_empty():
		role_id = normalize_role_id(str(archetype.get("role", "")))
	var role := get_role(role_id)
	var role_task_types := _as_array(role.get("task_types", []))
	var archetype_task_types := _as_array(archetype.get("task_types", []))
	var task_types := _merge_unique(role_task_types, archetype_task_types)
	task_types = _merge_unique(task_types, _as_array(staff_data.get("task_types", [])))

	return {
		"role": role_id,
		"role_name": str(role.get("name", role_id.capitalize())),
		"archetype": archetype_id,
		"archetype_name": str(archetype.get("name", legacy_job if legacy_job != "" else role_id.capitalize())),
		"job": str(archetype.get("name", legacy_job if legacy_job != "" else role_id.capitalize())),
		"task_types": task_types,
		"carry_capacity_kg": int(staff_data.get("carry_capacity_kg", archetype.get("carry_capacity_kg", 0))),
		"upkeep": int(staff_data.get("upkeep", archetype.get("upkeep", 0))),
		"status": str(staff_data.get("status", "Ready")),
		"assigned_task": str(staff_data.get("assigned_task", "")),
		"source_role": str(npc_data.get("role", "crew")),
	}


static func can_do_task_type(crew_member: Dictionary, task_type: String) -> bool:
	var task_types: Variant = crew_member.get("task_types", [])
	return task_types is Array and task_types.has(task_type)


static func has_role(crew_member: Dictionary, role_id: String) -> bool:
	return normalize_role_id(str(crew_member.get("role", ""))) == normalize_role_id(role_id)


static func get_carry_capacity_kg(crew_member: Dictionary, fallback: int = 0) -> int:
	return max(0, int(crew_member.get("carry_capacity_kg", fallback)))


static func _merge_unique(first: Array, second: Array) -> Array:
	var merged := []
	for item in first:
		if not merged.has(item):
			merged.append(item)
	for item in second:
		if not merged.has(item):
			merged.append(item)
	return merged


static func _as_array(value: Variant) -> Array:
	if value is Array:
		return value
	return []
