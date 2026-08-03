extends RefCounted
class_name VisualAssetCatalog

const GOOD_ICONS := {
	"food": preload("res://assets/ui/goods/good_food.png"),
	"industrial": preload("res://assets/ui/goods/good_industrial.png"),
	"medical": preload("res://assets/ui/goods/good_medical.png"),
	"electronics": preload("res://assets/ui/goods/good_electronics.png"),
	"chemicals": preload("res://assets/ui/goods/good_chemicals.png"),
	"documents": preload("res://assets/ui/goods/good_documents.png"),
	"luxury": preload("res://assets/ui/goods/good_luxury.png"),
	"street": preload("res://assets/ui/goods/good_street.png"),
}

const GOOD_FAMILIES := {
	"fast_food": "food",
	"industrial_supplies": "industrial",
	"grocery_supplies": "food",
	"growing_supplies": "industrial",
	"packaging_stock": "industrial",
	"fuel_chits": "chemicals",
	"repair_parts": "industrial",
	"clean_textiles": "industrial",
	"paper_forms": "documents",
	"plain_wraps": "documents",
	"clean_labels": "documents",
	"safe_storage": "industrial",
	"cold_storage": "industrial",
	"route_access": "documents",
	"quiet_access": "documents",
	"burner_parts": "electronics",
	"encrypted_devices": "electronics",
	"ledger_keys": "electronics",
	"forged_papers": "documents",
	"bootleg_media": "street",
	"counterfeit_luxuries": "luxury",
	"mirror_silk": "luxury",
	"rare_meds": "medical",
	"art_fakes": "luxury",
	"street_goods": "street",
	"night_vials": "medical",
	"hush_tabs": "medical",
	"glimmer_drops": "medical",
}

static func get_good_icon(good_id: String) -> Texture2D:
	var family := str(GOOD_FAMILIES.get(good_id, "street"))
	return GOOD_ICONS[family]


static func get_good_family(good_id: String) -> String:
	return str(GOOD_FAMILIES.get(good_id, "street"))


static func get_known_good_ids() -> Array:
	return GOOD_FAMILIES.keys()
