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

## Minimum time between full LOD scans (seconds).
const LOD_SCAN_INTERVAL := 1.0

## Minimum camera XZ movement (meters) required to trigger a new scan.
## If the camera hasn't moved this far since the last scan, skip it.
## This eliminates the 1-second stutter when the player is standing still
## or moving slowly (most common while walking).
const LOD_MIN_MOVE_SQ := 4.0  # 2m threshold (squared for cheap comparison)

## Maximum BlockBuilder.build() calls per frame (the actual expensive work).
## 2 builds ≈ 2-4ms, keeps frame time contribution under 5ms.
const MAX_BUILDS_PER_FRAME := 2

## Tags that mark blocks as LOD-eligible (only these participate in LOD).
const LOD_TAGS := ["lod", "forest", "tree"]

## Blocks that are forced to max LOD regardless of distance.
var forced_max_lod: PackedStringArray = PackedStringArray()

var _registry: BlockRegistry = null
var _last_scan_time: float = 0.0
var _last_scan_pos: Vector3 = Vector3(1e10, 0.0, 1e10)  # Far away to force first scan
var _pending_ops: Array = []  # [{block_id, target_lod}]
var _world_root: Node3D = null
var _builds_this_frame: int = 0

## Cached list of LOD-eligible blocks, rebuilt on demand.
## Avoids iterating all blocks (potentially thousands) every scan.
var _lod_eligible_ids: PackedStringArray = PackedStringArray()
var _lod_cache_dirty: bool = true


## Initialize with a registry reference.
func init(registry: BlockRegistry) -> void:
	_registry = registry
	_lod_cache_dirty = true


## Mark the eligible cache as dirty (call when blocks are registered/unregistered).
func invalidate_lod_cache() -> void:
	_lod_cache_dirty = true


## Main tick — called every frame from BlocksFactory.update_lod().
## Scans for LOD changes periodically, then drains pending ops 1-2 per frame.
func update(camera_pos: Vector3, world_root: Node3D) -> void:
	if not _registry:
		return

	_world_root = world_root
	_builds_this_frame = 0

	# --- Periodic scan: discover which blocks need LOD changes ---
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_scan_time >= LOD_SCAN_INTERVAL:
		# Skip the scan if the camera hasn't moved significantly since last scan.
		# This avoids the 1-second GDScript loop spike when the player is walking
		# or standing still — LOD tiers only change when the player moves 30-60m+.
		var dx := camera_pos.x - _last_scan_pos.x
		var dz := camera_pos.z - _last_scan_pos.z
		var moved_sq := dx * dx + dz * dz
		if moved_sq >= LOD_MIN_MOVE_SQ or _lod_cache_dirty:
			_last_scan_time = now
			_last_scan_pos = camera_pos
			# Rebuild the eligible cache if blocks were added/removed since last scan
			if _lod_cache_dirty:
				_rebuild_lod_cache()
			_scan_blocks(camera_pos)
		else:
			# Reset timer so we check again next interval — don't let timer drift
			# past multiple intervals without ever scanning.
			_last_scan_time = now

	# --- Per-frame drain: execute 1-2 pending ops ---
	_drain_pending_ops()


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

## Rebuild the list of LOD-eligible block IDs from the registry.
## Called once after world load and whenever blocks are added/removed.
## Amortizes the per-block tag check so _scan_blocks() only sees eligible blocks.
func _rebuild_lod_cache() -> void:
	_lod_eligible_ids.clear()
	_lod_cache_dirty = false
	if not _registry:
		return
	for block: Block in _registry.get_active_blocks():
		if _is_lod_eligible(block):
			_lod_eligible_ids.append(block.block_id)


## Scan LOD-eligible blocks for LOD changes and queue operations.
## Uses cached eligible IDs instead of all active blocks — O(eligible) not O(total).
func _scan_blocks(camera_pos: Vector3) -> void:
	_pending_ops.clear()

	for block_id: String in _lod_eligible_ids:
		var block := _registry.get_block(block_id)
		if block == null or not block.active:
			continue

		# Check forced max LOD
		if block_id in forced_max_lod:
			if block.lod_level < 3 and block.can_subdivide():
				_pending_ops.append({"block_id": block_id, "target_lod": 3})
			continue

		var target := _compute_target_lod(block.position, camera_pos)
		if block.lod_level != target:
			_pending_ops.append({"block_id": block_id, "target_lod": target})


## Drain pending ops with a per-frame build budget.
func _drain_pending_ops() -> void:
	while not _pending_ops.is_empty() and _builds_this_frame < MAX_BUILDS_PER_FRAME:
		var op: Dictionary = _pending_ops[0]
		_pending_ops.remove_at(0)

		var block_id: String = op["block_id"]
		var target_lod: int = op["target_lod"]
		var block := _registry.get_block(block_id)

		if block == null or not block.active:
			continue

		if block.lod_level < target_lod:
			var builds_before := _builds_this_frame
			_subdivide_one_level(block)
			# Only re-queue if progress was made (builds_this_frame increased).
			# If no progress: block can't subdivide further — don't re-queue or
			# _drain_pending_ops() infinite-loops (block stays at same lod, never exits).
			if block.lod_level < target_lod and _builds_this_frame > builds_before:
				_pending_ops.append({"block_id": block.block_id, "target_lod": target_lod})

		elif block.lod_level > target_lod:
			var builds_before_merge := _builds_this_frame
			_merge_one_level(block)
			# Only re-queue if merge made progress (same infinite-loop guard).
			# Note: after merge, the original block may no longer be active — skip.
			if block.active and block.lod_level > target_lod and _builds_this_frame > builds_before_merge:
				_pending_ops.append({"block_id": block.block_id, "target_lod": target_lod})


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


## Subdivide a block ONE level (not recursive). Increments _builds_this_frame.
func _subdivide_one_level(block: Block) -> void:
	if _builds_this_frame >= MAX_BUILDS_PER_FRAME:
		return

	var children := _registry.subdivide_block(block.block_id)
	if children.is_empty():
		return

	# Destroy parent's visual node
	if block.node and is_instance_valid(block.node):
		block.node.queue_free()
		block.node = null

	# Build child nodes (each counts toward the frame budget)
	for child in children:
		if _builds_this_frame >= MAX_BUILDS_PER_FRAME:
			# Budget exhausted — remaining children will be built on next frame
			# Re-queue them as pending ops
			if child.active and child.collision_shape != BlockCategories.SHAPE_NONE:
				_pending_ops.append({"block_id": child.block_id, "target_lod": child.lod_level})
			continue

		if child.active and child.collision_shape != BlockCategories.SHAPE_NONE:
			BlockBuilder.build(child, _world_root)
			_builds_this_frame += 1


## Merge a block with its siblings ONE level. Increments _builds_this_frame.
func _merge_one_level(block: Block) -> void:
	if _builds_this_frame >= MAX_BUILDS_PER_FRAME:
		return

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
		BlockBuilder.build(merged, _world_root)
		_builds_this_frame += 1
