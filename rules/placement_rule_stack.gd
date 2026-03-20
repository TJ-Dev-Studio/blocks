class_name PlacementRuleStack
extends BlockPlacementRule
## Composable stack of placement rules — all rules must pass.
##
## Stacking validators is like stacking blocks: each layer adds constraints.
## check_connection() collects errors from ALL rules; valid only if ALL pass.
## get_snap_positions() returns the INTERSECTION of positions from all rules
## (within tolerance), so the final positions satisfy every constraint.
##
## NOTE: All block params are untyped (Variant) to avoid circular class_name
## dependency with Block. They are Block instances at runtime.
##
## Usage:
##   var stack := PlacementRuleStack.new()
##   stack.add_rule(EndpointSnapRule.new())
##   stack.add_rule(SameHeightRule.new())
##   block.add_placement_rule(stack)

## Ordered list of rules in this stack.
var rules: Array = []

## Tolerance for position intersection (two positions are "same" within this).
var intersection_tolerance: float = 0.5


func get_rule_name() -> String:
	return "stack"


## Add a rule to the stack.
func add_rule(rule) -> void:
	rules.append(rule)


## Remove a rule by name. Returns true if found and removed.
func remove_rule(rule_name: String) -> bool:
	for i in range(rules.size()):
		if rules[i].get_rule_name() == rule_name:
			rules.remove_at(i)
			return true
	return false


## Check if a rule with a given name is in the stack.
func has_rule(rule_name: String) -> bool:
	for r in rules:
		if r.get_rule_name() == rule_name:
			return true
	return false


## Get a rule by name (null if not found).
func get_rule(rule_name: String):
	for r in rules:
		if r.get_rule_name() == rule_name:
			return r
	return null


## Number of rules in the stack.
func get_rule_count() -> int:
	return rules.size()


# =========================================================================
# Composable validation — ALL rules must pass
# =========================================================================

## Run all rules' check_placement. Valid only if ALL pass.
func check_placement(block, pos: Vector3, registry) -> Dictionary:
	var all_errors: Array[String] = []
	for rule in rules:
		var result: Dictionary = rule.check_placement(block, pos, registry)
		if not result.get("valid", true):
			all_errors.append_array(result.get("errors", []))
	if all_errors.is_empty():
		return {"valid": true, "errors": [] as Array[String]}
	return {"valid": false, "errors": all_errors}


## Run all rules' check_connection. Valid only if ALL pass.
func check_connection(block_a, block_b) -> Dictionary:
	var all_errors: Array[String] = []
	for rule in rules:
		var result: Dictionary = rule.check_connection(block_a, block_b)
		if not result.get("valid", true):
			all_errors.append_array(result.get("errors", []))
	if all_errors.is_empty():
		return {"valid": true, "errors": [] as Array[String]}
	return {"valid": false, "errors": all_errors}


## Return the INTERSECTION of snap positions from all rules.
## A position must appear in every rule's output (within tolerance) to be kept.
func get_snap_positions(block, anchor) -> Array[Vector3]:
	if rules.is_empty():
		return [] as Array[Vector3]

	# Gather positions from first rule
	var candidates: Array[Vector3] = rules[0].get_snap_positions(block, anchor)
	if candidates.is_empty():
		return candidates

	# Intersect with each subsequent rule's positions
	for i in range(1, rules.size()):
		var rule_positions: Array[Vector3] = rules[i].get_snap_positions(block, anchor)
		if rule_positions.is_empty():
			# Rule has no position constraints — keep all candidates
			continue
		# Filter candidates to those near at least one position from this rule
		var filtered: Array[Vector3] = []
		for c: Vector3 in candidates:
			for rp: Vector3 in rule_positions:
				if c.distance_to(rp) <= intersection_tolerance:
					filtered.append(c)
					break
		candidates = filtered

	return candidates


## Return the INTERSECTION of snap rotations from all rules.
func get_snap_rotations(block, anchor) -> Array[float]:
	if rules.is_empty():
		return [] as Array[float]

	var candidates: Array[float] = rules[0].get_snap_rotations(block, anchor)
	if candidates.is_empty():
		return candidates

	var rot_tolerance := 0.01  # ~0.6 degrees

	for i in range(1, rules.size()):
		var rule_rots: Array[float] = rules[i].get_snap_rotations(block, anchor)
		if rule_rots.is_empty():
			continue
		var filtered: Array[float] = []
		for c: float in candidates:
			for rr: float in rule_rots:
				if absf(c - rr) <= rot_tolerance or absf(c - rr - TAU) <= rot_tolerance:
					filtered.append(c)
					break
		candidates = filtered

	return candidates
