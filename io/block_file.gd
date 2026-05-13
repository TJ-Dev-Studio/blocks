class_name BlockFile
## Loads block definitions from unified `world-node-v1` JSON files.
##
## Every JSON on disk under `assets/world/` uses the unified schema:
##
##     {
##       "$schema": "world-node-v1",
##       "type":    "element" | "assembly",
##       "id":      "...",
##       "name":    "...",
##       "tags":    [...],
##       "properties": {
##         "category":   "structure" | "prop" | ...,
##         "collision":  { shape, size, interaction, layer, server_collidable, offset },
##         "visual":     { material, mesh_type, mesh, scene_path, mesh_size,
##                         color, cast_shadow, roughness, metallic, bump_scale,
##                         noise: { strength, scale }, material_type, materials,
##                         noise_strength, noise_scale, shader_path },
##         "audio":      { material },
##         "blend":      { blend_group, blend_mode },
##         "placement":  { position, rotation_y, scale_factor },
##         "lod":        { min_size, dna },
##         "neuron":     { ... },
##         "light":      { type, color, energy, range, group, shadow, spot_angle },
##         "validators": [ ... ]
##       },
##       "children": [          // assemblies only
##         {
##           "ref": "category/name",   // element ref (no .json)
##           "id":  "...",              // unique per-placement handle
##           "position":   [x,y,z],
##           "rotation_y": <deg>,       // unified: degrees
##           "scale_factor": 1.0,
##           "overrides":  { "collision.size": [...], ... },
##           "blend":      { blend_group, blend_mode },
##           "light":      { ... },
##           "pattern":    { ... },     // BlockPatternExpander config
##           "child_overrides":  { ... },
##           "extra_children":   [ ... ],
##           "deleted_children": [ ... ]
##         }
##       ]
##     }
##
## There is no legacy schema support. A non-unified file is a hard error.

const SHAPE_MAP := {
	"box": BlockCategories.SHAPE_BOX,
	"cylinder": BlockCategories.SHAPE_CYLINDER,
	"capsule": BlockCategories.SHAPE_CAPSULE,
	"sphere": BlockCategories.SHAPE_SPHERE,
	"ramp": BlockCategories.SHAPE_RAMP,
	"dome": BlockCategories.SHAPE_DOME,
	"none": BlockCategories.SHAPE_NONE,
	"cone": BlockCategories.SHAPE_CONE,
	"torus": BlockCategories.SHAPE_TORUS,
	"arch": BlockCategories.SHAPE_ARCH,
	"wedge": BlockCategories.SHAPE_RAMP,
	"rock": BlockCategories.SHAPE_ROCK,
}

const INTERACT_MAP := {
	"solid": BlockCategories.INTERACT_SOLID,
	"walkable": BlockCategories.INTERACT_WALKABLE,
	"climbable": BlockCategories.INTERACT_CLIMBABLE,
	"trigger": BlockCategories.INTERACT_TRIGGER,
	"destructible": BlockCategories.INTERACT_DESTRUCTIBLE,
	"water": BlockCategories.INTERACT_WATER,
	"one_way": BlockCategories.INTERACT_ONE_WAY,
	"bridge": BlockCategories.INTERACT_BRIDGE,
	"none": BlockCategories.INTERACT_NONE,
}

const CATEGORY_MAP := {
	"terrain": BlockCategories.TERRAIN,
	"prop": BlockCategories.PROP,
	"structure": BlockCategories.STRUCTURE,
	"creature": BlockCategories.CREATURE,
	"effect": BlockCategories.EFFECT,
	"trigger": BlockCategories.TRIGGER_CAT,
	"furnishing": BlockCategories.FURNISHING,
	"tree": BlockCategories.TREE_CAT,
}

const LAYER_MAP := {
	"WORLD": CollisionLayers.WORLD,
	"PLATFORM": CollisionLayers.PLATFORM,
	"TRUNK": CollisionLayers.TRUNK,
	"BRIDGE": CollisionLayers.BRIDGE,
	"PLAYER": CollisionLayers.PLAYER,
	"NPC": CollisionLayers.NPC,
	"WATER": CollisionLayers.WATER,
	"TRIGGER": CollisionLayers.TRIGGER,
	"ONEWAY": CollisionLayers.ONEWAY,
}


## Load and parse a unified `world-node-v1` JSON file. Returns the parsed
## Dictionary as-is (the unified shape — top-level `id`/`name`/`tags`/
## `properties`/`children`). Returns empty dict on failure.
##
## In editor / dev builds we read via the OS path (ProjectSettings.globalize_
## path) to bypass Godot's resource-system cache — the Studio hot-reload path
## needs each parse to see current bytes on disk, not a snapshot from
## game-launch time. Falls back to the original path for packaged builds
## where files live inside the .pck archive.
static func load_file(path: String) -> Dictionary:
	var disk_path: String = path
	if path.begins_with("res://"):
		disk_path = ProjectSettings.globalize_path(path)
	var file := FileAccess.open(disk_path, FileAccess.READ)
	if not file:
		# Fall back to res:// for packaged builds where globalize fails.
		file = FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("[BlockFile] Cannot open file: %s" % path)
		return {}

	var text := file.get_as_text()
	file.close()

	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		push_error("[BlockFile] JSON parse error in %s line %d: %s" % [
			path, json.get_error_line(), json.get_error_message()])
		return {}

	var data: Dictionary = json.data
	if str(data.get("$schema", "")) != "world-node-v1":
		push_error("[BlockFile] Not a unified world-node-v1 file: %s" % path)
		return {}
	var type_str: String = str(data.get("type", ""))
	if type_str != "element" and type_str != "assembly":
		push_error("[BlockFile] Expected type 'element' or 'assembly' in %s (got '%s')" % [
			path, type_str])
		return {}

	return data


## Convert a unified element block JSON dict into a Block instance.
static func file_to_block(data: Dictionary) -> Block:
	var block := Block.new()
	var props: Dictionary = data.get("properties", {}) as Dictionary

	# Identity
	block.block_name = str(data.get("name", data.get("id", "")))
	block.category = CATEGORY_MAP.get(str(props.get("category", "prop")),
			BlockCategories.PROP)
	block.tags = PackedStringArray(data.get("tags", []))

	# Collision
	var collision: Dictionary = props.get("collision", {}) as Dictionary
	block.collision_shape = SHAPE_MAP.get(str(collision.get("shape", "box")),
			BlockCategories.SHAPE_BOX)
	block.collision_size = _arr_to_vec3(collision.get("size", [1, 1, 1]))
	block.collision_offset = _arr_to_vec3(collision.get("offset", [0, 0, 0]))
	block.interaction = INTERACT_MAP.get(str(collision.get("interaction", "solid")),
			BlockCategories.INTERACT_SOLID)
	block.collision_layer = LAYER_MAP.get(str(collision.get("layer", "WORLD")),
			CollisionLayers.WORLD)
	block.server_collidable = bool(collision.get("server_collidable", true))

	# Visual
	var visual: Dictionary = props.get("visual", {}) as Dictionary
	var mesh_type_str: String = str(visual.get("mesh_type", "primitive"))
	match mesh_type_str:
		"scene":
			block.mesh_type = 1
		"glb":
			block.mesh_type = 2
			block.scene_path = str(visual.get("mesh", ""))
		_:
			block.mesh_type = 0
	block.material_id = str(visual.get("material", "default"))
	block.mesh_size = _arr_to_vec3(visual.get("mesh_size", [0, 0, 0]))
	block.shader_path = str(visual.get("shader_path", ""))
	var explicit_scene_path: String = str(visual.get("scene_path", ""))
	if not explicit_scene_path.is_empty():
		block.scene_path = explicit_scene_path
	elif block.mesh_type != 2:
		block.scene_path = ""
	block.cast_shadow = bool(visual.get("cast_shadow", false))

	var color_arr: Array = visual.get("color", []) as Array
	if color_arr.size() >= 3:
		block.color_tint = Color(float(color_arr[0]), float(color_arr[1]), float(color_arr[2]))
		if color_arr.size() >= 4:
			block.color_tint.a = float(color_arr[3])

	var mat_params := {}
	if visual.has("roughness"):
		mat_params["roughness"] = float(visual["roughness"])
	if visual.has("metallic"):
		mat_params["metallic"] = float(visual["metallic"])
	if visual.has("bump_scale"):
		mat_params["surface_noise_strength"] = float(visual["bump_scale"])
	if visual.has("noise_scale"):
		mat_params["surface_noise_scale"] = float(visual["noise_scale"])
	var noise_data: Dictionary = visual.get("noise", {}) as Dictionary
	if not noise_data.is_empty():
		block.noise_strength = float(noise_data.get("strength", 0.0))
		block.noise_scale = float(noise_data.get("scale", 3.0))
		mat_params["surface_noise_scale"] = block.noise_scale
		mat_params["surface_noise_strength"] = block.noise_strength
	if not mat_params.is_empty():
		block.material_params = mat_params

	block.material_type_id = str(visual.get("material_type", ""))
	var materials_arr: Array = visual.get("materials", []) as Array
	if not materials_arr.is_empty():
		block.materials_list = materials_arr

	# Audio
	var audio_data: Dictionary = props.get("audio", {}) as Dictionary
	if not audio_data.is_empty():
		block.audio_material = str(audio_data.get("material", ""))

	# Blend (SDF group membership)
	var blend_data: Dictionary = props.get("blend", {}) as Dictionary
	var blend_group: String = str(blend_data.get("blend_group", ""))
	if not blend_group.is_empty():
		block.state["_blend_group"] = blend_group
		block.state["_blend_mode"] = str(blend_data.get("blend_mode", "union"))

	# Placement defaults — rare on elements but supported. ALL rotation
	# fields in the unified schema are DEGREES; convert to radians here
	# since block.rotation_y is consumed as radians (Godot's rotation.y).
	var placement: Dictionary = props.get("placement", {}) as Dictionary
	block.position = _arr_to_vec3(placement.get("position", [0, 0, 0]))
	block.rotation_y = deg_to_rad(float(placement.get("rotation_y", 0.0)))
	block.scale_factor = float(placement.get("scale_factor", 1.0))

	# LOD / Cellular
	var lod: Dictionary = props.get("lod", {}) as Dictionary
	block.min_size = _arr_to_vec3(lod.get("min_size", [0.1, 0.1, 0.1]))
	block.dna = lod.get("dna", {}) as Dictionary

	# Neuron
	var neuron_data: Dictionary = props.get("neuron", {}) as Dictionary
	if not neuron_data.is_empty():
		var neuron := BlockNeuron.new()
		neuron.init_from_file(neuron_data, block.block_id)
		block.neuron = neuron

	# Light
	var light_data: Dictionary = props.get("light", {}) as Dictionary
	if not light_data.is_empty():
		var lc := {}
		lc["type"] = str(light_data.get("type", "omni"))
		var light_color_arr: Array = light_data.get("color", []) as Array
		if light_color_arr.size() >= 3:
			lc["color"] = Color(float(light_color_arr[0]),
				float(light_color_arr[1]), float(light_color_arr[2]))
		lc["energy"] = float(light_data.get("energy", 1.0))
		lc["range"] = float(light_data.get("range", 4.0))
		lc["group"] = str(light_data.get("group", "steady"))
		lc["shadow"] = bool(light_data.get("shadow", false))
		if light_data.has("spot_angle"):
			lc["spot_angle"] = float(light_data["spot_angle"])
		block.light_config = lc

	# Validators (placement rules from JSON)
	var validators: Array = props.get("validators", []) as Array
	for v in validators:
		var rule_name: String = ""
		var params: Dictionary = {}
		if v is String:
			rule_name = v
		elif v is Dictionary:
			rule_name = str(v.get("type", ""))
			params = v.get("params", {}) as Dictionary
		if not rule_name.is_empty():
			var rule = BlockPlacementRule.create(rule_name, params)
			if rule:
				block.placement_rules.append(rule)

	# Source tracking (set externally via _source_path stamp on dict)
	block.source_file = str(data.get("_source_path", ""))

	return block


## Convert a unified assembly JSON dict into a list of Blocks with
## parent-child links.
##
## - `element_resolver`: Callable(ref: String) -> Dictionary that resolves
##   a child `ref` to its parsed element JSON Dict.
## - `child_overrides`: per-placement override map keyed by child id. Each
##   entry can carry `placement.{position, rotation_y, scale_factor}` and
##   `overrides` (dot-syntax keys). Applied AFTER the assembly's own
##   defaults so a structure that places this assembly can shift one child
##   without mutating the shared assembly file. Empty = no overrides.
## - `extra_children`: per-placement extra child entries appended to the
##   assembly's authored `children[]` AT LOAD TIME. Each entry has the
##   same shape as an authored child; gets a child_def_idx of
##   `original_count + i`.
## - `deleted_children`: per-placement DELETION markers. Each entry is a
##   Dictionary with `ref` / `id` / `position` keys. Children matching any
##   marker are SKIPPED during build. Per-placement: only THIS placement
##   loses that child — other placements of the same assembly file render
##   normally.
static func file_to_assembly(data: Dictionary, element_resolver: Callable,
		child_overrides: Dictionary = {}, extra_children: Array = [],
		deleted_children: Array = []) -> Array[Block]:
	var blocks: Array[Block] = []
	var props: Dictionary = data.get("properties", {}) as Dictionary

	# Assembly root block (no visual, just a container).
	var root := Block.new()
	root.block_name = str(data.get("name", data.get("id", "assembly")))
	root.category = CATEGORY_MAP.get(str(props.get("category", "structure")),
			BlockCategories.STRUCTURE)
	root.tags = PackedStringArray(data.get("tags", []))
	root.collision_shape = BlockCategories.SHAPE_NONE
	root.server_collidable = false
	root.ensure_id()

	# Assembly-level neuron.
	var neuron_data: Dictionary = props.get("neuron", {}) as Dictionary
	if not neuron_data.is_empty():
		var neuron := BlockNeuron.new()
		neuron.init_from_file(neuron_data, root.block_id)
		root.neuron = neuron

	# World position from neuron options (legacy assemblies could embed
	# their world position in the neuron config — preserved for compat).
	var world_pos := Vector3.ZERO
	if neuron_data.has("options") and neuron_data["options"] is Dictionary \
			and (neuron_data["options"] as Dictionary).has("world_position"):
		world_pos = _arr_to_vec3((neuron_data["options"] as Dictionary)["world_position"])
	root.position = world_pos
	root.source_file = str(data.get("_source_path", ""))

	blocks.append(root)

	# Iterate authored children + appended extras. Track child_def_idx so
	# per-instance overrides can target a specific child by index AND by
	# name. extras get idx >= original_count and are stamped on each block
	# as `assembly_child_def_index` — stable across reloads of the same
	# placement because the authored children[] never shifts.
	var children: Array = data.get("children", []) as Array
	var extras: Array = extra_children if extra_children is Array else []
	var combined_count: int = children.size() + extras.size()
	var has_per_instance_overrides: bool = not child_overrides.is_empty()

	for child_def_idx in combined_count:
		var is_extra: bool = child_def_idx >= children.size()
		var child_def: Dictionary
		if is_extra:
			var src = extras[child_def_idx - children.size()]
			if not src is Dictionary:
				push_warning("[BlockFile] extra_children[%d] is not a Dictionary in %s — skipping" % [
					child_def_idx - children.size(), root.block_name])
				continue
			child_def = src as Dictionary
		else:
			child_def = children[child_def_idx] as Dictionary

		# Pattern expansion: one JSON entry → many positioned children.
		var expanded: Array = []
		var is_pattern: bool = child_def.has("pattern")
		if is_pattern:
			expanded = BlockPatternExpander.expand(child_def)
			if expanded.is_empty():
				push_warning("[BlockFile] Pattern expansion produced 0 children for '%s' in %s"
					% [str(child_def.get("ref", "?")), root.block_name])
				continue
		else:
			expanded = [child_def]

		# Per-instance override lookup. Pattern-expanded children can't carry
		# per-instance overrides (one JSON entry → many positioned blocks
		# means keying is ambiguous), so they skip the override pass with a
		# warning if anyone tries.
		var per_instance: Dictionary = {}
		var child_id_key: String = str(child_def.get("id", ""))
		if has_per_instance_overrides:
			if is_pattern:
				if child_overrides.has(str(child_def_idx)) or child_overrides.has(child_id_key):
					push_warning("[BlockFile] Pattern-expanded child #%d (ref='%s') in '%s' carries a per-instance override but pattern children are not overridable. Override will be ignored." % [
						child_def_idx, str(child_def.get("ref", "?")), root.block_name])
			else:
				# Prefer name-keyed lookup (id), fall back to index-keyed.
				if not child_id_key.is_empty() and child_overrides.has(child_id_key):
					per_instance = child_overrides[child_id_key] as Dictionary
				else:
					per_instance = child_overrides.get(str(child_def_idx), {}) as Dictionary

		for effective_child: Dictionary in expanded:
			var element_ref: String = str(effective_child.get("ref", ""))
			if element_ref.is_empty():
				push_warning("[BlockFile] Assembly child missing 'ref' in %s" % root.block_name)
				continue

			# Per-placement deletion: skip this child if a marker matches.
			# Markers carry `ref` (element ref) + `id` (child handle) and/or
			# `position`. Match rules in _child_is_deleted().
			if not deleted_children.is_empty() \
					and _child_is_deleted(effective_child, element_ref, deleted_children):
				continue

			var element_data: Dictionary = element_resolver.call(element_ref)
			if element_data.is_empty():
				push_warning("[BlockFile] Could not resolve element ref '%s'" % element_ref)
				continue

			var child_block := file_to_block(element_data)

			# Apply the child entry's transform (flat at unified-child level).
			# Rotation is in DEGREES per unified spec; convert to radians.
			if effective_child.has("position"):
				child_block.position = world_pos + _arr_to_vec3(effective_child["position"])
			else:
				child_block.position = child_block.position + world_pos
			if effective_child.has("rotation_y"):
				child_block.rotation_y = deg_to_rad(float(effective_child["rotation_y"]))
			if effective_child.has("scale_factor"):
				child_block.scale_factor = float(effective_child["scale_factor"])

			# Override layer from the child entry's `overrides` dict.
			var overrides: Dictionary = effective_child.get("overrides", {}) as Dictionary
			if not overrides.is_empty():
				apply_overrides(child_block, overrides)

			# Blend override (assembly child can override the element's
			# blend declaration).
			var child_blend: Dictionary = effective_child.get("blend", {}) as Dictionary
			var child_blend_group: String = str(child_blend.get("blend_group", ""))
			if not child_blend_group.is_empty():
				child_block.state["_blend_group"] = child_blend_group
				child_block.state["_blend_mode"] = str(child_blend.get("blend_mode", "union"))

			# Light override.
			var child_light: Dictionary = effective_child.get("light", {}) as Dictionary
			if not child_light.is_empty():
				var lc := {}
				lc["type"] = str(child_light.get("type", "omni"))
				var lc_color_arr: Array = child_light.get("color", []) as Array
				if lc_color_arr.size() >= 3:
					lc["color"] = Color(float(lc_color_arr[0]),
						float(lc_color_arr[1]), float(lc_color_arr[2]))
				lc["energy"] = float(child_light.get("energy", 1.0))
				lc["range"] = float(child_light.get("range", 4.0))
				lc["group"] = str(child_light.get("group", "steady"))
				lc["shadow"] = bool(child_light.get("shadow", false))
				child_block.light_config = lc

			# Per-instance override layer (applied AFTER the assembly's own
			# defaults so the parent structure can shift / re-tint / rotate
			# THIS child without touching the shared assembly file).
			#
			# Same shape as a child entry: flat `position` / `rotation_y` /
			# `scale_factor` at the per_instance level. All rotations are
			# DEGREES per unified spec.
			if not per_instance.is_empty():
				if per_instance.has("position"):
					child_block.position = world_pos + _arr_to_vec3(per_instance["position"])
				if per_instance.has("rotation_y"):
					child_block.rotation_y = deg_to_rad(float(per_instance["rotation_y"]))
				if per_instance.has("scale_factor"):
					child_block.scale_factor = float(per_instance["scale_factor"])
				var pi_overrides: Dictionary = per_instance.get("overrides", {}) as Dictionary
				if not pi_overrides.is_empty():
					apply_overrides(child_block, pi_overrides)

			child_block.ensure_id()
			child_block.parent_id = root.block_id
			root.add_child_link(child_block.block_id)
			# Stamp the JSON child def index on the Block resource so the
			# Studio's save path can locate the correct override slot.
			child_block.set_meta("assembly_child_def_index", child_def_idx)
			blocks.append(child_block)

	return blocks


## Apply dot-path overrides to a block. The override key syntax is
## `<section>.<prop>` (e.g. `collision.size`, `visual.material`) or a
## bare `<prop>` for the few top-level fields on Block.
static func apply_overrides(block: Block, overrides: Dictionary) -> void:
	for key: String in overrides:
		var value = overrides[key]
		var parts := key.split(".")
		if parts.size() == 1:
			_set_block_property(block, parts[0], value)
		elif parts.size() == 2:
			_set_block_dotted(block, parts[0], parts[1], value)


## Resolve an element_ref to the actual element file path on disk.
## The unified asset tree uses bare `.json` extensions.
## ref format: "tree/trunk_small" → "<base>/tree/trunk_small.json"
static func resolve_element_path(ref: String, search_paths: PackedStringArray) -> String:
	var filename := ref + ".json"
	for base_path in search_paths:
		var full_path := base_path.path_join(filename)
		if FileAccess.file_exists(full_path):
			return full_path
	return ""


# =========================================================================
# Helpers
# =========================================================================


## Convert a JSON array [x, y, z] to Vector3.
static func _arr_to_vec3(arr) -> Vector3:
	if arr is Array and arr.size() >= 3:
		return Vector3(float(arr[0]), float(arr[1]), float(arr[2]))
	return Vector3.ZERO


## True if `child_def` matches any marker in `deleted_children`.
## Markers carry `ref` / `id` and/or `position`. Match rules:
##   - `id` match wins (most reliable across pattern shifts)
##   - else `ref` must equal child's ref AND position within 1mm
##   - else `ref` alone with no position is a wildcard delete of every
##     placement of that ref (rare; explicit position is the default)
static func _child_is_deleted(child_def: Dictionary, child_ref: String,
		deleted_children: Array) -> bool:
	var child_id: String = str(child_def.get("id", ""))
	var child_pos: Array = child_def.get("position", []) as Array
	for marker_v in deleted_children:
		if not marker_v is Dictionary:
			continue
		var marker: Dictionary = marker_v
		# id match wins
		var marker_id: String = str(marker.get("id", ""))
		if not child_id.is_empty() and not marker_id.is_empty():
			if marker_id == child_id:
				return true
			continue
		# ref + position match
		var marker_ref: String = str(marker.get("ref", ""))
		if not marker_ref.is_empty() and marker_ref != child_ref:
			continue
		var marker_pos: Array = marker.get("position", []) as Array
		if marker_pos.size() == 3 and child_pos.size() == 3:
			var matched: bool = true
			for i in 3:
				if abs(float(marker_pos[i]) - float(child_pos[i])) > 0.001:
					matched = false
					break
			if matched:
				return true
		elif marker_pos.is_empty() and not marker_ref.is_empty():
			# Wildcard: marker has ref but no position → match all
			# placements of that ref.
			return true
	return false


## Set a direct block property from a string key (top-level overrides).
static func _set_block_property(block: Block, prop: String, value) -> void:
	match prop:
		"block_name", "name":
			block.block_name = str(value)
		"category":
			block.category = CATEGORY_MAP.get(str(value), block.category)
		"material_id":
			block.material_id = str(value)
		"collision_shape", "shape":
			block.collision_shape = SHAPE_MAP.get(str(value), block.collision_shape)
		"collision_size":
			block.collision_size = _arr_to_vec3(value)
		"collision_layer", "layer":
			block.collision_layer = LAYER_MAP.get(str(value), block.collision_layer)
		"interaction":
			block.interaction = INTERACT_MAP.get(str(value), block.interaction)
		"server_collidable":
			block.server_collidable = bool(value)
		"cast_shadow":
			block.cast_shadow = bool(value)
		"scale_factor":
			block.scale_factor = float(value)
		"rotation_y":
			# Override values are DEGREES per the unified convention.
			block.rotation_y = deg_to_rad(float(value))
		_:
			push_warning("[BlockFile] Unknown direct property override: %s" % prop)


## Set a dotted block property like "collision.size" or "visual.material".
static func _set_block_dotted(block: Block, section: String, prop: String, value) -> void:
	match section:
		"identity":
			match prop:
				"name": block.block_name = str(value)
				"category": block.category = CATEGORY_MAP.get(str(value), block.category)
				"tags": block.tags = PackedStringArray(value if value is Array else [])
		"collision":
			match prop:
				"shape": block.collision_shape = SHAPE_MAP.get(str(value), block.collision_shape)
				"size": block.collision_size = _arr_to_vec3(value)
				"offset": block.collision_offset = _arr_to_vec3(value)
				"interaction": block.interaction = INTERACT_MAP.get(str(value), block.interaction)
				"layer": block.collision_layer = LAYER_MAP.get(str(value), block.collision_layer)
				"server_collidable": block.server_collidable = bool(value)
		"visual":
			match prop:
				"material": block.material_id = str(value)
				"mesh_size": block.mesh_size = _arr_to_vec3(value)
				"shader_path": block.shader_path = str(value)
				"scene_path": block.scene_path = str(value)
				"mesh":
					block.scene_path = str(value)
					if block.mesh_type == 0:
						block.mesh_type = 2
				"mesh_type":
					match str(value):
						"scene": block.mesh_type = 1
						"glb": block.mesh_type = 2
						_: block.mesh_type = 0
				"materials":
					block.materials_list = value if value is Array else []
				"cast_shadow": block.cast_shadow = bool(value)
				"noise_strength": block.noise_strength = float(value)
				"noise_scale":
					block.noise_scale = float(value)
					if block.material_params.is_empty():
						block.material_params = {}
					block.material_params["surface_noise_scale"] = float(value)
				"color":
					var arr: Array = value if value is Array else []
					if arr.size() >= 3:
						block.color_tint = Color(float(arr[0]), float(arr[1]), float(arr[2]))
						if arr.size() >= 4:
							block.color_tint.a = float(arr[3])
				"roughness":
					if block.material_params.is_empty():
						block.material_params = {}
					block.material_params["roughness"] = float(value)
				"metallic":
					if block.material_params.is_empty():
						block.material_params = {}
					block.material_params["metallic"] = float(value)
				"bump_scale":
					if block.material_params.is_empty():
						block.material_params = {}
					block.material_params["surface_noise_strength"] = float(value)
				"material_type": block.material_type_id = str(value)
		"placement":
			match prop:
				"position": block.position = _arr_to_vec3(value)
				"rotation_y": block.rotation_y = deg_to_rad(float(value))
				"scale_factor": block.scale_factor = float(value)
		"lod":
			match prop:
				"min_size": block.min_size = _arr_to_vec3(value)
				"dna": block.dna = value if value is Dictionary else {}
		"audio":
			match prop:
				"material": block.audio_material = str(value)
		"light":
			if block.light_config.is_empty():
				block.light_config = {}
			match prop:
				"type": block.light_config["type"] = str(value)
				"energy": block.light_config["energy"] = float(value)
				"range": block.light_config["range"] = float(value)
				"group": block.light_config["group"] = str(value)
				"shadow": block.light_config["shadow"] = bool(value)
				"color":
					var arr: Array = value if value is Array else []
					if arr.size() >= 3:
						block.light_config["color"] = Color(float(arr[0]), float(arr[1]), float(arr[2]))
		_:
			push_warning("[BlockFile] Unknown override section: %s.%s" % [section, prop])
