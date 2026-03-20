class_name BlockPlacementRule
extends RefCounted
## Base class for block placement validators.
##
## Placement rules constrain where blocks can be placed and which connections
## are valid. They return allowed positions (not just pass/fail) and can be
## stacked via PlacementRuleStack for composable constraint sets.
##
## Subclass this to create specific rules (EndpointSnapRule, SameHeightRule, etc.)
## or use the static `create()` factory for JSON-declared validators.
##
## NOTE: Function signatures use untyped params (not Block) to avoid circular
## class_name dependency (Block -> PlacementRuleStack -> BlockPlacementRule -> Block).
## All block params are Block instances at runtime.
##
## Usage:
##   var rule := BlockPlacementRule.create("endpoint_snap")
##   block.add_placement_rule(rule)
##   var result := rule.check_connection(block_a, block_b)
##   if not result.valid:
##       print(result.errors)

## Static registry of rule name -> loaded script.
## Populated lazily on first `create()` call.
static var _rule_registry: Dictionary = {}
static var _registry_initialized: bool = false


## Rule name identifier (override in subclasses).
func get_rule_name() -> String:
	return "base"


## Validate placing a block at a specific position.
## block: Block, registry: BlockRegistry (untyped to avoid circular deps)
## Returns: {"valid": bool, "errors": Array[String]}
func check_placement(block, pos: Vector3, registry) -> Dictionary:
	return {"valid": true, "errors": [] as Array[String]}


## Validate connecting two blocks.
## block_a, block_b: Block instances (untyped to avoid circular deps)
## Returns: {"valid": bool, "errors": Array[String]}
func check_connection(block_a, block_b) -> Dictionary:
	return {"valid": true, "errors": [] as Array[String]}


## Get valid snap positions where `block` can be placed relative to `anchor`.
## block, anchor: Block instances (untyped to avoid circular deps)
## Returns world-space positions. Empty = no constraints from this rule.
func get_snap_positions(block, anchor) -> Array[Vector3]:
	return [] as Array[Vector3]


## Get valid rotation_y values for `block` when snapping to `anchor`.
## block, anchor: Block instances (untyped to avoid circular deps)
## Returns radians. Empty = no rotation constraints from this rule.
func get_snap_rotations(block, anchor) -> Array[float]:
	return [] as Array[float]


# =========================================================================
# Static Factory
# =========================================================================

## Create a named placement rule with optional parameters.
## Returns null if the rule name is unknown.
static func create(rule_name: String, params: Dictionary = {}):
	_ensure_registry()

	if not _rule_registry.has(rule_name):
		push_warning("[BlockPlacementRule] Unknown rule: '%s'" % rule_name)
		return null

	var script: GDScript = _rule_registry[rule_name]
	var rule = script.new()

	# Apply params if the rule supports them
	if rule.has_method("set_params"):
		rule.set_params(params)

	return rule


## Register a custom rule script by name.
## Call this to extend the factory with project-specific rules.
static func register_rule(rule_name: String, script: GDScript) -> void:
	_ensure_registry()
	_rule_registry[rule_name] = script


## Get all registered rule names.
static func get_available_rules() -> PackedStringArray:
	_ensure_registry()
	return PackedStringArray(_rule_registry.keys())


# =========================================================================
# Internal
# =========================================================================

static func _ensure_registry() -> void:
	if _registry_initialized:
		return
	_registry_initialized = true

	# Register built-in rules.
	# MUST use load() (runtime) NOT preload() (parse-time) because
	# these scripts extend BlockPlacementRule — preload creates a
	# circular dependency that fails at parse time.
	_rule_registry["endpoint_snap"] = load("res://scripts/blocks/rules/endpoint_snap_rule.gd")
	_rule_registry["vertical_stack"] = load("res://scripts/blocks/rules/vertical_stack_rule.gd")

	# Future rules registered here:
	# _rule_registry["same_height"] = load("res://scripts/blocks/rules/same_height_rule.gd")
	# _rule_registry["grid_align"] = load("res://scripts/blocks/rules/grid_align_rule.gd")
