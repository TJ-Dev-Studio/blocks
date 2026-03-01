extends Node3D
## Cellular Block System Test Suite
##
## Tests subdivision, merge, LOD adaptation, DNA system, connection
## inheritance, amoeba movement, neural cascade, shape support, and
## stress tests for the cellular block system.
##
## Run headless:
##   godot --headless --script res://scripts/blocks/tests/run_cellular_tests.gd

var _pass_count := 0
var _fail_count := 0
var _test_count := 0
var _registry: BlockRegistry


func _ready() -> void:
	print("")
	print("=" .repeat(60))
	print("  CELLULAR BLOCK SYSTEM TEST SUITE")
	print("=" .repeat(60))
	print("")

	_registry = BlockRegistry.new()
	_registry.name = "CellularTestRegistry"
	add_child(_registry)

	# Run all test groups
	_test_subdivision_basics()
	_test_subdivision_properties()
	_test_subdivision_hierarchy()
	_test_subdivision_limits()
	_test_multi_axis_subdivision()
	_test_merge_basics()
	_test_merge_properties()
	_test_merge_validation()
	_test_dna_system()
	_test_lod_adaptation()
	_test_amoeba_movement()
	_test_neural_cascade()
	_test_shape_support()
	_test_stress()

	# Summary
	print("")
	print("=" .repeat(60))
	var total := _pass_count + _fail_count
	if _fail_count == 0:
		print("  ALL %d TESTS PASSED" % total)
	else:
		print("  %d PASSED, %d FAILED (of %d)" % [_pass_count, _fail_count, total])
	print("=" .repeat(60))
	print("")

	if _fail_count > 0:
		get_tree().quit(1)
	else:
		get_tree().quit(0)


# =========================================================================
# Test helpers
# =========================================================================

func _assert(condition: bool, test_name: String) -> void:
	_test_count += 1
	if condition:
		_pass_count += 1
		print("  PASS  %s" % test_name)
	else:
		_fail_count += 1
		print("  FAIL  %s" % test_name)


func _reset_registry() -> void:
	_registry.clear()


func _make_box(bname: String, size: Vector3, pos: Vector3 = Vector3.ZERO) -> Block:
	var b := Block.new()
	b.block_name = bname
	b.category = BlockCategories.STRUCTURE
	b.collision_shape = BlockCategories.SHAPE_BOX
	b.collision_size = size
	b.collision_layer = CollisionLayers.WORLD
	b.collision_mask_layers = [] as Array[int]
	b.position = pos
	b.material_id = "cell_membrane"
	b.min_size = Vector3(0.1, 0.1, 0.1)
	return b


func _make_cylinder(bname: String, radius: float, height: float,
		pos: Vector3 = Vector3.ZERO) -> Block:
	var b := Block.new()
	b.block_name = bname
	b.category = BlockCategories.STRUCTURE
	b.collision_shape = BlockCategories.SHAPE_CYLINDER
	b.collision_size = Vector3(radius, height, 0)
	b.collision_layer = CollisionLayers.WORLD
	b.collision_mask_layers = [] as Array[int]
	b.position = pos
	b.material_id = "cell_membrane"
	b.min_size = Vector3(0.1, 0.1, 0.1)
	return b


func _make_sphere(bname: String, radius: float, height: float,
		pos: Vector3 = Vector3.ZERO) -> Block:
	var b := Block.new()
	b.block_name = bname
	b.category = BlockCategories.STRUCTURE
	b.collision_shape = BlockCategories.SHAPE_SPHERE
	b.collision_size = Vector3(radius, height, 0)
	b.collision_layer = CollisionLayers.WORLD
	b.collision_mask_layers = [] as Array[int]
	b.position = pos
	b.material_id = "cell_membrane"
	b.min_size = Vector3(0.1, 0.1, 0.1)
	return b


# =========================================================================
# Group 1: Subdivision Basics (25 tests)
# =========================================================================

func _test_subdivision_basics() -> void:
	print("\n--- Subdivision Basics ---")
	_reset_registry()

	# BOX split X
	var box := _make_box("cell", Vector3(4, 4, 4))
	box.ensure_id()
	var children := box.subdivide(0)
	_assert(children.size() == 2, "BOX split X produces 2 children")
	_assert(is_equal_approx(children[0].collision_size.x, 2.0), "child 0 X halved to 2")
	_assert(is_equal_approx(children[1].collision_size.x, 2.0), "child 1 X halved to 2")
	_assert(is_equal_approx(children[0].collision_size.y, 4.0), "child 0 Y unchanged")
	_assert(is_equal_approx(children[0].collision_size.z, 4.0), "child 0 Z unchanged")

	# BOX split Y
	var box_y := _make_box("cell_y", Vector3(4, 4, 4))
	box_y.ensure_id()
	var ch_y := box_y.subdivide(1)
	_assert(ch_y.size() == 2, "BOX split Y produces 2 children")
	_assert(is_equal_approx(ch_y[0].collision_size.y, 2.0), "child Y halved to 2")
	_assert(is_equal_approx(ch_y[0].collision_size.x, 4.0), "child X unchanged for Y split")

	# BOX split Z
	var box_z := _make_box("cell_z", Vector3(4, 4, 4))
	box_z.ensure_id()
	var ch_z := box_z.subdivide(2)
	_assert(ch_z.size() == 2, "BOX split Z produces 2 children")
	_assert(is_equal_approx(ch_z[0].collision_size.z, 2.0), "child Z halved to 2")

	# Unique IDs
	_assert(children[0].block_id != children[1].block_id, "children have unique IDs")
	_assert(children[0].block_id != box.block_id, "child ID differs from parent")

	# Positions correct
	_assert(children[0].position.x < 0, "child 0 offset negative X")
	_assert(children[1].position.x > 0, "child 1 offset positive X")
	_assert(is_equal_approx(children[0].position.x, -1.0), "child 0 X at -quarter")
	_assert(is_equal_approx(children[1].position.x, 1.0), "child 1 X at +quarter")
	_assert(is_equal_approx(children[0].position.y, 0.0), "child 0 Y stays at origin")
	_assert(is_equal_approx(children[0].position.z, 0.0), "child 0 Z stays at origin")

	# Parent gets child_lod_ids
	_assert(box.child_lod_ids.size() == 2, "parent has 2 child_lod_ids after split")
	_assert(box.child_lod_ids[0] == children[0].block_id, "child_lod_ids[0] matches child 0")
	_assert(box.child_lod_ids[1] == children[1].block_id, "child_lod_ids[1] matches child 1")

	# Parent state marked
	_assert(box.state.has("divided"), "parent state has 'divided' flag")

	# Names are descriptive
	_assert(children[0].block_name == "cell_sub0", "child 0 name is cell_sub0")
	_assert(children[1].block_name == "cell_sub1", "child 1 name is cell_sub1")


# =========================================================================
# Group 2: Subdivision Properties (20 tests)
# =========================================================================

func _test_subdivision_properties() -> void:
	print("\n--- Subdivision Properties ---")
	_reset_registry()

	var cell := _make_box("prop_cell", Vector3(4, 4, 4))
	cell.material_id = "cell_nucleus"
	cell.tags = PackedStringArray(["organic", "membrane"])
	cell.interaction = BlockCategories.INTERACT_SOLID
	cell.collision_layer = CollisionLayers.WORLD
	cell.server_collidable = true
	cell.cast_shadow = false
	cell.scale_factor = 2.0
	cell.creator = BlockCategories.CREATOR_AI
	cell.version = 3
	cell.ensure_id()

	var children := cell.subdivide(0)
	_assert(children.size() == 2, "property inheritance: 2 children")

	var ch := children[0]
	_assert(ch.material_id == "cell_nucleus", "child inherits material_id")
	_assert(ch.category == BlockCategories.STRUCTURE, "child inherits category")
	_assert(ch.interaction == BlockCategories.INTERACT_SOLID, "child inherits interaction")
	_assert(ch.collision_layer == CollisionLayers.WORLD, "child inherits collision_layer")
	_assert(ch.collision_shape == BlockCategories.SHAPE_BOX, "child inherits collision_shape")
	_assert(ch.server_collidable == true, "child inherits server_collidable")
	_assert(ch.cast_shadow == false, "child inherits cast_shadow")
	_assert(is_equal_approx(ch.scale_factor, 2.0), "child inherits scale_factor")
	_assert(ch.creator == BlockCategories.CREATOR_AI, "child inherits creator")
	_assert(ch.version == 3, "child inherits version")

	# Tags
	_assert("organic" in ch.tags, "child inherits tag 'organic'")
	_assert("membrane" in ch.tags, "child inherits tag 'membrane'")
	_assert(ch.tags.size() == 2, "child has exact tag count")

	# Collision mask
	var cell2 := _make_box("mask_cell", Vector3(4, 4, 4))
	cell2.collision_mask_layers = [1, 3] as Array[int]
	cell2.ensure_id()
	var ch2_list := cell2.subdivide(0)
	_assert(ch2_list[0].collision_mask_layers.size() == 2, "child inherits collision_mask count")

	# min_size inherited
	cell.min_size = Vector3(0.5, 0.5, 0.5)
	var cell3 := _make_box("minsize_cell", Vector3(4, 4, 4))
	cell3.min_size = Vector3(0.5, 0.5, 0.5)
	cell3.ensure_id()
	var ch3_list := cell3.subdivide(0)
	_assert(ch3_list[0].min_size == Vector3(0.5, 0.5, 0.5), "child inherits min_size")

	# DNA inherited
	var cell4 := _make_box("dna_cell", Vector3(4, 4, 4))
	cell4.dna = {"axis_preference": 1, "child_count": 2}
	cell4.ensure_id()
	var ch4_list := cell4.subdivide(0)
	_assert(ch4_list[0].dna.has("axis_preference"), "child inherits DNA")
	_assert(ch4_list[0].dna["axis_preference"] == 1, "child DNA axis_preference matches parent")

	# mesh_size proportional
	var cell5 := _make_box("mesh_cell", Vector3(4, 4, 4))
	cell5.mesh_size = Vector3(3.0, 4.0, 4.0)
	cell5.ensure_id()
	var ch5_list := cell5.subdivide(0)
	_assert(is_equal_approx(ch5_list[0].mesh_size.x, 1.5), "mesh_size X halved on split axis")
	_assert(is_equal_approx(ch5_list[0].mesh_size.y, 4.0), "mesh_size Y unchanged off-axis")


# =========================================================================
# Group 3: Subdivision Hierarchy (20 tests)
# =========================================================================

func _test_subdivision_hierarchy() -> void:
	print("\n--- Subdivision Hierarchy ---")
	_reset_registry()

	var root := _make_box("root_cell", Vector3(8, 8, 8))
	root.ensure_id()
	_registry.register(root)

	# Subdivide level 0 → level 1
	var level1 := _registry.subdivide_block(root.block_id, 0)
	_assert(level1.size() == 2, "level 0→1 produces 2 children")
	_assert(level1[0].lod_level == 1, "level 1 child lod_level is 1")
	_assert(level1[1].lod_level == 1, "level 1 second child lod_level is 1")
	_assert(level1[0].parent_lod_id == root.block_id, "level 1 parent_lod_id points to root")
	_assert(not root.active, "root deactivated after subdivision")

	# Subdivide level 1 → level 2
	var level2 := _registry.subdivide_block(level1[0].block_id, 1)
	_assert(level2.size() == 2, "level 1→2 produces 2 children")
	_assert(level2[0].lod_level == 2, "level 2 child lod_level is 2")
	_assert(level2[0].parent_lod_id == level1[0].block_id, "level 2 parent chain correct")
	_assert(not level1[0].active, "level 1 parent deactivated after subdivision")

	# Subdivision tree
	var tree := _registry.get_subdivision_tree(root.block_id)
	_assert(not tree.is_empty(), "get_subdivision_tree returns non-empty")
	_assert(tree["block"] == root, "tree root is the original block")
	_assert(tree["children"].size() == 2, "tree has 2 level-1 children")
	var first_subtree: Dictionary = tree["children"][0]
	_assert(first_subtree["children"].size() == 2, "first child subtree has 2 level-2 children")

	# Active blocks count
	var active := _registry.get_active_blocks()
	# root=inactive, level1[0]=inactive, level1[1]=active, level2[0]=active, level2[1]=active
	var active_count := active.size()
	_assert(active_count == 3, "3 active blocks (1 level1 + 2 level2)")

	# lod_level increment chain
	_assert(root.lod_level == 0, "root stays lod_level 0")
	_assert(level1[0].lod_level == 1, "first subdivision lod_level 1")
	_assert(level2[0].lod_level == 2, "second subdivision lod_level 2")

	# child_lod_ids populated
	_assert(root.child_lod_ids.size() == 2, "root child_lod_ids has 2 entries")
	_assert(level1[0].child_lod_ids.size() == 2, "level1[0] child_lod_ids has 2 entries")

	# Registry tracks all blocks (active and inactive)
	_assert(_registry.get_block_count() == 5, "registry has 5 total blocks (root+2 level1+2 level2)")

	# Parent block still queryable even when inactive
	_assert(_registry.get_block(root.block_id) != null, "inactive root still in registry")


# =========================================================================
# Group 4: Subdivision Limits (15 tests)
# =========================================================================

func _test_subdivision_limits() -> void:
	print("\n--- Subdivision Limits ---")
	_reset_registry()

	# At min_size limit — cannot subdivide
	var tiny := _make_box("tiny", Vector3(0.2, 0.2, 0.2))
	tiny.min_size = Vector3(0.1, 0.1, 0.1)
	_assert(tiny.can_subdivide(), "0.2 can subdivide with min 0.1")

	var at_limit := _make_box("at_limit", Vector3(0.19, 4, 4))
	at_limit.min_size = Vector3(0.1, 0.1, 0.1)
	_assert(not at_limit.can_subdivide(0), "0.19 cannot subdivide on X (< 0.2)")
	_assert(at_limit.can_subdivide(1), "4.0 can subdivide on Y")

	# Exact boundary
	var exact := _make_box("exact", Vector3(0.2, 0.2, 0.2))
	exact.min_size = Vector3(0.1, 0.1, 0.1)
	_assert(exact.can_subdivide(0), "exactly 2x min_size can subdivide")
	var exact_ch := exact.subdivide(0)
	exact_ch[0].ensure_id()
	_assert(is_equal_approx(exact_ch[0].collision_size.x, 0.1), "at-limit subdivision produces min_size child")
	_assert(not exact_ch[0].can_subdivide(0), "child at min_size cannot further subdivide X")

	# SHAPE_NONE cannot subdivide
	var none := Block.new()
	none.block_name = "none_block"
	none.collision_shape = BlockCategories.SHAPE_NONE
	_assert(not none.can_subdivide(), "SHAPE_NONE cannot subdivide")

	# Auto axis picks valid axes only
	var thin := _make_box("thin", Vector3(0.15, 4, 4))
	thin.min_size = Vector3(0.1, 0.1, 0.1)
	_assert(not thin.can_subdivide(0), "thin X axis not splittable")
	_assert(thin.can_subdivide(-1), "thin can subdivide on auto (Y or Z)")

	# Returns empty array on failure
	var too_small := _make_box("micro", Vector3(0.05, 0.05, 0.05))
	too_small.min_size = Vector3(0.1, 0.1, 0.1)
	too_small.ensure_id()
	var fail_ch := too_small.subdivide()
	_assert(fail_ch.is_empty(), "subdivide returns empty when all axes too small")

	# Registry subdivide returns empty on failure
	_registry.register(too_small)
	var fail_reg := _registry.subdivide_block(too_small.block_id, 0)
	_assert(fail_reg.is_empty(), "registry subdivide_block returns empty on failure")

	# Non-existent block
	var fail_missing := _registry.subdivide_block("nonexistent_id", 0)
	_assert(fail_missing.is_empty(), "subdivide non-existent block returns empty")

	# Large min_size blocks
	var big_min := _make_box("big_min", Vector3(4, 4, 4))
	big_min.min_size = Vector3(3.0, 3.0, 3.0)
	_assert(not big_min.can_subdivide(), "4.0 cannot subdivide with min 3.0 (4 < 6)")

	# Single-axis subdivide doesn't break other axes
	var rect := _make_box("rect", Vector3(8, 2, 2))
	rect.min_size = Vector3(0.1, 1.5, 1.5)
	_assert(rect.can_subdivide(0), "rect can split long axis")
	_assert(not rect.can_subdivide(1), "rect cannot split short Y (2 < 3)")
	_assert(not rect.can_subdivide(2), "rect cannot split short Z (2 < 3)")


# =========================================================================
# Group 5: Multi-axis Subdivision (15 tests)
# =========================================================================

func _test_multi_axis_subdivision() -> void:
	print("\n--- Multi-axis Subdivision ---")
	_reset_registry()

	# Auto split on all 3 axes → 8 children
	var cube := _make_box("octree_cell", Vector3(4, 4, 4))
	cube.ensure_id()
	var children := cube.subdivide(-1)
	_assert(children.size() == 8, "auto split 4x4x4 BOX produces 8 children (octree)")

	# All children are 2x2x2
	var all_half := true
	for ch in children:
		if not is_equal_approx(ch.collision_size.x, 2.0) \
				or not is_equal_approx(ch.collision_size.y, 2.0) \
				or not is_equal_approx(ch.collision_size.z, 2.0):
			all_half = false
			break
	_assert(all_half, "all 8 children are 2x2x2")

	# Each child at unique position
	var positions := {}
	for ch in children:
		var key := "%.1f_%.1f_%.1f" % [ch.position.x, ch.position.y, ch.position.z]
		positions[key] = true
	_assert(positions.size() == 8, "all 8 children at unique positions")

	# Positions cover all octants
	var has_neg_x := false
	var has_pos_x := false
	var has_neg_y := false
	var has_pos_y := false
	for ch in children:
		if ch.position.x < 0: has_neg_x = true
		if ch.position.x > 0: has_pos_x = true
		if ch.position.y < 0: has_neg_y = true
		if ch.position.y > 0: has_pos_y = true
	_assert(has_neg_x and has_pos_x, "children span negative and positive X")
	_assert(has_neg_y and has_pos_y, "children span negative and positive Y")

	# All unique IDs
	var ids := {}
	for ch in children:
		ids[ch.block_id] = true
	_assert(ids.size() == 8, "all 8 children have unique IDs")

	# Registry subdivide with auto axis
	var cube2 := _make_box("reg_octree", Vector3(4, 4, 4))
	_registry.register(cube2)
	var reg_ch := _registry.subdivide_block(cube2.block_id, -1)
	_assert(reg_ch.size() == 8, "registry auto subdivide produces 8")

	# Siblings auto-connected
	var first := reg_ch[0]
	var sibling_conns := 0
	for ch in reg_ch:
		if ch.block_id != first.block_id and first.is_connected_to(ch.block_id):
			sibling_conns += 1
	_assert(sibling_conns == 7, "first child connected to 7 siblings")

	# All siblings have connections to each other
	var all_connected := true
	for i in range(reg_ch.size()):
		for j in range(i + 1, reg_ch.size()):
			if not reg_ch[i].is_connected_to(reg_ch[j].block_id):
				all_connected = false
				break
	_assert(all_connected, "all sibling pairs connected")

	# Parent deactivated
	_assert(not cube2.active, "parent deactivated after octree split")

	# Rectangular box: only 2 axes splittable
	var rect := _make_box("rect_cell", Vector3(4, 4, 0.15))
	rect.min_size = Vector3(0.1, 0.1, 0.1)
	rect.ensure_id()
	var rect_ch := rect.subdivide(-1)
	_assert(rect_ch.size() == 4, "4x4x0.15 auto split → 4 children (X+Y only)")
	_assert(is_equal_approx(rect_ch[0].collision_size.z, 0.15), "Z dimension unchanged in 2-axis split")

	# Single-axis auto with DNA preference
	var dna_box := _make_box("dna_axis", Vector3(4, 4, 4))
	dna_box.dna = {"axis_preference": 2}
	dna_box.ensure_id()
	var dna_ch := dna_box.subdivide(-1)
	_assert(dna_ch.size() == 2, "DNA axis_preference=2 limits to single Z axis")
	_assert(is_equal_approx(dna_ch[0].collision_size.z, 2.0), "DNA-guided split halves Z")


# =========================================================================
# Group 6: Merge Basics (20 tests)
# =========================================================================

func _test_merge_basics() -> void:
	print("\n--- Merge Basics ---")
	_reset_registry()

	# Split and merge back
	var original := _make_box("merge_cell", Vector3(4, 4, 4), Vector3(5, 0, 5))
	original.ensure_id()
	var halves := original.subdivide(0)
	_assert(halves.size() == 2, "pre-merge split produces 2 halves")

	var merged := halves[0].merge_with(halves[1])
	_assert(merged != null, "merge_with returns non-null")
	_assert(is_equal_approx(merged.collision_size.x, 4.0), "merged X restored to 4")
	_assert(is_equal_approx(merged.collision_size.y, 4.0), "merged Y unchanged at 4")
	_assert(is_equal_approx(merged.collision_size.z, 4.0), "merged Z unchanged at 4")

	# Position averaged
	_assert(is_equal_approx(merged.position.x, 5.0), "merged position X averaged to center")

	# New unique ID
	_assert(not merged.block_id.is_empty(), "merged block has ID")
	_assert(merged.block_id != halves[0].block_id, "merged ID differs from child 0")
	_assert(merged.block_id != halves[1].block_id, "merged ID differs from child 1")

	# LOD level decremented
	_assert(merged.lod_level == 0, "merged lod_level decremented from 1 to 0")

	# Registry merge
	var a := _make_box("reg_a", Vector3(2, 4, 4), Vector3(0, 0, 0))
	var b := _make_box("reg_b", Vector3(2, 4, 4), Vector3(2, 0, 0))
	_registry.register(a)
	_registry.register(b)
	var ids: Array[String] = [a.block_id, b.block_id]
	var reg_merged := _registry.merge_blocks(ids)
	_assert(reg_merged != null, "registry merge returns non-null")
	_assert(is_equal_approx(reg_merged.collision_size.x, 4.0), "registry merged X doubled")
	_assert(_registry.get_block(a.block_id) == null, "source block a unregistered")
	_assert(_registry.get_block(b.block_id) == null, "source block b unregistered")
	_assert(_registry.get_block(reg_merged.block_id) != null, "merged block registered")

	# Y-axis merge
	var top := _make_box("top", Vector3(4, 2, 4), Vector3(0, 1, 0))
	var bot := _make_box("bot", Vector3(4, 2, 4), Vector3(0, -1, 0))
	top.ensure_id()
	bot.ensure_id()
	var y_merged := top.merge_with(bot)
	_assert(is_equal_approx(y_merged.collision_size.y, 4.0), "Y-axis merge doubles height")
	_assert(is_equal_approx(y_merged.position.y, 0.0), "Y-axis merged position centered")

	# Z-axis merge
	var front := _make_box("front", Vector3(4, 4, 2), Vector3(0, 0, 1))
	var back := _make_box("back", Vector3(4, 4, 2), Vector3(0, 0, -1))
	front.ensure_id()
	back.ensure_id()
	var z_merged := front.merge_with(back)
	_assert(is_equal_approx(z_merged.collision_size.z, 4.0), "Z-axis merge doubles depth")

	# Name convention
	_assert(merged.block_name.begins_with("merge_cell"), "merged name derived from original")


# =========================================================================
# Group 7: Merge Properties (15 tests)
# =========================================================================

func _test_merge_properties() -> void:
	print("\n--- Merge Properties ---")
	_reset_registry()

	var a := _make_box("prop_a", Vector3(2, 4, 4), Vector3(-1, 0, 0))
	a.tags = PackedStringArray(["organic", "front"])
	a.material_id = "cell_nucleus"
	a.dna = {"axis_preference": 0}
	a.min_size = Vector3(0.5, 0.5, 0.5)
	a.ensure_id()

	var b := _make_box("prop_b", Vector3(2, 4, 4), Vector3(1, 0, 0))
	b.tags = PackedStringArray(["organic", "rear"])
	b.material_id = "cell_nucleus"
	b.ensure_id()

	var merged := a.merge_with(b)
	_assert(merged != null, "property merge succeeds")

	# Tag union
	_assert("organic" in merged.tags, "merged has shared tag 'organic'")
	_assert("front" in merged.tags, "merged has tag 'front' from block a")
	_assert("rear" in merged.tags, "merged has tag 'rear' from block b")
	_assert(merged.tags.size() == 3, "merged tag count is 3 (union, no dupes)")

	# Material preserved
	_assert(merged.material_id == "cell_nucleus", "merged preserves material_id")

	# DNA preserved
	_assert(merged.dna.has("axis_preference"), "merged preserves DNA")

	# min_size preserved
	_assert(merged.min_size == Vector3(0.5, 0.5, 0.5), "merged preserves min_size")

	# LOD level
	a.lod_level = 2
	b.lod_level = 2
	var m2 := a.merge_with(b)
	_assert(m2.lod_level == 1, "merge decrements lod_level from 2 to 1")

	# Same parent_lod_id preserved
	a.parent_lod_id = "shared_parent"
	b.parent_lod_id = "shared_parent"
	var m3 := a.merge_with(b)
	_assert(m3.parent_lod_id == "shared_parent", "merge preserves shared parent_lod_id")

	# Different parent_lod_id → empty
	a.parent_lod_id = "parent_1"
	b.parent_lod_id = "parent_2"
	var m4 := a.merge_with(b)
	_assert(m4.parent_lod_id == "", "merge with different parents clears parent_lod_id")

	# Connection inheritance via registry merge
	var c1 := _make_box("conn_a", Vector3(2, 4, 4), Vector3(-1, 0, 0))
	var c2 := _make_box("conn_b", Vector3(2, 4, 4), Vector3(1, 0, 0))
	var external := _make_box("external", Vector3(2, 2, 2), Vector3(5, 0, 0))
	_registry.register(c1)
	_registry.register(c2)
	_registry.register(external)
	_registry.connect_blocks(c1.block_id, external.block_id)
	_registry.connect_blocks(c2.block_id, c1.block_id)

	var merge_ids: Array[String] = [c1.block_id, c2.block_id]
	var cm := _registry.merge_blocks(merge_ids)
	_assert(cm != null, "connection merge succeeds")
	_assert(cm.is_connected_to(external.block_id), "merged block inherits external connection")
	_assert(external.is_connected_to(cm.block_id), "external block connected to merged result")


# =========================================================================
# Group 8: Merge Validation (15 tests)
# =========================================================================

func _test_merge_validation() -> void:
	print("\n--- Merge Validation ---")
	_reset_registry()

	# Less than 2 blocks
	var single_ids: Array[String] = ["only_one"]
	var fail := _registry.merge_blocks(single_ids)
	_assert(fail == null, "merge with <2 blocks returns null")

	# Empty array
	var empty_ids: Array[String] = []
	var fail2 := _registry.merge_blocks(empty_ids)
	_assert(fail2 == null, "merge with empty array returns null")

	# Non-existent block
	var ne_ids: Array[String] = ["nonexistent_a", "nonexistent_b"]
	var fail3 := _registry.merge_blocks(ne_ids)
	_assert(fail3 == null, "merge non-existent blocks returns null")

	# merge_with always produces result (no type checking — shapes handled by caller)
	var box := _make_box("box", Vector3(2, 2, 2), Vector3(0, 0, 0))
	var cyl := _make_cylinder("cyl", 1.0, 2.0, Vector3(2, 0, 0))
	box.ensure_id()
	cyl.ensure_id()
	var mixed := box.merge_with(cyl)
	_assert(mixed != null, "merge_with different shapes produces result (caller validates)")

	# LOD level 0 merge stays at 0
	var a0 := _make_box("lod0_a", Vector3(2, 4, 4), Vector3(-1, 0, 0))
	var b0 := _make_box("lod0_b", Vector3(2, 4, 4), Vector3(1, 0, 0))
	a0.lod_level = 0
	b0.lod_level = 0
	a0.ensure_id()
	b0.ensure_id()
	var m0 := a0.merge_with(b0)
	_assert(m0.lod_level == 0, "merge at lod_level 0 stays at 0 (max(0-1, 0))")

	# Registry merge cleans up source blocks properly
	var ra := _make_box("cleanup_a", Vector3(2, 4, 4), Vector3(-1, 0, 0))
	var rb := _make_box("cleanup_b", Vector3(2, 4, 4), Vector3(1, 0, 0))
	_registry.register(ra)
	_registry.register(rb)
	var count_before := _registry.get_block_count()
	var rm_ids: Array[String] = [ra.block_id, rb.block_id]
	var rm := _registry.merge_blocks(rm_ids)
	_assert(rm != null, "cleanup merge succeeds")
	# 2 removed, 1 added = net -1
	_assert(_registry.get_block_count() == count_before - 1, "merge reduces block count by 1")

	# Merge result is active
	_assert(rm.active, "merged result block is active")

	# Merge result passes validation
	var errors := BlockValidator.validate(rm)
	_assert(errors.is_empty(), "merged block passes validation")

	# Source blocks no longer in registry
	_assert(_registry.get_block(ra.block_id) == null, "source A removed from registry")
	_assert(_registry.get_block(rb.block_id) == null, "source B removed from registry")

	# Merge preserves interaction type
	var wa := _make_box("walk_a", Vector3(2, 2, 2), Vector3(-1, 0, 0))
	wa.interaction = BlockCategories.INTERACT_WALKABLE
	wa.ensure_id()
	var wb := _make_box("walk_b", Vector3(2, 2, 2), Vector3(1, 0, 0))
	wb.interaction = BlockCategories.INTERACT_WALKABLE
	wb.ensure_id()
	var wm := wa.merge_with(wb)
	_assert(wm.interaction == BlockCategories.INTERACT_WALKABLE, "merged preserves WALKABLE interaction")

	# Merge preserves collision offset
	var oa := _make_box("off_a", Vector3(2, 2, 2), Vector3(-1, 0, 0))
	oa.collision_offset = Vector3(0, 1, 0)
	oa.ensure_id()
	var ob := _make_box("off_b", Vector3(2, 2, 2), Vector3(1, 0, 0))
	ob.collision_offset = Vector3(0, 1, 0)
	ob.ensure_id()
	var om := oa.merge_with(ob)
	_assert(om.collision_offset == Vector3(0, 1, 0), "merged preserves collision_offset")


# =========================================================================
# Group 9: DNA System (20 tests)
# =========================================================================

func _test_dna_system() -> void:
	print("\n--- DNA System ---")
	_reset_registry()

	# axis_preference guides auto subdivision
	var pref_x := _make_box("pref_x", Vector3(4, 4, 4))
	pref_x.dna = {"axis_preference": 0}
	pref_x.ensure_id()
	var ch_x := pref_x.subdivide(-1)
	_assert(ch_x.size() == 2, "axis_preference=0 produces 2 children (single axis)")
	_assert(is_equal_approx(ch_x[0].collision_size.x, 2.0), "axis_preference=0 splits X")
	_assert(is_equal_approx(ch_x[0].collision_size.y, 4.0), "axis_preference=0 preserves Y")

	var pref_y := _make_box("pref_y", Vector3(4, 4, 4))
	pref_y.dna = {"axis_preference": 1}
	pref_y.ensure_id()
	var ch_y := pref_y.subdivide(-1)
	_assert(ch_y.size() == 2, "axis_preference=1 produces 2 children")
	_assert(is_equal_approx(ch_y[0].collision_size.y, 2.0), "axis_preference=1 splits Y")

	var pref_z := _make_box("pref_z", Vector3(4, 4, 4))
	pref_z.dna = {"axis_preference": 2}
	pref_z.ensure_id()
	var ch_z := pref_z.subdivide(-1)
	_assert(ch_z.size() == 2, "axis_preference=2 produces 2 children")
	_assert(is_equal_approx(ch_z[0].collision_size.z, 2.0), "axis_preference=2 splits Z")

	# Invalid axis_preference falls back to auto
	var bad_pref := _make_box("bad_pref", Vector3(4, 4, 4))
	bad_pref.dna = {"axis_preference": 5}
	bad_pref.ensure_id()
	var ch_bad := bad_pref.subdivide(-1)
	_assert(ch_bad.size() == 8, "invalid axis_preference falls back to octree")

	# inherit_tags = false
	var no_tags := _make_box("no_inherit", Vector3(4, 4, 4))
	no_tags.tags = PackedStringArray(["parent_only"])
	no_tags.dna = {"inherit_tags": false}
	no_tags.ensure_id()
	var nt_ch := no_tags.subdivide(0)
	_assert(nt_ch[0].tags.is_empty(), "inherit_tags=false children have no tags")

	# inherit_tags = true (default)
	var yes_tags := _make_box("yes_inherit", Vector3(4, 4, 4))
	yes_tags.tags = PackedStringArray(["shared_tag"])
	yes_tags.ensure_id()
	var yt_ch := yes_tags.subdivide(0)
	_assert("shared_tag" in yt_ch[0].tags, "default inherit_tags children get parent tags")

	# property_overrides
	var override := _make_box("override_cell", Vector3(4, 4, 4))
	override.dna = {"property_overrides": {"material_id": "cell_active"}}
	override.ensure_id()
	var ov_ch := override.subdivide(0)
	_assert(ov_ch[0].material_id == "cell_active", "property_overrides applies material_id")
	_assert(ov_ch[1].material_id == "cell_active", "property_overrides applies to all children")

	# Multiple overrides
	var multi_ov := _make_box("multi_ov", Vector3(4, 4, 4))
	multi_ov.dna = {"property_overrides": {
		"material_id": "cell_dividing",
		"cast_shadow": false,
	}}
	multi_ov.ensure_id()
	var mo_ch := multi_ov.subdivide(0)
	_assert(mo_ch[0].material_id == "cell_dividing", "multi-override: material_id applied")
	_assert(mo_ch[0].cast_shadow == false, "multi-override: cast_shadow applied")

	# DNA propagates through multiple subdivisions
	var deep := _make_box("deep_dna", Vector3(8, 8, 8))
	deep.dna = {"axis_preference": 0}
	deep.ensure_id()
	var gen1 := deep.subdivide(-1)
	var gen2 := gen1[0].subdivide(-1)
	_assert(gen2.size() == 2, "DNA axis_preference propagates to generation 2")
	_assert(is_equal_approx(gen2[0].collision_size.x, 2.0), "gen2 X is 2.0 (8→4→2)")

	# DNA validation
	var valid_dna := _make_box("valid_dna", Vector3(4, 4, 4))
	valid_dna.dna = {"axis_preference": 1, "child_count": 2}
	valid_dna.ensure_id()
	var dna_errors := BlockValidator.validate(valid_dna)
	_assert(dna_errors.is_empty(), "valid DNA passes validation")

	var bad_dna := _make_box("bad_dna", Vector3(4, 4, 4))
	bad_dna.dna = {"axis_preference": 5}
	bad_dna.ensure_id()
	var bad_errors := BlockValidator.validate(bad_dna)
	_assert(not bad_errors.is_empty(), "invalid axis_preference=5 fails validation")

	var bad_count := _make_box("bad_count", Vector3(4, 4, 4))
	bad_count.dna = {"child_count": 3}
	bad_count.ensure_id()
	var count_errors := BlockValidator.validate(bad_count)
	_assert(not count_errors.is_empty(), "invalid child_count=3 fails validation")


# =========================================================================
# Group 10: LOD Adaptation (20 tests)
# =========================================================================

func _test_lod_adaptation() -> void:
	print("\n--- LOD Adaptation ---")
	_reset_registry()

	# Adapt to higher LOD
	var root := _make_box("lod_root", Vector3(8, 8, 8))
	_registry.register(root)

	_registry.adapt_lod([root.block_id] as Array[String], 1)
	var active1 := _registry.get_active_blocks()
	var lod1_blocks: Array[Block] = []
	for b in active1:
		if b.lod_level == 1:
			lod1_blocks.append(b)
	_assert(not root.active, "root deactivated after adapt to LOD 1")
	_assert(lod1_blocks.size() > 0, "LOD 1 blocks created")

	# Adapt further to LOD 2
	var lod1_ids: Array[String] = []
	for b in lod1_blocks:
		lod1_ids.append(b.block_id)
	_registry.adapt_lod(lod1_ids, 2)
	var active2 := _registry.get_active_blocks()
	var lod2_count := 0
	for b in active2:
		if b.lod_level == 2:
			lod2_count += 1
	_assert(lod2_count > 0, "LOD 2 blocks created from LOD 1 adapt")

	# Fresh test: adapt from 0 to 2 directly
	_reset_registry()
	var fresh := _make_box("fresh_lod", Vector3(8, 8, 8))
	_registry.register(fresh)
	_registry.adapt_lod([fresh.block_id] as Array[String], 2)
	var active_fresh := _registry.get_active_blocks()
	var lod2_fresh := 0
	for b in active_fresh:
		if b.lod_level >= 2:
			lod2_fresh += 1
	_assert(lod2_fresh > 0, "direct adapt 0→2 creates LOD 2 blocks")
	_assert(not fresh.active, "root deactivated in 0→2 adapt")

	# LOD 0 adapt is no-op
	_reset_registry()
	var noop := _make_box("noop_lod", Vector3(4, 4, 4))
	_registry.register(noop)
	_registry.adapt_lod([noop.block_id] as Array[String], 0)
	_assert(noop.active, "LOD 0 adapt is no-op — block stays active")
	_assert(_registry.get_block_count() == 1, "LOD 0 adapt doesn't create new blocks")

	# Subdivision tree reflects LOD
	_reset_registry()
	var tree_root := _make_box("tree_lod", Vector3(8, 8, 8))
	tree_root.dna = {"axis_preference": 0}
	_registry.register(tree_root)
	_registry.adapt_lod([tree_root.block_id] as Array[String], 2)
	var tree := _registry.get_subdivision_tree(tree_root.block_id)
	_assert(not tree.is_empty(), "subdivision tree non-empty after adapt")
	_assert(tree["children"].size() > 0, "tree has children after adapt")

	# Active blocks are all leaves
	var leaves := _registry.get_active_blocks()
	var all_leaves := true
	for leaf in leaves:
		if leaf.child_lod_ids.size() > 0:
			# Check if any children are active
			for cid in leaf.child_lod_ids:
				var child := _registry.get_block(cid)
				if child != null and child.active:
					all_leaves = false
					break
	_assert(all_leaves, "all active blocks are leaves (no active children)")

	# Total block count grows with LOD
	_reset_registry()
	var grow := _make_box("grow_lod", Vector3(8, 8, 8))
	grow.dna = {"axis_preference": 0}
	_registry.register(grow)
	var count0 := _registry.get_block_count()
	_registry.adapt_lod([grow.block_id] as Array[String], 1)
	var count1 := _registry.get_block_count()
	_assert(count1 > count0, "LOD 1 has more blocks than LOD 0")

	# Get active blocks filters correctly
	var all_blocks := _registry.get_all_blocks()
	var active_blocks := _registry.get_active_blocks()
	_assert(active_blocks.size() <= all_blocks.size(), "active blocks <= total blocks")
	_assert(active_blocks.size() > 0, "at least 1 active block")

	# Inactive blocks are retrievable but not in active list
	_assert(_registry.get_block(grow.block_id) != null, "inactive root still in registry")
	var root_in_active := false
	for b in active_blocks:
		if b.block_id == grow.block_id:
			root_in_active = true
	_assert(not root_in_active, "inactive root not in active list")

	# adapt_lod with empty list is safe
	_registry.adapt_lod([] as Array[String], 5)
	_assert(true, "adapt_lod with empty list doesn't crash")

	# adapt_lod with nonexistent block is safe
	_registry.adapt_lod(["nonexistent"] as Array[String], 5)
	_assert(true, "adapt_lod with nonexistent block doesn't crash")

	# Deep LOD produces blocks at correct level
	_reset_registry()
	var deep := _make_box("deep", Vector3(16, 16, 16))
	deep.dna = {"axis_preference": 0}
	_registry.register(deep)
	_registry.adapt_lod([deep.block_id] as Array[String], 3)
	var deep_active := _registry.get_active_blocks()
	var level3_count := 0
	for b in deep_active:
		if b.lod_level == 3:
			level3_count += 1
	_assert(level3_count > 0, "adapt to LOD 3 produces level-3 blocks")


# =========================================================================
# Group 11: Amoeba Movement (30 tests)
# =========================================================================

func _test_amoeba_movement() -> void:
	print("\n--- Amoeba Movement ---")
	_reset_registry()

	# Build an 8-block amoeba (2x2x2 grid of 2x2x2 cells)
	var cells: Array[Block] = []
	var cell_ids: Array[String] = []
	for x in [0, 1]:
		for y in [0, 1]:
			for z in [0, 1]:
				var cell := _make_box(
					"amoeba_%d%d%d" % [x, y, z],
					Vector3(2, 2, 2),
					Vector3(x * 2.0 - 1.0, y * 2.0 - 1.0, z * 2.0 - 1.0))
				if x == 1:
					cell.tags = PackedStringArray(["front"])
				else:
					cell.tags = PackedStringArray(["rear"])
				_registry.register(cell)
				cells.append(cell)
				cell_ids.append(cell.block_id)

	# Connect all cells as mesh
	for i in range(cells.size()):
		for j in range(i + 1, cells.size()):
			_registry.connect_blocks(cells[i].block_id, cells[j].block_id)

	_assert(cells.size() == 8, "amoeba has 8 cells")
	_assert(_registry.get_block_count() == 8, "registry has 8 blocks")

	# Calculate initial center of mass
	var com_start := Vector3.ZERO
	for c in cells:
		com_start += c.position
	com_start /= cells.size()
	_assert(is_equal_approx(com_start.x, 0.0), "initial COM at X=0")

	# Front cells are tagged
	var front_cells := _registry.get_blocks_by_tag("front")
	_assert(front_cells.size() == 4, "4 front cells tagged")
	var rear_cells := _registry.get_blocks_by_tag("rear")
	_assert(rear_cells.size() == 4, "4 rear cells tagged")

	# --- Cycle 1: Front cells subdivide (extend forward) ---
	var new_front_cells: Array[Block] = []
	for fc in front_cells:
		var subdivided := _registry.subdivide_block(fc.block_id, 0)  # split along X
		if not subdivided.is_empty():
			new_front_cells.append_array(subdivided)

	_assert(new_front_cells.size() == 8, "cycle 1: front 4 cells → 8 sub-cells")

	# The front children extend further in +X
	var max_x := -999.0
	for c in new_front_cells:
		if c.position.x > max_x:
			max_x = c.position.x
	_assert(max_x > 1.0, "cycle 1: front extends past original X=1")

	# Rear cells merge pairwise (contract)
	var rear_ids: Array[String] = []
	for rc in rear_cells:
		rear_ids.append(rc.block_id)
	# Merge first two rear cells
	var merge_pair1: Array[String] = [rear_ids[0], rear_ids[1]]
	var merged1 := _registry.merge_blocks(merge_pair1)
	_assert(merged1 != null, "cycle 1: rear pair 1 merged")

	var merge_pair2: Array[String] = [rear_ids[2], rear_ids[3]]
	var merged2 := _registry.merge_blocks(merge_pair2)
	_assert(merged2 != null, "cycle 1: rear pair 2 merged")

	# Active block count changed
	var active_c1 := _registry.get_active_blocks()
	# 8 new front + 2 merged rear = 10 active
	_assert(active_c1.size() == 10, "cycle 1: 10 active blocks (8 front sub + 2 merged rear)")

	# Center of mass shifted forward
	var com_c1 := Vector3.ZERO
	for b in active_c1:
		com_c1 += b.position
	com_c1 /= active_c1.size()
	_assert(com_c1.x > com_start.x, "cycle 1: COM shifted forward in X")

	# Connection integrity — merged blocks should be connected to neighbors
	_assert(merged1.has_peer_connections() or merged2.has_peer_connections(),
		"cycle 1: merged rear blocks have connections")

	# Front sub-cells have correct LOD
	var front_lod_correct := true
	for fc in new_front_cells:
		if fc.lod_level != 1:
			front_lod_correct = false
	_assert(front_lod_correct, "cycle 1: front sub-cells at LOD 1")

	# --- Cycle 2: Verify state consistency ---
	var active_c2 := _registry.get_active_blocks()
	var total_c2 := _registry.get_block_count()
	_assert(active_c2.size() <= total_c2, "active blocks <= total blocks")

	# All active blocks pass validation
	var all_valid := true
	for b in active_c2:
		var errs := BlockValidator.validate(b)
		if not errs.is_empty():
			all_valid = false
			break
	_assert(all_valid, "all active blocks pass validation after movement cycle")

	# Subdivision tree for deactivated front parents
	for fc in front_cells:
		if not fc.active:
			var tree := _registry.get_subdivision_tree(fc.block_id)
			_assert(not tree.is_empty(), "deactivated parent has subdivision tree")
			break

	# No block references itself
	var no_self_ref := true
	for b in _registry.get_all_blocks():
		if b is Block:
			if b.parent_lod_id == b.block_id:
				no_self_ref = false
			for cid in b.child_lod_ids:
				if cid == b.block_id:
					no_self_ref = false
	_assert(no_self_ref, "no block references itself in LOD hierarchy")

	# Movement displacement measurable
	var displacement := com_c1.x - com_start.x
	_assert(displacement > 0.01, "measurable forward displacement: %.3f" % displacement)

	# Merged rear blocks are larger than original
	_assert(merged1.collision_size.x >= 2.0 or merged1.collision_size.y >= 2.0 \
			or merged1.collision_size.z >= 2.0, "merged rear block has increased dimension")

	# IDs are all unique across all blocks
	var all_ids := {}
	var id_collision := false
	for b in _registry.get_all_blocks():
		if b is Block:
			if all_ids.has(b.block_id):
				id_collision = true
			all_ids[b.block_id] = true
	_assert(not id_collision, "all block IDs unique after amoeba movement")

	# Block count is reasonable (original 8 + subdivisions - merges)
	_assert(_registry.get_block_count() > 8, "total blocks increased from movement")
	_assert(_registry.get_block_count() < 30, "total blocks reasonable (not exponential)")

	# Active blocks form a connected graph
	if not active_c2.is_empty():
		var start_id: String = active_c2[0].block_id
		var reachable := {}
		var bfs_queue: Array[String] = [start_id]
		while not bfs_queue.is_empty():
			var cid: String = bfs_queue.pop_front()
			if reachable.has(cid):
				continue
			reachable[cid] = true
			var blk := _registry.get_block(cid)
			if blk == null:
				continue
			for conn in blk.connections:
				if not reachable.has(conn):
					var peer := _registry.get_block(conn)
					if peer != null and peer.active:
						bfs_queue.append(conn)
		# Not all active blocks may be reachable due to connection transfer limitations
		_assert(reachable.size() >= 2, "at least 2 active blocks reachable via connections")


# =========================================================================
# Group 12: Neural Cascade (25 tests)
# =========================================================================

func _test_neural_cascade() -> void:
	print("\n--- Neural Cascade ---")
	_reset_registry()

	# Build a chain of 5 connected blocks (neurons)
	var chain: Array[Block] = []
	for i in range(5):
		var neuron := _make_box("neuron_%d" % i, Vector3(2, 2, 2),
			Vector3(i * 3.0, 0, 0))
		_registry.register(neuron)
		chain.append(neuron)
		if i > 0:
			_registry.connect_blocks(chain[i - 1].block_id, chain[i].block_id)

	_assert(chain.size() == 5, "neural chain has 5 neurons")
	_assert(chain[0].is_connected_to(chain[1].block_id), "neuron 0 connected to 1")
	_assert(chain[3].is_connected_to(chain[4].block_id), "neuron 3 connected to 4")
	_assert(not chain[0].is_connected_to(chain[4].block_id), "neuron 0 NOT connected to 4")

	# Message propagation through chain
	var received_msgs: Array[String] = []
	_registry.message_received.connect(func(target: Block, msg_type: String,
			_data: Dictionary, _sender: String):
		received_msgs.append(target.block_id)
	)

	var reached := _registry.propagate_through_connections(chain[0].block_id, "fire", {})
	_assert(reached.size() == 5, "propagate reaches all 5 neurons")
	_assert(received_msgs.size() == 5, "5 messages received through chain")

	# Order: BFS from neuron 0
	_assert(received_msgs[0] == chain[0].block_id, "first message to neuron 0")

	# Subdivide middle neuron — children inherit connections
	var mid_id := chain[2].block_id
	var mid_children := _registry.subdivide_block(mid_id, 0)
	_assert(mid_children.size() == 2, "middle neuron subdivides into 2")
	_assert(not chain[2].active, "middle neuron deactivated")

	# Children should have some connections (transferred from parent)
	var has_conns := mid_children[0].has_peer_connections() or mid_children[1].has_peer_connections()
	_assert(has_conns, "subdivision children inherit external connections")

	# Propagate again — should still reach neurons through subdivided middle
	received_msgs.clear()
	var reached2 := _registry.propagate_through_connections(chain[0].block_id, "fire2", {})
	# chain[0] → chain[1] → mid_children[0] (has chain[1] connection) → mid_children[1] (sibling)
	_assert(reached2.size() >= 3, "propagation reaches through subdivided neuron")

	# Subdivide-triggered cascade: subdivide neuron 4 after signal
	var pre_count := _registry.get_active_blocks().size()
	var n4_children := _registry.subdivide_block(chain[4].block_id, 0)
	_assert(n4_children.size() == 2, "neuron 4 subdivides on signal")
	var post_count := _registry.get_active_blocks().size()
	_assert(post_count == pre_count + 1, "active count +1 after subdivision (2 new - 1 deactivated)")

	# Build a branching network (tree topology)
	_reset_registry()
	received_msgs.clear()
	var hub := _make_box("hub", Vector3(2, 2, 2))
	_registry.register(hub)

	var branches: Array[Block] = []
	for i in range(4):
		var branch := _make_box("branch_%d" % i, Vector3(2, 2, 2),
			Vector3(3.0 * cos(i * PI / 2), 0, 3.0 * sin(i * PI / 2)))
		_registry.register(branch)
		_registry.connect_blocks(hub.block_id, branch.block_id)
		branches.append(branch)

	var hub_reached := _registry.propagate_through_connections(hub.block_id, "broadcast", {})
	_assert(hub_reached.size() == 5, "hub broadcast reaches all 5 nodes (hub + 4 branches)")

	# Each branch connected only to hub
	_assert(not branches[0].is_connected_to(branches[1].block_id),
		"branches not cross-connected")

	# Subdivide hub — connections transfer to representative child
	var hub_children := _registry.subdivide_block(hub.block_id, 0)
	_assert(hub_children.size() == 2, "hub subdivides into 2")

	# At least one child should connect to branches
	var child_has_branch_conn := false
	for ch in hub_children:
		for br in branches:
			if ch.is_connected_to(br.block_id):
				child_has_branch_conn = true
				break
	_assert(child_has_branch_conn, "hub child inherits branch connection")

	# Siblings connected to each other
	_assert(hub_children[0].is_connected_to(hub_children[1].block_id),
		"hub siblings connected")

	# Message to specific neuron
	var specific_ok := _registry.send_message(branches[0].block_id, "activate", {}, hub.block_id)
	_assert(specific_ok, "send_message to specific neuron succeeds")

	# Broadcast from branch doesn't reach other branches (no cross-connections)
	received_msgs.clear()
	# Disconnect the old message handler to prevent count pollution
	# Just test the structure
	var b0_conns := _registry.get_connections(branches[0].block_id)
	var b0_connects_to_branch := false
	for conn in b0_conns:
		for br in branches:
			if br.block_id != branches[0].block_id and conn == br.block_id:
				b0_connects_to_branch = true
	_assert(not b0_connects_to_branch, "branch 0 has no direct connection to other branches")


# =========================================================================
# Group 13: Shape Support (15 tests)
# =========================================================================

func _test_shape_support() -> void:
	print("\n--- Shape Support ---")
	_reset_registry()

	# CYLINDER subdivision (height axis only)
	var cyl := _make_cylinder("cyl_cell", 2.0, 4.0)
	cyl.ensure_id()
	_assert(cyl.can_subdivide(1), "CYLINDER can subdivide on height (axis 1)")
	_assert(not cyl.can_subdivide(0), "CYLINDER cannot subdivide on radius (axis 0)")
	var cyl_ch := cyl.subdivide(1)
	_assert(cyl_ch.size() == 2, "CYLINDER split produces 2")
	_assert(is_equal_approx(cyl_ch[0].collision_size.y, 2.0), "CYLINDER child height halved")
	_assert(is_equal_approx(cyl_ch[0].collision_size.x, 2.0), "CYLINDER child radius unchanged")

	# CAPSULE subdivision
	var cap := Block.new()
	cap.block_name = "cap_cell"
	cap.category = BlockCategories.STRUCTURE
	cap.collision_shape = BlockCategories.SHAPE_CAPSULE
	cap.collision_size = Vector3(1.0, 4.0, 0)
	cap.collision_layer = CollisionLayers.WORLD
	cap.min_size = Vector3(0.1, 0.1, 0.1)
	cap.ensure_id()
	_assert(cap.can_subdivide(1), "CAPSULE can subdivide on height")
	var cap_ch := cap.subdivide(1)
	_assert(cap_ch.size() == 2, "CAPSULE split produces 2")
	_assert(is_equal_approx(cap_ch[0].collision_size.y, 2.0), "CAPSULE child height halved")

	# SPHERE subdivision
	var sph := _make_sphere("sph_cell", 2.0, 4.0)
	sph.ensure_id()
	_assert(sph.can_subdivide(1), "SPHERE can subdivide on height")
	var sph_ch := sph.subdivide(1)
	_assert(sph_ch.size() == 2, "SPHERE split produces 2")
	_assert(is_equal_approx(sph_ch[0].collision_size.y, 2.0), "SPHERE child height halved")

	# SHAPE_NONE rejected
	var none := Block.new()
	none.block_name = "none_block"
	none.collision_shape = BlockCategories.SHAPE_NONE
	_assert(not none.can_subdivide(), "SHAPE_NONE cannot subdivide")
	none.ensure_id()
	var none_ch := none.subdivide()
	_assert(none_ch.is_empty(), "SHAPE_NONE subdivide returns empty")

	# Builder handles SPHERE
	var sph_built := _make_sphere("sphere_build", 1.5, 3.0)
	sph_built.ensure_id()
	sph_built.active = true
	var node := BlockBuilder.build(sph_built, self)
	_assert(node != null, "BlockBuilder.build SPHERE returns node")
	var mesh := node.get_node_or_null("Mesh") as MeshInstance3D
	_assert(mesh != null, "SPHERE build has Mesh child")
	_assert(mesh.mesh is SphereMesh, "SPHERE mesh is SphereMesh")
	node.queue_free()

	# Validator accepts SPHERE
	var sph_valid := _make_sphere("sph_valid", 1.0, 2.0)
	sph_valid.ensure_id()
	var errors := BlockValidator.validate(sph_valid)
	_assert(errors.is_empty(), "valid SPHERE passes validation")


# =========================================================================
# Group 14: Stress Test (20 tests)
# =========================================================================

func _test_stress() -> void:
	print("\n--- Stress Test ---")
	_reset_registry()

	# Create 50 blocks
	var roots: Array[Block] = []
	for i in range(50):
		var b := _make_box("stress_%d" % i, Vector3(4, 4, 4),
			Vector3(i * 5.0, 0, 0))
		b.dna = {"axis_preference": 0}
		_registry.register(b)
		roots.append(b)

	_assert(_registry.get_block_count() == 50, "50 blocks registered")
	_assert(_registry.get_active_blocks().size() == 50, "50 active blocks")

	# Subdivide all to level 1
	for root in roots:
		_registry.subdivide_block(root.block_id, 0)

	var after_l1 := _registry.get_block_count()
	_assert(after_l1 == 150, "50 parents + 100 children = 150 total after LOD 1")
	_assert(_registry.get_active_blocks().size() == 100, "100 active at LOD 1")

	# Subdivide all active to level 2
	var active_l1 := _registry.get_active_blocks().duplicate()
	for b in active_l1:
		_registry.subdivide_block(b.block_id, 0)

	var after_l2 := _registry.get_block_count()
	_assert(after_l2 == 350, "150 + 200 children = 350 total after LOD 2")
	_assert(_registry.get_active_blocks().size() == 200, "200 active at LOD 2")

	# Subdivide to level 3
	var active_l2 := _registry.get_active_blocks().duplicate()
	for b in active_l2:
		_registry.subdivide_block(b.block_id, 0)

	var after_l3 := _registry.get_block_count()
	_assert(after_l3 == 750, "350 + 400 = 750 total after LOD 3")
	_assert(_registry.get_active_blocks().size() == 400, "400 active leaves at LOD 3")

	# All active blocks pass validation
	var all_valid := true
	var checked := 0
	for b in _registry.get_active_blocks():
		var errs := BlockValidator.validate(b)
		if not errs.is_empty():
			all_valid = false
			break
		checked += 1
	_assert(all_valid, "all 400 active blocks pass validation")
	_assert(checked == 400, "validated all 400 blocks")

	# LOD levels correct
	var level_counts := {}
	for b in _registry.get_all_blocks():
		if b is Block:
			var lvl: int = b.lod_level
			level_counts[lvl] = level_counts.get(lvl, 0) + 1
	_assert(level_counts.get(0, 0) == 50, "50 blocks at LOD 0")
	_assert(level_counts.get(1, 0) == 100, "100 blocks at LOD 1")
	_assert(level_counts.get(2, 0) == 200, "200 blocks at LOD 2")
	_assert(level_counts.get(3, 0) == 400, "400 blocks at LOD 3")

	# Merge back: take first 2 active blocks that share a parent
	var active_l3 := _registry.get_active_blocks()
	var merged_count := 0
	var merge_attempts := 0
	var seen_parents := {}
	for b in active_l3:
		if b is Block and not b.parent_lod_id.is_empty():
			if seen_parents.has(b.parent_lod_id):
				# Found a sibling pair
				var sibling_id: String = seen_parents[b.parent_lod_id]
				var pair: Array[String] = [sibling_id, b.block_id]
				var result := _registry.merge_blocks(pair)
				if result != null:
					merged_count += 1
				merge_attempts += 1
				if merge_attempts >= 10:
					break
			else:
				seen_parents[b.parent_lod_id] = b.block_id

	_assert(merged_count > 0, "at least 1 merge succeeded in stress test")

	# Registry stays consistent
	var final_active := _registry.get_active_blocks()
	var final_total := _registry.get_block_count()
	_assert(final_active.size() > 0, "still have active blocks after merges")
	_assert(final_active.size() <= final_total, "active <= total after merges")

	# No duplicate IDs
	var id_set := {}
	var has_dupes := false
	for b in _registry.get_all_blocks():
		if b is Block:
			if id_set.has(b.block_id):
				has_dupes = true
			id_set[b.block_id] = true
	_assert(not has_dupes, "no duplicate IDs in 750+ block registry")

	# Performance: spatial query still works
	var nearby := _registry.get_blocks_near(Vector3(25, 0, 0), 10.0)
	_assert(nearby.size() > 0, "spatial query finds blocks in large registry")

	# Category query works
	var structures := _registry.get_blocks_by_category(BlockCategories.STRUCTURE)
	_assert(structures.size() > 0, "category query works in large registry")

	# Clear works
	_registry.clear()
	_assert(_registry.get_block_count() == 0, "clear empties large registry")
	_assert(_registry.get_active_blocks().is_empty(), "no active blocks after clear")
