class_name BlockCollisionMerger
extends RefCounted
## The physics twin of BlockMeshMerger. Contract: addons/blocks/CLAUDE.md
## § "Collision Merger Contract".
##
## N blocks each carry StaticBody3D + CollisionShape3D (+ a Node3D root).
## Godot's main thread pays per NODE every frame — measured on the FrogMog hub
## as a 68 ms floor with the whole world hidden, from 133k physics nodes for
## 8.9k meshes. This collapses every eligible body under a root into ONE
## StaticBody3D per (layer, mask, stair_walkable) group, with each block's
## shape added through PhysicsServer3D.body_add_shape — shapes WITHOUT nodes.
## Physics is unchanged: same shapes, same world transforms, same layers.
##
## Runs at load time (WorldCacheLoader), never in the Design Studio.

const META_MERGED := "merged_collision"
const META_SHAPE_IDS := "shape_block_ids"
const STAIR_GROUP := "stair_walkable"

## Result of merge(): counts for the caller's report line.
class Result:
	var bodies_in: int = 0
	var bodies_out: int = 0
	var shapes: int = 0
	var skipped: int = 0


## Merge every eligible per-block body found under `root`.
##
## `blocks` may be empty — the walk finds bodies by structure. When given, it
## is used only to look up neuron-ness by block_id (neuron blocks never merge).
## `layer_filter`: if non-empty, only bodies whose collision_layer is in it
## merge (lets a caller keep e.g. walkable floors per-block if it wants).
static func merge(root: Node3D, blocks: Array = [], skip_block_ids: Dictionary = {}) -> Result:
	var res := Result.new()
	if root == null or not root.is_inside_tree():
		return res

	# 1. Collect candidates: StaticBody3D whose parent carries block_id meta,
	#    whose only children are CollisionShape3D, and which is not skipped.
	var groups: Dictionary = {}   # key -> Array[StaticBody3D]
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			if c is StaticBody3D and _eligible(c, skip_block_ids):
				res.bodies_in += 1
				var key := _group_key(c)
				if not groups.has(key):
					groups[key] = []
				groups[key].append(c)
			elif c is Area3D:
				continue          # triggers never merge; nothing under them does either
			else:
				stack.append(c)

	if res.bodies_in == 0:
		return res

	# 2. One merged body per group.
	for key in groups.keys():
		var members: Array = groups[key]
		if members.size() < 2:
			res.skipped += members.size()
			continue
		var first: StaticBody3D = members[0]
		var merged := StaticBody3D.new()
		merged.name = "MergedCollision_%s" % str(key).replace(",", "_").replace(" ", "")
		merged.collision_layer = first.collision_layer
		merged.collision_mask = first.collision_mask
		if first.is_in_group(STAIR_GROUP):
			merged.add_to_group(STAIR_GROUP, true)
		merged.set_meta(META_MERGED, true)
		# Anchor the merged body at the root's global transform so shape
		# transforms are root-relative — the least surprising frame for
		# anyone reading them back.
		root.add_child(merged)
		merged.global_transform = root.global_transform
		var inv := merged.global_transform.affine_inverse()
		var body_rid := merged.get_rid()

		var ids := PackedStringArray()
		for b in members:
			var block_id: String = str(b.get_parent().get_meta("block_id", ""))
			for sc in b.get_children():
				if not (sc is CollisionShape3D):
					continue
				var cs := sc as CollisionShape3D
				if cs.shape == null or cs.disabled:
					continue
				# World transform of the shape, re-expressed relative to the
				# merged body. Scale on the block root (rare) is baked in here.
				var rel: Transform3D = inv * cs.global_transform
				PhysicsServer3D.body_add_shape(body_rid, cs.shape.get_rid(), rel, false)
				ids.append(block_id)
				res.shapes += 1
			# Keep the Shape resources alive: the per-block CollisionShape3D
			# node held the only reference. Park them on the merged body.
			for sc2 in b.get_children():
				if sc2 is CollisionShape3D and (sc2 as CollisionShape3D).shape != null:
					_retain(merged, (sc2 as CollisionShape3D).shape)
		merged.set_meta(META_SHAPE_IDS, ids)
		res.bodies_out += 1

		# 3. Free the per-block bodies (and their shape nodes with them).
		for b in members:
			b.get_parent().remove_child(b)
			b.free()

	return res


## block_id for a raycast/shape-cast hit on a merged body, "" otherwise.
static func block_id_at(body: Object, shape_idx: int) -> String:
	if body == null or not (body is Node) or not (body as Node).has_meta(META_SHAPE_IDS):
		return ""
	var ids: PackedStringArray = (body as Node).get_meta(META_SHAPE_IDS)
	if shape_idx < 0 or shape_idx >= ids.size():
		return ""
	return ids[shape_idx]


## Remove every shape belonging to `block_id` from a merged body (runtime
## deletion — studio god-mode delete, deleted_children). Compacts the id map
## because PhysicsServer shape indices shift down on removal.
static func remove_block(body: StaticBody3D, block_id: String) -> int:
	if body == null or not body.has_meta(META_SHAPE_IDS):
		return 0
	var ids: PackedStringArray = body.get_meta(META_SHAPE_IDS)
	var rid := body.get_rid()
	var removed := 0
	# Walk from the end so indices below stay valid as we remove.
	for i in range(ids.size() - 1, -1, -1):
		if ids[i] == block_id:
			PhysicsServer3D.body_remove_shape(rid, i)
			ids.remove_at(i)
			removed += 1
	body.set_meta(META_SHAPE_IDS, ids)
	return removed


static func _eligible(body: StaticBody3D, skip: Dictionary) -> bool:
	var parent := body.get_parent()
	if parent == null or not parent.has_meta("block_id"):
		return false
	var bid: String = str(parent.get_meta("block_id"))
	if skip.has(bid):
		return false
	# Only plain bodies: every child must be a CollisionShape3D. A body with
	# extra children (a behaviour brain, an audio player) is somebody's
	# addressable object — leave it.
	if body.get_child_count() == 0:
		return false
	for c in body.get_children():
		if not (c is CollisionShape3D):
			return false
	# A body that is itself scripted is somebody's object too.
	if body.get_script() != null:
		return false
	return true


static func _group_key(body: StaticBody3D) -> String:
	return "%d,%d,%s" % [body.collision_layer, body.collision_mask,
		"stairs" if body.is_in_group(STAIR_GROUP) else "flat"]


## Godot frees a Shape3D when its last owner goes; the merged body owns the
## RID through the physics server but not the Resource. Park references in a
## meta array so they outlive the freed CollisionShape3D nodes.
static func _retain(merged: StaticBody3D, shape: Shape3D) -> void:
	var held: Array = merged.get_meta("_held_shapes", [])
	held.append(shape)
	merged.set_meta("_held_shapes", held)
