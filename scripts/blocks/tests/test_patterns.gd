extends Node3D
## Pattern Expansion Test Suite
##
## Validates all pattern types (ring, grid, line, scatter, along_path),
## the variation system, max instance truncation, validation, and edge cases.
##
## Run headless:
##   godot --headless --path godot_project --script res://scripts/blocks/tests/run_pattern_tests.gd

var _pass_count := 0
var _fail_count := 0
var _test_count := 0


func _ready() -> void:
	print("")
	print("=" .repeat(60))
	print("  PATTERN EXPANSION TEST SUITE")
	print("=" .repeat(60))
	print("")

	# Run all test groups
	_test_ring_pattern()
	_test_grid_pattern()
	_test_line_pattern()
	_test_scatter_pattern()
	_test_along_path_pattern()
	_test_variation()
	_test_max_instances()
	_test_validation()
	_test_edge_cases()

	# Summary
	print("")
	print("=" .repeat(60))
	var total := _pass_count + _fail_count
	if _fail_count == 0:
		print("  ALL %d TESTS PASSED" % total)
	else:
		print("  %d PASSED, %d FAILED (of %d)" % [_pass_count, _fail_count, total])
	print("=" .repeat(60))
	print("")

	# Exit with code for CI
	if _fail_count > 0:
		get_tree().quit(1)
	else:
		get_tree().quit(0)


# =========================================================================
# Test helpers
# =========================================================================

func _assert(condition: bool, test_name: String) -> void:
	_test_count += 1
	if condition:
		_pass_count += 1
		print("  PASS  %s" % test_name)
	else:
		_fail_count += 1
		print("  FAIL  %s" % test_name)


func _section(name: String) -> void:
	print("")
	print("--- %s ---" % name)


func _approx_eq(a: float, b: float, tol: float = 0.01) -> bool:
	return absf(a - b) < tol


func _vec3_from_arr(arr: Array) -> Vector3:
	if arr.size() >= 3:
		return Vector3(float(arr[0]), float(arr[1]), float(arr[2]))
	return Vector3.ZERO


# =========================================================================
# Test groups
# =========================================================================

func _test_ring_pattern() -> void:
	_section("Ring Pattern")

	# 8-element ring at radius 5
	var child_def := {
		"element_ref": "test_element",
		"pattern": {"type": "ring", "count": 8, "radius": 5.0, "facing": "inward"},
	}
	var expanded: Array = BlockPatternExpander.expand(child_def)
	_assert(expanded.size() == 8, "ring: 8 elements generated")

	# Verify all positions are at distance ~5.0 from origin
	var all_at_radius := true
	for entry in expanded:
		var pos := _vec3_from_arr(entry["placement"]["position"])
		var dist := Vector2(pos.x, pos.z).length()
		if not _approx_eq(dist, 5.0, 0.05):
			all_at_radius = false
			break
	_assert(all_at_radius, "ring: all positions at distance ~5.0 from origin")

	# Verify "inward" facing: each element's rotation_y points toward center
	# For inward facing, rotation_y = angle + PI, where angle = atan2(z, x)
	var all_face_inward := true
	for entry in expanded:
		var pos := _vec3_from_arr(entry["placement"]["position"])
		var rot_y: float = entry["placement"]["rotation_y"]
		# The angle of the position on the ring
		var pos_angle := atan2(pos.z, pos.x)
		# Inward facing means rot_y = pos_angle + PI (mod TAU)
		var expected_rot := fmod(pos_angle + PI, TAU)
		var actual_rot := fmod(rot_y, TAU)
		# Normalize both to [0, TAU)
		if expected_rot < 0:
			expected_rot += TAU
		if actual_rot < 0:
			actual_rot += TAU
		if not _approx_eq(expected_rot, actual_rot, 0.05):
			# Check if they differ by exactly TAU (wrapping)
			if not _approx_eq(absf(expected_rot - actual_rot), TAU, 0.05):
				all_face_inward = false
				break
	_assert(all_face_inward, "ring: all elements face inward toward center")

	# Verify start_angle offsets correctly
	var child_def_offset := {
		"element_ref": "test_element",
		"pattern": {"type": "ring", "count": 4, "radius": 3.0, "facing": "none", "start_angle": PI / 2.0},
	}
	var expanded_offset: Array = BlockPatternExpander.expand(child_def_offset)
	_assert(expanded_offset.size() == 4, "ring with start_angle: 4 elements generated")
	# First element should be at angle PI/2 from X axis
	var first_pos := _vec3_from_arr(expanded_offset[0]["placement"]["position"])
	var first_angle := atan2(first_pos.z, first_pos.x)
	_assert(_approx_eq(first_angle, PI / 2.0, 0.05), "ring: start_angle=PI/2 offsets first element correctly")


func _test_grid_pattern() -> void:
	_section("Grid Pattern")

	# 3x4 grid with spacing 2.0
	var child_def := {
		"element_ref": "test_element",
		"pattern": {"type": "grid", "columns": 3, "rows": 4, "spacing_x": 2.0, "spacing_z": 2.0},
	}
	var expanded: Array = BlockPatternExpander.expand(child_def)
	_assert(expanded.size() == 12, "grid: 3x4 = 12 elements generated")

	# Verify grid is centered on origin
	var sum_x := 0.0
	var sum_z := 0.0
	for entry in expanded:
		var pos := _vec3_from_arr(entry["placement"]["position"])
		sum_x += pos.x
		sum_z += pos.z
	var avg_x := sum_x / expanded.size()
	var avg_z := sum_z / expanded.size()
	_assert(_approx_eq(avg_x, 0.0, 0.05), "grid: centered on X axis (avg_x ~= 0)")
	_assert(_approx_eq(avg_z, 0.0, 0.05), "grid: centered on Z axis (avg_z ~= 0)")

	# Verify spacing between adjacent elements along columns (X axis)
	# Get all unique X values, sort them, check spacing
	var x_vals: Array = []
	for entry in expanded:
		var pos := _vec3_from_arr(entry["placement"]["position"])
		var x_rounded: float = snapped(pos.x, 0.01)
		if x_rounded not in x_vals:
			x_vals.append(x_rounded)
	x_vals.sort()
	_assert(x_vals.size() == 3, "grid: 3 unique X positions (columns)")

	var spacing_correct := true
	for i in range(1, x_vals.size()):
		if not _approx_eq(x_vals[i] - x_vals[i - 1], 2.0, 0.05):
			spacing_correct = false
			break
	_assert(spacing_correct, "grid: X spacing between columns is 2.0")


func _test_line_pattern() -> void:
	_section("Line Pattern")

	# 5 elements along [1,0,0] with spacing 3.0
	var child_def := {
		"element_ref": "test_element",
		"pattern": {"type": "line", "count": 5, "spacing": 3.0, "direction": [1, 0, 0]},
	}
	var expanded: Array = BlockPatternExpander.expand(child_def)
	_assert(expanded.size() == 5, "line: 5 elements generated")

	# Verify centered on origin: first at -6, last at +6
	var positions: Array = []
	for entry in expanded:
		positions.append(_vec3_from_arr(entry["placement"]["position"]))
	positions.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.x < b.x)

	_assert(_approx_eq(positions[0].x, -6.0, 0.05), "line: first element at x = -6.0")
	_assert(_approx_eq(positions[4].x, 6.0, 0.05), "line: last element at x = +6.0")

	# Verify all positions are on the X axis (y=0, z=0)
	var all_on_x_axis := true
	for pos: Vector3 in positions:
		if not _approx_eq(pos.y, 0.0, 0.05) or not _approx_eq(pos.z, 0.0, 0.05):
			all_on_x_axis = false
			break
	_assert(all_on_x_axis, "line: all positions on X axis (y=0, z=0)")


func _test_scatter_pattern() -> void:
	_section("Scatter Pattern")

	# 20 elements in [10,10] bounds
	var child_def := {
		"element_ref": "test_element",
		"pattern": {"type": "scatter", "count": 20, "bounds": [10, 10], "seed": 42, "min_spacing": 1.0},
	}
	var expanded: Array = BlockPatternExpander.expand(child_def)
	_assert(expanded.size() == 20, "scatter: 20 elements generated")

	# Verify all positions within bounds (-5 to +5 on X and Z)
	var all_in_bounds := true
	for entry in expanded:
		var pos := _vec3_from_arr(entry["placement"]["position"])
		if absf(pos.x) > 5.05 or absf(pos.z) > 5.05:
			all_in_bounds = false
			break
	_assert(all_in_bounds, "scatter: all positions within [10,10] bounds")

	# Verify min_spacing is respected (no two closer than 1.0)
	var spacing_respected := true
	var scatter_positions: Array = []
	for entry in expanded:
		scatter_positions.append(_vec3_from_arr(entry["placement"]["position"]))
	for i in scatter_positions.size():
		for j in range(i + 1, scatter_positions.size()):
			var dist: float = (scatter_positions[i] as Vector3).distance_to(scatter_positions[j] as Vector3)
			if dist < 0.99:  # Slight tolerance
				spacing_respected = false
				break
		if not spacing_respected:
			break
	_assert(spacing_respected, "scatter: min_spacing=1.0 respected between all pairs")

	# Verify deterministic: same seed produces same positions
	var expanded2: Array = BlockPatternExpander.expand(child_def)
	var deterministic := true
	if expanded.size() != expanded2.size():
		deterministic = false
	else:
		for i in expanded.size():
			var pos1 := _vec3_from_arr(expanded[i]["placement"]["position"])
			var pos2 := _vec3_from_arr(expanded2[i]["placement"]["position"])
			if not _approx_eq(pos1.x, pos2.x) or not _approx_eq(pos1.z, pos2.z):
				deterministic = false
				break
	_assert(deterministic, "scatter: same seed=42 produces identical positions across runs")


func _test_along_path_pattern() -> void:
	_section("Along Path Pattern")

	# Path: [0,0,0] -> [10,0,0] with spacing 2.0
	# Total length = 10, spacing = 2 -> instances at 0, 2, 4, 6, 8, 10 = 6
	var child_def := {
		"element_ref": "test_element",
		"pattern": {
			"type": "along_path",
			"points": [[0, 0, 0], [10, 0, 0]],
			"spacing": 2.0,
		},
	}
	var expanded: Array = BlockPatternExpander.expand(child_def)
	_assert(expanded.size() == 6, "along_path: 6 elements at spacing 2.0 along length 10")

	# Verify positions: at 0, 2, 4, 6, 8, 10
	var expected_x := [0.0, 2.0, 4.0, 6.0, 8.0, 10.0]
	var positions_correct := true
	for i in expanded.size():
		var pos := _vec3_from_arr(expanded[i]["placement"]["position"])
		if not _approx_eq(pos.x, expected_x[i], 0.05):
			positions_correct = false
			break
	_assert(positions_correct, "along_path: positions at 0,2,4,6,8,10 along X")

	# Multi-segment path: [0,0,0] -> [5,0,0] -> [5,0,5]
	# Total length = 5 + 5 = 10, spacing = 3 -> instances at 0, 3, 6, 9 = 4
	var child_def_multi := {
		"element_ref": "test_element",
		"pattern": {
			"type": "along_path",
			"points": [[0, 0, 0], [5, 0, 0], [5, 0, 5]],
			"spacing": 3.0,
		},
	}
	var expanded_multi: Array = BlockPatternExpander.expand(child_def_multi)
	_assert(expanded_multi.size() == 4, "along_path multi-segment: 4 elements at spacing 3.0 along length 10")

	# Verify first instance at origin
	var first_pos := _vec3_from_arr(expanded_multi[0]["placement"]["position"])
	_assert(_approx_eq(first_pos.x, 0.0) and _approx_eq(first_pos.z, 0.0),
		"along_path multi-segment: first element at origin")

	# Verify second instance at (3,0,0) — along first segment
	var second_pos := _vec3_from_arr(expanded_multi[1]["placement"]["position"])
	_assert(_approx_eq(second_pos.x, 3.0) and _approx_eq(second_pos.z, 0.0),
		"along_path multi-segment: second element at (3,0,0)")

	# Third instance at distance 6 from start: 5 along first segment + 1 along second = (5,0,1)
	var third_pos := _vec3_from_arr(expanded_multi[2]["placement"]["position"])
	_assert(_approx_eq(third_pos.x, 5.0) and _approx_eq(third_pos.z, 1.0),
		"along_path multi-segment: third element follows path bend at (5,0,1)")

	# Fourth instance at distance 9: 5 along first + 4 along second = (5,0,4)
	var fourth_pos := _vec3_from_arr(expanded_multi[3]["placement"]["position"])
	_assert(_approx_eq(fourth_pos.x, 5.0) and _approx_eq(fourth_pos.z, 4.0),
		"along_path multi-segment: fourth element at (5,0,4)")


func _test_variation() -> void:
	_section("Variation System")

	# Scale jitter: verify scale_factor differs from 1.0
	var child_def_scale := {
		"element_ref": "test_element",
		"pattern": {"type": "ring", "count": 10, "radius": 5.0},
		"variation": {"scale_jitter": 0.3, "seed": 123},
	}
	var expanded_scale: Array = BlockPatternExpander.expand(child_def_scale)
	var has_scale_variation := false
	for entry in expanded_scale:
		if entry["placement"].has("scale_factor"):
			var sf: float = entry["placement"]["scale_factor"]
			if not _approx_eq(sf, 1.0, 0.001):
				has_scale_variation = true
				break
	_assert(has_scale_variation, "variation: scale_jitter produces non-1.0 scale_factor")

	# Rotation jitter: verify rotations differ from default
	var child_def_rot := {
		"element_ref": "test_element",
		"pattern": {"type": "line", "count": 10, "spacing": 1.0, "direction": [1, 0, 0]},
		"variation": {"rotation_jitter": 45.0, "seed": 456},
	}
	var expanded_rot: Array = BlockPatternExpander.expand(child_def_rot)
	# Line pattern has rotation_y = 0 by default; with jitter some should differ
	var has_rot_variation := false
	for entry in expanded_rot:
		var rot_y: float = entry["placement"]["rotation_y"]
		if not _approx_eq(rot_y, 0.0, 0.001):
			has_rot_variation = true
			break
	_assert(has_rot_variation, "variation: rotation_jitter produces non-zero rotation_y")

	# Material variants: verify overrides contain different materials
	var child_def_mat := {
		"element_ref": "test_element",
		"pattern": {"type": "ring", "count": 20, "radius": 3.0},
		"variation": {"material_variants": ["wood", "stone", "moss"], "seed": 789},
	}
	var expanded_mat: Array = BlockPatternExpander.expand(child_def_mat)
	var materials_seen := {}
	for entry in expanded_mat:
		if entry["overrides"].has("visual.material"):
			materials_seen[entry["overrides"]["visual.material"]] = true
	_assert(materials_seen.size() >= 2, "variation: material_variants produces multiple different materials")

	# Deterministic seed: same seed = same results across runs
	var expanded_mat2: Array = BlockPatternExpander.expand(child_def_mat)
	var mats_match := true
	for i in expanded_mat.size():
		var mat1 = expanded_mat[i]["overrides"].get("visual.material", "")
		var mat2 = expanded_mat2[i]["overrides"].get("visual.material", "")
		if mat1 != mat2:
			mats_match = false
			break
	_assert(mats_match, "variation: same seed produces same material assignments")


func _test_max_instances() -> void:
	_section("Max Instances Truncation")

	# Ring with count=300: should be truncated to MAX_PATTERN_INSTANCES (200)
	var child_def := {
		"element_ref": "test_element",
		"pattern": {"type": "ring", "count": 300, "radius": 50.0},
	}
	var expanded: Array = BlockPatternExpander.expand(child_def)
	_assert(expanded.size() == BlockPatternExpander.MAX_PATTERN_INSTANCES,
		"max_instances: ring count=300 truncated to %d" % BlockPatternExpander.MAX_PATTERN_INSTANCES)


func _test_validation() -> void:
	_section("Pattern Validation (BlockValidator.validate_pattern)")

	# Valid ring pattern: should return empty
	var valid_ring := {"type": "ring", "count": 8, "radius": 5.0}
	var errors_valid := BlockValidator.validate_pattern(valid_ring, "test_element")
	_assert(errors_valid.is_empty(), "validation: valid ring pattern returns no errors")

	# Valid grid pattern
	var valid_grid := {"type": "grid", "columns": 3, "rows": 4}
	var errors_grid := BlockValidator.validate_pattern(valid_grid, "test_element")
	_assert(errors_grid.is_empty(), "validation: valid grid pattern returns no errors")

	# Valid line pattern
	var valid_line := {"type": "line", "count": 5, "spacing": 2.0, "direction": [1, 0, 0]}
	var errors_line := BlockValidator.validate_pattern(valid_line, "test_element")
	_assert(errors_line.is_empty(), "validation: valid line pattern returns no errors")

	# Valid scatter pattern
	var valid_scatter := {"type": "scatter", "count": 10, "bounds": [10, 10]}
	var errors_scatter := BlockValidator.validate_pattern(valid_scatter, "test_element")
	_assert(errors_scatter.is_empty(), "validation: valid scatter pattern returns no errors")

	# Valid along_path pattern
	var valid_path := {"type": "along_path", "points": [[0, 0, 0], [10, 0, 0]], "spacing": 2.0}
	var errors_path := BlockValidator.validate_pattern(valid_path, "test_element")
	_assert(errors_path.is_empty(), "validation: valid along_path pattern returns no errors")

	# Invalid: unknown type
	var bad_type := {"type": "spiral", "count": 8}
	var errors_type := BlockValidator.validate_pattern(bad_type, "test_element")
	_assert(not errors_type.is_empty(), "validation: unknown type 'spiral' returns errors")
	_assert(errors_type[0].contains("unknown"), "validation: error mentions 'unknown'")

	# Invalid: missing radius for ring
	var no_radius := {"type": "ring", "count": 8}
	var errors_radius := BlockValidator.validate_pattern(no_radius, "test_element")
	_assert(not errors_radius.is_empty(), "validation: ring with no radius returns errors")

	# Invalid: count > 200 for ring
	var too_many := {"type": "ring", "count": 300, "radius": 10.0}
	var errors_count := BlockValidator.validate_pattern(too_many, "test_element")
	_assert(not errors_count.is_empty(), "validation: ring with count=300 returns errors")

	# Invalid: missing type
	var no_type := {"count": 8, "radius": 5.0}
	var errors_notype := BlockValidator.validate_pattern(no_type, "test_element")
	_assert(not errors_notype.is_empty(), "validation: missing 'type' field returns errors")

	# Invalid: grid with 0 columns
	var bad_grid := {"type": "grid", "columns": 0, "rows": 4}
	var errors_bgrid := BlockValidator.validate_pattern(bad_grid, "test_element")
	_assert(not errors_bgrid.is_empty(), "validation: grid with 0 columns returns errors")

	# Invalid: line with no direction
	var bad_line := {"type": "line", "count": 5, "spacing": 2.0}
	var errors_bline := BlockValidator.validate_pattern(bad_line, "test_element")
	_assert(not errors_bline.is_empty(), "validation: line without direction returns errors")

	# Invalid: scatter with no bounds
	var bad_scatter := {"type": "scatter", "count": 10}
	var errors_bscatter := BlockValidator.validate_pattern(bad_scatter, "test_element")
	_assert(not errors_bscatter.is_empty(), "validation: scatter without bounds returns errors")

	# Invalid: along_path with only 1 point
	var bad_path := {"type": "along_path", "points": [[0, 0, 0]], "spacing": 2.0}
	var errors_bpath := BlockValidator.validate_pattern(bad_path, "test_element")
	_assert(not errors_bpath.is_empty(), "validation: along_path with 1 point returns errors")


func _test_edge_cases() -> void:
	_section("Edge Cases")

	# Empty pattern dict: expand() returns empty
	var empty_def := {
		"element_ref": "test_element",
		"pattern": {},
	}
	var result_empty: Array = BlockPatternExpander.expand(empty_def)
	_assert(result_empty.is_empty(), "edge: empty pattern dict returns empty array")

	# Missing element_ref: expand() returns empty
	var no_ref := {
		"pattern": {"type": "ring", "count": 4, "radius": 2.0},
	}
	var result_noref: Array = BlockPatternExpander.expand(no_ref)
	_assert(result_noref.is_empty(), "edge: missing element_ref returns empty array")

	# Unknown pattern type: expand() returns empty
	var unknown_type := {
		"element_ref": "test_element",
		"pattern": {"type": "helix", "count": 8},
	}
	var result_unknown: Array = BlockPatternExpander.expand(unknown_type)
	_assert(result_unknown.is_empty(), "edge: unknown pattern type returns empty array")

	# Count of 0: expand() returns empty
	var zero_count := {
		"element_ref": "test_element",
		"pattern": {"type": "ring", "count": 0, "radius": 5.0},
	}
	var result_zero: Array = BlockPatternExpander.expand(zero_count)
	_assert(result_zero.is_empty(), "edge: count=0 returns empty array")

	# Missing pattern key entirely
	var no_pattern := {
		"element_ref": "test_element",
	}
	var result_nopattern: Array = BlockPatternExpander.expand(no_pattern)
	_assert(result_nopattern.is_empty(), "edge: missing pattern key returns empty array")

	# Negative count
	var neg_count := {
		"element_ref": "test_element",
		"pattern": {"type": "line", "count": -5, "spacing": 1.0, "direction": [1, 0, 0]},
	}
	var result_neg: Array = BlockPatternExpander.expand(neg_count)
	_assert(result_neg.is_empty(), "edge: negative count returns empty array")

	# Grid with 1x1: should produce exactly 1 element
	var one_by_one := {
		"element_ref": "test_element",
		"pattern": {"type": "grid", "columns": 1, "rows": 1},
	}
	var result_1x1: Array = BlockPatternExpander.expand(one_by_one)
	_assert(result_1x1.size() == 1, "edge: 1x1 grid produces exactly 1 element")

	# Along path with zero spacing
	var zero_spacing := {
		"element_ref": "test_element",
		"pattern": {"type": "along_path", "points": [[0, 0, 0], [10, 0, 0]], "spacing": 0.0},
	}
	var result_zerospace: Array = BlockPatternExpander.expand(zero_spacing)
	_assert(result_zerospace.is_empty(), "edge: along_path with spacing=0 returns empty array")

	# Verify expanded child dict structure
	var valid_def := {
		"element_ref": "pillar_stone",
		"pattern": {"type": "ring", "count": 3, "radius": 2.0},
	}
	var result_valid: Array = BlockPatternExpander.expand(valid_def)
	_assert(result_valid.size() == 3, "edge structure: 3 elements from ring")
	var first := result_valid[0] as Dictionary
	_assert(first.has("element_ref"), "edge structure: child has element_ref")
	_assert(first["element_ref"] == "pillar_stone", "edge structure: element_ref preserved")
	_assert(first.has("placement"), "edge structure: child has placement")
	_assert(first["placement"].has("position"), "edge structure: placement has position")
	_assert(first["placement"]["position"] is Array, "edge structure: position is Array")
	_assert((first["placement"]["position"] as Array).size() == 3, "edge structure: position has 3 components")
	_assert(first["placement"].has("rotation_y"), "edge structure: placement has rotation_y")
	_assert(first.has("overrides"), "edge structure: child has overrides")
