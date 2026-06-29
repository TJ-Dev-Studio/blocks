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

## Shader file paths — INJECTED by the game (these live in the game, not the
## engine). Empty by default so the library stays headless/game-agnostic; when
## unset, get_material() falls back to StandardMaterial3D. A game registers its
## block_world + procedural shaders via register_materials() at startup.
static var shader_path: String = ""
static var proc_shader_path: String = ""

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

## Inject a game's material library into the (otherwise game-agnostic) engine.
## Call ONCE at startup, BEFORE any block is built (e.g. from a game style
## autoload). Every key is optional; the provided dictionaries are MERGED on top
## of the engine's generic defaults — the game wins on key conflicts. This is the
## seam that keeps the blocks library headless: all FrogMog art (palette tuning,
## texture paths, shaders) lives in the game and is registered here.
##   palette: {id -> Color}              roughness: {id -> float}
##   textured: {id -> texture_path}      triplanar / local_space: {id -> bool}
##   scale_overrides: {id -> float}      aspect_overrides: {id -> Vector2}
##   material_type_map: {type -> int}
##   shader_path / proc_shader_path: String (block world + procedural shaders)
static func register_materials(library: Dictionary) -> void:
	_merge_into(PALETTE, library.get("palette", {}))
	_merge_into(ROUGHNESS, library.get("roughness", {}))
	_merge_into(TEXTURED_MATERIALS, library.get("textured", {}))
	_merge_into(TEXTURED_USE_TRIPLANAR, library.get("triplanar", {}))
	_merge_into(TEXTURED_USE_LOCAL_SPACE, library.get("local_space", {}))
	_merge_into(TEXTURED_SCALE_OVERRIDES, library.get("scale_overrides", {}))
	_merge_into(TEXTURED_ASPECT_OVERRIDES, library.get("aspect_overrides", {}))
	_merge_into(MATERIAL_TYPE_MAP, library.get("material_type_map", {}))
	if library.has("shader_path"):
		shader_path = String(library["shader_path"])
	if library.has("proc_shader_path"):
		proc_shader_path = String(library["proc_shader_path"])
	# Drop any materials/shaders cached against a previous library (hot-reload safe).
	clear_caches()


## Merge src into dst in place (src values win). Helper for register_materials().
static func _merge_into(dst: Dictionary, src: Dictionary) -> void:
	for k in src:
		dst[k] = src[k]


## Clear ALL caches (base + override) and force shader reload. Called by
## register_materials() so a freshly-injected shader path takes effect.
static func clear_caches() -> void:
	_cache.clear()
	_override_cache.clear()
	_shader = null
	_proc_shader = null


## Maps material_type string to the int uniform value used in the uber-shader.
## 0 = flat (fallback), 1 = bark, 2 = stone, 3 = moss, 4 = water, 5 = wood.
## Generic default — a game may extend it via register_materials(material_type_map).
static var MATERIAL_TYPE_MAP: Dictionary = {
	"bark": 1,
	"stone": 2,
	"moss": 3,
	"water": 4,
	"wood": 5,
}

## Materials with hand-painted PNG textures: material_id → texture path. When a
## material is here, BOTH get_material() AND get_procedural_material() route
## through the textured shader path (use_albedo_texture=true), bypassing the
## procedural noise uber-shader.
## EMPTY in the headless library — texture paths are GAME assets, registered via
## register_materials(textured). (Was FrogMog bark/brick/bog_* paths.)
static var TEXTURED_MATERIALS: Dictionary = {}

## Per-material triplanar toggle (plain per-face UV vs world-position triplanar
## projection). Per-material OBJECT/LOCAL-space triplanar toggle (welds the
## texture to a MOVING mesh). Per-material tiling scale + U:V aspect overrides.
## ALL EMPTY in the headless library — these are GAME texture-art tuning,
## registered via register_materials(triplanar/local_space/scale_overrides/
## aspect_overrides). Defaults below apply to any material the game doesn't list.
static var TEXTURED_USE_TRIPLANAR: Dictionary = {}
static var TEXTURED_USE_LOCAL_SPACE: Dictionary = {}
const TEXTURED_DEFAULT_SCALE: float = 0.5
static var TEXTURED_SCALE_OVERRIDES: Dictionary = {}
const TEXTURED_DEFAULT_ASPECT: Vector2 = Vector2(1.0, 1.0)
static var TEXTURED_ASPECT_OVERRIDES: Dictionary = {}

## Lazy-load the game-registered block world shader. Returns null if no shader
## was registered (headless library) or the file is missing.
static func _get_shader() -> Shader:
	if _shader == null and not shader_path.is_empty():
		_shader = load(shader_path) as Shader
		if _shader == null:
			push_warning("[BlockMaterials] Failed to load block shader from '%s' — falling back to StandardMaterial3D" % shader_path)
	return _shader


## Lazy-load the game-registered procedural uber-shader. Returns null if no
## shader was registered (headless library) or the file is missing.
static func _get_proc_shader() -> Shader:
	if _proc_shader == null and not proc_shader_path.is_empty():
		_proc_shader = load(proc_shader_path) as Shader
		if _proc_shader == null:
			push_warning("[BlockMaterials] Failed to load procedural shader from '%s' — falling back to base material" % proc_shader_path)
	return _proc_shader

# Generic DEFAULT palette — the library's own demo/test materials (used by the
# car / power-grid / cellular test suites) plus diagnostics. NOT a game's art
# identity: a game registers its full production palette via register_materials()
# (merged on top), and per-map tweaks go through palette_override. FrogMog's
# earth-tone props (bog_*, house_*, leaf_canopy, dumpster, terrain, …) live in
# the game now, not here.
static var PALETTE := {
	# Wood / organic
	"wood": Color(0.3, 0.2, 0.1),
	"wood_light": Color(0.5, 0.35, 0.15),
	"wood_dark": Color(0.2, 0.12, 0.06),
	"bark": Color(0.25, 0.15, 0.08),
	"rope": Color(0.35, 0.28, 0.15),

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

	# Basic
	"white": Color(0.933, 0.933, 0.933),
	"black": Color(0.1, 0.1, 0.1),

	# Glass / transparent
	"glass": Color(0.667, 0.8, 0.933, 0.5),
	"water": Color(0.1, 0.3, 0.6, 0.7),

	# Effects
	"glow_yellow": Color(1.0, 0.9, 0.3),
	"glow_blue": Color(0.3, 0.5, 1.0),
	"glow_green": Color(0.0, 0.9, 0.3),
	"glow_pink": Color(1.0, 0.2, 0.7),
	"glow_orange": Color(1.0, 0.5, 0.0),

	# Power grid (demo suite)
	"power_red": Color(0.8, 0.15, 0.1),
	"power_green": Color(0.1, 0.8, 0.2),
	"wire_copper": Color(0.72, 0.45, 0.2),
	"transformer_gray": Color(0.45, 0.45, 0.5),
	"generator_yellow": Color(0.9, 0.75, 0.1),
	"light_pole": Color(0.35, 0.35, 0.35),

	# Cellular / organic (demo suite)
	"cell_membrane": Color(0.7, 0.85, 0.7, 0.8),
	"cell_nucleus": Color(0.3, 0.2, 0.5),
	"cell_cytoplasm": Color(0.75, 0.9, 0.75, 0.6),
	"cell_active": Color(0.2, 0.8, 0.3),
	"cell_dividing": Color(0.9, 0.7, 0.2),

	# Fallback / diagnostics
	"default": Color(0.5, 0.5, 0.5),
	"debug": Color(1.0, 0.0, 1.0),
	"error_pink": Color(1.0, 0.0, 0.5),
}

# Generic DEFAULT roughness — paired with the demo PALETTE above. A game
# registers its production roughness via register_materials(roughness).
static var ROUGHNESS := {
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
	"cell_membrane": 0.3,
	"cell_nucleus": 0.6,
	"cell_cytoplasm": 0.2,
	"cell_active": 0.4,
	"cell_dividing": 0.5,
}


## Get or create a material by palette name.
## Returns ShaderMaterial (block_world.gdshader) for opaque blocks,
## StandardMaterial3D for transparent blocks or if the shader fails to load.
static func get_material(material_id: String) -> Material:
	# Hand-painted PNG textures override the flat-color path entirely.
	# Covers blocks that don't set material_type_id (most blocks in the world).
	if TEXTURED_MATERIALS.has(material_id):
		return _get_textured_material(material_id, TEXTURED_MATERIALS[material_id])

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
		# Transparent — must use StandardMaterial3D for alpha blending.
		# V23 attempted TRANSPARENCY_ALPHA_HASH and ALPHA_DEPTH_PRE_PASS to
		# stabilize depth sorting on Nvidia, but both produce visible dithering
		# artifacts on the relatively-transparent glass (alpha=0.5) and water
		# (alpha=0.7) — worse than the original subtle sort flicker. Reverted
		# to the original TRANSPARENCY_ALPHA + render_priority + no-depth-write
		# config. Glass + water render smoothly; the residual depth-sort
		# flicker between adjacent transparent surfaces is a separate problem
		# that requires geometry-level or sorting-priority work, not a
		# material-level fix.
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

	# Tag with material_id so WorldCacheLoader can re-apply current block_style
	# after loading a zone .scn that has baked-in materials from a previous compile.
	# resource_name survives PackedScene packing and loading.
	mat.resource_name = material_id

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
	return palette_override.has(material_id) or PALETTE.has(material_id) or TEXTURED_MATERIALS.has(material_id)


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
	# If the requested effect type has a hand-painted PNG texture, route through
	# the textured shader path to avoid motion-aliased per-pixel noise.
	# Check material_type (the intended effect), NOT palette_key, so that
	# e.g. get_procedural_material("moss", "bark") correctly uses procedural
	# moss noise rather than being redirected to the bark texture.
	if TEXTURED_MATERIALS.has(material_type):
		return _get_textured_material(palette_key, TEXTURED_MATERIALS[material_type])

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


## Get or create a textured ShaderMaterial using block_world.gdshader with
## albedo_texture sampled from a hand-painted PNG (NOT procedural noise).
## Cache key: "tex|{palette_key}|{texture_path}" — stored in _override_cache.
## Falls back to get_material(palette_key) if shader or texture cannot be loaded.
static func _get_textured_material(palette_key: String, texture_path: String) -> Material:
	var key: String = "tex|%s|%s" % [palette_key, texture_path]
	if _override_cache.has(key):
		return _override_cache[key]

	var shader: Shader = _get_shader()
	if shader == null:
		# Bypass our own get_material() routing to avoid recursion
		return _make_color_material_uncached(palette_key)

	var tex: Texture2D = load(texture_path) as Texture2D
	if tex == null:
		push_warning("[BlockMaterials] Texture not found: %s — falling back to flat material" % texture_path)
		return _make_color_material_uncached(palette_key)

	var color: Color = get_color(palette_key)
	var rough: float = roughness_override.get(palette_key, ROUGHNESS.get(palette_key, 0.8))

	var smat := ShaderMaterial.new()
	smat.shader = shader
	# albedo_color stays for tinting compatibility, but block_world.gdshader
	# ignores it when use_albedo_texture=true (texture's authored color wins)
	smat.set_shader_parameter("albedo_color", color)
	smat.set_shader_parameter("roughness", rough)
	smat.set_shader_parameter("tint_color", Color.WHITE)
	smat.set_shader_parameter("use_albedo_texture", true)
	smat.set_shader_parameter("albedo_texture", tex)
	smat.set_shader_parameter("albedo_texture_scale",
			float(TEXTURED_SCALE_OVERRIDES.get(palette_key, TEXTURED_DEFAULT_SCALE)))
	smat.set_shader_parameter("albedo_uv_aspect",
			TEXTURED_ASPECT_OVERRIDES.get(palette_key, TEXTURED_DEFAULT_ASPECT) as Vector2)
	# Per-material triplanar toggle. False for cubic blocks (brick / stone /
	# parapet) where triplanar's 3-projection blend strobes pixel-by-pixel
	# under camera motion. True for organic meshes (bark on cylindrical
	# trunks, sphere canopies) where plain UV would stretch.
	smat.set_shader_parameter("use_triplanar_uv",
			bool(TEXTURED_USE_TRIPLANAR.get(palette_key, true)))
	# Object-space triplanar locks the texture to moving meshes (walking boss).
	smat.set_shader_parameter("use_local_space_triplanar",
			bool(TEXTURED_USE_LOCAL_SPACE.get(palette_key, false)))
	if shader_param_injector.is_valid():
		shader_param_injector.call(palette_key, smat)

	var final_mat: Material = smat
	if material_post_processor.is_valid():
		final_mat = material_post_processor.call(palette_key, smat)

	# Stamp resource_name so _reapply_materials_recursive() can identify and
	# replace this material after loading a cached .scn (resource_name survives
	# PackedScene serialization). Without this, all textured materials have
	# resource_name="" and the reapply pass silently skips them every time.
	final_mat.resource_name = palette_key

	_override_cache[key] = final_mat
	return final_mat


## Recursion-safe color fallback used by _get_textured_material when shader/texture
## load fails. Bypasses get_material()'s TEXTURED_MATERIALS check.
static func _make_color_material_uncached(material_id: String) -> Material:
	var color: Color = palette_override.get(material_id, PALETTE.get(material_id, PALETTE["default"]))
	var rough: float = roughness_override.get(material_id, ROUGHNESS.get(material_id, 0.8))
	var std := StandardMaterial3D.new()
	std.albedo_color = color
	std.roughness = rough
	if color.a < 1.0:
		std.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return std


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
		mi.queue_free()  # Freed after one frame 