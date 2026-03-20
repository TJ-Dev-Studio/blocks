class_name BlockSpring
extends RefCounted
## Per-block spring physics state.
##
## Tracks displacement from rest position, velocity, and pending impulses.
## Reads spring constants from BlockNeuron options (spring_k, damping, mass, etc.)
## so different block types have different material feels (straw vs cinderblock).
##
## Physics model: damped harmonic oscillator
##   F_spring = -spring_k * displacement
##   F_damp   = -damping * velocity
##   accel    = (F_spring + F_damp) / mass
##
## When all connections are severed the block enters "freed" mode:
##   - Spring restoring force is disabled
##   - Gravity pulls the block down (9.8 m/s²)
##   - Light air damping slows lateral drift
##   - Block despawns after FREE_LIFETIME seconds
##
## Propagation: when this block receives an impulse, it schedules delayed
## impulses to each connected neighbor. The delay + attenuation creates a
## ripple wave through the connection graph.

# =========================================================================
# Spring constants (read from neuron.options at init)
# =========================================================================

## Spring stiffness. Higher = snappier return. Cinderblock ~200, straw ~15.
var spring_k: float = 50.0

## Velocity damping. Prevents infinite oscillation.
## Critical damping ≈ 2 * sqrt(spring_k * mass).
var damping: float = 5.0

## Block mass. Heavier = less displacement from same impulse.
var mass: float = 1.0

## Seconds before displacement transfers to each connected neighbor.
var propagation_delay: float = 0.08

## Fraction of impulse passed to each neighbor (0–1). Attenuates per hop.
var propagation_strength: float = 0.6

## Displacement magnitude at which connections sever. 0 = unbreakable.
var break_distance: float = 3.0

## Maximum displacement clamp (prevents blocks flying to infinity).
var max_displacement: float = 5.0

## Gravity acceleration applied when block is freed (all connections broken).
const GRAVITY: float = 9.8

## Light air damping for freed blocks (gentle slowdown, not spring damping).
const FREE_AIR_DAMPING: float = 0.5

## How long a freed block lives before despawning (seconds).
const FREE_LIFETIME: float = 4.0

## Ground plane Y — freed blocks stop falling here.
const GROUND_Y: float = 0.0

# =========================================================================
# Runtime state
# =========================================================================

## Original world position (set once at init, never changes).
var rest_position: Vector3 = Vector3.ZERO

## Current offset from rest position.
var displacement: Vector3 = Vector3.ZERO

## Current motion velocity.
var velocity: Vector3 = Vector3.ZERO

## Whether this spring needs per-frame updates.
var is_active: bool = false

## Block ID this spring belongs to.
var block_id: String = ""

## Whether this block has been freed (all connections severed → gravity mode).
var freed: bool = false

## How long this block has been in freed state (for despawn timer).
var _free_age: float = 0.0

## Total number of connections this block started with (set at first impulse).
var _original_connection_count: int = -1

## Pending impulses to propagate: [{impulse: Vector3, delay_remaining: float, target_id: String}]
var _pending_propagations: Array = []

## Connections that have been severed (don't re-break or re-propagate).
var broken_connections: PackedStringArray = PackedStringArray()

## Threshold for deactivation.
const SLEEP_THRESHOLD := 0.005

## Maximum pending propagations to prevent exponential explosion.
## If a block has this many queued, new propagations are dropped.
const MAX_PENDING_PROPAGATIONS := 20

## Minimum impulse magnitude to bother propagating (skip tiny ripples).
const MIN_PROPAGATION_IMPULSE := 0.05


# =========================================================================
# Initialization
# =========================================================================

## Initialize from a Block's neuron options.
func init_from_block(block: Block) -> void:
	block_id = block.block_id
	rest_position = block.position

	# Read spring constants from neuron options (if present)
	if block.neuron:
		spring_k = block.neuron.get_option("spring_k", spring_k)
		damping = block.neuron.get_option("damping", damping)
		mass = block.neuron.get_option("mass", mass)
		propagation_delay = block.neuron.get_option("propagation_delay", propagation_delay)
		propagation_strength = block.neuron.get_option("propagation_strength", propagation_strength)
		break_distance = block.neuron.get_option("break_distance", break_distance)
		max_displacement = block.neuron.get_option("max_displacement", max_displacement)


# =========================================================================
# Impulse
# =========================================================================

## Apply an immediate impulse (adds to velocity).
## from_id: who sent it ("player" for frog contact, "fly_projectile", or a block_id).
func apply_impulse(impulse: Vector3, from_id: String) -> void:
	# F = impulse, v += F/mass
	velocity += impulse / mass
	is_active = true

	# Projectile hits get extra upward kick for dramatic effect
	if from_id == "fly_projectile":
		velocity.y += 1.0 / mass


## Schedule propagation impulses to connected neighbors.
## Called internally after this block receives an impulse.
## Includes safety limits to prevent exponential explosion in dense graphs.
func schedule_propagation(impulse: Vector3, from_id: String, block: Block) -> void:
	# Safety: cap pending queue to prevent exponential growth
	if _pending_propagations.size() >= MAX_PENDING_PROPAGATIONS:
		return

	var attenuated_impulse: Vector3 = impulse * propagation_strength

	# Skip if attenuated impulse is too weak to matter
	if attenuated_impulse.length() < MIN_PROPAGATION_IMPULSE:
		return

	for conn_id in block.connections:
		# Don't propagate back to sender
		if conn_id == from_id:
			continue
		# Don't propagate through broken connections
		if conn_id in broken_connections:
			continue
		# Safety: don't exceed cap mid-loop
		if _pending_propagations.size() >= MAX_PENDING_PROPAGATIONS:
			break
		_pending_propagations.append({
			"impulse": attenuated_impulse,
			"delay_remaining": propagation_delay,
			"target_id": conn_id,
		})


# =========================================================================
# Physics step
# =========================================================================

## Advance one physics frame. Returns Array of propagation requests:
## [{target_id: String, impulse: Vector3, from_id: String}]
func step(dt: float, block: Block, registry) -> Array:
	var propagation_requests: Array = []

	# --- Process pending propagations (tick down delays) ---
	var still_pending: Array = []
	for p in _pending_propagations:
		p["delay_remaining"] -= dt
		if p["delay_remaining"] <= 0.0:
			# Fire! Return as a propagation request for the system to dispatch.
			propagation_requests.append({
				"target_id": p["target_id"],
				"impulse": p["impulse"],
				"from_id": block_id,
			})
		else:
			still_pending.append(p)
	_pending_propagations = still_pending

	# --- Track original connection count on first activity ---
	if _original_connection_count < 0:
		_original_connection_count = block.connections.size()

	# --- FREED MODE: gravity + air damping, no spring force ---
	if freed:
		_free_age += dt

		# Gravity
		velocity.y -= GRAVITY * dt

		# Light air damping (not the heavy spring damping)
		velocity.x *= (1.0 - FREE_AIR_DAMPING * dt)
		velocity.z *= (1.0 - FREE_AIR_DAMPING * dt)

		# Integrate
		displacement += velocity * dt

		# Ground collision: stop falling at ground plane
		var world_y: float = rest_position.y + displacement.y
		if world_y < GROUND_Y:
			displacement.y = GROUND_Y - rest_position.y
			velocity.y = 0.0
			# Friction on ground
			velocity.x *= 0.9
			velocity.z *= 0.9

		# Update visual
		if block.node and is_instance_valid(block.node):
			block.node.position = rest_position + displacement
			# Tumble rotation for drama
			block.node.rotation.x += velocity.z * dt * 2.0
			block.node.rotation.z -= velocity.x * dt * 2.0

		# Despawn after FREE_LIFETIME: fade out and free
		if _free_age > FREE_LIFETIME:
			if block.node and is_instance_valid(block.node):
				block.node.queue_free()
				block.node = null
			is_active = false

		# Sleeping on ground
		if absf(velocity.x) < 0.05 and absf(velocity.z) < 0.05 \
				and absf(velocity.y) < 0.05 and world_y <= GROUND_Y + 0.05:
			# Still active for despawn timer, but skip physics
			pass

		return propagation_requests

	# --- SPRING MODE: F = -k*x - c*v ---
	var spring_force: Vector3 = -spring_k * displacement
	var damp_force: Vector3 = -damping * velocity
	var acceleration: Vector3 = (spring_force + damp_force) / mass

	# --- Semi-implicit Euler integration ---
	velocity += acceleration * dt
	displacement += velocity * dt

	# --- Clamp displacement ---
	if displacement.length() > max_displacement:
		displacement = displacement.normalized() * max_displacement
		# Also reduce velocity to prevent continued pushing past clamp
		var outward_vel := velocity.dot(displacement.normalized())
		if outward_vel > 0:
			velocity -= displacement.normalized() * outward_vel

	# --- Check connection breaking ---
	if break_distance > 0.0 and displacement.length() > break_distance:
		_check_break_connections(block, registry)

	# --- Check if ALL connections are now broken → enter freed mode ---
	if _original_connection_count > 0 and block.connections.size() == 0 and not freed:
		_enter_freed_mode(block)

	# --- Update visual position ---
	if block.node and is_instance_valid(block.node):
		block.node.position = rest_position + displacement

	# --- Sleep check ---
	if displacement.length() < SLEEP_THRESHOLD and velocity.length() < SLEEP_THRESHOLD \
			and _pending_propagations.is_empty():
		displacement = Vector3.ZERO
		velocity = Vector3.ZERO
		is_active = false
		# Snap visual back to rest
		if block.node and is_instance_valid(block.node):
			block.node.position = rest_position

	return propagation_requests


# =========================================================================
# Connection breaking
# =========================================================================

## Check if displacement exceeds break_distance and sever connections.
func _check_break_connections(block: Block, registry) -> void:
	if registry == null:
		return

	var to_break: PackedStringArray = PackedStringArray()

	for conn_id in block.connections:
		if conn_id in broken_connections:
			continue
		# Check if neighbor has diverged enough
		var neighbor: Block = registry.get_block(conn_id)
		if neighbor == null:
			continue

		# Relative displacement between this block and neighbor
		# If they've moved too far apart, break the link
		var my_world_pos: Vector3 = rest_position + displacement
		var neighbor_world_pos: Vector3 = neighbor.position  # neighbor may have its own spring
		# Try to get neighbor's spring displacement too
		# (The system will handle this via the spring lookup)

		# Simple check: if THIS block is beyond break distance, start breaking
		if displacement.length() > break_distance:
			to_break.append(conn_id)

	# Sever connections
	for conn_id in to_break:
		broken_connections.append(conn_id)
		block.remove_connection(conn_id)
		var neighbor: Block = registry.get_block(conn_id)
		if neighbor:
			neighbor.remove_connection(block_id)
		# Cancel any pending propagations to this neighbor
		_pending_propagations = _pending_propagations.filter(
			func(p): return p["target_id"] != conn_id
		)

	if not to_break.is_empty():
		print("[BlockSpring] %s broke %d connections (displacement: %.2fm, remaining: %d)" % [
			block_id, to_break.size(), displacement.length(), block.connections.size()])
		# Flash the block orange on break
		if block.node and is_instance_valid(block.node):
			var mesh := block.node.get_node_or_null("Mesh") as MeshInstance3D
			if mesh and mesh.material_override is StandardMaterial3D:
				var mat: StandardMaterial3D = mesh.material_override.duplicate()
				mat.emission_enabled = true
				mat.emission = Color(1.0, 0.5, 0.0)
				mat.emission_energy_multiplier = 2.0
				mesh.material_override = mat


## Enter freed mode — all connections severed, block becomes a physics debris.
func _enter_freed_mode(block: Block) -> void:
	freed = true
	_free_age = 0.0
	# Disable the StaticBody3D collision so freed blocks don't block projectiles/player
	if block.node and is_instance_valid(block.node):
		var body := block.node.get_node_or_null("Body") as StaticBody3D
		if body:
			body.collision_layer = 0
			body.collision_mask = 0
	print("[BlockSpring] %s FREED — entering gravity mode" % block_id)
