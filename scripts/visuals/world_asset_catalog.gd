extends RefCounted
class_name WorldAssetCatalog

const SURFACE_TEXTURES := {
	"asphalt": preload("res://assets/tiles/core/tile_asphalt.png"),
	"concrete": preload("res://assets/tiles/core/tile_concrete.png"),
	"dirt": preload("res://assets/tiles/core/tile_dirt.png"),
	"grass": preload("res://assets/tiles/core/tile_grass.png"),
	"wood": preload("res://assets/tiles/core/tile_wood.png"),
	"carpet": preload("res://assets/tiles/core/tile_carpet.png"),
	"ceramic": preload("res://assets/tiles/core/tile_ceramic.png"),
	"brick": preload("res://assets/tiles/core/tile_brick.png"),
}

static func get_surface_family(material: String) -> String:
	var normalized := material.to_lower()
	if normalized.contains("asphalt") or normalized.contains("road") or normalized.contains("alley"):
		return "asphalt"
	if normalized.contains("carpet") or normalized.contains("rug"):
		return "carpet"
	if normalized.contains("tile") or normalized.contains("bath") or normalized.contains("ceramic"):
		return "ceramic"
	if normalized.contains("grass") or normalized.contains("woods"):
		return "grass"
	if normalized.contains("wood") or normalized.contains("plank"):
		return "wood"
	if normalized.contains("dirt") or normalized.contains("earth"):
		return "dirt"
	if normalized.contains("brick"):
		return "brick"
	return "concrete"


static func get_surface_texture(material: String) -> Texture2D:
	return SURFACE_TEXTURES[get_surface_family(material)]
