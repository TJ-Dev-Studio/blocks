class_name BlockMaterials
## Shared material palette and cache for the Block system.
##
## Consolidates all material creation into a single cache.
## Request materials by name (palette key) or by Color.
## Same material instance is returned on repeated requests.

static var _cache: Dictionary = {}

# Named palette — common materials across all game objects.
const PALETTE := {
	# Wood / organic
	"wood": Color(0.3, 0.2, 0.1),
	"wood_light": Color(0.5, 0.35, 0.15),
	"wood_dark": Color(0.2, 0.12, 0.06),
	"bark": Color(0.25, 0.15, 0.08),
	"rope": Color(0.35, 0.28, 0.15),
	"plant_green": Color(0.267, 0.667, 0.267),
	"leaf": Color(0.2, 0.5, 0.15),
	"mushroom": Color(0.6, 0.15, 0.1),

	# Metal
	"metal_dark": Color(0.267, 0.267, 0.267),
	"metal_light": Color(0.6, 0.6, 0.6),
	"metal_rust": Color(0.5, 0.3, 0.15),
	"chrome": Color(0.8, 0.8, 0.85),
	"blue_metal": Color(0.133, 0.267, 0.667),

	# Stone / concrete
	"stone": Color(0.4, 0.38, 0.35),
	"concrete": Color(0.667, 0.667, 0.667),
	"brick": Color(0.6, 0.3, 0.2),

	# Paint / manufactured
	"red": Color(0.8, 0.133, 0.133),
	"green_bin": Color(0.2, 0.4, 0.2),
	"sign_green": Color(0.0, 0.4, 0.2),
	"dumpster": Color(0.176, 0.353, 0.153),
	"crate": Color(0.722, 0.525, 0.043),
	"bench_wood": Color(0.627, 0.447, 0.165),
	"white": Color(0.933, 0.933, 0.933),
	"black": Color(0.1, 0.1, 0.1),

	# Glass / transparent
	"glass": Color(0.667, 0.8, 0.933, 0.5),
	"water": Color(0.1, 0.3, 0.6, 0.7),

	# Terrain
	"terrain": Color(0.3, 0.5, 0.2),
	"sand": Color(0.76, 0.7, 0.5),
	"dirt": Color(0.4, 0.3, 0.2),

	# Effects
	"glow_yellow": Color(1.0, 0.9, 0.3),
	"glow_blue": Color(0.3, 0.5, 1.0),

	# Power grid
	"power_red": Color(0.8, 0.15, 0.1),
	"power_green": Color(0.1, 0.8, 0.2),
	"wire_copper": Color(0.72, 0.45, 0.2),
	"transformer_gray": Color(0.45, 0.45, 0.5),
	"generator_yellow": Color(0.9, 0.75, 0.1),
	"house_beige": Color(0.85, 0.78, 0.65),
	"house_blue": Color(0.55, 0.65, 0.8),
	"light_pole": Color(0.35, 0.35, 0.35),

	# Fallback
	"default": Color(0.5, 0.5, 0.5),
	"debug": Color(1.0, 0.0, 1.0),
}

const ROUGHNESS := {
	"wood": 0.8,
	"wood_light": 0.75,
	"wood_dark": 0.85,
	"bark": 0.85,
	"rope": 0.9,
	"metal_dark": 0.7,
	"metal_light": 0.5,
	"metal_rust": 0.8,
	"chrome": 0.15,
	"glass": 0.1,
	"stone": 0.8,
	"concrete": 0.85,
	"water": 0.05,
	"wire_copper": 0.6,
	"transformer_gray": 0.7,
	"generator_yellow": 0.65,
	"light_pole": 0.5,
}


## Get or create a StandardMaterial3D by palette name.
static func get_material(material_id: String) -> StandardMaterial3D:
	if _cache.has(material_id):
		return _cache[material_id]

	var mat := StandardMaterial3D.new()

	if PALETTE.has(material_id):
		mat.albedo_color = PALETTE[material_id]
	else:
		mat.albedo_color = PALETTE["default"]
		push_warning("[BlockMaterials] Unknown material '%s', using default" % material_id)

	mat.roughness = ROUGHNESS.get(material_id, 0.8)

	if mat.albedo_color.a < 1.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	_cache[material_id] = mat
	return mat


## Get or create a material from an arbitrary Color.
static func get_material_from_color(color: Color) -> StandardMaterial3D:
	var key := "color_%s" % color.to_html()
	if _cache.has(key):
		return _cache[key]

	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.8
	if color.a < 1.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	_cache[key] = mat
	return mat


## Check if a material_id exists in the palette.
static func has_material(material_id: String) -> bool:
	return PALETTE.has(material_id)


## Get all palette keys.
static func get_palette_keys() -> PackedStringArray:
	var keys := PackedStringArray()
	for k in PALETTE:
		keys.append(k)
	return keys


## Clear the cache (useful for testing).
static func clear_cache() -> void:
	_cache.clear()
