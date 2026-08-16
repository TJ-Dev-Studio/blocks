extends Node3D
## BlockCollisionMerger test suite — see addons/blocks/CLAUDE.md
## § "Collision Merger Contract" (GC-91).
##
## The merger collapses N per-block StaticBody3D+CollisionShape3D pairs into
## one compound body per (layer, mask, stairs) group with server-side shapes.
## These tests pin the parts a session could silently break:
##   - every shape survives, at the SAME world transform (a ray hits the same
##     wall at the same point before and after)
##   - grouping respects layer, mask and stair_walkable
##   - neuron blocks, triggers (Area3D), and scripted bodies are left alone
##   - block_id_at() maps a hit shape back to its block
##   - remove_block() takes exactly that block's shapes out and keeps the map
##     consistent for the rest

var _registry: BlockRegistry
var _pass_count := 0
var _fail_count := 0


func _ready() -> void:
	print("")
	print("=".repeat(60))
	print("  COLLISION MERGER TEST SUITE")
	print("=".repeat(60))
	_registry = BlockRegistry.new()
	add_child(_registry)

	await _test_basic_merge_counts()
	await _test_raycast_same_wall_same_point()
	await _test_grouping_by_layer_mask()
	await _test_stairs_group_split()
	await _test_neuron_and_trigger_skipped()
	await _test_block_id_at()
	await _test_remove_block()
	await _test_scaled_root_transform()

	print("")
	print("=".repeat(60))
	var total := _pass_count + _fail_count
	if _fail_count == 0:
		print("  ALL %d TESTS PASSED" % total)
	else:
		print("  %d PASSED, %d FAILED (of %d)" % [_pass_count, _fail_count, total])
	print("=".repeat(60))
	get_tree().quit(1 if _fail_count > 0 else 0)


func _assert(cond: bool, name: String) -> void:
	if cond:
		_pass_count += 1
		print("  PASS  %s" % name)
	else:
		_fail_count += 1
		print("  FAIL  %s" % name)


func _section(name: String) -> void:
	print("")
	print("--- %s ---" % name)


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

func _box(bname: String, size: Vector3, pos: Vector3, layer: int = CollisionLayers.WORLD,
		interaction: int = BlockCategories.INTERACT_SOLID, tags: Array = []) -> Block:
	var b := Block.new()
	b.block_name = bname
	b.category = BlockCategories.STRUCTURE
	b.collision_shape = BlockCategories.SHAPE_BOX
	b.collision_size = size
	b.position = pos
	b.interaction = interaction
	b.collision_layer = layer
	b.material_id = "wood"
	b.mesh_type = 0
	for t in tags:
		b.tags.append(t)
	b.ensure_id()
	return b


func _build(blocks: Array) -> Node3D:
	var root := Node3D.new()
	root.name = "Asm"
	add_child(root)
	for b: Block in blocks:
		_registry.register(b)
		BlockBuilder.build(b, root)
	return root


func _count(root: Node, cls: String) -> int:
	var n := 0
	var st: Array = [root]
	while not st.is_empty():
		var x: Node = st.pop_back()
		if x.get_class() == cls:
			n += 1
		for c in x.get_children():
			st.append(c)
	return n


func _shape_count_server(body: StaticBody3D) -> int:
	return PhysicsServer3D.body_get_shape_count(body.get_rid())


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collide_with_areas = false
	q.collide_with_bodies = true
	return get_world_3d().direct_space_state.intersect_ray(q)


func _merged_bodies(root: Node) -> Array:
	var out: Array = []
	for c in root.get_children():
		if c is StaticBody3D and c.has_meta(BlockCollisionMerger.META_MERGED):
			out.append(c)
	return out


# ---------------------------------------------------------------------------
# tests
# ---------------------------------------------------------------------------

func _test_basic_merge_counts() -> void:
	_section("basic merge: N bodies -> 1, every shape survives")
	var blocks: Array = []
	for i in 12:
		blocks.append(_box("w%d" % i, Vector3(1, 2, 0.3), Vector3(i * 1.5, 1, 0)))
	var root := _build(blocks)
	await get_tree().physics_frame
	var before_bodies := _count(root, "StaticBody3D")
	var before_shapes := _count(root, "CollisionShape3D")
	_assert(before_bodies == 12 and before_shapes == 12, "before: 12 bodies, 12 shape nodes")

	var res = BlockCollisionMerger.merge(root, blocks)
	await get_tree().physics_frame
	_assert(res.bodies_in == 12, "merger saw 12 bodies (got %d)" % res.bodies_in)
	_assert(res.bodies_out == 1, "one merged body out (got %d)" % res.bodies_out)
	_assert(res.shapes == 12, "12 shapes added (got %d)" % res.shapes)
	_assert(_count(root, "StaticBody3D") == 1, "after: exactly 1 StaticBody3D in tree")
	_assert(_count(root, "CollisionShape3D") == 0, "after: zero CollisionShape3D nodes")
	var mb := _merged_bodies(root)
	_assert(mb.size() == 1 and _shape_count_server(mb[0]) == 12, "server reports 12 shapes on the merged body")
	root.queue_free()


func _test_raycast_same_wall_same_point() -> void:
	_section("raycast: same wall, same hit point, before and after")
	var blocks: Array = []
	for i in 6:
		blocks.append(_box("w%d" % i, Vector3(1, 3, 0.4), Vector3(i * 2.0, 1.5, 5.0)))
	var root := _build(blocks)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var from := Vector3(4.0, 1.0, -5.0)
	var to := Vector3(4.0, 1.0, 20.0)
	var before := _ray(from, to)
	_assert(not before.is_empty(), "ray hits a wall before merge")
	var p_before: Vector3 = before.get("position", Vector3.INF)

	BlockCollisionMerger.merge(root, blocks)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var after := _ray(from, to)
	_assert(not after.is_empty(), "ray still hits a wall after merge")
	var p_after: Vector3 = after.get("position", Vector3.INF)
	_assert(p_before.distance_to(p_after) < 0.01,
		"hit point unchanged (before %s, after %s)" % [p_before, p_after])
	_assert(after.get("collider") != null and (after.get("collider") as Node).has_meta(BlockCollisionMerger.META_MERGED),
		"after: collider is the merged body")
	root.queue_free()


func _test_grouping_by_layer_mask() -> void:
	_section("grouping: different layer -> different merged body")
	var blocks: Array = []
	for i in 4:
		blocks.append(_box("a%d" % i, Vector3(1, 1, 1), Vector3(i * 2, 0.5, 0), CollisionLayers.WORLD))
	for i in 4:
		blocks.append(_box("b%d" % i, Vector3(1, 1, 1), Vector3(i * 2, 0.5, 4), CollisionLayers.TRIGGER))
	var root := _build(blocks)
	await get_tree().physics_frame
	var res = BlockCollisionMerger.merge(root, blocks)
	await get_tree().physics_frame
	_assert(res.bodies_out == 2, "two merged bodies for two layers (got %d)" % res.bodies_out)
	var layers := {}
	for mb in _merged_bodies(root):
		layers[mb.collision_layer] = _shape_count_server(mb)
	_assert(layers.size() == 2, "merged bodies carry distinct collision_layer values")
	var all4 := true
	for k in layers.keys():
		if layers[k] != 4:
			all4 = false
	_assert(all4, "each merged body holds its own 4 shapes")
	root.queue_free()


func _test_stairs_group_split() -> void:
	_section("grouping: stair_walkable bodies merge separately and keep the group")
	var blocks: Array = []
	for i in 3:
		blocks.append(_box("f%d" % i, Vector3(1, 0.2, 1), Vector3(i, 0.1, 0)))
	for i in 3:
		blocks.append(_box("s%d" % i, Vector3(1, 0.2, 1), Vector3(i, 0.1, 3), CollisionLayers.WORLD, BlockCategories.INTERACT_SOLID, ["stairs"]))
	var root := _build(blocks)
	await get_tree().physics_frame
	var res = BlockCollisionMerger.merge(root, blocks)
	await get_tree().physics_frame
	_assert(res.bodies_out == 2, "stairs and flat merge into separate bodies (got %d)" % res.bodies_out)
	var stair_bodies := 0
	for mb in _merged_bodies(root):
		if mb.is_in_group("stair_walkable"):
			stair_bodies += 1
			_assert(_shape_count_server(mb) == 3, "stair body holds the 3 stair shapes")
	_assert(stair_bodies == 1, "exactly one merged body is in stair_walkable")
	root.queue_free()


func _test_neuron_and_trigger_skipped() -> void:
	_section("skip: neuron blocks and Area3D triggers are left alone")
	var blocks: Array = []
	for i in 4:
		blocks.append(_box("w%d" % i, Vector3(1, 1, 1), Vector3(i * 2, 0.5, 0)))
	var trig := _box("trig", Vector3(2, 2, 2), Vector3(0, 1, 6), CollisionLayers.TRIGGER, BlockCategories.INTERACT_TRIGGER)
	blocks.append(trig)
	var neuron_b := _box("neuron", Vector3(1, 1, 1), Vector3(10, 0.5, 0))
	neuron_b.neuron = BlockNeuron.new()
	blocks.append(neuron_b)
	var root := _build(blocks)
	await get_tree().physics_frame
	var skip := {neuron_b.block_id: true}
	var res = BlockCollisionMerger.merge(root, blocks, skip)
	await get_tree().physics_frame
	_assert(res.bodies_in == 4, "only the 4 plain walls were candidates (got %d)" % res.bodies_in)
	_assert(_count(root, "Area3D") == 1, "the trigger Area3D survives untouched")
	# The neuron block's own body must still be a per-block StaticBody3D under its root.
	var neuron_root: Node = null
	for c in root.get_children():
		if c.has_meta("block_id") and str(c.get_meta("block_id")) == neuron_b.block_id:
			neuron_root = c
	_assert(neuron_root != null and _count(neuron_root, "StaticBody3D") == 1, "neuron block keeps its per-block body")
	root.queue_free()


func _test_block_id_at() -> void:
	_section("block_id_at: hit shape index -> block id")
	var blocks: Array = []
	for i in 5:
		blocks.append(_box("w%d" % i, Vector3(1, 3, 0.4), Vector3(i * 3.0, 1.5, 5.0)))
	var root := _build(blocks)
	await get_tree().physics_frame
	BlockCollisionMerger.merge(root, blocks)
	await get_tree().physics_frame
	await get_tree().physics_frame
	# Ray at x=6 hits w2.
	var hit := _ray(Vector3(6.0, 1.0, -5.0), Vector3(6.0, 1.0, 20.0))
	_assert(not hit.is_empty(), "ray hits")
	var bid := BlockCollisionMerger.block_id_at(hit.get("collider"), int(hit.get("shape", -1)))
	_assert(bid == blocks[2].block_id, "block_id_at resolves to w2 (got '%s')" % bid)
	_assert(BlockCollisionMerger.block_id_at(null, 0) == "", "block_id_at(null) is ''")
	_assert(BlockCollisionMerger.block_id_at(root, 0) == "", "block_id_at(non-merged) is ''")
	root.queue_free()


func _test_remove_block() -> void:
	_section("remove_block: only that block's shapes go; map stays consistent")
	var blocks: Array = []
	for i in 5:
		blocks.append(_box("w%d" % i, Vector3(1, 3, 0.4), Vector3(i * 3.0, 1.5, 5.0)))
	var root := _build(blocks)
	await get_tree().physics_frame
	BlockCollisionMerger.merge(root, blocks)
	await get_tree().physics_frame
	var mb: StaticBody3D = _merged_bodies(root)[0]
	var removed := BlockCollisionMerger.remove_block(mb, blocks[2].block_id)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_assert(removed == 1, "removed 1 shape for w2 (got %d)" % removed)
	_assert(_shape_count_server(mb) == 4, "server now holds 4 shapes")
	var gone := _ray(Vector3(6.0, 1.0, -5.0), Vector3(6.0, 1.0, 20.0))
	_assert(gone.is_empty(), "ray through w2's slot no longer hits")
	var still := _ray(Vector3(9.0, 1.0, -5.0), Vector3(9.0, 1.0, 20.0))
	_assert(not still.is_empty(), "w3 still there")
	var bid := BlockCollisionMerger.block_id_at(still.get("collider"), int(still.get("shape", -1)))
	_assert(bid == blocks[3].block_id, "after removal, index map still resolves w3 (got '%s')" % bid)
	root.queue_free()


func _test_scaled_root_transform() -> void:
	_section("transform: shapes under a rotated+scaled assembly root land where they were")
	var blocks: Array = []
	for i in 4:
		blocks.append(_box("w%d" % i, Vector3(1, 3, 0.4), Vector3(i * 3.0, 1.5, 0.0)))
	var root := _build(blocks)
	root.rotation.y = deg_to_rad(37.0)
	root.scale = Vector3(1.5, 1.5, 1.5)
	root.position = Vector3(20, 0, 20)
	await get_tree().physics_frame
	await get_tree().physics_frame
	# Cast toward where w1 sits in WORLD space (compute from its global transform).
	var w1_root: Node3D = null
	for c in root.get_children():
		if c.has_meta("block_id") and str(c.get_meta("block_id")) == blocks[1].block_id:
			w1_root = c
	var target: Vector3 = w1_root.global_position
	var from: Vector3 = target + Vector3(0, 0, -6).rotated(Vector3.UP, deg_to_rad(37.0))
	var to: Vector3 = target + Vector3(0, 0, 6).rotated(Vector3.UP, deg_to_rad(37.0))
	var before := _ray(from, to)
	_assert(not before.is_empty(), "rotated/scaled: ray hits before merge")
	var pb: Vector3 = before.get("position", Vector3.INF)
	BlockCollisionMerger.merge(root, blocks)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var after := _ray(from, to)
	_assert(not after.is_empty(), "rotated/scaled: ray hits after merge")
	var pa: Vector3 = after.get("position", Vector3.INF)
	_assert(pb.distance_to(pa) < 0.02, "rotated/scaled: hit point unchanged (Δ=%.4f)" % pb.distance_to(pa))
	root.queue_free()
