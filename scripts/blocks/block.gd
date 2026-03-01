class_name Block
extends Resource
## Core building block primitive.
##
## Every game world object is composed of Blocks. A Block carries its own
## identity, collision geometry, interaction rules, visual description,
## metadata, and links to other blocks. The framework validates, builds,
## registers, and exports blocks automatically.
##
## Use as a Resource so blocks can be saved to .tres, loaded from disk,
## and inspected in the Godot editor.

# =========================================================================
# Identity
# =========================================================================

## Unique identifier (auto-generated if empty on registration).
@export var block_id: String = ""

## Human-readable name.
@export var block_name: String = ""

## Category — what kind of object this block represents.
## Use BlockCategories constants: TERRAIN, PROP, STRUCTURE, CREATURE, EFFECT, TRIGGER_CAT.
@export var category: int = BlockCategories.PROP

## Optional tags for filtering and search.
@export var tags: PackedStringArray = PackedStringArray()

# =========================================================================
# Collision
# =========================================================================

## Shape type for physics collision.
## Use BlockCategories constants: SHAPE_BOX, SHAPE_CYLINDER, SHAPE_CAPSULE, SHAPE_NONE.
@export var collision_shape: int = BlockCategories.SHAPE_BOX

## Dimensions of the collision shape.
## BOX: Vector3(width, height, depth).
## CYLINDER/CAPSULE: Vector3(radius, height, 0) — z unused.
@export var collision_size: Vector3 = Vector3(1.0, 1.0, 1.0)

## Offset of collision center relative to block origin.
@export var collision_offset: Vector3 = Vector3.ZERO

## Which collision layer this block lives on (1-32).
## Use CollisionLayers constants: WORLD, PLATFORM, TRUNK, BRIDGE, etc.
@export var collision_layer: int = CollisionLayers.WORLD

## Additional layers this block should detect (empty = static, doesn't detect).
@export var collision_mask_layers: Array[int] = []

# =========================================================================
# Interaction
# =========================================================================

## How entities interact with this block.
## Use BlockCategories constants: INTERACT_SOLID, INTERACT_WALKABLE, etc.
@export var interaction: int = BlockCategories.INTERACT_SOLID

## Trigger radius (only meaningful when interaction is INTERACT_TRIGGER).
@export var trigger_radius: float = 0.0

## Whether to include in server-side collision export.
@export var server_collidable: bool = true

# =========================================================================
# Visual
# =========================================================================

## 0 = primitive mesh (derived from collision_shape), 1 = custom scene.
@export var mesh_type: int = 0

## Primitive mesh dimensions (if Vector3.ZERO, uses collision_size).
@export var mesh_size: Vector3 = Vector3.ZERO

## Material palette key (looked up via BlockMaterials).
@export var material_id: String = "default"

## Optional shader resource path.
@export var shader_path: String = ""

## Optional custom scene path (when mesh_type == 1).
@export var scene_path: String = ""

## Whether this block casts shadows.
@export var cast_shadow: bool = false

# =========================================================================
# Placement (instance-specific)
# =========================================================================

## World position.
@export var position: Vector3 = Vector3.ZERO

## Y-axis rotation in radians.
@export var rotation_y: float = 0.0

## Uniform scale factor.
@export var scale_factor: float = 1.0

# =========================================================================
# Metadata
# =========================================================================

## Who created this block.
## Use BlockCategories constants: CREATOR_HUMAN, CREATOR_AI, CREATOR_SYSTEM.
@export var creator: int = BlockCategories.CREATOR_SYSTEM

## Schema version for forward compatibility.
@export var version: int = 1

## Creation timestamp (Unix seconds, 0 = unset).
@export var created_at: int = 0

# =========================================================================
# Links (parent/child hierarchy for compound objects)
# =========================================================================

## Parent block ID (empty = root / standalone).
@export var parent_id: String = ""

## Child block IDs.
@export var child_ids: PackedStringArray = PackedStringArray()

# =========================================================================
# Peer Connections (arbitrary block-to-block edges, separate from hierarchy)
# =========================================================================

## IDs of peer-connected blocks (bidirectional edges for graphs like power grids).
@export var connections: PackedStringArray = PackedStringArray()

# =========================================================================
# Runtime state (not exported — managed by BlockRegistry)
# =========================================================================

## Monotonic counter for unique ID generation (shared across all instances).
static var _id_counter: int = 0

## The Node3D instance built from this block (null until built).
var node: Node3D = null

## Whether this block is currently active in the world.
var active: bool = false

## Timestamps for lifecycle tracking.
var instantiated_at: int = 0
var destroyed_at: int = 0

## Mutable runtime state dictionary. Tracks dynamic properties like
## "powered", "health", "temperature". Not persisted to .tres.
var state: Dictionary = {}

# =========================================================================
# Methods
# =========================================================================

## Generate a unique block ID if none is set.
func ensure_id() -> void:
	if block_id.is_empty():
		_id_counter += 1
		block_id = "%s_%s_%d_%d" % [
			BlockCategories.category_name(category),
			block_name.to_snake_case() if not block_name.is_empty() else "unnamed",
			Time.get_ticks_msec(),
			_id_counter,
		]


## Convert to server-side collision box dictionary.
## Format: {min_x, max_x, min_z, max_z, height, one_way?, bridge?}
## Returns empty dict if not server_collidable or no collision shape.
func to_collision_dict() -> Dictionary:
	if not server_collidable or collision_shape == BlockCategories.SHAPE_NONE:
		return {}

	var half_x: float
	var half_z: float
	var height: float

	match collision_shape:
		BlockCategories.SHAPE_BOX:
			half_x = collision_size.x * scale_factor / 2.0
			half_z = collision_size.z * scale_factor / 2.0
			height = position.y + collision_offset.y + collision_size.y * scale_factor
		BlockCategories.SHAPE_CYLINDER, BlockCategories.SHAPE_CAPSULE:
			half_x = collision_size.x * scale_factor  # radius
			half_z = collision_size.x * scale_factor
			height = position.y + collision_offset.y + collision_size.y * scale_factor
		_:
			return {}

	var cx := position.x + collision_offset.x
	var cz := position.z + collision_offset.z

	var result := {
		"min_x": cx - half_x,
		"max_x": cx + half_x,
		"min_z": cz - half_z,
		"max_z": cz + half_z,
		"height": height,
	}

	if interaction == BlockCategories.INTERACT_ONE_WAY:
		result["one_way"] = true
	if interaction == BlockCategories.INTERACT_BRIDGE:
		result["bridge"] = true

	return result


## Clone this block with a new auto-generated ID.
func duplicate_block() -> Block:
	var b := duplicate(true) as Block
	b.block_id = ""
	b.ensure_id()
	b.node = null
	b.active = false
	b.instantiated_at = 0
	b.destroyed_at = 0
	b.state = {}
	b.connections = PackedStringArray()
	return b


## Add a child link (by block_id).
func add_child_link(child_block_id: String) -> void:
	if child_block_id not in child_ids:
		child_ids.append(child_block_id)


## Remove a child link.
func remove_child_link(child_block_id: String) -> void:
	var idx := -1
	for i in range(child_ids.size()):
		if child_ids[i] == child_block_id:
			idx = i
			break
	if idx >= 0:
		child_ids.remove_at(idx)


## Check if this block has a parent.
func has_parent() -> bool:
	return not parent_id.is_empty()


## Check if this block has children.
func has_children() -> bool:
	return not child_ids.is_empty()


# =========================================================================
# Peer Connection Methods
# =========================================================================

## Add a peer connection (by block_id). Idempotent.
func add_connection(peer_block_id: String) -> void:
	if peer_block_id not in connections:
		connections.append(peer_block_id)


## Remove a peer connection.
func remove_connection(peer_block_id: String) -> void:
	var idx := -1
	for i in range(connections.size()):
		if connections[i] == peer_block_id:
			idx = i
			break
	if idx >= 0:
		connections.remove_at(idx)


## Check if this block has any peer connections.
func has_peer_connections() -> bool:
	return not connections.is_empty()


## Check if connected to a specific peer.
func is_connected_to(peer_block_id: String) -> bool:
	return peer_block_id in connections


## Human-readable summary for debugging.
func summary() -> String:
	var extras := ""
	if has_peer_connections():
		extras += " conns=%d" % connections.size()
	if not state.is_empty():
		extras += " state=%s" % str(state.keys())
	return "[Block '%s' id=%s cat=%s shape=%s interact=%s pos=(%s)%s]" % [
		block_name, block_id,
		BlockCategories.category_name(category),
		BlockCategories.shape_name(collision_shape),
		BlockCategories.interaction_name(interaction),
		"%.1f, %.1f, %.1f" % [position.x, position.y, position.z],
		extras,
	]
