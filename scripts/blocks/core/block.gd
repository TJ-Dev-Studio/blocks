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
## BOX/RAMP: Vector3(width, height, depth).
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

## 0 = primitive mesh (derived from collision_shape), 1 = custom scene, 2 = GLB model.
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

## Per-element color tint multiplied against palette material color.
## White (1,1,1,1) = no tint (default). Parsed from visual.color in JSON.
@export var color_tint: Color = Color.WHITE

## Per-element shader parameter overrides (roughness, metallic, surface_noise_scale, surface_noise_strength).
## Empty dict = use palette defaults. Keys are shader uniform names.
@export var material_params: Dictionary = {}

## Procedural material type. Empty string = use standard palette pipeline.
## Parsed from visual.material_type in JSON.
## Valid values: "bark", "stone", "moss", "water", "wood"
@export var material_type_id: String = ""

## Multi-material slot definitions. Empty = single material from material_id.
## Each dict: { "palette_key": String, "params": Dictionary (optional) }
## When non-empty, block is excluded from BlockMeshMerger batching.
@export var materials_list: Array = []

## Noise vertex displacement strength (0 = disabled). Applied post-merge to visual mesh only.
@export var noise_strength: float = 0.0

## Noise frequency scale (lower = smoother, higher = rougher). Applied post-merge.
@export var noise_scale: float = 3.0

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
# Cellular / LOD
# =========================================================================

## Subdivision depth (0 = original, 1+ = subdivided child).
@export var lod_level: int = 0

## Block ID of the block this was subdivided from.
@export var parent_lod_id: String = ""

## IDs of blocks produced by subdividing this block.
@export var child_lod_ids: PackedStringArray = PackedStringArray()

## Minimum dimensions before further subdivision stops.
@export var min_size: Vector3 = Vector3(0.1, 0.1, 0.1)

## DNA: rules governing how this block divides.
## Keys: axis_preference (int: -1=auto, 0=X, 1=Y, 2=Z),
##        inherit_tags (bool), inherit_connections (bool),
##        property_overrides (Dictionary)
@export var dna: Dictionary = {}

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
##
## Physics state keys (managed by BlockPhysicsState):
##   "force_vec"  — Vector3: accumulated force acting on block
##   "velocity"   — Vector3: last committed velocity (propagation layer)
##   "mass"       — float:   rest mass (default 1.0)
##   "damping"    — float:   per-tick velocity damping (default 0.85)
##   "hop_count"  — int:     propagation hops received this wave
##   "displaced"  — bool:    whether displaced from rest this wave
##
## Message types (see BlockMessages): FORCE_PROPAGATE, DISPLACEMENT_RESULT
var state: Dictionary = {}

## Path to the .block.json file this was loaded from (empty if programmatic).
var source_file: String = ""

## Runtime neuron (null if no neuron defined in block-file).
var neuron = null  # BlockNeuron

## Placement validators attached to this block. Array of BlockPlacementRule.
## Rules constrain where this block can be placed and which connections are valid.
## Parsed from "validators" in block-file JSON; can also be added at runtime.
var placement_rules: Array = []

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
		BlockCategories.SHAPE_BOX, BlockCategories.SHAPE_RAMP:
			half_x = collision_size.x * scale_factor / 2.0
			half_z = collision_size.z * scale_factor / 2.0
			height = position.y + collision_offset.y + collision_size.y * scale_factor
		BlockCategories.SHAPE_CYLINDER, BlockCategories.SHAPE_CAPSULE, BlockCategories.SHAPE_SPHERE:
			half_x = collision_size.x * scale_factor  # radius
			half_z = collision_size.x * scale_factor
			height = position.y + collision_offset.y + collision_size.y * scale_factor
		BlockCategories.SHAPE_CONE, BlockCategories.SHAPE_ROCK:
			half_x = collision_size.x * scale_factor  # radius
			half_z = collision_size.x * scale_factor
			height = position.y + collision_offset.y + collision_size.y * scale_factor
		BlockCategories.SHAPE_TORUS, BlockCategories.SHAPE_ARCH:
			half_x = collision_size.y * scale_factor  # outer_radius
			half_z = collision_size.y * scale_factor
			var ring_r := (collision_size.y - collision_size.x) * scale_factor
			height = position.y + collision_offset.y + ring_r * 2.0
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
	b.lod_level = 0
	b.parent_lod_id = ""
	b.child_lod_ids = PackedStringArray()
	b.color_tint = color_tint
	b.material_params = material_params.duplicate()
	b.material_type_id = material_type_id
	b.materials_list = materials_list.duplicate()
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


## Add a placement validator rule.
func add_placement_rule(rule) -> void:
	placement_rules.append(rule)


## Validate whether connecting to another block satisfies placement rules.
## Uses OR logic: valid if ANY rule accepts the connection. This allows
## blocks to have multiple connection types (e.g. endpoint_snap for horizontal
## neighbors + vertical_stack for blocks above/below).
## Returns: {"valid": bool, "errors": Array[String]}
## If no placement rules exist, connection is always valid.
func validate_connection_to(other: Block) -> Dictionary:
	if placement_rules.is_empty():
		return {"valid": true, "errors": [] as Array[String]}
	var all_errors: Array[String] = []
	for rule in placement_rules:
		var result: Dictionary = rule.check_connection(self, other)
		if result.get("valid", false):
			# At least one rule accepts → connection valid
			return {"valid": true, "errors": [] as Array[String]}
		all_errors.append_array(result.get("errors", []))
	if all_errors.is_empty():
		return {"valid": true, "errors": [] as Array[String]}
	return {"valid": false, "errors": all_errors}


## Get all valid snap positions for this block relative to an anchor.
## Combines results from all placement rules. If multiple rules provide
## positions, returns the intersection (positions satisfying all rules).
func get_all_snap_positions(anchor: Block) -> Array[Vector3]:
	if placement_rules.is_empty():
		return [] as Array[Vector3]
	if placement_rules.size() == 1:
		return placement_rules[0].get_snap_positions(self, anchor)
	# Multiple rules — use a temporary stack for intersection.
	# Load PlacementRuleStack at runtime to avoid circular class_name dependency
	# (Block -> PlacementRuleStack -> BlockPlacementRule -> Block).
	var stack_script := load("res://scripts/blocks/rules/placement_rule_stack.gd")
	var stack = stack_script.new()
	for rule in placement_rules:
		stack.add_rule(rule)
	return stack.get_snap_positions(self, anchor)


## Human-readable summary for debugging.
func summary() -> String:
	var extras := ""
	if has_peer_connections():
		extras += " conns=%d" % connections.size()
	if not state.is_empty():
		extras += " state=%s" % str(state.keys())
	if lod_level > 0:
		extras += " lod=%d" % lod_level
	if not child_lod_ids.is_empty():
		extras += " lod_children=%d" % child_lod_ids.size()
	return "[Block '%s' id=%s cat=%s shape=%s interact=%s pos=(%s)%s]" % [
		block_name, block_id,
		BlockCategories.category_name(category),
		BlockCategories.shape_name(collision_shape),
		BlockCategories.interaction_name(interaction),
		"%.1f, %.1f, %.1f" % [position.x, position.y, position.z],
		extras,
	]


# =========================================================================
# Cellular Division / Recombination
# =========================================================================

## Check if this block can be subdivided on the given axis (or any axis if -1).
func can_subdivide(axis: int = -1) -> bool:
	if collision_shape == BlockCategories.SHAPE_NONE:
		return false
	if axis == -1:
		for a in _valid_split_axes():
			if _dim_for_axis(a) >= _min_for_axis(a) * 2.0:
				return true
		return false
	if axis not in _valid_split_axes():
		return false
	return _dim_for_axis(axis) >= _min_for_axis(axis) * 2.0


## Split this block into smaller child blocks.
## axis: 0=X, 1=Y, 2=Z, -1=auto (use DNA preference or split all valid axes).
## Returns empty array if subdivision is not possible.
func subdivide(axis: int = -1) -> Array[Block]:
	var results: Array[Block] = []
	if not can_subdivide(axis):
		return results

	var axes_to_split: Array[int] = []
	if axis >= 0:
		axes_to_split = [axis]
	else:
		var pref: int = dna.get("axis_preference", -1)
		if pref >= 0 and pref <= 2 and can_subdivide(pref):
			axes_to_split = [pref]
		else:
			for a in _valid_split_axes():
				if _dim_for_axis(a) >= _min_for_axis(a) * 2.0:
					axes_to_split.append(a)

	if axes_to_split.is_empty():
		return results

	var child_count := int(pow(2, axes_to_split.size()))
	for i in range(child_count):
		results.append(_make_subdivision_child(i, axes_to_split))

	state["divided"] = true
	for child in results:
		child_lod_ids.append(child.block_id)

	return results


## Combine this block with another into a merged block.
## The merge axis is inferred from the position delta between the two blocks.
func merge_with(other: Block) -> Block:
	var merged := Block.new()
	merged.block_name = "%s_merged" % block_name.split("_sub")[0]
	merged.ensure_id()
	merged.category = category
	merged.collision_shape = collision_shape
	merged.interaction = interaction
	merged.collision_layer = collision_layer
	merged.collision_mask_layers = collision_mask_layers.duplicate()
	merged.collision_offset = collision_offset
	merged.server_collidable = server_collidable
	merged.mesh_type = mesh_type
	merged.material_id = material_id
	merged.shader_path = shader_path
	merged.cast_shadow = cast_shadow
	merged.color_tint = color_tint
	merged.material_params = material_params.duplicate()
	merged.material_type_id = material_type_id
	merged.materials_list = materials_list.duplicate()
	merged.scale_factor = scale_factor
	merged.min_size = min_size
	merged.dna = dna.duplicate(true)
	merged.lod_level = maxi(lod_level - 1, 0)

	if parent_lod_id == other.parent_lod_id:
		merged.parent_lod_id = parent_lod_id

	# Infer merge axis from position delta
	var diff := other.position - position
	var merge_axis := 0
	var max_diff := 0.0
	for a in [0, 1, 2]:
		if absf(diff[a]) > max_diff:
			max_diff = absf(diff[a])
			merge_axis = a

	merged.collision_size = collision_size
	merged.collision_size[merge_axis] = collision_size[merge_axis] * 2.0
	merged.position = (position + other.position) / 2.0

	# Mesh size follows collision if it was default
	if mesh_size != Vector3.ZERO or other.mesh_size != Vector3.ZERO:
		var ms := mesh_size if mesh_size != Vector3.ZERO else collision_size
		var oms := other.mesh_size if other.mesh_size != Vector3.ZERO else other.collision_size
		merged.mesh_size = ms
		merged.mesh_size[merge_axis] = ms[merge_axis] + oms[merge_axis]

	# Union tags
	var tag_set := {}
	for t in tags:
		tag_set[t] = true
	for t in other.tags:
		tag_set[t] = true
	merged.tags = PackedStringArray(tag_set.keys())

	return merged


# --- Subdivision helpers ---

## Return which axes are valid for splitting based on shape type.
func _valid_split_axes() -> Array[int]:
	match collision_shape:
		BlockCategories.SHAPE_BOX, BlockCategories.SHAPE_RAMP:
			return [0, 1, 2]
		BlockCategories.SHAPE_CYLINDER, BlockCategories.SHAPE_CAPSULE, \
				BlockCategories.SHAPE_SPHERE, BlockCategories.SHAPE_CONE:
			return [1]  # height axis only
		BlockCategories.SHAPE_TORUS, BlockCategories.SHAPE_ARCH, BlockCategories.SHAPE_ROCK:
			return []  # no subdivision for organic shapes
		_:
			return []


## Get the effective dimension for the given axis.
func _dim_for_axis(axis: int) -> float:
	match collision_shape:
		BlockCategories.SHAPE_BOX, BlockCategories.SHAPE_RAMP:
			return collision_size[axis]
		BlockCategories.SHAPE_CYLINDER, BlockCategories.SHAPE_CAPSULE, \
				BlockCategories.SHAPE_SPHERE, BlockCategories.SHAPE_CONE:
			if axis == 1:
				return collision_size.y  # height
			return collision_size.x * 2.0  # diameter
	return 0.0


## Get the minimum dimension for the given axis.
func _min_for_axis(axis: int) -> float:
	return min_size[axis]


## Create a single subdivision child at the given index for the given split axes.
func _make_subdivision_child(index: int, axes: Array[int]) -> Block:
	var child := Block.new()
	child.block_name = "%s_sub%d" % [block_name, index]
	child.ensure_id()
	child.category = category
	child.collision_shape = collision_shape
	child.interaction = interaction
	child.collision_layer = collision_layer
	child.collision_mask_layers = collision_mask_layers.duplicate()
	child.collision_offset = collision_offset
	child.server_collidable = server_collidable
	child.mesh_type = mesh_type
	child.material_id = material_id
	child.shader_path = shader_path
	child.cast_shadow = cast_shadow
	child.color_tint = color_tint
	child.material_params = material_params.duplicate()
	child.material_type_id = material_type_id
	child.scale_factor = scale_factor
	child.creator = creator
	child.version = version
	child.lod_level = lod_level + 1
	child.parent_lod_id = block_id
	child.min_size = min_size
	child.dna = dna.duplicate(true)

	if dna.get("inherit_tags", true):
		child.tags = tags.duplicate()

	# Calculate child dimensions and position offset
	var new_size := collision_size
	var pos_offset := Vector3.ZERO
	for axis_idx in range(axes.size()):
		var a: int = axes[axis_idx]
		var bit := (index >> axis_idx) & 1
		match collision_shape:
			BlockCategories.SHAPE_BOX, BlockCategories.SHAPE_RAMP:
				new_size[a] = collision_size[a] / 2.0
				var quarter := collision_size[a] / 4.0
				pos_offset[a] = -quarter if bit == 0 else quarter
			BlockCategories.SHAPE_CYLINDER, BlockCategories.SHAPE_CAPSULE, \
					BlockCategories.SHAPE_SPHERE:
				if a == 1:
					new_size.y = collision_size.y / 2.0
					var quarter := collision_size.y / 4.0
					pos_offset.y = -quarter if bit == 0 else quarter

	child.collision_size = new_size

	# Scale mesh_size proportionally if it was set
	if mesh_size != Vector3.ZERO:
		var ms := mesh_size
		for axis_idx in range(axes.size()):
			var a: int = axes[axis_idx]
			ms[a] = mesh_size[a] / 2.0
		child.mesh_size = ms

	child.position = position + pos_offset

	# Apply DNA property overrides
	var overrides: Dictionary = dna.get("property_overrides", {})
	for key in overrides:
		if key in child:
			child.set(key, overrides[key])

	return child
