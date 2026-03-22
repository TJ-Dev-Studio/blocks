class_name BlockLodController
extends RefCounted
## Distance-based LOD controller for the blocks system.
##
## Drives the existing Block cellular subdivision/merge to create
## the dense-forest-near, sparse-forest-far visual effect.
##
## LOD Tiers (XZ distance from camera):
##   Tier 0: 0-30m    -> lod_level 3 (8 sub-blocks per tree, full detail)
##   Tier 1: 30-60m   -> lod_level 2 (4 sub-blocks, simplified)
##   Tier 2: 60-120m  -> lod_level 1 (2 sub-blocks, trunk + canopy blob)
##   Tier 3: 120m+    -> lod_level 0 (1 block, colored box/cylinder)

const LOD_TIERS := [
	{"max_distance": 30.0, "target_lod": 3},
	{"max_distance": 60.0, "target_lod": 2},
	{"max_distance": 120.0, "target_lod": 1},
]
# Beyond 120m -> lod_level 0 (implicit)

## Minimum time between LOD updates (seconds).
const LOD_UPDATE_INTERVAL := 0.5

## Maximum LOD operations (subdivide or merge) per update.
const MAX_LOD_OPS_PER_UPDATE := 8

## Tags that mark blocks as LOD-eligible (only these participate in LOD).
const LOD_TAGS := ["lod", "forest", "tree"]

## Blocks that are forced to max LOD regardless of distance.
var forced_max_lod: PackedStringArray = PackedStringArray()

var _registry: BlockRegistry = null
var _last_update_time: float = 0.0
var _pending_ops: Array = []  # [{block_id, target_lod}]


## Initialize with a registry reference.
func init(registry: BlockRegistry) -> void:
	_registry = registry


## Main tick. Checks distances, queues LOD operations, processes budget.
## Call from BlocksFactory.update_lod().
func update(camera_pos: Vector3, world_root: Node3D) -> void:
	if not _registry:
		return

	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_update_time < LOD_UPDATE_INTERVAL:
		return
	_last_update_time = now

	# Find all LOD-eligible blocks
	var active_blocks := _registry.get_active_blocks()
	_pending_ops.clear()

	for block in active_blocks:
		if not _is_lod_eligible(block):
			continue

		# Check forced max LOD
		if block.block_id in forced_max_lod:
			if block.lod_level < 3 and block.can_subdivide():
				_pending_ops.append({"block_id": block.block_id, "target_lod": 3})
			continue

		var target := _compute_target_lod(block.position, camera_pos)
		if block.lod_level != target:
			_pending_ops.append({"block_id": block.block_id, "target_lod": target})

	# Process within budget
	_process_pending_ops(world_root)


## Force a block to always render at max LOD (e.g. Mother Tree).
func force_max_lod(block_id: String) -> void:
	if block_id not in forced_max_lod:
		forced_max_lod.append(block_id)


## Remove forced max LOD.
func unforce_max_lod(block_id: String) -> void:
	var idx := -1
	for i in range(forced_max_lod.size()):
		if forced_max_lod[i] == block_id:
			idx = i
			break
	if idx >= 0:
		forced_max_lod.remove_at(idx)


# =========================================================================
# Internal
# =========================================================================

## Determine target LOD level based on XZ distance from camera.
func _compute_target_lod(block_pos: Vector3, camera_pos: Vector3) -> int:
	var dx := block_pos.x - camera_pos.x
	var dz := block_pos.z - camera_pos.z
	var dist := sqrt(dx * dx + dz * dz)

	for tier: Dictionary in LOD_TIERS:
		if dist <= tier["max_distance"]:
			return tier["target_lod"]

	return 0  # Beyond all tiers -> coarsest LOD


## Check if a block should participate in LOD.
func _is_lod_eligible(block: Block) -> bool:
	# GLB/scene mesh blocks can't be subdivided into primitives — skip them.
	if block.mesh_type != 0:
		return false
	for tag in LOD_TAGS:
		if tag in block.tags:
			return true
	return false


## Execute up to MAX_LOD_OPS_PER_UPDATE operations.
func _process_pending_ops(world_root: Node3D) -> void:
	var ops_done := 0

	for op: Dictionary in _pending_ops:
		if ops_done >= MAX_LOD_OPS_PER_UPDATE:
			break

		var block_id: String = op["block_id"]
		var target_lod: int = op["target_lod"]
		var block := _registry.get_block(block_id)

		if block == null or not block.active:
			continue

		if block.lod_level < target_lod:
			# Need more detail — subdivide
			_subdivide_toward(block, target_lod, world_root)
			ops_done += 1

		elif block.lod_level > target_lod:
			# Need less detail — merge toward parent
			_merge_toward(block, target_lod, world_root)
			ops_done += 1


## Subdivide a block one level toward the target, building new child nodes.
## Maximum recursion depth for subdivision to prevent memory explosion.
const MAX_SUBDIVIDE_DEPTH := 8

func _subdivide_toward(block: Block, target_lod: int, world_root: Node3D, depth: int = 0) -> void:
	if depth >= MAX_SUBDIVIDE_DEPTH:
		push_warning("[LOD] Subdivision depth limit reached for block %s" % block.block_id)
		return
	var children := _registry.subdivide_block(block.block_id)
	if children.is_empty():
		return

	# Destroy parent's visual node
	if block.node and is_instance_valid(block.node):
		block.node.queue_free()
		block.node = null

	# Build child nodes
	for child in children:
		if child.active and child.collision_shape != BlockCategories.SHAPE_NONE:
			BlockBuilder.build(child, world_root)

		# Recurse if still below target
		if child.lod_level < target_lod and child.can_subdivide():
			_subdivide_toward(child, target_lod, world_root, depth + 1)


## Merge a block with its siblings toward the target LOD level.
func _merge_toward(block: Block, target_lod: int, world_root: Node3D) -> void:
	if block.parent_lod_id.is_empty():
		return

	var parent := _registry.get_block(block.parent_lod_id)
	if parent == null:
		return

	# Collect all active siblings from the same parent
	var sibling_ids: Array[String] = []
	for cid in parent.child_lod_ids:
		var sibling := _registry.get_block(cid)
		if sibling != null and sibling.active:
			sibling_ids.append(cid)

	if sibling_ids.size() < 2:
		return

	# Free sibling nodes before merge
	for sid in sibling_ids:
		var sibling := _registry.get_block(sid)
		if sibling and sibling.node and is_instance_valid(sibling.node):
			sibling.node.queue_free()
			sibling.node = null

	var merged := _registry.merge_blocks(sibling_ids)
	if merged == null:
		return

	# Build merged node
	if merged.active and merged.collision_shape != BlockCategories.SHAPE_NONE:
		BlockBuilder.build(merged, world_root)

	# Continue merging if still above target
	if merged.lod_level > target_lod:
		_merge_toward(merged, target_lod, world_root)
