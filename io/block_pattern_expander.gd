class_name BlockPatternExpander
## Expands pattern-based child definitions into arrays of positioned children.
##
## A pattern child in an assembly JSON carries a "pattern" key describing how
## to replicate an element_ref into multiple instances (ring, grid, line, scatter,
## along_path).  This class takes that single definition and returns an Array of
## regular child dictionaries — identical in format to hand-placed children — so
## the rest of the pipeline (validation, building, registration) is unaware that
## patterns exist.
##
## Usage:
##   var children: Array = BlockPatternExpander.expand(child_def)


## Hard ceiling on generated instances per pattern to prevent runaway loops.
const MAX_PATTERN_INSTANCES := 200


## Expand a single pattern child definition into an Array of regular child dicts.
##
## Input dict must have at minimum:
##   - "element_ref": String
##   - "pattern": Dictionary with "type" key
##
## Returns an empty Array on invalid input.
static func expand(child_def: Dictionary) -> Array:
	if not child_def.has("pattern") or not child_def["pattern"] is Dictionary:
		push_warning("[BlockPatternExpander] Child definition missing 'pattern' dict")
		return []

	var pattern: Dictionary = child_def["pattern"]
	var pattern_type: String = pattern.get("type", "")
	if pattern_type.is_empty():
		push_warning("[BlockPatternExpander] Pattern missing 'type' field")
		return []

	var element_ref: String = child_def.get("element_ref", "")
	if element_ref.is_empty():
		push_warning("[BlockPatternExpander] Pattern child missing 'element_ref'")
		return []

	# Base placement offset — the pattern is centered here
	var base_pos := _dict_to_vec3(child_def.get("placement", {}).get("position", [0, 0, 0]))
	var base_overrides: Dictionary = child_def.get("overrides", {})
	var variation: Dictionary = child_def.get("variation", {})

	var positions: Array  # Array of Dictionary { "position": Vector3, "rotation_y": float }
	match pattern_type:
		"ring":
			positions = _expand_ring(pattern)
		"grid":
			positions = _expand_grid(pattern)
		"line":
			positions = _expand_line(pattern)
		"scatter":
			positions = _expand_scatter(pattern)
		"along_path":
			positions = _expand_along_path(pattern)
		_:
			push_warning("[BlockPatternExpander] Unknown pattern type: '%s'" % pattern_type)
			return []

	if positions.is_empty():
		return []

	# Enforce instance cap
	if positions.size() > MAX_PATTERN_INSTANCES:
		push_warning("[BlockPatternExpander] Pattern '%s' generated %d instances, truncating to %d" % [
			pattern_type, positions.size(), MAX_PATTERN_INSTANCES])
		positions.resize(MAX_PATTERN_INSTANCES)

	# Build variation RNG
	var rng := RandomNumberGenerator.new()
	var variation_seed: int = variation.get("seed", 0)
	rng.seed = variation_seed if variation_seed != 0 else hash(element_ref)

	var scale_jitter: float = variation.get("scale_jitter", 0.0)
	var rotation_jitter: float = variation.get("rotation_jitter", 0.0)
	var position_jitter: Array = variation.get("position_jitter", [])
	var material_variants: Array = variation.get("material_variants", [])
	var pos_jitter_vec := _dict_to_vec3(position_jitter) if position_jitter.size() >= 3 else Vector3.ZERO

	# Assemble output children
	var result: Array = []
	for i in positions.size():
		var entry: Dictionary = positions[i]
		var pos: Vector3 = entry["position"] + base_pos
		var rot_y: float = entry.get("rotation_y", 0.0)

		# Apply variation
		if pos_jitter_vec != Vector3.ZERO:
			pos.x += rng.randf_range(-pos_jitter_vec.x, pos_jitter_vec.x)
			pos.y += rng.randf_range(-pos_jitter_vec.y, pos_jitter_vec.y)
			pos.z += rng.randf_range(-pos_jitter_vec.z, pos_jitter_vec.z)

		if rotation_jitter > 0.0:
			rot_y += deg_to_rad(rng.randf_range(-rotation_jitter, rotation_jitter))

		var child := {
			"element_ref": element_ref,
			"placement": {
				"position": [snapped(pos.x, 0.001), snapped(pos.y, 0.001), snapped(pos.z, 0.001)],
				"rotation_y": snapped(rot_y, 0.001),
			},
			"overrides": base_overrides.duplicate(true),
		}

		# Scale jitter
		if scale_jitter > 0.0:
			var factor := 1.0 + rng.randf_range(-scale_jitter, scale_jitter)
			child["placement"]["scale_factor"] = snapped(factor, 0.001)

		# Material variant override
		if not material_variants.is_empty():
			var mat_index := rng.randi() % material_variants.size()
			child["overrides"]["visual.material"] = material_variants[mat_index]

		result.append(child)

	return result


# =============================================================================
# Pattern generators
# =============================================================================
# Each returns Array of { "position": Vector3, "rotation_y": float }.


static func _expand_ring(pattern: Dictionary) -> Array:
	var count: int = pattern.get("count", 0)
	if count <= 0:
		return []

	var radius: float = pattern.get("radius", 1.0)
	var facing: String = pattern.get("facing", "none")
	var start_angle: float = pattern.get("start_angle", 0.0)
	var angle_step := TAU / float(count)

	var result: Array = []
	for i in count:
		var angle := start_angle + angle_step * i
		var x := cos(angle) * radius
		var z := sin(angle) * radius

		var rot_y := 0.0
		match facing:
			"inward":
				# Face toward the center — the element at angle A faces inward
				rot_y = angle + PI
			"outward":
				rot_y = angle
			_:
				rot_y = 0.0

		result.append({"position": Vector3(x, 0.0, z), "rotation_y": rot_y})

	return result


static func _expand_grid(pattern: Dictionary) -> Array:
	var columns: int = pattern.get("columns", 0)
	var rows: int = pattern.get("rows", 0)
	if columns <= 0 or rows <= 0:
		return []

	var spacing_x: float = pattern.get("spacing_x", 1.0)
	var spacing_z: float = pattern.get("spacing_z", 1.0)

	# Center the grid on origin
	var offset_x := (columns - 1) * spacing_x * 0.5
	var offset_z := (rows - 1) * spacing_z * 0.5

	var result: Array = []
	for row in rows:
		for col in columns:
			var x := col * spacing_x - offset_x
			var z := row * spacing_z - offset_z
			result.append({"position": Vector3(x, 0.0, z), "rotation_y": 0.0})

	return result


static func _expand_line(pattern: Dictionary) -> Array:
	var count: int = pattern.get("count", 0)
	if count <= 0:
		return []

	var spacing: float = pattern.get("spacing", 1.0)
	var dir_arr: Array = pattern.get("direction", [1, 0, 0])
	var direction := _dict_to_vec3(dir_arr)
	if direction.is_zero_approx():
		direction = Vector3(1, 0, 0)
	direction = direction.normalized()

	# Center the line on origin
	var total_length := (count - 1) * spacing
	var start := -direction * total_length * 0.5

	var result: Array = []
	for i in count:
		var pos := start + direction * spacing * i
		result.append({"position": pos, "rotation_y": 0.0})

	return result


static func _expand_scatter(pattern: Dictionary) -> Array:
	var count: int = pattern.get("count", 0)
	if count <= 0:
		return []

	var bounds_arr: Array = pattern.get("bounds", [10, 10])
	var bounds_x: float = bounds_arr[0] if bounds_arr.size() >= 1 else 10.0
	var bounds_z: float = bounds_arr[1] if bounds_arr.size() >= 2 else 10.0
	var seed_val: int = pattern.get("seed", 0)
	var min_spacing: float = pattern.get("min_spacing", 0.0)

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val if seed_val != 0 else hash("scatter_default")

	var half_x := bounds_x * 0.5
	var half_z := bounds_z * 0.5

	var placed: Array = []  # Array[Vector3]
	var max_attempts := count * 20  # Rejection sampling budget
	var attempts := 0

	while placed.size() < count and attempts < max_attempts:
		attempts += 1
		var x := rng.randf_range(-half_x, half_x)
		var z := rng.randf_range(-half_z, half_z)
		var candidate := Vector3(x, 0.0, z)

		# Enforce minimum spacing via rejection
		if min_spacing > 0.0:
			var too_close := false
			var min_sq := min_spacing * min_spacing
			for existing: Vector3 in placed:
				if candidate.distance_squared_to(existing) < min_sq:
					too_close = true
					break
			if too_close:
				continue

		placed.append(candidate)

	if placed.size() < count:
		push_warning("[BlockPatternExpander] Scatter: placed %d of %d requested (min_spacing=%.2f may be too large for bounds)" % [
			placed.size(), count, min_spacing])

	var result: Array = []
	for pos: Vector3 in placed:
		# Random Y rotation per scatter instance
		var rot_y := rng.randf_range(0.0, TAU)
		result.append({"position": pos, "rotation_y": rot_y})

	return result


static func _expand_along_path(pattern: Dictionary) -> Array:
	var points_arr: Array = pattern.get("points", [])
	if points_arr.size() < 2:
		push_warning("[BlockPatternExpander] along_path requires at least 2 points")
		return []

	var spacing: float = pattern.get("spacing", 1.0)
	if spacing <= 0.0:
		push_warning("[BlockPatternExpander] along_path spacing must be positive")
		return []

	var align_to_path: bool = pattern.get("align_to_path", false)

	# Convert point arrays to Vector3
	var points: Array = []  # Array[Vector3]
	for p in points_arr:
		if p is Array and p.size() >= 3:
			points.append(Vector3(float(p[0]), float(p[1]), float(p[2])))

	if points.size() < 2:
		return []

	# Walk the path placing instances at spacing intervals
	var result: Array = []
	var distance_along := 0.0  # How far along the path we've traveled
	var segment_start: Vector3 = points[0]
	var segment_index := 0
	var segment_offset := 0.0  # Distance already consumed in the current segment

	# Place first instance at the start
	var first_rot := 0.0
	if align_to_path:
		var seg_dir: Vector3 = points[1] - points[0]
		if not seg_dir.is_zero_approx():
			first_rot = atan2(seg_dir.x, seg_dir.z)
	result.append({"position": points[0], "rotation_y": first_rot})

	var remaining := spacing  # Distance until next placement

	while segment_index < points.size() - 1:
		var seg_start: Vector3 = points[segment_index]
		var seg_end: Vector3 = points[segment_index + 1]
		var seg_vec := seg_end - seg_start
		var seg_length := seg_vec.length()

		if seg_length < 0.0001:
			segment_index += 1
			continue

		var seg_dir := seg_vec / seg_length

		# How much of this segment is left from where we are
		var available := seg_length - segment_offset

		while remaining <= available:
			segment_offset += remaining
			available -= remaining
			remaining = spacing

			var pos := seg_start + seg_dir * segment_offset
			var rot_y := 0.0
			if align_to_path:
				rot_y = atan2(seg_dir.x, seg_dir.z)

			result.append({"position": pos, "rotation_y": rot_y})

			if result.size() >= MAX_PATTERN_INSTANCES:
				return result

		# We consumed the rest of this segment without placing
		remaining -= available
		segment_index += 1
		segment_offset = 0.0

	return result


# =============================================================================
# Helpers
# =============================================================================


## Convert a JSON array [x, y, z] to Vector3. Returns ZERO for invalid input.
static func _dict_to_vec3(arr) -> Vector3:
	if arr is Array and arr.size() >= 3:
		return Vector3(float(arr[0]), float(arr[1]), float(arr[2]))
	return Vector3.ZERO
