class_name BlockFile
## Loads block definitions from JSON block-files.
##
## Handles both "element" (single block) and "assembly" (composed block tree) types.
## Resolves element_ref paths, applies overrides, and returns Block instances
## ready for registration.

# String-to-constant maps for JSON deserialization.

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


## Load and parse a .block.json file. Returns the raw Dictionary.
## Returns empty dict on failure.
static func load_file(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("[BlockFile] Cannot open file: %s" % path)
		return {}

	var text := file.get_as_text()
	file.close()

	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		push_error("[BlockFile] JSON parse error in %s line %d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return {}

	var data: Dictionary = json.data
	if not data.has("format_version"):
		push_error("[BlockFile] Missing required field (format_version) in %s" % path)
		return {}

	return data


## Convert an element block-file dict into a Block instance.
static func file_to_block(data: Dictionary) -> Block:
	var block := Block.new()

	# Identity
	var identity: Dictionary = data.get("identity", {})
	block.block_name = identity.get("name", "")
	block.category = CATEGORY_MAP.get(identity.get("category", "prop"), BlockCategories.PROP)
	var tags_arr: Array = identity.get("tags", [])
	block.tags = PackedStringArray(tags_arr)

	# Collision
	var collision: Dictionary = data.get("collision", {})
	block.collision_shape = SHAPE_MAP.get(collision.get("shape", "box"), BlockCategories.SHAPE_BOX)
	block.collision_size = _arr_to_vec3(collision.get("size", [1, 1, 1]))
	block.collision_offset = _arr_to_vec3(collision.get("offset", [0, 0, 0]))
	block.interaction = INTERACT_MAP.get(collision.get("interaction", "solid"), BlockCategories.INTERACT_SOLID)
	block.collision_layer = LAYER_MAP.get(collision.get("layer", "WORLD"), CollisionLayers.WORLD)
	block.server_collidable = collision.get("server_collidable", true)

	# Visual
	var visual: Dictionary = data.get("visual", {})
	var mesh_type_str: String = visual.get("mesh_type", "primitive")
	match mesh_type_str:
		"scene":
			block.mesh_type = 1
		"glb":
			block.mesh_type = 2
			block.scene_path = visual.get("mesh", "")
		_:
			block.mesh_type = 0
	block.material_id = visual.get("material", "default")
	block.mesh_size = _arr_to_vec3(visual.get("mesh_size", [0, 0, 0]))
	block.shader_path = visual.get("shader_path", "")
	# scene_path: only overwrite if explicitly set in JSON and not already set by GLB mesh path
	var explicit_scene_path: String = visual.get("scene_path", "")
	if not explicit_scene_path.is_empty():
		block.scene_path = explicit_scene_path
	elif block.mesh_type != 2:
		block.scene_path = ""  # clear for non-GLB blocks
	block.cast_shadow = visual.get("cast_shadow", false)

	# Color tint
	var color_arr: Array = visual.get("color", [])
	if color_arr.size() >= 3:
		block.color_tint = Color(float(color_arr[0]), float(color_arr[1]), float(color_arr[2]))
		if color_arr.size() >= 4:
			block.color_tint.a = float(color_arr[3])

	# Material parameter overrides
	var mat_params := {}
	if visual.has("roughness"):
		mat_params["roughness"] = float(visual["roughness"])
	if visual.has("metallic"):
		mat_params["metallic"] = float(visual["metallic"])
	if visual.has("bump_scale"):
		mat_params["surface_noise_strength"] = float(visual["bump_scale"])
	if visual.has("noise_scale"):
		mat_params["surface_noise_scale"] = float(visual["noise_scale"])

	var noise_data: Dictionary = visual.get("noise", {})
	if not noise_data.is_empty():
		block.noise_strength = float(noise_data.get("strength", 0.0))
		block.noise_scale = float(noise_data.get("scale", 3.0))
		mat_params["surface_noise_scale"] = block.noise_scale
		mat_params["surface_noise_strength"] = block.noise_strength

	if not mat_params.is_empty():
		block.material_params = mat_params

	# Procedural material type
	block.material_type_id = visual.get("material_type", "")

	# Multi-material slots (GLB surface overrides)
	var materials_arr: Array = visual.get("materials", [])
	if not materials_arr.is_empty():
		block.materials_list = materials_arr

	# Blend (SDF group membership — may be overridden by assembly child def)
	var blend_data: Dictionary = data.get("blend", {})
	var blend_group: String = blend_data.get("blend_group", "")
	if not blend_group.is_empty():
		block.state["_blend_group"] = blend_group
		block.state["_blend_mode"] = blend_data.get("blend_mode", "union")

	# Placement
	var placement: Dictionary = data.get("placement", {})
	block.position = _arr_to_vec3(placement.get("position", [0, 0, 0]))
	block.rotation_y = placement.get("rotation_y", 0.0)
	block.scale_factor = placement.get("scale_factor", 1.0)

	# LOD / Cellular
	var lod: Dictionary = data.get("lod", {})
	block.min_size = _arr_to_vec3(lod.get("min_size", [0.1, 0.1, 0.1]))
	block.dna = lod.get("dna", {})

	# Neuron
	var neuron_data: Dictionary = data.get("neuron", {})
	if not neuron_data.is_empty():
		var neuron := BlockNeuron.new()
		neuron.init_from_file(neuron_data, block.block_id)
		block.neuron = neuron

	# Light
	var light_data: Dictionary = data.get("light", {})
	if not light_data.is_empty():
		var lc := {}
		lc["type"] = light_data.get("type", "omni")
		var light_color_arr: Array = light_data.get("color", [])
		if light_color_arr.size() >= 3:
			lc["color"] = Color(float(light_color_arr[0]), float(light_color_arr[1]), float(light_color_arr[2]))
		lc["energy"] = float(light_data.get("energy", 1.0))
		lc["range"] = float(light_data.get("range", 4.0))
		lc["group"] = light_data.get("group", "steady")
		lc["shadow"] = bool(light_data.get("shadow", false))
		if light_data.has("spot_angle"):
			lc["spot_angle"] = float(light_data["spot_angle"])
		block.light_config = lc

	# Validators (placement rules from JSON)
	var validators: Array = data.get("validators", [])
	for v in validators:
		var rule_name: String = ""
		var params: Dictionary = {}
		if v is String:
			rule_name = v
		elif v is Dictionary:
			rule_name = v.get("type", "")
			params = v.get("params", {})
		if not rule_name.is_empty():
			var rule = BlockPlacementRule.create(rule_name, params)
			if rule:
				block.placement_rules.append(rule)

	# Source tracking
	block.source_file = data.get("_source_path", "")

	return block


## Convert an assembly block-file dict into an array of Blocks with parent-child links.
## element_resolver: Callable(ref: String) -> Dictionary — resolves an element_ref
## to its parsed JSON data.
static func file_to_assembly(data: Dictionary, element_resolver: Callable) -> Array[Block]:
	var blocks: Array[Block] = []

	# Create assembly root block (no visual, just a container)
	var root := Block.new()
	var identity: Dictionary = data.get("identity", {})
	root.block_name = identity.get("name", "assembly")
	root.category = CATEGORY_MAP.get(identity.get("category", "structure"), BlockCategories.STRUCTURE)
	root.tags = PackedStringArray(identity.get("tags", []))
	root.collision_shape = BlockCategories.SHAPE_NONE
	root.server_collidable = false
	root.ensure_id()

	# Assembly-level neuron
	var neuron_data: Dictionary = data.get("neuron", {})
	if not neuron_data.is_empty():
		var neuron := BlockNeuron.new()
		neuron.init_from_file(neuron_data, root.block_id)
		root.neuron = neuron

	# World position from neuron options
	var world_pos := Vector3.ZERO
	if neuron_data.has("options") and neuron_data["options"].has("world_position"):
		world_pos = _arr_to_vec3(neuron_data["options"]["world_position"])
	root.position = world_pos
	root.source_file = data.get("_source_path", "")

	blocks.append(root)

	# Process children (with pattern expansion)
	var children: Array = data.get("children", [])
	for child_def: Dictionary in children:
		# Pattern expansion: one JSON entry → many positioned children
		var expanded: Array = []
		if child_def.has("pattern"):
			expanded = BlockPatternExpander.expand(child_def)
			if expanded.is_empty():
				push_warning("[BlockFile] Pattern expansion produced 0 children for '%s' in %s"
					% [child_def.get("element_ref", "?"), root.block_name])
				continue
		else:
			expanded = [child_def]

		for effective_child: Dictionary in expanded:
			var element_ref: String = effective_child.get("element_ref", "")
			if element_ref.is_empty():
				push_warning("[BlockFile] Assembly child missing element_ref in %s" % root.block_name)
				continue

			var element_data: Dictionary = element_resolver.call(element_ref)
			if element_data.is_empty():
				push_warning("[BlockFile] Could not resolve element_ref '%s'" % element_ref)
				continue

			var child_block := file_to_block(element_data)

			var child_placement: Dictionary = effective_child.get("placement", {})
			if child_placement.has("position"):
				child_block.position = world_pos + _arr_to_vec3(child_placement["position"])
			else:
				child_block.position = child_block.position + world_pos

			if child_placement.has("rotation_y"):
				child_block.rotation_y = child_placement["rotation_y"]
			if child_placement.has("scale_factor"):
				child_block.scale_factor = child_placement["scale_factor"]

			var overrides: Dictionary = effective_child.get("overrides", {})
			apply_overrides(child_block, overrides)

			# Assembly child can override the element's blend group declaration
			var child_blend: Dictionary = effective_child.get("blend", {})
			var child_blend_group: String = child_blend.get("blend_group", "")
			if not child_blend_group.is_empty():
				child_block.state["_blend_group"] = child_blend_group
				child_block.state["_blend_mode"] = child_blend.get("blend_mode", "union")

			# Assembly child can override the element's light config
			var child_light: Dictionary = effective_child.get("light", {})
			if not child_light.is_empty():
				var lc := {}
				lc["type"] = child_light.get("type", "omni")
				var lc_color_arr: Array = child_light.get("color", [])
				if lc_color_arr.size() >= 3:
					lc["color"] = Color(float(lc_color_arr[0]), float(lc_color_arr[1]), float(lc_color_arr[2]))
				lc["energy"] = float(child_light.get("energy", 1.0))
				lc["range"] = float(child_light.get("range", 4.0))
				lc["group"] = child_light.get("group", "steady")
				lc["shadow"] = bool(child_light.get("shadow", false))
				child_block.light_config = lc

			child_block.ensure_id()
			child_block.parent_id = root.block_id
			root.add_child_link(child_block.block_id)
			blocks.append(child_block)

	return blocks


## Apply dot-path overrides to a block.
## Example: {"collision.size": [2, 3, 1], "visual.material": "bark_dark"}
static func apply_overrides(block: Block, overrides: Dictionary) -> void:
	for key: String in overrides:
		var value = overrides[key]
		var parts := key.split(".")

		if parts.size() == 1:
			# Direct property override
			_set_block_property(block, parts[0], value)
		elif parts.size() == 2:
			# Dotted property like "collision.size"
			_set_block_dotted(block, parts[0], parts[1], value)


## Resolve an element_ref path to the actual .block.json file path.
## Searches through provided search paths in order.
static func resolve_element_path(ref: String, search_paths: PackedStringArray) -> String:
	# ref format: "tree/trunk_small" -> looks for "tree/trunk_small.block.json"
	var filename := ref + ".block.json"
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


## Set a direct block property from a string key.
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
			block.rotation_y = float(value)
		_:
			push_warning("[BlockFile] Unknown direct property override: %s" % prop)


## Set a dotted block property like "collision.size".
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
				"rotation_y": block.rotation_y = float(value)
				"scale_factor": block.scale_factor = float(value)
		"lod":
			match prop:
				"min_size": block.min_size = _arr_to_vec3(value)
				"dna": block.dna = value if value is Dictionary else {}
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
