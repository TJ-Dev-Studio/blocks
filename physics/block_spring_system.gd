class_name BlockSpringSystem
extends RefCounted
## Centralized spring physics update loop.
##
## Manages all spring-capable blocks. Called once per display frame from
## BlocksFactory.update_springs(). Only actively-displaced blocks run
## per-frame updates — blocks at rest are skipped for performance.
##
## Propagation flow:
##   1. Frog hits block A → apply_impulse(A, impulse, "player")
##   2. BlockSpring A schedules delayed impulses to connected neighbors
##   3. Each frame: system ticks pending impulses, decrements delays
##   4. When delay hits 0: neighbor receives attenuated impulse
##   5. Neighbor schedules ITS neighbors → ripple wave
##   6. Attenuation per hop: 0.6^n → fades: 0.6, 0.36, 0.22, 0.13...

## Preload to avoid class_name dependency
const _BlockSpring = preload("res://addons/blocks/physics/block_spring.gd")

## All spring-capable blocks: {block_id: BlockSpring}
var _springs: Dictionary = {}

## Only blocks currently in motion (performance optimization).
var _active_ids: Array[String] = []

## Reference to the block registry for connection lookups.
var _registry = null  # BlockRegistry (untyped to avoid cyclic dep)

## Optional callback invoked on every impulse: func(block_id, impulse, from_id).
## Follows the same Callable extension pattern as BlockMaterials.shader_param_injector.
## Set by the game layer (e.g. BlocksFactory) to wire audio or VFX on impact.
var on_impulse_applied: Callable = Callable()


# =========================================================================
# Registration
# =========================================================================

## Register a block for spring physics. Reads options from neuron.
func register_block(block: Block) -> void:
	if _springs.has(block.block_id):
		return  # Already registered

	var spring: BlockSpring = _BlockSpring.new()
	spring.init_from_block(block)
	_springs[block.block_id] = spring


## Unregister a block from spring physics.
func unregister_block(block_id: String) -> void:
	_springs.erase(block_id)
	_active_ids.erase(block_id)


## Check if a block has spring physics.
func has_spring(block_id: String) -> bool:
	return _springs.has(block_id)


## Get the spring state for a block (or null).
func get_spring(block_id: String) -> BlockSpring:
	return _springs.get(block_id, null) as BlockSpring


# =========================================================================
# Impulse application
# =========================================================================

## Apply an impulse to a block. Activates it and schedules propagation.
func apply_impulse(block_id: String, impulse: Vector3, from_id: String) -> void:
	var spring: BlockSpring = _springs.get(block_id, null) as BlockSpring
	if spring == null:
		return  # Not a spring block

	# Apply velocity change
	spring.apply_impulse(impulse, from_id)

	# Notify external listeners (audio, VFX)
	if on_impulse_applied.is_valid():
		on_impulse_applied.call(block_id, impulse, from_id)

	# Schedule propagation to neighbors
	if _registry:
		var block: Block = _registry.get_block(block_id)
		if block:
			spring.schedule_propagation(impulse, from_id, block)

	# Add to active set if not already there
	if block_id not in _active_ids:
		_active_ids.append(block_id)


# =========================================================================
# Per-frame update
# =========================================================================

## Advance all active springs by dt seconds.
## Call once per display frame from BlocksFactory.update_springs().
func step(dt: float) -> void:
	if _active_ids.is_empty() or _registry == null:
		return

	# Collect propagation requests from all active springs
	var all_propagations: Array = []

	# Process active springs (iterate copy to allow removal)
	var ids_to_process := _active_ids.duplicate()
	var ids_to_deactivate: Array[String] = []

	for bid in ids_to_process:
		var spring: BlockSpring = _springs.get(bid, null) as BlockSpring
		if spring == null:
			ids_to_deactivate.append(bid)
			continue

		var block: Block = _registry.get_block(bid)
		if block == null:
			ids_to_deactivate.append(bid)
			continue

		# Step the spring physics
		var propagations: Array = spring.step(dt, block, _registry)
		all_propagations.append_array(propagations)

		# Check if spring went to sleep (freed blocks stay active for despawn timer)
		if not spring.is_active and spring._pending_propagations.is_empty() and not spring.freed:
			ids_to_deactivate.append(bid)
		# Freed block that has despawned (node freed) — remove from system entirely
		elif spring.freed and not spring.is_active:
			ids_to_deactivate.append(bid)
			_springs.erase(bid)

	# Remove sleeping springs from active set
	for bid in ids_to_deactivate:
		_active_ids.erase(bid)

	# Dispatch propagation requests (impulses to neighbors)
	# Cap per-frame dispatches to prevent runaway propagation
	var dispatch_count: int = 0
	const MAX_DISPATCHES_PER_FRAME: int = 50
	for prop in all_propagations:
		if dispatch_count >= MAX_DISPATCHES_PER_FRAME:
			break
		var target_id: String = prop.get("target_id", "")
		var impulse: Vector3 = prop.get("impulse", Vector3.ZERO)
		var from_id: String = prop.get("from_id", "")

		if target_id.is_empty() or impulse.length() < 0.01:
			continue

		# Apply to target (this may activate it and schedule further propagation)
		apply_impulse(target_id, impulse, from_id)
		dispatch_count += 1


# =========================================================================
# Queries
# =========================================================================

## Get count of currently active (moving) spring blocks.
func get_active_count() -> int:
	return _active_ids.size()


## Get total registered spring block count.
func get_registered_count() -> int:
	return _springs.size()


## Check if any springs are currently active.
func is_active() -> bool:
	return not _active_ids.is_empty()
