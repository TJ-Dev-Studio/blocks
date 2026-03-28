class_name BlockMaterials
## Shared material palette and cache for the Block system.
##
## Consolidates all material creation into a single cache.
## Request materials by name (palette key) or by Color.
## Same material instance is returned on repeated requests.

static var _cache: Dictionary = {}
static var _override_cache: Dictionary = {}
static var _shader: Shader = null
static var _proc_shader: Shader = null

## Extension points — game-specific overrides registered at startup.
## palette_override: Dictionary of material_id -> Color. Merged on top of PALETTE.
static var palette_override: Dictionary = {}
## roughness_override: Dictionary of material_id -> float. Merged on top of ROUGHNESS.
static var roughness_override: Dictionary = {}
## material_post_processor: Callable(material_id: String, mat: Material) -> Material.
## Called after every material is created, before caching. Use to add next_pass,
## shader parameters, or replace the material entirely. Return the (possibly modified) material.
static var material_post_processor: Callable = Callable()
## shader_param_injector: Callable(material_id: String, smat: ShaderMaterial) -> void.
## Called after shader parameters are set on opaque ShaderMaterials. Use to inject
## additional textures or uniforms (e.g. brush strokes, canvas grain).
static var shader_param_injector: Callable = Callable()

## Maps material_type string to the int uniform value used in the uber-shader.
## 0 = flat (fallback), 1 = bark, 2 = stone, 3 = moss, 4 = water, 5 = wood
const MATERIAL_TYPE_MAP: Dictionary = {
	"bark": 1,
	"stone": 2,
	"moss": 3,
	"water": 4,
	"wood": 5,
}

## Lazy-load the block world shader. Returns null if the file is missing.
static func _get_shader() -> Shader:
	if _shader == null:
		_shader = load("res://assets/shaders/block_world.gdshader") as Shader
		if _shader == null:
			push_warning("[BlockMaterials] Failed to load block_world.gdshader — falling back to StandardMaterial3D")
	return _shader


## Lazy-load the procedural uber-shader. Returns null if the file is missing.
static func _get_proc_shader() -> Shader:
	if _proc_shader == null:
		_proc_shader = load("res://assets/shaders/block_world_procedural.gdshader") as Shader
		if _proc_shader == null:
			push_warning("[BlockMaterials] Failed to load block_world_procedural.gdshader — falling back to base material")
	return _proc_shader

# Named palette — common materials across all game objects.
const PALETTE := {
	# Wood / organic
	"wood": Color(0.3, 0.2, 0.1),
	"wood_light": Color(0.5, 0.35, 0.15),
	"wood_dark": Color(0.2, 0.12, 0.06),
	"bark": Color(0.25, 0.15, 0.08),
	"rope": Color(0.35, 0.28, 0.15),
	"driftwood": Color(0.45, 0.40, 0.32),
	"seashell": Color(0.88, 0.85, 0.78),
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
	"chain_link": Color(0.533, 0.533, 0.533),
	"lamp_warm": Color(1.0, 0.95, 0.8),

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
	"glow_green": Color(0.0, 0.9, 0.3),
	"glow_pink": Color(1.0, 0.2, 0.7),
	"glow_orange": Color(1.0, 0.5, 0.0),

	# Power grid
	"power_red": Color(0.8, 0.15, 0.1),
	"power_green": Color(0.1, 0.8, 0.2),
	"wire_copper": Color(0.72, 0.45, 0.2),
	"transformer_gray": Color(0.45, 0.45, 0.5),
	"generator_yellow": Color(0.9, 0.75, 0.1),
	"house_beige": Color(0.85, 0.78, 0.65),
	"house_blue": Color(0.55, 0.65, 0.8),
	"light_pole": Color(0.35, 0.35, 0.35),

	# Cellular / organic
	"cell_membrane": Color(0.7, 0.85, 0.7, 0.8),
	"cell_nucleus": Color(0.3, 0.2, 0.5),
	"cell_cytoplasm": Color(0.75, 0.9, 0.75, 0.6),
	"cell_active": Color(0.2, 0.8, 0.3),
	"cell_dividing": Color(0.9, 0.7, 0.2),

	# Tree (Mother Tree palette)
	"bark_dark": Color(0.15, 0.08, 0.04),
	"leaf_canopy": Color(0.08, 0.28, 0.06),
	"leaf_bright": Color(0.18, 0.42, 0.12),
	"lantern_glow": Color(0.9, 0.7, 0.2),

	# Fallback / diagnostics
	"default": Color(0.5, 0.5, 0.5),
	"debug": Color(1.0, 0.0, 1.0),
	"error_pink": Color(1.0, 0.0, 0.5),
}

const ROUGHNESS := {
	"wood": 0.8,
	"wood_light": 0.75,
	"wood_dark": 0.85,
	"bark": 0.85,
	"rope": 0.9,
	"driftwood": 0.9,
	"seashell": 0.6,
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
	"cell_membrane": 0.3,
	"cell_nucleus": 0.6,
	"cell_cytoplasm": 0.2,
	"cell_active": 0.4,
	"cell_dividing": 0.5,
	"bark_dark": 0.9,
	"leaf_canopy": 0.7,
	"leaf_bright": 0.65,
	"lantern_glow": 0.4,
	"chain_link": 0.6,
	"lamp_warm": 0.3,
}


## Get or create a material by palette name.
## Returns ShaderMaterial (block_world.gdshader) for opaque blocks,
## StandardMaterial3D for transparent blocks or if the shader fails to load.
static func get_material(material_id: String) -> Material:
	if _cache.has(material_id):
		return _cache[material_id]

	var color: Color
	if palette_override.has(material_id):
		color = palette_override[material_id]
	elif PALETTE.has(material_id):
		color = PALETTE[material_id]
	else:
		color = palette_override.get("default", PALETTE["default"])
		push_warning("[BlockMaterials] Unknown material '%s', using default" % material_id)

	var rough: float = roughness_override.get(material_id, ROUGHNESS.get(material_id, 0.8))

	var mat: Material
	if color.a < 1.0:
		# Transparent — must use StandardMaterial3D for alpha blending
		var std := StandardMaterial3D.new()
		std.albedo_color = color
		std.roughness = rough
		std.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		std.render_priority = 1  # Draw after opaque geometry
		std.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED  # Prevent z-fighting with ground
		mat = std
	else:
		# Opaque — prefer ShaderMaterial with block_world shader
		var shader := _get_shader()
		if shader != null:
			var smat := ShaderMaterial.new()
			smat.shader = shader
			smat.set_shader_parameter("albedo_color", color)
			smat.set_shader_parameter("roughness", rough)
			if shader_param_injector.is_valid():
				shader_param_injector.call(material_id, smat)
			mat = smat
		else:
			# Shader unavailable — graceful fallback
			var std := StandardMaterial3D.new()
			std.albedo_color = color
			std.roughness = rough
			mat = std

	if material_post_processor.is_valid():
		mat = material_post_processor.call(material_id, mat)

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


## Get the Color for a palette material_id directly.
static func get_color(material_id: String) -> Color:
	if palette_override.has(material_id):
		return palette_override[material_id]
	return PALETTE.get(material_id, PALETTE["default"])


## Check if a material_id exists in the palette.
static func has_material(material_id: String) -> bool:
	return palette_override.has(material_id) or PALETTE.has(material_id)


## Get all palette keys (base + overrides merged).
static func get_palette_keys() -> PackedStringArray:
	var keys := PackedStringArray()
	for k in PALETTE:
		keys.append(k)
	for k in palette_override:
		if k not in PALETTE:
			keys.append(k)
	return keys


## Get or create a material with per-element shader parameter overrides.
## Builds a composite cache key from material_id + quantized params (0.05 step).
## If base material is not a ShaderMaterial (e.g. transparent), returns base unchanged.
static func get_material_with_overrides(material_id: String, params: Dictionary) -> Material:
	var key: String = _make_override_key(material_id, params)
	if _override_cache.has(key):
		return _override_cache[key]

	var base: Material = get_material(material_id)
	if not (base is ShaderMaterial):
		# Transparent or fallback — cannot override shader params
		return base

	var mat: ShaderMaterial = (base as ShaderMaterial).duplicate() as ShaderMaterial
	for param_name: String in params:
		mat.set_shader_parameter(param_name, params[param_name])

	if _override_cache.size() >= 200:
		push_warning("[BlockMaterials] Override cache at 200+ entries — consider clearing on zone unload")

	_override_cache[key] = mat
	return mat


## Get or create a material with a color tint applied.
## Pre-multiplies the palette color by the tint and sets the tint_color uniform.
## If base material is not a ShaderMaterial, returns base unchanged.
static func get_material_tinted(material_id: String, tint: Color) -> Material:
	var key: String = "%s|tint_%s" % [material_id, tint.to_html(false)]
	if _override_cache.has(key):
		return _override_cache[key]

	var base: Material = get_material(material_id)
	if not (base is ShaderMaterial):
		return base

	var mat: ShaderMaterial = (base as ShaderMaterial).duplicate() as ShaderMaterial
	mat.set_shader_parameter("tint_color", tint)
	# Also pre-multiply albedo_color so the base color is correct even without the tint uniform
	mat.set_shader_parameter("albedo_color", get_color(material_id) * tint)

	if _override_cache.size() >= 200:
		push_warning("[BlockMaterials] Override cache at 200+ entries — consider clearing on zone unload")

	_override_cache[key] = mat
	return mat


## Build a composite cache key for material_id + parameter overrides.
## Floats are quantized to 0.05 increments to prevent unbounded cache growth.
## Keys are sorted for determinism.
static func _make_override_key(material_id: String, params: Dictionary) -> String:
	var parts: Array[String] = [material_id]
	var sorted_keys: Array = params.keys()
	sorted_keys.sort()
	for k: String in sorted_keys:
		var v = params[k]
		if v is float or v is int:
			# Quantize to 0.05 step
			var qv: float = roundf(float(v) / 0.05) * 0.05
			parts.append("%s=%.4f" % [k, qv])
		elif v is Color:
			parts.append("%s=%s" % [k, (v as Color).to_html(false)])
		else:
			parts.append("%s=%s" % [k, str(v)])
	return "|".join(parts)


## Get or create a procedural ShaderMaterial for the given material_type + palette key.
## Uses the block_world_procedural.gdshader uber-shader with material_type int uniform.
## Cache key: "proc|{material_type}|{palette_key}" — stored in _override_cache so it
## is evicted on zone unload along with other per-element instances.
## Falls back to get_material(palette_key) if the shader cannot be loaded.
static func get_procedural_material(material_type: String, palette_key: String) -> Material:
	var key: String = "proc|%s|%s" % [material_type, palette_key]
	if _override_cache.has(key):
		return _override_cache[key]

	var shader: Shader = _get_proc_shader()
	if shader == null:
		# Shader unavailable (e.g. headless test) — fallback to base palette
		return get_material(palette_key)

	var type_int: int = int(MATERIAL_TYPE_MAP.get(material_type, 0))
	var color: Color = get_color(palette_key)
	var rough: float = roughness_override.get(palette_key, ROUGHNESS.get(palette_key, 0.8))

	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("material_type", type_int)
	mat.set_shader_parameter("albedo_color", color)
	mat.set_shader_parameter("roughness", rough)
	mat.set_shader_parameter("tint_color", Color.WHITE)
	if shader_param_injector.is_valid():
		shader_param_injector.call(palette_key, mat)

	var final_mat: Material = mat
	if material_post_processor.is_valid():
		final_mat = material_post_processor.call(palette_key, mat)

	if _override_cache.size() >= 200:
		push_warning("[BlockMaterials] Override cache at 200+ entries — consider clearing on zone unload")

	_override_cache[key] = final_mat
	return final_mat


## Clear only the override cache (called from zone unload to evict per-element instances).
## Keeps base palette cache intact.
static func clear_override_cache() -> void:
	_override_cache.clear()


## Pre-warm all procedural shader variants by creating invisible meshes.
## Forces GPU to compile the uber-shader before gameplay — prevents Quest 2 stutter.
## Call during zone load, before zone geometry becomes visible.
static func prewarm_procedural_shaders(parent: Node3D) -> void:
	var shader: Shader = _get_proc_shader()
	if shader == null:
		return
	var box := BoxMesh.new()
	box.size = Vector3(0.01, 0.01, 0.01)
	for type_key: String in MATERIAL_TYPE_MAP.keys():
		var mat: Material = get_procedural_material(type_key, "default")
		var mi := MeshInstance3D.new()
		mi.mesh = box
		mi.material_override = mat
		mi.visible = false
		parent.add_child(mi)
		mi.queue_free()  # Freed after one frame — shader is compiled by then


## Clear the cache (useful for testing).
static func clear_cache() -> void:
	_cache.clear()
	_override_cache.clear()
