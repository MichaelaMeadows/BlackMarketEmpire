extends RefCounted
class_name BaseProductionState

var recipes: Dictionary = {}
var active_jobs: Dictionary = {}


func load_recipes(path: String) -> bool:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		push_error("Base production data must contain a dictionary: %s" % path)
		return false
	recipes.clear()
	for value in parsed.get("recipes", []):
		if value is Dictionary:
			var recipe: Dictionary = value.duplicate(true)
			recipes[str(recipe.get("id", ""))] = recipe
	return not recipes.is_empty()


func get_recipe(recipe_id: String) -> Dictionary:
	var recipe: Variant = recipes.get(recipe_id, {})
	return recipe.duplicate(true) if recipe is Dictionary else {}


func get_jobs() -> Array:
	var jobs: Array = []
	for job in active_jobs.values():
		if job is Dictionary:
			jobs.append(job.duplicate(true))
	return jobs


func get_recipe_rows(context: Dictionary) -> Array:
	var rows: Array = []
	for facility in context.get("facilities", []):
		if not (facility is Dictionary) or str(facility.get("type", "")) != "production" or int(facility.get("capacity", 0)) <= 0:
			continue
		var facility_id := str(facility.get("id", ""))
		var supported: Array = facility.get("recipe_ids", recipes.keys())
		for value in supported:
			var recipe := get_recipe(str(value))
			if recipe.is_empty():
				continue
			var row := recipe.duplicate(true)
			row["facility_id"] = facility_id
			row["facility_name"] = str(facility.get("name", "Production Facility"))
			row["active_job"] = get_job(facility_id)
			var check := _can_start(context, facility, recipe)
			row["can_start"] = bool(check.get("ok", false))
			row["block_reason"] = str(check.get("message", ""))
			rows.append(row)
	return rows


func get_job(facility_id: String) -> Dictionary:
	var job: Variant = active_jobs.get(facility_id, {})
	return job.duplicate(true) if job is Dictionary else {}


func start_job(context: Dictionary, facility_id: String, recipe_id: String) -> Dictionary:
	var facility := _find_facility(context, facility_id)
	var recipe := get_recipe(recipe_id)
	if facility.is_empty() or recipe.is_empty():
		return _result(false, "Production option is not available.")
	var check := _can_start(context, facility, recipe)
	if not bool(check.get("ok", false)):
		return check
	for good_id in recipe.get("inputs", {}):
		_add_stock(context, str(good_id), -int(recipe["inputs"][good_id]))
	var duration := maxf(1.0, float(recipe.get("duration_seconds", 20.0)))
	var job := {
		"facility_id": facility_id,
		"facility_name": str(facility.get("name", "Production Facility")),
		"recipe_id": recipe_id,
		"recipe_name": str(recipe.get("name", recipe_id.capitalize())),
		"inputs": recipe.get("inputs", {}).duplicate(true),
		"output": recipe.get("output", {}).duplicate(true),
		"duration_seconds": duration,
		"remaining_seconds": duration,
		"status": "running",
	}
	active_jobs[facility_id] = job
	return {"ok": true, "message": "Started %s." % str(job["recipe_name"]), "job": job.duplicate(true)}


func advance(context: Dictionary, delta_seconds: float) -> Array:
	var completed: Array = []
	if delta_seconds <= 0.0:
		return completed
	for facility_id in active_jobs.keys():
		if not active_jobs.has(facility_id):
			continue
		var job: Dictionary = active_jobs[facility_id]
		job["remaining_seconds"] = maxf(0.0, float(job.get("remaining_seconds", 0.0)) - delta_seconds)
		if float(job["remaining_seconds"]) > 0.0:
			active_jobs[facility_id] = job
			continue
		if not _has_output_space(context, job.get("output", {})):
			job["status"] = "waiting_storage"
			active_jobs[facility_id] = job
			continue
		var output: Dictionary = job.get("output", {})
		var good_id := str(output.get("good", ""))
		var quantity := int(output.get("quantity", 0))
		_add_stock(context, good_id, quantity)
		active_jobs.erase(facility_id)
		completed.append({
			"facility_id": str(facility_id), "recipe_id": str(job.get("recipe_id", "")),
			"good_id": good_id, "quantity": quantity,
			"message": "%s finished %d %s." % [str(job.get("facility_name", "Production")), quantity, _good_name(context, good_id)],
		})
	return completed


func cancel_job(context: Dictionary, facility_id: String) -> Dictionary:
	var job := get_job(facility_id)
	if job.is_empty():
		return _result(false, "No active batch at that facility.")
	for good_id in job.get("inputs", {}):
		_add_stock(context, str(good_id), int(job["inputs"][good_id]))
	active_jobs.erase(facility_id)
	return _result(true, "Canceled %s and returned its inputs." % str(job.get("recipe_name", "batch")))


func _can_start(context: Dictionary, facility: Dictionary, recipe: Dictionary) -> Dictionary:
	var facility_id := str(facility.get("id", ""))
	if active_jobs.has(facility_id):
		return _result(false, "Facility already has an active batch.")
	if not facility.get("recipe_ids", recipes.keys()).has(str(recipe.get("id", ""))):
		return _result(false, "That facility cannot make this recipe.")
	var workers_required: int = max(0, int(facility.get("workers_required", 0)))
	if int(context.get("ready_production_workers", 0)) < workers_required:
		return _result(false, "Need %d ready production worker(s)." % workers_required)
	var inventory: Dictionary = context.get("inventory", {})
	for good_id in recipe.get("inputs", {}):
		var required := int(recipe["inputs"][good_id])
		if int(inventory.get(good_id, 0)) < required:
			return _result(false, "Need %d %s." % [required, _good_name(context, str(good_id))])
	return _result(true, "Ready")


func _has_output_space(context: Dictionary, output: Dictionary) -> bool:
	var good_id := str(output.get("good", ""))
	var quantity := int(output.get("quantity", 0))
	return _storage_used(context) + quantity * _unit_weight(context, good_id) <= int(context.get("storage_capacity", 0))


func _storage_used(context: Dictionary) -> int:
	var total := 0
	for good_id in context.get("inventory", {}):
		total += int(context.get("inventory", {})[good_id]) * _unit_weight(context, str(good_id))
	return total


func _unit_weight(context: Dictionary, good_id: String) -> int:
	return max(1, int(context.get("unit_weights", {}).get(good_id, 1)))


func _good_name(context: Dictionary, good_id: String) -> String:
	return str(context.get("good_names", {}).get(good_id, good_id.capitalize().replace("_", " ")))


func _add_stock(context: Dictionary, good_id: String, amount: int) -> void:
	var inventory: Dictionary = context.get("inventory", {})
	var storage: Dictionary = context.get("storage_inventory", {})
	inventory[good_id] = max(0, int(inventory.get(good_id, 0)) + amount)
	storage[good_id] = int(inventory[good_id])


func _find_facility(context: Dictionary, facility_id: String) -> Dictionary:
	for facility in context.get("facilities", []):
		if facility is Dictionary and str(facility.get("id", "")) == facility_id:
			return facility
	return {}


func _result(ok: bool, message: String) -> Dictionary:
	return {"ok": ok, "message": message}
