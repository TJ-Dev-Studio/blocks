class_name BlockValidator
## Validation rules for Block primitives.
##
## Returns an array of error strings. Empty array = valid block.
## Run before registration to catch bad definitions early.
## This is the quality gate — LLM-generated blocks must pass validation
## or be rejected with actionable error messages.

const MAX_DIMENSION := 500.0
const MIN_DIMENSION := 0.01
const MAX_COLLISION_VISUAL_RATIO := 3.0
const MAX_VISUAL_COLLISION_RATIO := 5.0
const MAX_POSITION_XZ := 500.0
const MIN_POSITION_Y := -50.0
const MAX_POSITION_Y := 400.0
const MIN_CLIMBABLE_HEIGHT := 1.0


## Validate a Block definition. Returns empty array if valid.
static func validate(block: Block) -> Array[String]:
	var errors: Array[String] = []

	_validate_identity(block, errors)
	if block.collision_shape != BlockCategories.SHAPE_NONE:
		_validate_dimensions(block, errors)
	_validate_layers(block, errors)
	if block.collision_shape != BlockCategories.SHAPE_NONE and block.mesh_type == 0:
		_validate_visual_collision_ratio(block, errors)
	_validate_interaction(block, errors)
	if block.position != Vector3.ZERO:
		_validate_position(block, errors)
	_validate_links(block, errors)
	_validate_connections(block, errors)
	_validate_lod(block, errors)
	if block.mesh_type == 2:
		_validate_glb(block, errors)

	return errors


## Quick check — returns true if block is valid.
static func is_valid(block: Block) -> bool:
	return validate(block).is_empty()


# =========================================================================
# Rule implementations
# =========================================================================

static func _validate_identity(block: Block, errors: Array[String]) -> void:
	if block.block_name.is_empty():
		errors.append("block_name is empty")
	if block.category < 0 or block.category > 7:
		errors.append("category %d is out of range [0,7]" % block.category)


static func _validate_dimensions(block: Block, errors: Array[String]) -> void:
	var dims := block.collision_size
	match block.collision_shape:
		BlockCategories.SHAPE_BOX, BlockCategories.SHAPE_RAMP:
			if dims.x <= MIN_DIMENSION or dims.y <= MIN_DIMENSION or dims.z <= MIN_DIMENSION:
				errors.append(
					"%s collision_size has zero/negative component: (%.3f, %.3f, %.3f)"
					% [BlockCategories.shape_name(block.collision_shape).to_upper(), dims.x, dims.y, dims.z])
			if dims.x > MAX_DIMENSION or dims.y > MAX_DIMENSION or dims.z > MAX_DIMENSION:
				errors.append(
					"%s collision_size exceeds max %.0f: (%.1f, %.1f, %.1f)"
					% [BlockCategories.shape_name(block.collision_shape).to_upper(), MAX_DIMENSION, dims.x, dims.y, dims.z])
		BlockCategories.SHAPE_CYLINDER, BlockCategories.SHAPE_CAPSULE, \
				BlockCategories.SHAPE_SPHERE, BlockCategories.SHAPE_DOME:
			if dims.x <= MIN_DIMENSION:
				errors.append("radius is zero/negative: %.3f" % dims.x)
			if dims.y <= MIN_DIMENSION:
				errors.append("height is zero/negative: %.3f" % dims.y)
			if dims.x > MAX_DIMENSION or dims.y > MAX_DIMENSION:
				errors.append(
					"collision_size exceeds max %.0f: radius=%.1f height=%.1f"
					% [MAX_DIMENSION, dims.x, dims.y])
		BlockCategories.SHAPE_CONE, BlockCategories.SHAPE_ROCK:
			# Same as cylinder: x=radius, y=height
			if dims.x <= MIN_DIMENSION:
				errors.append("radius is zero/negative: %.3f" % dims.x)
			if dims.y <= MIN_DIMENSION:
				errors.append("height is zero/negative: %.3f" % dims.y)
			if dims.x > MAX_DIMENSION or dims.y > MAX_DIMENSION:
				errors.append(
					"collision_size exceeds max %.0f: radius=%.1f height=%.1f"
					% [MAX_DIMENSION, dims.x, dims.y])
		BlockCategories.SHAPE_TORUS, BlockCategories.SHAPE_ARCH:
			# x=inner_radius, y=outer_radius
			if dims.x < 0.0:
				errors.append("inner_radius cannot be negative: %.3f" % dims.x)
			if dims.y <= MIN_DIMENSION:
				errors.append("outer_radius is zero/negative: %.3f" % dims.y)
			if dims.y <= dims.x:
				errors.append(
					"outer_radius (%.3f) must be greater than inner_radius (%.3f)"
					% [dims.y, dims.x])
			if dims.y > MAX_DIMENSION:
				errors.append("outer_radius exceeds max %.0f: %.1f" % [MAX_DIMENSION, dims.y])

	if block.scale_factor <= 0.0:
		errors.append("scale_factor must be positive, got %.3f" % block.scale_factor)
	if block.scale_factor > 100.0:
		errors.append("scale_factor %.1f is unreasonably large" % block.scale_factor)


static func _validate_layers(block: Block, errors: Array[String]) -> void:
	if block.collision_shape == BlockCategories.SHAPE_NONE:
		return

	if block.collision_layer < 1 or block.collision_layer > 32:
		errors.append("collision_layer %d out of range [1,32]" % block.collision_layer)
		return

	# Strict rules — certain interactions MUST use specific layers
	if block.interaction == BlockCategories.INTERACT_TRIGGER \
			and block.collision_layer != CollisionLayers.TRIGGER:
		errors.append(
			"TRIGGER interaction must use TRIGGER layer (%d), got %d"
			% [CollisionLayers.TRIGGER, block.collision_layer])

	if block.interaction == BlockCategories.INTERACT_WATER \
			and block.collision_layer != CollisionLayers.WATER:
		errors.append(
			"WATER interaction must use WATER layer (%d), got %d"
			% [CollisionLayers.WATER, block.collision_layer])

	# Validate mask layers are all in range
	for ml in block.collision_mask_layers:
		if ml < 1 or ml > 32:
			errors.append("collision_mask_layers contains invalid layer %d" % ml)


static func _validate_visual_collision_ratio(block: Block, errors: Array[String]) -> void:
	var mesh_dims := block.mesh_size if block.mesh_size != Vector3.ZERO else block.collision_size
	var col_dims := block.collision_size

	if block.collision_shape in [BlockCategories.SHAPE_BOX, BlockCategories.SHAPE_RAMP]:
		for axis in ["x", "y", "z"]:
			var m: float = mesh_dims[axis]
			var c: float = col_dims[axis]
			if m > MIN_DIMENSION and c > MIN_DIMENSION:
				if c / m > MAX_COLLISION_VISUAL_RATIO:
					errors.append(
						"collision %s (%.1f) is %.1fx larger than mesh (%.1f)"
						% [axis, c, c / m, m])
				if m / c > MAX_VISUAL_COLLISION_RATIO:
					errors.append(
						"mesh %s (%.1f) is %.1fx larger than collision (%.1f)"
						% [axis, m, m / c, c])
	elif block.collision_shape in [BlockCategories.SHAPE_CYLINDER, BlockCategories.SHAPE_CAPSULE,
			BlockCategories.SHAPE_SPHERE, BlockCategories.SHAPE_DOME]:
		# Check radius and height
		if mesh_dims.x > MIN_DIMENSION and col_dims.x > MIN_DIMENSION:
			var ratio := col_dims.x / mesh_dims.x
			if ratio > MAX_COLLISION_VISUAL_RATIO:
				errors.append(
					"collision radius (%.1f) is %.1fx larger than mesh (%.1f)"
					% [col_dims.x, ratio, mesh_dims.x])
		if mesh_dims.y > MIN_DIMENSION and col_dims.y > MIN_DIMENSION:
			var ratio := col_dims.y / mesh_dims.y
			if ratio > MAX_COLLISION_VISUAL_RATIO:
				errors.append(
					"collision height (%.1f) is %.1fx larger than mesh (%.1f)"
					% [col_dims.y, ratio, mesh_dims.y])


static func _validate_interaction(block: Block, errors: Array[String]) -> void:
	if block.interaction < 0 or block.interaction > 8:
		errors.append("interaction %d is out of range [0,8]" % block.interaction)
		return

	if block.interaction == BlockCategories.INTERACT_TRIGGER:
		if block.collision_shape == BlockCategories.SHAPE_NONE:
			errors.append("TRIGGER interaction requires a collision shape")

	if block.interaction == BlockCategories.INTERACT_TRIGGER and block.trigger_radius <= 0.0:
		errors.append("TRIGGER interaction requires trigger_radius > 0")

	if block.interaction == BlockCategories.INTERACT_CLIMBABLE:
		if block.collision_size.y < MIN_CLIMBABLE_HEIGHT:
			errors.append(
				"CLIMBABLE interaction requires height >= %.1f, got %.3f"
				% [MIN_CLIMBABLE_HEIGHT, block.collision_size.y])


static func _validate_position(block: Block, errors: Array[String]) -> void:
	if absf(block.position.x) > MAX_POSITION_XZ or absf(block.position.z) > MAX_POSITION_XZ:
		errors.append(
			"position (%.1f, %.1f) outside bounds (%.0f)"
			% [block.position.x, block.position.z, MAX_POSITION_XZ])
	if block.position.y < MIN_POSITION_Y:
		errors.append("position Y (%.1f) is underground (min %.0f)" % [block.position.y, MIN_POSITION_Y])
	if block.position.y > MAX_POSITION_Y:
		errors.append("position Y (%.1f) is unreasonably high (max %.0f)" % [block.position.y, MAX_POSITION_Y])


static func _validate_links(block: Block, errors: Array[String]) -> void:
	# Parent and child IDs should not contain the block's own ID
	if not block.block_id.is_empty():
		if block.parent_id == block.block_id:
			errors.append("block cannot be its own parent")
		for cid in block.child_ids:
			if cid == block.block_id:
				errors.append("block cannot be its own child")


static func _validate_connections(block: Block, errors: Array[String]) -> void:
	var seen := {}
	for conn_id in block.connections:
		if conn_id.is_empty():
			errors.append("connections contains empty block_id")
		elif not block.block_id.is_empty() and conn_id == block.block_id:
			errors.append("block cannot connect to itself")
		if seen.has(conn_id):
			errors.append("duplicate connection to '%s'" % conn_id)
		seen[conn_id] = true


static func _validate_glb(block: Block, errors: Array[String]) -> void:
	if block.scene_path.is_empty():
		errors.append("GLB element (mesh_type=glb) has empty visual.mesh path")
		return
	if not block.scene_path.ends_with(".glb"):
		errors.append("visual.mesh path '%s' is not a .glb file" % block.scene_path)
		return
	if not ResourceLoader.exists(block.scene_path) \
			and not FileAccess.file_exists(block.scene_path):
		errors.append("visual.mesh path '%s' does not exist" % block.scene_path)
	if block.state.has("_blend_group"):
		errors.append("GLB elements cannot participate in SDF blending (has _blend_group='%s')" % block.state["_blend_group"])


static func _validate_lod(block: Block, errors: Array[String]) -> void:
	if block.lod_level < 0:
		errors.append("lod_level cannot be negative: %d" % block.lod_level)
	if block.lod_level > 10:
		errors.append("lod_level %d exceeds maximum depth of 10" % block.lod_level)
	if not block.parent_lod_id.is_empty() and not block.block_id.is_empty():
		if block.parent_lod_id == block.block_id:
			errors.append("block cannot be its own LOD parent")
	if block.min_size.x < MIN_DIMENSION or block.min_size.y < MIN_DIMENSION \
			or block.min_size.z < MIN_DIMENSION:
		errors.append("min_size has component below MIN_DIMENSION (%.3f)" % MIN_DIMENSION)
	if not block.dna.is_empty():
		var axis_pref = block.dna.get("axis_preference", -1)
		if axis_pref is int and (axis_pref < -1 or axis_pref > 2):
			errors.append("dna.axis_preference %d out of range [-1, 2]" % axis_pref)
		var child_count = block.dna.get("child_count", 2)
		if child_count is int and child_count not in [2, 4, 8]:
			errors.append("dna.child_count %d must be 2, 4, or 8" % child_count)


# =========================================================================
# Pattern pre-flight validation
# =========================================================================

const _VALID_PATTERN_TYPES := ["ring", "grid", "line", "scatter", "along_path"]


## Validate a pattern definition before expansion.
## Returns empty array if valid, array of error strings if invalid.
static func validate_pattern(pattern: Dictionary, element_ref: String) -> Array[String]:
	var errors: Array[String] = []

	# --- type check ---
	var ptype: String = pattern.get("type", "")
	if ptype.is_empty():
		errors.append("pattern missing 'type' field")
		return errors  # nothing else to validate without a type

	if ptype not in _VALID_PATTERN_TYPES:
		errors.append("unknown pattern type '%s' (valid: %s)" % [ptype, ", ".join(_VALID_PATTERN_TYPES)])
		return errors

	# --- instance count estimation + budget check ---
	var estimated_count := _estimate_pattern_count(pattern, ptype)
	if estimated_count <= 0:
		errors.append("pattern '%s' produces 0 instances" % ptype)
	elif estimated_count > BlockPatternExpander.MAX_PATTERN_INSTANCES:
		errors.append(
			"pattern '%s' would produce ~%d instances (max %d)"
			% [ptype, estimated_count, BlockPatternExpander.MAX_PATTERN_INSTANCES])

	# --- type-specific validation ---
	match ptype:
		"ring":
			_validate_pattern_ring(pattern, errors)
		"grid":
			_validate_pattern_grid(pattern, errors)
		"line":
			_validate_pattern_line(pattern, errors)
		"scatter":
			_validate_pattern_scatter(pattern, errors)
		"along_path":
			_validate_pattern_along_path(pattern, errors)

	return errors


static func _estimate_pattern_count(pattern: Dictionary, ptype: String) -> int:
	match ptype:
		"ring", "line", "scatter":
			return int(pattern.get("count", 0))
		"grid":
			var cols: int = int(pattern.get("columns", 0))
			var rows: int = int(pattern.get("rows", 0))
			return cols * rows
		"along_path":
			var points_arr: Array = pattern.get("points", [])
			var spacing: float = float(pattern.get("spacing", 1.0))
			if points_arr.size() < 2 or spacing <= 0.0:
				return 0
			# Walk segments and sum total path length
			var total_length := 0.0
			for i in range(1, points_arr.size()):
				var prev = points_arr[i - 1]
				var curr = points_arr[i]
				if prev is Array and prev.size() >= 3 and curr is Array and curr.size() >= 3:
					var dx := float(curr[0]) - float(prev[0])
					var dy := float(curr[1]) - float(prev[1])
					var dz := float(curr[2]) - float(prev[2])
					total_length += sqrt(dx * dx + dy * dy + dz * dz)
			# +1 for the start point
			return int(total_length / spacing) + 1
	return 0


static func _validate_pattern_ring(pattern: Dictionary, errors: Array[String]) -> void:
	var count: int = int(pattern.get("count", 0))
	if count <= 0:
		errors.append("ring pattern requires 'count' > 0")
	var radius: float = float(pattern.get("radius", 0.0))
	if radius <= 0.0:
		errors.append("ring pattern requires 'radius' > 0")


static func _validate_pattern_grid(pattern: Dictionary, errors: Array[String]) -> void:
	var columns: int = int(pattern.get("columns", 0))
	if columns <= 0:
		errors.append("grid pattern requires 'columns' > 0")
	var rows: int = int(pattern.get("rows", 0))
	if rows <= 0:
		errors.append("grid pattern requires 'rows' > 0")


static func _validate_pattern_line(pattern: Dictionary, errors: Array[String]) -> void:
	var count: int = int(pattern.get("count", 0))
	if count <= 0:
		errors.append("line pattern requires 'count' > 0")
	var spacing: float = float(pattern.get("spacing", 0.0))
	if spacing <= 0.0:
		errors.append("line pattern requires 'spacing' > 0")
	var direction = pattern.get("direction", null)
	if direction == null or not direction is Array or direction.size() < 3:
		errors.append("line pattern requires 'direction' array with >= 3 components")


static func _validate_pattern_scatter(pattern: Dictionary, errors: Array[String]) -> void:
	var count: int = int(pattern.get("count", 0))
	if count <= 0:
		errors.append("scatter pattern requires 'count' > 0")
	var bounds = pattern.get("bounds", null)
	if bounds == null or not bounds is Array or bounds.size() < 1:
		errors.append("scatter pattern requires 'bounds' array with >= 1 value")
	elif bounds is Array:
		var all_positive := true
		for val in bounds:
			if float(val) <= 0.0:
				all_positive = false
				break
		if not all_positive:
			errors.append("scatter pattern 'bounds' values must all be > 0")


static func _validate_pattern_along_path(pattern: Dictionary, errors: Array[String]) -> void:
	var points = pattern.get("points", null)
	if points == null or not points is Array or points.size() < 2:
		errors.append("along_path pattern requires 'points' array with >= 2 entries")
	var spacing: float = float(pattern.get("spacing", 0.0))
	if spacing <= 0.0:
		errors.append("along_path pattern requires 'spacing' > 0")
