class_name BlockPhysicsState
extends RefCounted
## Schema enforcement for block physics state keys in block.state.
##
## Blocks are particles — each block carries serialized physics state used by
## FORCE_PROPAGATE messages, coordinator queries, and snapshot encoding.
## These keys are the public interface; BlockSpring is the private simulation.
##
## Physics state keys (all written into block.state):
##   "force_vec"  — Vector3: accumulated force acting on block (default Vector3.ZERO)
##   "velocity"   — Vector3: last committed velocity, propagation layer (default Vector3.ZERO)
##   "mass"       — float:   rest mass, range [0.01, 1000.0] (default 1.0)
##   "damping"    — float:   per-tick velocity damping factor, range [0.0, 1.0] (default 0.85)
##   "hop_count"  — int:     propagation hops received this wave (default 0)
##   "displaced"  — bool:    whether displaced from rest this wave (default false)

# =========================================================================
# Defaults
# =========================================================================

const DEFAULT_FORCE_VEC := Vector3.ZERO
const DEFAULT_VELOCITY := Vector3.ZERO
const DEFAULT_MASS := 1.0
const DEFAULT_DAMPING := 0.85
const DEFAULT_HOP_COUNT := 0
const DEFAULT_DISPLACED := false

const MASS_MIN := 0.01
const MASS_MAX := 1000.0
const DAMPING_MIN := 0.0
const DAMPING_MAX := 1.0


# =========================================================================
# Lifecycle
# =========================================================================

## Initialize physics state keys in block.state with defaults.
## Idempotent — safe to call on a block that already has physics state.
## Does NOT overwrite existing values.
static func init(block: Block) -> void:
	if not block.state.has("force_vec"):
		block.state["force_vec"] = DEFAULT_FORCE_VEC
	if not block.state.has("velocity"):
		block.state["velocity"] = DEFAULT_VELOCITY
	if not block.state.has("mass"):
		block.state["mass"] = DEFAULT_MASS
	if not block.state.has("damping"):
		block.state["damping"] = DEFAULT_DAMPING
	if not block.state.has("hop_count"):
		block.state["hop_count"] = DEFAULT_HOP_COUNT
	if not block.state.has("displaced"):
		block.state["displaced"] = DEFAULT_DISPLACED


## Reset physics state to defaults.
## Used for wave reset between propagation rounds.
static func reset(block: Block) -> void:
	block.state["force_vec"] = DEFAULT_FORCE_VEC
	block.state["velocity"] = DEFAULT_VELOCITY
	block.state["mass"] = DEFAULT_MASS
	block.state["damping"] = DEFAULT_DAMPING
	block.state["hop_count"] = DEFAULT_HOP_COUNT
	block.state["displaced"] = DEFAULT_DISPLACED


## Validate physics state keys in block.state.
## Returns array of error strings. Empty array = valid.
static func validate(block: Block) -> Array[String]:
	var errors: Array[String] = []

	# force_vec: must be present and Vector3
	if not block.state.has("force_vec"):
		errors.append("force_vec: missing")
	elif not block.state["force_vec"] is Vector3:
		errors.append("force_vec: expected Vector3, got %s" % typeof(block.state["force_vec"]))

	# velocity: must be present and Vector3
	if not block.state.has("velocity"):
		errors.append("velocity: missing")
	elif not block.state["velocity"] is Vector3:
		errors.append("velocity: expected Vector3, got %s" % typeof(block.state["velocity"]))

	# mass: must be present, numeric, in range
	if not block.state.has("mass"):
		errors.append("mass: missing")
	else:
		var m = block.state["mass"]
		if not (m is float or m is int):
			errors.append("mass: expected float, got %s" % typeof(m))
		elif float(m) < MASS_MIN or float(m) > MASS_MAX:
			errors.append("mass: value %.4f out of range [%.2f, %.1f]" % [float(m), MASS_MIN, MASS_MAX])

	# damping: must be present, numeric, in range
	if not block.state.has("damping"):
		errors.append("damping: missing")
	else:
		var d = block.state["damping"]
		if not (d is float or d is int):
			errors.append("damping: expected float, got %s" % typeof(d))
		elif float(d) < DAMPING_MIN or float(d) > DAMPING_MAX:
			errors.append("damping: value %.4f out of range [%.2f, %.2f]" % [float(d), DAMPING_MIN, DAMPING_MAX])

	# hop_count: must be present, int, >= 0
	if not block.state.has("hop_count"):
		errors.append("hop_count: missing")
	else:
		var h = block.state["hop_count"]
		if not h is int:
			errors.append("hop_count: expected int, got %s" % typeof(h))
		elif int(h) < 0:
			errors.append("hop_count: value %d must be >= 0" % int(h))

	# displaced: must be present and bool
	if not block.state.has("displaced"):
		errors.append("displaced: missing")
	elif not block.state["displaced"] is bool:
		errors.append("displaced: expected bool, got %s" % typeof(block.state["displaced"]))

	return errors


# =========================================================================
# Type-safe getters
# =========================================================================

## Get the accumulated force vector. Returns Vector3.ZERO if missing or wrong type.
static func get_force_vec(block: Block) -> Vector3:
	var v = block.state.get("force_vec", DEFAULT_FORCE_VEC)
	if v is Vector3:
		return v
	return DEFAULT_FORCE_VEC


## Get the last committed velocity. Returns Vector3.ZERO if missing or wrong type.
static func get_velocity(block: Block) -> Vector3:
	var v = block.state.get("velocity", DEFAULT_VELOCITY)
	if v is Vector3:
		return v
	return DEFAULT_VELOCITY


## Get the rest mass. Returns 1.0 if missing or wrong type.
static func get_mass(block: Block) -> float:
	var m = block.state.get("mass", DEFAULT_MASS)
	if m is float or m is int:
		return float(m)
	return DEFAULT_MASS


## Get the per-tick velocity damping factor. Returns 0.85 if missing or wrong type.
static func get_damping(block: Block) -> float:
	var d = block.state.get("damping", DEFAULT_DAMPING)
	if d is float or d is int:
		return float(d)
	return DEFAULT_DAMPING


## Get the propagation hop count. Returns 0 if missing or wrong type.
static func get_hop_count(block: Block) -> int:
	var h = block.state.get("hop_count", DEFAULT_HOP_COUNT)
	if h is int:
		return h
	return DEFAULT_HOP_COUNT


## Get whether block is displaced from rest this wave. Returns false if missing or wrong type.
static func is_displaced(block: Block) -> bool:
	var b = block.state.get("displaced", DEFAULT_DISPLACED)
	if b is bool:
		return b
	return DEFAULT_DISPLACED


# =========================================================================
# Type-safe setters
# =========================================================================

## Set the accumulated force vector in block.state.
static func set_force_vec(block: Block, v: Vector3) -> void:
	block.state["force_vec"] = v


## Set the last committed velocity in block.state.
static func set_velocity(block: Block, v: Vector3) -> void:
	block.state["velocity"] = v


## Set the rest mass in block.state.
static func set_mass(block: Block, m: float) -> void:
	block.state["mass"] = m


## Set the per-tick damping factor in block.state.
static func set_damping(block: Block, d: float) -> void:
	block.state["damping"] = d


## Set the propagation hop count in block.state.
static func set_hop_count(block: Block, n: int) -> void:
	block.state["hop_count"] = n


## Set whether block is displaced from rest this wave in block.state.
static func set_displaced(block: Block, b: bool) -> void:
	block.state["displaced"] = b
