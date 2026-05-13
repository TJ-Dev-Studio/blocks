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


## Load and parse a block/element/assembly JSON file. Returns the raw Dictionary
## in the LEGACY shape (with `format_version`, `identity`, top-level `collision`
## etc.) regardless of whether the file on disk uses the legacy `.block.json`
## schema or the unified `world-node-v1` schema. Returns empty dict on failure.
##
## Unified-schema files are detected by `$schema == "world-node-v1"` OR by the
## presence of `type` + `properties` (and absence of `block_type`). They get
## translated through `_unified_to_legacy_dict()` so the rest of this module
## (file_to_block, file_to_assembly, apply_overrides) keeps working unchanged.
## This is the bridge that lets the new `assets/world/` data tree drive the
## existing renderer without rewriting BlocksFactory.
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
		push_error("[BlockFile] JSON parse error in %s line %d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return {}

	var data: Dictionary = json.data
	# Unified schema detection: `world-node-v1` files use top-level `type` +
	# `properties`. Translate to the legacy shape so the rest of the module
	# operates on a single canonical form. The unified files don't carry
	# `format_version`, so detect FIRST then convert before the legacy check.
	if _is_unified_dict(data):
		data = _unified_to_legacy_dict(data)
	if not data.has("format_version"):
		push_error("[BlockFile] Missing required field (format_version) in %s" % path)
		return {}

	return data


## True when `data` looks like a unified-schema file (world-node-v1).
## Identified by `$schema == "world-node-v1"` OR by `type` + `properties`
## present together AND no `block_type` discriminator. Defensive: keeps
## legacy_block files from being mis-routed even if they happen to grow a
## `type` field in some future schema bump.
static func _is_unified_dict(data: Dictionary) -> bool:
	if data.has("block_type"):
		return false
	if str(data.get("$schema", "")) == "world-node-v1":
		return true
	return data.has("type") and data.has("properties")


## Translate a unified-schema dict into the legacy `.block.json` shape so
## file_to_block / file_to_assembly can consume it without modification.
##
## Element translation:
##   unified: { type, id, name, tags, properties: {category, description,
##               collision, visual, audio, blend, placement, lod, neuron,
##               light, validators} }
##   legacy:  { format_version, block_type, identity: {name, category, tags,
##               description}, collision, visual, audio, blend, placement,
##               lod, neuron, light, validators }
##
## Assembly translation: same identity translation as element, plus the
## children array is re-shaped from the unified flat form back to the
## legacy `element_ref` + `placement` wrapping. Per-child keys translated:
##   ref → element_ref
##   position / rotation_y / scale_factor → placement.{position, rotation_y, scale_factor}
##   overrides, blend, light, child_overrides, extra_children — passed through
##   identity.name carried over when `id` is present (used by save path for
##   stable child lookups).
static func _unified_to_legacy_dict(unified: Dictionary) -> Dictionary:
	var legacy := {}
	legacy["format_version"] = "1.0"
	var type_str := str(unified.get("type", ""))
	if type_str == "assembly":
		legacy["block_type"] = "assembly"
	else:
		legacy["block_type"] = "element"
	var props: Dictionary = unified.get("properties", {}) as Dictionary
	# Build the legacy identity block from top-level name/tags + props.category/description.
	var identity := {
		"name": str(unified.get("name", unified.get("id", ""))),
		"category": str(props.get("category", "prop")),
		"tags": (unified.get("tags", []) as Array).duplicate(),
		"description": str(props.get("description", "")),
	}
	legacy["identity"] = identity
	# Pull renderer-relevant subsections from properties up to top level.
	for key in ["collision", "visual", "audio", "blend", "placement", "lod",
			"neuron", "light", "validators"]:
		if props.has(key):
			legacy[key] = props[key]
	# Pass through any other top-level legacy fields the unified file may carry
	# verbatim (e.g. _source_path used internally by Studio hot-reload).
	for k in ["_source_path"]:
		if unified.has(k):
			legacy[k] = unified[k]
	# Assembly: re-shape each child via the shared normalizer so a unified
	# `ref + position + rotation_y` entry becomes a legacy
	# `element_ref + placement.{position, rotation_y}` entry. Same helper as
	# the per-child path in file_to_assembly, ensuring consistent behavior.
	if type_str == "assembly":
		var legacy_children: Array = []
		for raw in unified.get("children", []):
			if not raw is Dictionary:
				continue
			legacy_children.append(_normalize_child_to_legacy(raw as Dictionary))
		legacy["children"] = legacy_children
	return legacy


## Convert an element block-file dict into a Block instance.
##
## Accepts either schema:
##   - legacy `.block.json` shape (identity{}, top-level collision/visual/...)
##   - unified `world-node-v1` shape (top-level name/tags, properties{})
## A unified dict is auto-translated via _unified_to_legacy_dict so the rest
## of this function operates on a single canonical form. This means callers
## that bypass load_file() (e.g. tests, in-memory fixtures) still get the
## same behavior whether they pass unified or legacy data.
static func file_to_block(data: Dictionary) -> Block:
	if _is_unified_dict(data):
		data = _unified_to_legacy_dict(data)
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

	# Audio (per-block sound override)
	var audio_data: Dictionary = data.get("audio", {})
	if not audio_data.is_empty():
		block.audio_material = audio_data.get("material", "")

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
## child_overrides: optional per-instance override map keyed by stringified child
## index. Each entry can carry `placement.position`, `placement.rotation_y`, and
## `overrides` (dot-syntax keys). Applied AFTER the assembly's own defaults so
## the structure that placed this assembly can edit individual children without
## mutating the shared assembly JSON. Empty dict = no per-instance overrides.
## Pattern-expanded children are NOT overridable through this path (they share
## one source entry, so per-position keying is ambiguous).
##
## extra_children: optional per-placement extra child entries appended to the
## assembly's authored children[] AT LOAD TIME. Used by the design-studio COPY
## flow to add new instances at the structure scope without mutating the shared
## assembly JSON. Each extra carries the same shape as an authored child entry
## (element_ref + placement + overrides), gets a child_def_idx of
## original_count + i, and respects per-instance child_overrides keyed by its
## identity.name. Empty array = no extras (default; preserves existing behavior).
## `deleted_children` is a list of per-placement DELETION markers — each entry
## is `{element_ref: String, position: [x,y,z]}`. Children matching any marker
## (element_ref equal, position within 1mm) are SKIPPED during build. This is
## the per-instance delete primitive: deleting one floor tile in studio writes
## one marker to the parent structure's `assemblies[N].deleted_children`,
## and only THIS placement loses that child — other placements of the same
## assembly file render normally. Without this, deletes had to fall back to
## mutating the shared assembly JSON's `children[]`, which removed the child
## from EVERY placement world-wide (the "deleted one tile, all tiles gone"
## bug). Empty array = no deletions (default; preserves existing behavior).
static func file_to_assembly(data: Dictionary, element_resolver: Callable,
		child_overrides: Dictionary = {}, extra_children: Array = [],
		deleted_children: Array = []) -> Array[Block]:
	# Accept either schema. A unified dict (no `block_type`, has `properties`)
	# is translated to the legacy shape so the children-iteration logic below
	# can read `element_ref` + `placement.position` consistently regardless of
	# how the dict was originally authored. Defensive at this boundary because
	# callers (tests, in-memory fixtures, hot-reload paths) may bypass
	# load_file() and hand us raw JSON directly.
	if _is_unified_dict(data):
		data = _unified_to_legacy_dict(data)
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

	# Process children (with pattern expansion). We track the JSON child index
	# (`child_def_idx`) so each non-pattern child can opt into a per-instance
	# override layer keyed by that index.
	#
	# `extra_children` are appended to the iteration AFTER the authored
	# children. They get child_def_idx values starting at children.size(),
	# stamped on each block as `assembly_child_def_index`. This means a
	# structure-scoped COPY (which appends an entry to a placement's
	# extra_children) produces blocks with idx ≥ original_count — these
	# indices are STABLE across reloads of the same placement because the
	# authored children[] never shifts. The Studio save path's
	# `_find_persist_target` resolves these blocks back to the structure
	# JSON via identity.name (the universal stable handle).
	var children: Array = data.get("children", [])
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
			child_def = children[child_def_idx]
		# Per-child normalization: callers may hand us hybrid dicts that mix
		# unified keys (`ref`, flat `position`/`rotation_y`) with legacy keys
		# (`placement.*`). Normalize so the rest of this loop only reads the
		# legacy spelling. Idempotent on already-legacy entries.
		child_def = _normalize_child_to_legacy(child_def)
		# Pattern expansion: one JSON entry → many positioned children
		var expanded: Array = []
		var is_pattern: bool = child_def.has("pattern")
		if is_pattern:
			expanded = BlockPatternExpander.expand(child_def)
			if expanded.is_empty():
				push_warning("[BlockFile] Pattern expansion produced 0 children for '%s' in %s"
					% [child_def.get("element_ref", "?"), root.block_name])
				continue
		else:
			expanded = [child_def]

		# Per-instance override for this child (only valid for non-pattern children).
		# Pattern-expanded entries can produce many positioned blocks from one
		# JSON entry — keying by index/name is ambiguous, so this path skips them.
		#
		# Lookup priority for non-pattern children:
		#   1. by identity.name (stable across array reordering / sibling
		#      deletions — preferred for new saves)
		#   2. by str(child_def_idx) (legacy index-keyed format — kept for
		#      backward compat with structure JSONs written before name keying)
		#
		# Index-keyed entries are inherently brittle because deleting a
		# sibling shifts every later index by 1, silently re-pointing the
		# override at the wrong child. New writes go through editor_selection
		# which always emits name keys; this read tolerates both.
		var per_instance: Dictionary = {}
		var child_name_key: String = ""
		if not is_pattern:
			child_name_key = str(child_def.get("overrides", {}).get("identity.name", ""))
		if has_per_instance_overrides:
			if is_pattern:
				if child_overrides.has(str(child_def_idx)):
					push_warning("[BlockFile] Pattern-expanded child #%d (element_ref='%s') in '%s' carries a per-instance override but pattern children are not overridable. Override will be ignored." % [
						child_def_idx, child_def.get("element_ref", "?"), root.block_name])
			else:
				if not child_name_key.is_empty() and child_overrides.has(child_name_key):
					per_instance = child_overrides[child_name_key]
				else:
					per_instance = child_overrides.get(str(child_def_idx), {})

		for effective_child: Dictionary in expanded:
			var element_ref: String = effective_child.get("element_ref", "")
			if element_ref.is_empty():
				push_warning("[BlockFile] Assembly child missing element_ref in %s" % root.block_name)
				continue

			# Per-placement deletion: skip this child if a matching marker is
			# in `deleted_children` for THIS placement. Matches when element_ref
			# is identical AND placement.position is within 1mm of the marker.
			# Identity.name (when present) is also accepted as a match key.
			if not deleted_children.is_empty() \
					and _child_is_deleted(effective_child, element_ref, deleted_children):
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

			# Per-instance override layer — applied AFTER the assembly's own
			# defaults so the structure that placed this assembly can shift one
			# child's position / change its material / rotate it without touching
			# the shared assembly JSON. Same dot-syntax as the assembly's own
			# overrides; placement.position is interpreted as the new local
			# position relative to the assembly origin (we re-add world_pos).
			if not per_instance.is_empty():
				# `placement` may be missing or — if a faulty save serialized
				# it as a string `"{...}"` — non-dict. Defensive: a malformed
				# entry should warn loudly and skip its per-instance fields
				# rather than crash the whole assembly load. The structure
				# JSON may still carry a flat `position`/`rotation_y` at the
				# per_instance level (sibling to `placement`), which we treat
				# as a fallback so the salvageable data still lands.
				var pi_raw_placement = per_instance.get("placement", {})
				var pi_placement: Dictionary = {}
				if pi_raw_placement is Dictionary:
					pi_placement = pi_raw_placement as Dictionary
				else:
					push_warning("[BlockFile] per-instance 'placement' is not a Dictionary in %s (got %s) — skipping placement override for this child" % [
						root.block_name, typeof(pi_raw_placement)])
				if per_instance.has("position") and not pi_placement.has("position"):
					pi_placement["position"] = per_instance["position"]
				if per_instance.has("rotation_y") and not pi_placement.has("rotation_y"):
					pi_placement["rotation_y"] = per_instance["rotation_y"]
				if pi_placement.has("position"):
					child_block.position = world_pos + _arr_to_vec3(pi_placement["position"])
				if pi_placement.has("rotation_y"):
					child_block.rotation_y = pi_placement["rotation_y"]
				if pi_placement.has("scale_factor"):
					child_block.scale_factor = pi_placement["scale_factor"]
				var pi_raw_overrides = per_instance.get("overrides", {})
				var pi_overrides: Dictionary = pi_raw_overrides as Dictionary if pi_raw_overrides is Dictionary else {}
				if not pi_overrides.is_empty():
					apply_overrides(child_block, pi_overrides)

			child_block.ensure_id()
			child_block.parent_id = root.block_id
			root.add_child_link(child_block.block_id)
			# Stamp the JSON child def index on the Block resource so the
			# Studio's save path can locate the correct override slot. The
			# legacy assembly_child_index meta (set by BlocksFactory after
			# load_assembly returns) used a flat output index that drifted
			# under pattern expansion; this is the unambiguous source-side
			# index in the children[] array.
			child_block.set_meta("assembly_child_def_index", child_def_idx)
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


## Resolve an element_ref path to the actual element file on disk.
##
## Search order per base path:
##   1. <base>/<ref>.json           (unified `world-node-v1` schema; canonical)
##   2. <base>/<ref>.block.json     (legacy extension; fallback safety net)
##
## The unified extension wins when both exist. The `.block.json` fallback is
## kept only as a safety net for any in-flight callers that might still pass
## a legacy filename — the actual data tree is `assets/world/` after Phase 5.
static func resolve_element_path(ref: String, search_paths: PackedStringArray) -> String:
	# ref format: "tree/trunk_small" -> tries "tree/trunk_small.json" first,
	# then falls back to "tree/trunk_small.block.json".
	var unified_filename := ref + ".json"
	var legacy_filename := ref + ".block.json"
	for base_path in search_paths:
		var unified_path := base_path.path_join(unified_filename)
		if FileAccess.file_exists(unified_path):
			return unified_path
		var legacy_path := base_path.path_join(legacy_filename)
		if FileAccess.file_exists(legacy_path):
			return legacy_path
	return ""


# =========================================================================
# Helpers
# =========================================================================


## Convert a JSON array [x, y, z] to Vector3.
static func _arr_to_vec3(arr) -> Vector3:
	if arr is Array and arr.size() >= 3:
		return Vector3(float(arr[0]), float(arr[1]), float(arr[2]))
	return Vector3.ZERO


## Normalize a single child entry to the legacy shape. Idempotent: an entry
## already in legacy form passes through unchanged. Used inside the assembly
## children loop so the rest of the code can read one canonical layout
## regardless of whether the caller handed us unified, legacy, or hybrid
## (post-COPY) data.
##
## Translations applied:
##   ref → element_ref
##   flat position → placement.position
##   flat rotation_y (degrees) → placement.rotation_y (radians)
##   flat scale_factor → placement.scale_factor
##   id → overrides.identity.name (when overrides lacks an explicit name)
static func _normalize_child_to_legacy(child: Dictionary) -> Dictionary:
	if not child is Dictionary:
		return child
	# Fast path: no unified-only keys → nothing to do.
	var has_unified_keys: bool = child.has("ref") or child.has("position") \
			or child.has("rotation_y") or child.has("scale_factor")
	if not has_unified_keys:
		return child
	# Build a normalized COPY (don't mutate input — callers may hold the original).
	var out: Dictionary = child.duplicate(true)
	if out.has("ref") and not out.has("element_ref"):
		out["element_ref"] = out["ref"]
		out.erase("ref")
	# Promote flat placement keys into placement{}. Convert rotation_y deg→rad
	# because the unified schema authors rotations in degrees (per
	# WorldParser.parse_unified docs) while the legacy renderer expects rad.
	var placement: Dictionary = out.get("placement", {})
	if not placement is Dictionary:
		placement = {}
	if out.has("position") and not placement.has("position"):
		placement["position"] = out["position"]
		out.erase("position")
	if out.has("rotation_y") and not placement.has("rotation_y"):
		placement["rotation_y"] = deg_to_rad(float(out["rotation_y"]))
		out.erase("rotation_y")
	if out.has("scale_factor") and not placement.has("scale_factor"):
		placement["scale_factor"] = out["scale_factor"]
		out.erase("scale_factor")
	if not placement.is_empty():
		out["placement"] = placement
	# Migrate flat `id` into overrides.identity.name so the stable-handle
	# lookups in file_to_assembly still resolve correctly.
	if out.has("id"):
		var overrides: Dictionary = out.get("overrides", {})
		if not overrides is Dictionary:
			overrides = {}
		if not overrides.has("identity.name"):
			overrides["identity.name"] = str(out["id"])
		out["overrides"] = overrides
		out.erase("id")
	return out


## True if `child_def` matches any marker in `deleted_children`. Markers are
## `{element_ref, position}` dicts (and optionally `name` for named children).
## Match rules: element_ref must equal (case-sensitive) AND position within
## 1mm OR identity.name equals when the marker carries one.
static func _child_is_deleted(child_def: Dictionary, child_element_ref: String,
		deleted_children: Array) -> bool:
	var child_pos: Array = child_def.get("placement", {}).get("position", [])
	var child_name: String = str(child_def.get("overrides", {}).get("identity.name", ""))
	for marker_v in deleted_children:
		if not marker_v is Dictionary:
			continue
		var marker: Dictionary = marker_v
		# Name-based match wins if both sides have a name.
		var marker_name: String = str(marker.get("name", ""))
		if not child_name.is_empty() and not marker_name.is_empty():
			if marker_name == child_name:
				return true
			continue  # different names — not this child
		# Fall back to element_ref + position match.
		var marker_er: String = str(marker.get("element_ref", ""))
		if not marker_er.is_empty() and marker_er != child_element_ref:
			continue
		var marker_pos: Array = marker.get("position", [])
		if marker_pos.size() == 3 and child_pos.size() == 3:
			var matched: bool = true
			for i in 3:
				if abs(float(marker_pos[i]) - float(child_pos[i])) > 0.001:
					matched = false
					break
			if matched:
				return true
		elif marker_pos.is_empty() and not marker_er.is_empty():
			# Marker has element_ref but no position — wildcard match on
			# element_ref alone. Used when deleting an entire family of
			# duplicates (rare; explicit position is the default).
			return true
	return false


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
