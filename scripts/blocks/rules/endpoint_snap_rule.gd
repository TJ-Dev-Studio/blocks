class_name EndpointSnapRule
extends BlockPlacementRule
## Validates that connected blocks are adjacent in a chain.
##
## Uses center-to-center distance with a half-width sum threshold. This works
## for both LINEAR chains (wall segments in a row) and CIRCULAR chains (wall
## segments tangent to a curve). Pure endpoint-to-endpoint distance fails for
## circular arrangements because tangent-line divergence causes endpoints to
## separate unpredictably at different positions on the curve.
##
## Connection criterion:
##   center_distance < half_width_a + half_width_b + tolerance
##
## For perimeter walls (4m wide, R=40m, ~6° spacing):
##   - Adjacent center-to-center ≈ 4.19m → 4.19 < 2 + 2 + 1.5 = 5.5 ✓
##   - Skip-one center-to-center ≈ 8.33m → 8.33 < 5.5 ✗ (rejected)
##   - Entrance gap ≈ 12.5m → 12.5 < 5.5 ✗ (rejected)
##
## get_snap_positions() returns world positions where a new block's endpoint
## would meet an anchor block's free endpoint — the valid "next" spots.
##
## Works for: wall chains, bridge planks, fence segments, any linear structure.
##
## NOTE: All block params are untyped (Variant) to avoid circular class_name
## dependency with Block. They are Block instances at runtime.

## Tolerance added to the sum of half-widths for center-to-center connection
## check. Default 1.5m is generous enough for perimeter walls at R=40m (~6°).
var tolerance: float = 1.5

## Maximum Y (height) difference allowed for horizontal chain connections.
## Blocks further apart vertically are rejected — use vertical_stack for those.
var max_y_difference: float = 2.0


func get_rule_name() -> String:
	return "endpoint_snap"


## Accept optional params from JSON: {"tolerance": 2.0}
func set_params(params: Dictionary) -> void:
	tolerance = params.get("tolerance", tolerance)


## Validate that two blocks are adjacent using center-to-center distance.
## Passes if: distance(A.center, B.center) < hw_A + hw_B + tolerance
## This criterion works for both linear and circular block arrangements.
func check_connection(block_a, block_b) -> Dictionary:
	var hw_a := _get_half_width(block_a)
	var hw_b := _get_half_width(block_b)

	if hw_a <= 0.0 or hw_b <= 0.0:
		return {"valid": false, "errors": ["Cannot compute half-width (non-box shape or zero size)"] as Array[String]}

	# Reject blocks at different heights — vertical connections use vertical_stack rule
	var y_diff: float = absf(block_a.position.y - block_b.position.y)
	if y_diff > max_y_difference:
		return {
			"valid": false,
			"errors": [
				"Y difference %.2fm exceeds max %.2fm for horizontal chain (%s ↔ %s)" % [
					y_diff, max_y_difference, block_a.block_name, block_b.block_name
				]
			] as Array[String]
		}

	# Use XZ-plane distance (ignore small height differences for horizontal chains)
	var center_a := Vector3(block_a.position.x, 0, block_a.position.z)
	var center_b := Vector3(block_b.position.x, 0, block_b.position.z)
	var center_dist: float = center_a.distance_to(center_b)
	var max_dist: float = hw_a + hw_b + tolerance

	if center_dist <= max_dist:
		return {"valid": true, "errors": [] as Array[String]}

	return {
		"valid": false,
		"errors": [
			"Center distance %.2fm exceeds threshold %.2fm (hw %.1f+%.1f+tol %.1f) (%s ↔ %s)" % [
				center_dist, max_dist, hw_a, hw_b, tolerance,
				block_a.block_name, block_b.block_name
			]
		] as Array[String]
	}


## Check that a block at a proposed position would satisfy endpoint constraints
## relative to already-placed blocks in the registry.
func check_placement(block, pos: Vector3, registry) -> Dictionary:
	if registry == null:
		return {"valid": true, "errors": [] as Array[String]}

	# Get nearby blocks that share tags (potential neighbors)
	var nearby: Array = registry.get_blocks_near(pos, tolerance * 4.0)
	if nearby.is_empty():
		# No neighbors = placement OK (first block in chain)
		return {"valid": true, "errors": [] as Array[String]}

	# Check that at least one neighbor has a matching endpoint
	var temp_block = block.duplicate_block()
	temp_block.position = pos
	for neighbor in nearby:
		if neighbor.block_id == block.block_id:
			continue
		var result := check_connection(temp_block, neighbor)
		if result.get("valid", false):
			return {"valid": true, "errors": [] as Array[String]}

	return {
		"valid": false,
		"errors": [
			"No neighbor endpoint within tolerance %.2fm at pos (%.1f, %.1f, %.1f)" % [
				tolerance, pos.x, pos.y, pos.z
			]
		] as Array[String]
	}


## Get the two world-space positions where `block` could snap to `anchor`'s endpoints.
## Each returned position is where `block`'s center would need to be so that one of
## its endpoints aligns with one of `anchor`'s endpoints.
func get_snap_positions(block, anchor) -> Array[Vector3]:
	var positions: Array[Vector3] = []
	var anchor_eps := _get_endpoints(anchor)
	var block_half_width := _get_half_width(block)

	if anchor_eps.is_empty() or block_half_width <= 0.0:
		return positions

	for ep: Vector3 in anchor_eps:
		# The block would snap so its endpoint aligns with anchor's endpoint.
		# Block center = endpoint + half_width along tangent direction.
		# Use anchor's tangent direction (rotation_y) extended.
		var tangent := Vector3(cos(anchor.rotation_y), 0, -sin(anchor.rotation_y))

		# Two possible snap positions: extending in either direction from the endpoint
		positions.append(ep + tangent * block_half_width)
		positions.append(ep - tangent * block_half_width)

	return positions


## Get valid rotation_y values for snapping to anchor.
## Returns the anchor's rotation + slight adjustments for curvature.
func get_snap_rotations(block, anchor) -> Array[float]:
	var rotations: Array[float] = []
	# For straight chains: same rotation as anchor
	rotations.append(anchor.rotation_y)
	# For curved chains: slight offsets in both directions
	var angle_step := 0.1047  # ~6 degrees (perimeter wall spacing)
	rotations.append(anchor.rotation_y + angle_step)
	rotations.append(anchor.rotation_y - angle_step)
	return rotations


# =========================================================================
# Endpoint computation
# =========================================================================

## Compute world-space endpoints for a block.
## For BOX: two points at ±(width/2) along the width axis, rotated by rotation_y.
## For CYLINDER/CAPSULE: two points at ±(radius) along X, rotated by rotation_y.
## Returns empty array for unsupported shapes.
func _get_endpoints(block) -> Array[Vector3]:
	var endpoints: Array[Vector3] = []
	var half_w := _get_half_width(block)
	if half_w <= 0.0:
		return endpoints

	# Local endpoints along X axis
	var local_left := Vector3(-half_w, 0, 0)
	var local_right := Vector3(half_w, 0, 0)

	# Rotate by block's rotation_y around Y axis
	var rotated_left := local_left.rotated(Vector3.UP, block.rotation_y)
	var rotated_right := local_right.rotated(Vector3.UP, block.rotation_y)

	# Translate to world position (XZ only — Y stays at block height)
	endpoints.append(Vector3(
		block.position.x + rotated_left.x,
		block.position.y,
		block.position.z + rotated_left.z
	))
	endpoints.append(Vector3(
		block.position.x + rotated_right.x,
		block.position.y,
		block.position.z + rotated_right.z
	))

	return endpoints


## Get half-width of a block (the distance from center to each endpoint).
func _get_half_width(block) -> float:
	match block.collision_shape:
		BlockCategories.SHAPE_BOX:
			# Width is collision_size.x for box shapes
			return block.collision_size.x * block.scale_factor / 2.0
		BlockCategories.SHAPE_CYLINDER, BlockCategories.SHAPE_CAPSULE:
			# Radius = collision_size.x
			return block.collision_size.x * block.scale_factor
		BlockCategories.SHAPE_SPHERE:
			return block.collision_size.x * block.scale_factor
	return 0.0
