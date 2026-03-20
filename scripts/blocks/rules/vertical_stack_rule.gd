class_name VerticalStackRule
extends BlockPlacementRule
## Validates that two blocks are vertically stacked (directly above/below).
##
## Used for connecting wall blocks across stacked rings. Two blocks pass if:
##   - Their XZ (horizontal) distance is within tolerance
##   - Their Y difference matches the expected stack height ± tolerance
##
## This rule works alongside EndpointSnapRule: endpoint_snap handles horizontal
## chain connections within a ring, vertical_stack handles connections between
## rings at different heights.
##
## NOTE: All block params are untyped (Variant) to avoid circular class_name
## dependency with Block. They are Block instances at runtime.

## Expected vertical offset between stacked blocks (matches wall height).
var stack_height: float = 6.0

## Horizontal tolerance for "same XZ position" check.
var xz_tolerance: float = 1.0

## Vertical tolerance for height match.
var y_tolerance: float = 0.5


func get_rule_name() -> String:
	return "vertical_stack"


## Accept optional params from JSON: {"stack_height": 6.0, "xz_tolerance": 1.0}
func set_params(params: Dictionary) -> void:
	stack_height = params.get("stack_height", stack_height)
	xz_tolerance = params.get("xz_tolerance", xz_tolerance)
	y_tolerance = params.get("y_tolerance", y_tolerance)


## Validate that two blocks are vertically stacked.
## Passes if: same XZ position (within tolerance) AND Y difference = stack_height (± tolerance)
func check_connection(block_a, block_b) -> Dictionary:
	# XZ distance (ignore Y)
	var xz_a := Vector2(block_a.position.x, block_a.position.z)
	var xz_b := Vector2(block_b.position.x, block_b.position.z)
	var xz_dist: float = xz_a.distance_to(xz_b)

	if xz_dist > xz_tolerance:
		return {
			"valid": false,
			"errors": [
				"XZ distance %.2fm exceeds tolerance %.2fm (%s ↔ %s)" % [
					xz_dist, xz_tolerance, block_a.block_name, block_b.block_name
				]
			] as Array[String]
		}

	# Y difference should match stack_height
	var y_diff: float = absf(block_a.position.y - block_b.position.y)
	if absf(y_diff - stack_height) > y_tolerance:
		return {
			"valid": false,
			"errors": [
				"Y difference %.2fm doesn't match stack height %.2fm (±%.2fm) (%s ↔ %s)" % [
					y_diff, stack_height, y_tolerance, block_a.block_name, block_b.block_name
				]
			] as Array[String]
		}

	return {"valid": true, "errors": [] as Array[String]}


## Check placement relative to registry (not used for vertical stacking).
func check_placement(block, pos: Vector3, registry) -> Dictionary:
	return {"valid": true, "errors": [] as Array[String]}
