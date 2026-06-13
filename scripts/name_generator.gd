extends RefCounted
class_name NameGenerator

const FIRST_NAMES := [
	"Arlo", "Ari", "Benji", "Bo", "Cass", "Dani", "Dev", "Emi",
	"Ezra", "Hale", "Inez", "Jules", "Kade", "Len", "Mara", "Mira",
	"Nia", "Oren", "Renn", "Rhea", "Sana", "Tomas", "Vale", "Voss",
	"Wren", "Zara", "Noa", "Kit", "Lux", "Nico", "Rey", "Sloane",
]

const SURNAMES := [
	"Alder", "Briar", "Cairn", "Cross", "Denton", "Vale", "Fenn",
	"Graves", "Hollow", "Kestrel", "Mercer", "Morrow", "Pike", "Rook",
	"Sable", "Stone", "Valez", "Ward", "Wicker", "Yardley",
]

const NICKNAMES := [
	"Ace", "Brick", "Cipher", "Dash", "Doc", "Ghost", "Latch", "Lucky",
	"Moth", "Patch", "Penny", "Rook", "Shade", "Sparks", "Switch", "Wire",
]

var _rng := RandomNumberGenerator.new()
var _seed: int = 9301
var _used_names: Dictionary = {}


func _init(seed: int = 9301) -> void:
	set_seed(seed)


func set_seed(seed: int) -> void:
	_seed = seed
	_rng.seed = _seed
	_used_names.clear()


func reset_used_names() -> void:
	_used_names.clear()


func generate_npc_name(options: Dictionary = {}) -> String:
	var include_surname := bool(options.get("include_surname", false))
	var allow_nickname := bool(options.get("allow_nickname", true))
	var unique := bool(options.get("unique", true))

	for _attempt in range(64):
		var candidate := _compose_name(include_surname, allow_nickname)
		if not unique or not _used_names.has(candidate):
			if unique:
				_used_names[candidate] = true
			return candidate

	var fallback := "%s %d" % [_pick(FIRST_NAMES), _used_names.size() + 1]
	if unique:
		_used_names[fallback] = true
	return fallback


func generate_many(count: int, options: Dictionary = {}) -> Array:
	var names: Array = []
	for _index in range(max(0, count)):
		names.append(generate_npc_name(options))
	return names


func _compose_name(include_surname: bool, allow_nickname: bool) -> String:
	var first_name := _pick(FIRST_NAMES)
	if allow_nickname and not include_surname and _rng.randf() < 0.24:
		return _pick(NICKNAMES)
	if not include_surname:
		return first_name

	var surname := _pick(SURNAMES)
	if allow_nickname and _rng.randf() < 0.14:
		return "%s \"%s\" %s" % [first_name, _pick(NICKNAMES), surname]
	return "%s %s" % [first_name, surname]


func _pick(pool: Array) -> String:
	if pool.is_empty():
		return "Unknown"
	return str(pool[_rng.randi_range(0, pool.size() - 1)])
