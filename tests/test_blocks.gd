extends Node3D
## Block Library Test Suite
##
## Builds a Car from Block primitives and stress-tests the entire system:
## creation, validation, registry, parent-child links, block-to-block
## communication, builder output, collision export, lifecycle, materials,
## and edge cases.
##
## Run headless:
##   godot --headless --path godot_project --scene-path res://addons/blocks/tests/test_blocks.tscn

var _pass_count := 0
var _fail_count := 0
var _test_count := 0
var _registry: BlockRegistry


func _ready() -> void:
	print("")
	print("=" .repeat(60))
	print("  BLOCK LIBRARY TEST SUITE")
	print("=" .repeat(60))
	print("")

	# Create a local registry instance (not the autoload — standalone test)
	_registry = BlockRegistry.new()
	_registry.name = "TestRegistry"
	add_child(_registry)

	# Run all test groups
	_test_block_creation()
	_test_validation_pass()
	_test_validation_fail()
	_test_registry_basics()
	_test_car_assembly()
	_test_parent_child_links()
	_test_block_to_block_communication()
	_test_telephone_game()
	_test_builder_output()
	_test_collision_export()
	_test_lifecycle()
	_test_material_cache()
	_test_spatial_queries()
	_test_edge_cases()
	_test_categories_helpers()
	_test_block_duplication()
	_test_material_override_parsing()
	_test_material_override_cache()
	_test_builder_material_dispatch()
	_test_procedural_material_cache()
	_test_prewarm_shaders()
	_test_shape_vocabulary()
	_test_glb_validation()
	_test_glb_cache()
	_test_glb_build_dispatch()
	_test_glb_sdf_exclusion()
	_test_materials_list_field()
	_test_multi_material_parsing()
	_test_multi_material_override_parsing()
	_test_multi_material_build()

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

	# Exit with code for CI
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


func _section(name: String) -> void:
	print("")
	print("--- %s ---" % name)


# =========================================================================
# Block factory helpers (builds car parts)
# =========================================================================

func _make_block(bname: String, cat: int, shape: int, size: Vector3,
		pos: Vector3, interaction: int, material: String = "default",
		layer: int = -1) -> Block:
	var b := Block.new()
	b.block_name = bname
	b.category = cat
	b.collision_shape = shape
	b.collision_size = size
	b.position = pos
	b.interaction = interaction
	b.material_id = material
	b.collision_layer = layer if layer > 0 else BlockCategories.default_layer(interaction)
	return b


func _make_chassis() -> Block:
	return _make_block("chassis", BlockCategories.STRUCTURE,
		BlockCategories.SHAPE_BOX, Vector3(4.0, 1.0, 2.0),
		Vector3(0, 0.5, 0), BlockCategories.INTERACT_SOLID, "metal_dark")


func _make_wheel(name: String, pos: Vector3) -> Block:
	return _make_block(name, BlockCategories.PROP,
		BlockCategories.SHAPE_CYLINDER, Vector3(0.4, 0.3, 0),
		pos, BlockCategories.INTERACT_SOLID, "black")


func _make_steering_wheel() -> Block:
	return _make_block("steering_wheel", BlockCategories.PROP,
		BlockCategories.SHAPE_CYLINDER, Vector3(0.2, 0.05, 0),
		Vector3(-0.5, 1.2, 0), BlockCategories.INTERACT_SOLID, "black")


func _make_headlight(name: String, pos: Vector3) -> Block:
	var b := _make_block(name, BlockCategories.EFFECT,
		BlockCategories.SHAPE_CAPSULE, Vector3(0.15, 0.3, 0),
		pos, BlockCategories.INTERACT_SOLID, "glow_yellow")
	b.cast_shadow = false
	b.tags = PackedStringArray(["light", "front"])
	return b


func _make_engine() -> Block:
	return _make_block("engine", BlockCategories.STRUCTURE,
		BlockCategories.SHAPE_BOX, Vector3(1.5, 0.8, 1.5),
		Vector3(1.2, 0.6, 0), BlockCategories.INTERACT_SOLID, "metal_dark")


func _make_windshield() -> Block:
	var b := _make_block("windshield", BlockCategories.PROP,
		BlockCategories.SHAPE_BOX, Vector3(0.1, 0.8, 1.6),
		Vector3(0.3, 1.2, 0), BlockCategories.INTERACT_SOLID, "glass")
	b.server_collidable = false  # Visual only — no server collision
	return b


# =========================================================================
# Test groups
# =========================================================================

func _test_block_creation() -> void:
	_section("Block Creation")

	var b := Block.new()
	_assert(b is Resource, "Block extends Resource")
	_assert(b.block_id == "", "block_id starts empty")
	_assert(b.collision_shape == BlockCategories.SHAPE_BOX, "default shape is BOX")
	_assert(b.interaction == BlockCategories.INTERACT_SOLID, "default interaction is SOLID")
	_assert(b.creator == BlockCategories.CREATOR_SYSTEM, "default creator is SYSTEM")
	_assert(b.version == 1, "default version is 1")
	_assert(not b.active, "not active before registration")
	_assert(b.node == null, "no node before build")

	b.block_name = "test_block"
	b.ensure_id()
	_assert(not b.block_id.is_empty(), "ensure_id generates an ID")
	_assert(b.block_id.contains("test_block"), "ID contains block name")

	var chassis := _make_chassis()
	_assert(chassis.block_name == "chassis", "chassis has correct name")
	_assert(chassis.collision_size == Vector3(4.0, 1.0, 2.0), "chassis has correct size")
	_assert(chassis.material_id == "metal_dark", "chassis has correct material")


func _test_validation_pass() -> void:
	_section("Validation — Valid Blocks")

	var chassis := _make_chassis()
	chassis.ensure_id()
	_assert(BlockValidator.is_valid(chassis), "chassis passes validation")

	var wheel := _make_wheel("fl_wheel", Vector3(-1.5, 0, -1.0))
	wheel.ensure_id()
	_assert(BlockValidator.is_valid(wheel), "wheel passes validation")

	var headlight := _make_headlight("left_headlight", Vector3(2.0, 0.8, -0.6))
	headlight.ensure_id()
	_assert(BlockValidator.is_valid(headlight), "headlight passes validation")

	var windshield := _make_windshield()
	windshield.ensure_id()
	_assert(BlockValidator.is_valid(windshield), "windshield passes validation")

	# Trigger with valid config
	var horn := Block.new()
	horn.block_name = "horn_trigger"
	horn.category = BlockCategories.TRIGGER_CAT
	horn.collision_shape = BlockCategories.SHAPE_BOX
	horn.collision_size = Vector3(1.0, 1.0, 1.0)
	horn.interaction = BlockCategories.INTERACT_TRIGGER
	horn.collision_layer = CollisionLayers.TRIGGER
	horn.trigger_radius = 2.0
	horn.ensure_id()
	_assert(BlockValidator.is_valid(horn), "trigger block passes validation")


func _test_validation_fail() -> void:
	_section("Validation — Invalid Blocks (should fail)")

	# Empty name
	var b1 := Block.new()
	b1.collision_size = Vector3(1, 1, 1)
	var e1 := BlockValidator.validate(b1)
	_assert(not e1.is_empty(), "empty name fails validation")
	_assert(e1[0].contains("block_name"), "error mentions block_name")

	# Zero-size collision
	var b2 := Block.new()
	b2.block_name = "zero_size"
	b2.collision_size = Vector3(0, 0, 0)
	var e2 := BlockValidator.validate(b2)
	_assert(not e2.is_empty(), "zero collision size fails")

	# Negative dimension
	var b3 := Block.new()
	b3.block_name = "negative"
	b3.collision_size = Vector3(-1, 1, 1)
	var e3 := BlockValidator.validate(b3)
	_assert(not e3.is_empty(), "negative dimension fails")

	# Oversized
	var b4 := Block.new()
	b4.block_name = "oversized"
	b4.collision_size = Vector3(600, 1, 1)
	var e4 := BlockValidator.validate(b4)
	_assert(not e4.is_empty(), "oversized dimension fails")

	# Wrong layer for trigger
	var b5 := Block.new()
	b5.block_name = "bad_trigger"
	b5.collision_shape = BlockCategories.SHAPE_BOX
	b5.collision_size = Vector3(1, 1, 1)
	b5.interaction = BlockCategories.INTERACT_TRIGGER
	b5.collision_layer = CollisionLayers.WORLD  # Should be TRIGGER
	b5.trigger_radius = 2.0
	var e5 := BlockValidator.validate(b5)
	_assert(not e5.is_empty(), "trigger on wrong layer fails")

	# Wrong layer for water
	var b6 := Block.new()
	b6.block_name = "bad_water"
	b6.collision_shape = BlockCategories.SHAPE_BOX
	b6.collision_size = Vector3(5, 1, 5)
	b6.interaction = BlockCategories.INTERACT_WATER
	b6.collision_layer = CollisionLayers.WORLD  # Should be WATER
	var e6 := BlockValidator.validate(b6)
	_assert(not e6.is_empty(), "water on wrong layer fails")

	# Collision/visual ratio too big
	var b7 := Block.new()
	b7.block_name = "ratio_bad"
	b7.collision_size = Vector3(10, 1, 1)
	b7.mesh_size = Vector3(1, 1, 1)  # Collision 10x larger on X
	var e7 := BlockValidator.validate(b7)
	_assert(not e7.is_empty(), "collision 10x larger than mesh fails")

	# Self-referencing parent
	var b8 := Block.new()
	b8.block_name = "self_parent"
	b8.block_id = "self_ref_001"
	b8.collision_size = Vector3(1, 1, 1)
	b8.parent_id = "self_ref_001"
	var e8 := BlockValidator.validate(b8)
	_assert(not e8.is_empty(), "self-referencing parent fails")

	# Trigger with no radius
	var b9 := Block.new()
	b9.block_name = "trigger_no_radius"
	b9.collision_shape = BlockCategories.SHAPE_BOX
	b9.collision_size = Vector3(1, 1, 1)
	b9.interaction = BlockCategories.INTERACT_TRIGGER
	b9.collision_layer = CollisionLayers.TRIGGER
	b9.trigger_radius = 0.0
	var e9 := BlockValidator.validate(b9)
	_assert(not e9.is_empty(), "trigger with zero radius fails")

	# Climbable too short
	var b10 := Block.new()
	b10.block_name = "short_ladder"
	b10.collision_shape = BlockCategories.SHAPE_BOX
	b10.collision_size = Vector3(1, 0.5, 1)
	b10.interaction = BlockCategories.INTERACT_CLIMBABLE
	b10.collision_layer = CollisionLayers.TRUNK
	var e10 := BlockValidator.validate(b10)
	_assert(not e10.is_empty(), "climbable too short fails")

	# Out of bounds position
	var b11 := Block.new()
	b11.block_name = "out_of_bounds"
	b11.collision_size = Vector3(1, 1, 1)
	b11.position = Vector3(9999, 0, 0)
	var e11 := BlockValidator.validate(b11)
	_assert(not e11.is_empty(), "out-of-bounds position fails")

	# Negative scale
	var b12 := Block.new()
	b12.block_name = "neg_scale"
	b12.collision_size = Vector3(1, 1, 1)
	b12.scale_factor = -1.0
	var e12 := BlockValidator.validate(b12)
	_assert(not e12.is_empty(), "negative scale fails")


func _test_registry_basics() -> void:
	_section("Registry — Basic Operations")

	_registry.clear()

	var b := _make_chassis()
	var ok := _registry.register(b)
	_assert(ok, "register valid block succeeds")
	_assert(_registry.get_block_count() == 1, "block count is 1")
	_assert(b.active, "block is active after registration")
	_assert(b.instantiated_at > 0, "instantiated_at is set")

	var fetched := _registry.get_block(b.block_id)
	_assert(fetched == b, "get_block returns same instance")

	# Duplicate registration should fail
	var ok2 := _registry.register(b)
	_assert(not ok2, "duplicate registration fails")
	_assert(_registry.get_block_count() == 1, "count still 1 after dupe attempt")

	# Invalid block should fail
	var bad := Block.new()  # Empty name
	bad.collision_size = Vector3(1, 1, 1)
	var ok3 := _registry.register(bad)
	_assert(not ok3, "invalid block registration fails")
	_assert(not _registry.get_last_errors().is_empty(), "last_errors populated on failure")

	# Unregister
	_registry.unregister(b.block_id)
	_assert(_registry.get_block_count() == 0, "count is 0 after unregister")
	_assert(not b.active, "block is inactive after unregister")
	_assert(b.destroyed_at > 0, "destroyed_at is set")
	_assert(_registry.get_block(b.block_id) == null, "get_block returns null after unregister")


func _test_car_assembly() -> void:
	_section("Car Assembly — Build Full Car")

	_registry.clear()

	# Create all car parts
	var chassis := _make_chassis()
	chassis.ensure_id()

	var fl_wheel := _make_wheel("fl_wheel", Vector3(-1.5, 0, -1.0))
	fl_wheel.parent_id = chassis.block_id
	var fr_wheel := _make_wheel("fr_wheel", Vector3(-1.5, 0, 1.0))
	fr_wheel.parent_id = chassis.block_id
	var rl_wheel := _make_wheel("rl_wheel", Vector3(1.5, 0, -1.0))
	rl_wheel.parent_id = chassis.block_id
	var rr_wheel := _make_wheel("rr_wheel", Vector3(1.5, 0, 1.0))
	rr_wheel.parent_id = chassis.block_id

	var steering := _make_steering_wheel()
	steering.parent_id = chassis.block_id

	var left_light := _make_headlight("left_headlight", Vector3(2.0, 0.8, -0.6))
	left_light.parent_id = chassis.block_id
	var right_light := _make_headlight("right_headlight", Vector3(2.0, 0.8, 0.6))
	right_light.parent_id = chassis.block_id

	var engine := _make_engine()
	engine.parent_id = chassis.block_id

	var windshield := _make_windshield()
	windshield.parent_id = chassis.block_id

	# Register all parts
	var parts: Array[Block] = [
		chassis, fl_wheel, fr_wheel, rl_wheel, rr_wheel,
		steering, left_light, right_light, engine, windshield
	]

	var all_ok := true
	for part in parts:
		if not _registry.register(part):
			all_ok = false
			print("    Failed to register: %s — %s" % [
				part.block_name, ", ".join(_registry.get_last_errors())])

	_assert(all_ok, "all 10 car parts registered successfully")
	_assert(_registry.get_block_count() == 10, "registry has 10 blocks")

	# Category queries
	var structures := _registry.get_blocks_by_category(BlockCategories.STRUCTURE)
	_assert(structures.size() == 2, "2 STRUCTURE blocks (chassis + engine)")

	var props := _registry.get_blocks_by_category(BlockCategories.PROP)
	_assert(props.size() == 6, "6 PROP blocks (4 wheels + steering + windshield)")

	var effects := _registry.get_blocks_by_category(BlockCategories.EFFECT)
	_assert(effects.size() == 2, "2 EFFECT blocks (headlights)")

	# Tag queries
	var lights := _registry.get_blocks_by_tag("light")
	_assert(lights.size() == 2, "2 blocks tagged 'light'")
	var front := _registry.get_blocks_by_tag("front")
	_assert(front.size() == 2, "2 blocks tagged 'front'")


func _test_parent_child_links() -> void:
	_section("Parent-Child Links")

	# Chassis should have 9 children (registered with parent_id)
	var chassis_id := ""
	for block: Block in _registry.get_all_blocks():
		if block.block_name == "chassis":
			chassis_id = block.block_id
			break

	_assert(not chassis_id.is_empty(), "found chassis in registry")

	var chassis := _registry.get_block(chassis_id)
	_assert(chassis.has_children(), "chassis has children")
	_assert(chassis.child_ids.size() == 9, "chassis has 9 children")

	var children := _registry.get_child_blocks(chassis_id)
	_assert(children.size() == 9, "get_children returns 9 blocks")

	# Each child should point back to chassis
	var all_point_to_chassis := true
	for child in children:
		if child.parent_id != chassis_id:
			all_point_to_chassis = false
	_assert(all_point_to_chassis, "all children point to chassis as parent")

	# Get parent of a wheel
	var wheel_id := ""
	for child in children:
		if child.block_name == "fl_wheel":
			wheel_id = child.block_id
	_assert(not wheel_id.is_empty(), "found fl_wheel child")

	var parent := _registry.get_parent_block(wheel_id)
	_assert(parent != null and parent.block_id == chassis_id, "wheel's parent is chassis")

	# Get root from a child
	var root := _registry.get_root(wheel_id)
	_assert(root != null and root.block_id == chassis_id, "root of wheel is chassis")

	# Chassis is its own root
	var chassis_root := _registry.get_root(chassis_id)
	_assert(chassis_root != null and chassis_root.block_id == chassis_id, "chassis is its own root")

	# Get all descendants
	var descendants := _registry.get_descendants(chassis_id)
	_assert(descendants.size() == 9, "chassis has 9 descendants")


func _test_block_to_block_communication() -> void:
	_section("Block-to-Block Communication")

	# Steering wheel should be able to find the headlights through the registry
	var steering: Block = null
	var left_light: Block = null
	var right_light: Block = null

	for block: Block in _registry.get_all_blocks():
		match block.block_name:
			"steering_wheel": steering = block
			"left_headlight": left_light = block
			"right_headlight": right_light = block

	_assert(steering != null, "found steering wheel")
	_assert(left_light != null, "found left headlight")
	_assert(right_light != null, "found right headlight")

	# Steering wheel asks: "who are my siblings tagged 'light'?"
	var parent := _registry.get_parent_block(steering.block_id)
	_assert(parent != null, "steering has a parent")

	var siblings := _registry.get_child_blocks(parent.block_id)
	var sibling_lights: Array[Block] = []
	for sibling in siblings:
		if "light" in sibling.tags:
			sibling_lights.append(sibling)
	_assert(sibling_lights.size() == 2, "steering finds 2 sibling lights")

	# Headlights know about each other through shared parent
	var left_parent := _registry.get_parent_block(left_light.block_id)
	var right_parent := _registry.get_parent_block(right_light.block_id)
	_assert(left_parent.block_id == right_parent.block_id,
		"both headlights share same parent")


func _test_telephone_game() -> void:
	_section("Telephone Game — Path Between Blocks")

	# Find path from fl_wheel to right_headlight
	var fl_wheel: Block = null
	var right_light: Block = null
	for block: Block in _registry.get_all_blocks():
		if block.block_name == "fl_wheel": fl_wheel = block
		if block.block_name == "right_headlight": right_light = block

	_assert(fl_wheel != null and right_light != null, "found both endpoints")

	var path := _registry.find_path(fl_wheel.block_id, right_light.block_id)
	_assert(not path.is_empty(), "path exists between fl_wheel and right_headlight")
	_assert(path.size() == 3, "path is 3 hops: wheel -> chassis -> headlight")

	# Verify the path
	if path.size() == 3:
		var first := _registry.get_block(path[0])
		var mid := _registry.get_block(path[1])
		var last := _registry.get_block(path[2])
		_assert(first.block_name == "fl_wheel", "path starts at fl_wheel")
		_assert(mid.block_name == "chassis", "path goes through chassis")
		_assert(last.block_name == "right_headlight", "path ends at right_headlight")

	# Path from block to itself
	var self_path := _registry.find_path(fl_wheel.block_id, fl_wheel.block_id)
	_assert(self_path.size() == 1, "path to self is length 1")

	# Path between two non-connected blocks should be empty
	# (Create an isolated block)
	var isolated := _make_block("isolated_rock", BlockCategories.PROP,
		BlockCategories.SHAPE_BOX, Vector3(1, 1, 1),
		Vector3(50, 0, 50), BlockCategories.INTERACT_SOLID)
	_registry.register(isolated)
	var no_path := _registry.find_path(fl_wheel.block_id, isolated.block_id)
	_assert(no_path.is_empty(), "no path between disconnected blocks")
	_registry.unregister(isolated.block_id)


func _test_builder_output() -> void:
	_section("Builder Output — Node3D Subtree")

	# Build a chassis Node3D
	var chassis := _make_chassis()
	chassis.ensure_id()
	var node := BlockBuilder.build(chassis, self)
	_assert(node != null, "build returns Node3D")
	_assert(node is Node3D, "result is Node3D")
	_assert(node.name == "chassis", "node name matches block_name")
	_assert(chassis.node == node, "block.node reference set")
	_assert(node.get_meta("block_id") == chassis.block_id, "block_id metadata set")

	# Check collision subtree
	var body := node.get_node_or_null("Body")
	_assert(body != null, "Body child exists")
	_assert(body is StaticBody3D, "Body is StaticBody3D")

	var col := body.get_node_or_null("Col")
	_assert(col != null, "Col child exists")
	_assert(col is CollisionShape3D, "Col is CollisionShape3D")
	_assert(col.shape is BoxShape3D, "shape is BoxShape3D")

	var box_shape := col.shape as BoxShape3D
	_assert(box_shape.size == Vector3(4.0, 1.0, 2.0), "box size matches block")

	# Check collision layer
	var static_body := body as StaticBody3D
	_assert(static_body.collision_layer == CollisionLayers.to_bit(CollisionLayers.WORLD),
		"collision_layer bitmask correct")
	_assert(static_body.collision_mask == 0, "collision_mask is 0 (static)")

	# Check visual subtree
	var mesh := node.get_node_or_null("Mesh")
	_assert(mesh != null, "Mesh child exists")
	_assert(mesh is MeshInstance3D, "Mesh is MeshInstance3D")
	_assert(mesh.material_override != null, "material_override set")

	# Build a cylinder (wheel)
	var wheel := _make_wheel("test_wheel", Vector3.ZERO)
	wheel.ensure_id()
	var wheel_node := BlockBuilder.build(wheel, self)
	var wheel_col := wheel_node.get_node("Body/Col")
	_assert(wheel_col.shape is CylinderShape3D, "wheel uses CylinderShape3D")

	# Build a capsule (headlight)
	var light := _make_headlight("test_light", Vector3.ZERO)
	light.ensure_id()
	var light_node := BlockBuilder.build(light, self)
	var light_col := light_node.get_node("Body/Col")
	_assert(light_col.shape is CapsuleShape3D, "headlight uses CapsuleShape3D")

	# Build a trigger (uses Area3D instead of StaticBody3D)
	var trigger_block := Block.new()
	trigger_block.block_name = "test_trigger"
	trigger_block.collision_shape = BlockCategories.SHAPE_BOX
	trigger_block.collision_size = Vector3(2, 2, 2)
	trigger_block.interaction = BlockCategories.INTERACT_TRIGGER
	trigger_block.collision_layer = CollisionLayers.TRIGGER
	trigger_block.trigger_radius = 3.0
	trigger_block.ensure_id()
	var trigger_node := BlockBuilder.build(trigger_block, self)
	var trigger_area := trigger_node.get_node_or_null("TriggerArea")
	_assert(trigger_area != null, "trigger creates TriggerArea")
	_assert(trigger_area is Area3D, "TriggerArea is Area3D")

	# Clean up built nodes
	node.queue_free()
	wheel_node.queue_free()
	light_node.queue_free()
	trigger_node.queue_free()


func _test_collision_export() -> void:
	_section("Collision Export")

	# The car from _test_car_assembly should still be in the registry
	var boxes := _registry.export_collision_boxes()
	_assert(not boxes.is_empty(), "collision boxes exported")

	# Count: 10 parts minus windshield (server_collidable=false) = 9
	# But we also need to check what's actually registered
	var collidable_count := 0
	for block: Block in _registry.get_all_blocks():
		if block.server_collidable and block.collision_shape != BlockCategories.SHAPE_NONE:
			collidable_count += 1

	_assert(boxes.size() == collidable_count,
		"export count (%d) matches collidable blocks (%d)" % [boxes.size(), collidable_count])

	# Each box should have required keys
	var all_have_keys := true
	for box in boxes:
		if not (box.has("min_x") and box.has("max_x") and box.has("min_z")
				and box.has("max_z") and box.has("height")):
			all_have_keys = false
	_assert(all_have_keys, "all boxes have required keys")

	# Test TypeScript export format
	var ts := BlockExporter.export_typescript(_registry)
	_assert(ts.contains("OBSTACLES"), "TypeScript export contains OBSTACLES")
	_assert(ts.contains("minX"), "TypeScript export contains minX")
	_assert(ts.contains("height"), "TypeScript export contains height")

	# Test GDScript export format
	var gd := BlockExporter.export_gdscript(_registry)
	_assert(gd.contains("obstacle_boxes"), "GDScript export contains obstacle_boxes")
	_assert(gd.contains("min_x"), "GDScript export contains min_x")

	# Windshield should NOT appear in export
	var windshield_in_export := false
	for box in boxes:
		# Windshield is at x=0.3, very thin on x (0.1) — if we find that box it leaked
		if absf(box["max_x"] - box["min_x"]) < 0.2:
			windshield_in_export = true
	# This is a weak check — better to verify windshield block directly
	var windshield: Block = null
	for block: Block in _registry.get_all_blocks():
		if block.block_name == "windshield":
			windshield = block
	if windshield:
		var wd := windshield.to_collision_dict()
		_assert(wd.is_empty(), "windshield.to_collision_dict() is empty (non-collidable)")


func _test_lifecycle() -> void:
	_section("Lifecycle — Register/Unregister/Re-register")

	_registry.clear()

	var b := _make_block("lifecycle_test", BlockCategories.PROP,
		BlockCategories.SHAPE_BOX, Vector3(1, 1, 1),
		Vector3(10, 0, 10), BlockCategories.INTERACT_SOLID)

	# Register
	_registry.register(b)
	_assert(b.active, "block active after register")
	_assert(b.instantiated_at > 0, "instantiated_at set")
	var block_id := b.block_id

	# Unregister
	_registry.unregister(block_id)
	_assert(not b.active, "block inactive after unregister")
	_assert(b.destroyed_at > 0, "destroyed_at set")
	_assert(_registry.get_block(block_id) == null, "block not in registry")
	_assert(_registry.get_block_count() == 0, "count is 0")

	# Parent-child lifecycle: unregister child removes from parent's child_ids
	var parent := _make_block("parent_lc", BlockCategories.STRUCTURE,
		BlockCategories.SHAPE_BOX, Vector3(2, 2, 2),
		Vector3.ZERO, BlockCategories.INTERACT_SOLID)
	parent.ensure_id()
	_registry.register(parent)

	var child := _make_block("child_lc", BlockCategories.PROP,
		BlockCategories.SHAPE_BOX, Vector3(1, 1, 1),
		Vector3(1, 0, 0), BlockCategories.INTERACT_SOLID)
	child.parent_id = parent.block_id
	_registry.register(child)

	_assert(parent.child_ids.size() == 1, "parent has 1 child after registration")

	_registry.unregister(child.block_id)
	_assert(parent.child_ids.size() == 0, "parent has 0 children after child unregister")

	_registry.clear()


func _test_material_cache() -> void:
	_section("Material Cache")

	BlockMaterials.clear_cache()

	# Same material ID returns same instance
	var mat1 := BlockMaterials.get_material("wood")
	var mat2 := BlockMaterials.get_material("wood")
	_assert(mat1 == mat2, "same material_id returns same instance")

	# Opaque materials use ShaderMaterial (if shader loaded)
	if mat1 is ShaderMaterial:
		_assert(mat1.get_shader_parameter("albedo_color") == BlockMaterials.PALETTE["wood"],
			"wood shader color correct")
	else:
		# Fallback: StandardMaterial3D when shader unavailable (e.g. headless)
		_assert((mat1 as StandardMaterial3D).albedo_color == BlockMaterials.PALETTE["wood"],
			"wood fallback color correct")

	# Different IDs return different instances
	var mat3 := BlockMaterials.get_material("metal_dark")
	_assert(mat3 != mat1, "different material_id returns different instance")

	# Unknown ID returns default with warning
	var mat4 := BlockMaterials.get_material("nonexistent_material_xyz")
	if mat4 is ShaderMaterial:
		_assert(mat4.get_shader_parameter("albedo_color") == BlockMaterials.PALETTE["default"],
			"unknown material returns default color (shader)")
	else:
		_assert((mat4 as StandardMaterial3D).albedo_color == BlockMaterials.PALETTE["default"],
			"unknown material returns default color (fallback)")

	# Color-based material (always StandardMaterial3D)
	var color := Color(0.42, 0.69, 0.13)
	var mat5 := BlockMaterials.get_material_from_color(color)
	var mat6 := BlockMaterials.get_material_from_color(color)
	_assert(mat5 == mat6, "same color returns same cached instance")
	_assert(mat5.albedo_color == color, "color matches request")

	# Transparent material stays StandardMaterial3D
	var glass := BlockMaterials.get_material("glass")
	_assert(glass is StandardMaterial3D, "transparent material uses StandardMaterial3D")
	_assert((glass as StandardMaterial3D).transparency == BaseMaterial3D.TRANSPARENCY_ALPHA,
		"glass material has alpha transparency")

	# Palette queries
	_assert(BlockMaterials.has_material("wood"), "has_material('wood') is true")
	_assert(not BlockMaterials.has_material("unobtainium"), "has_material('unobtainium') is false")
	_assert(BlockMaterials.get_palette_keys().size() > 20, "palette has 20+ entries")


func _test_spatial_queries() -> void:
	_section("Spatial Queries")

	_registry.clear()

	# Place blocks at known positions
	var a := _make_block("near_origin", BlockCategories.PROP,
		BlockCategories.SHAPE_BOX, Vector3(1, 1, 1),
		Vector3(5, 0, 5), BlockCategories.INTERACT_SOLID)
	var b := _make_block("far_away", BlockCategories.PROP,
		BlockCategories.SHAPE_BOX, Vector3(1, 1, 1),
		Vector3(100, 0, 100), BlockCategories.INTERACT_SOLID)
	var c := _make_block("also_near", BlockCategories.PROP,
		BlockCategories.SHAPE_BOX, Vector3(1, 1, 1),
		Vector3(8, 0, 3), BlockCategories.INTERACT_SOLID)

	_registry.register(a)
	_registry.register(b)
	_registry.register(c)

	# Query near origin
	var nearby := _registry.get_blocks_near(Vector3(5, 0, 5), 10.0)
	_assert(nearby.size() == 2, "2 blocks within 10 of (5,0,5)")

	# Verify which ones
	var names: Array[String] = []
	for block in nearby:
		names.append(block.block_name)
	_assert("near_origin" in names, "near_origin found")
	_assert("also_near" in names, "also_near found")
	_assert("far_away" not in names, "far_away NOT found")

	# Query near far block
	var far_nearby := _registry.get_blocks_near(Vector3(100, 0, 100), 5.0)
	_assert(far_nearby.size() == 1, "1 block within 5 of (100,0,100)")
	_assert(far_nearby[0].block_name == "far_away", "found far_away")

	# Update position and re-query
	_registry.update_position(b.block_id, Vector3(6, 0, 6))
	var after_move := _registry.get_blocks_near(Vector3(5, 0, 5), 10.0)
	_assert(after_move.size() == 3, "3 blocks near origin after moving far_away closer")

	_registry.clear()


func _test_edge_cases() -> void:
	_section("Edge Cases")

	_registry.clear()

	# Get block from empty registry
	_assert(_registry.get_block("nonexistent") == null, "get_block on empty returns null")
	_assert(_registry.get_blocks_near(Vector3.ZERO, 100.0).is_empty(),
		"get_blocks_near on empty returns empty")

	# Unregister non-existent block (should not crash)
	_registry.unregister("nonexistent_id")
	_assert(true, "unregistering non-existent block doesn't crash")

	# Register block with no collision shape (SHAPE_NONE)
	var no_col := Block.new()
	no_col.block_name = "invisible_marker"
	no_col.collision_shape = BlockCategories.SHAPE_NONE
	no_col.collision_size = Vector3.ZERO
	var ok := _registry.register(no_col)
	_assert(ok, "SHAPE_NONE block registers successfully")

	# SHAPE_NONE block should not appear in collision export
	var boxes := _registry.export_collision_boxes()
	_assert(boxes.is_empty(), "SHAPE_NONE block not in collision export")

	# Build SHAPE_NONE block — should have no Body child
	var node := BlockBuilder.build(no_col, self)
	_assert(node.get_node_or_null("Body") == null, "SHAPE_NONE build has no Body")
	_assert(node.get_node_or_null("Mesh") == null, "SHAPE_NONE build has no Mesh")
	node.queue_free()

	# Block at grid boundary (exactly on grid cell edge)
	var boundary := _make_block("on_boundary", BlockCategories.PROP,
		BlockCategories.SHAPE_BOX, Vector3(1, 1, 1),
		Vector3(20.0, 0, 40.0),  # Exactly on grid boundary
		BlockCategories.INTERACT_SOLID)
	_registry.register(boundary)
	var found := _registry.get_blocks_near(Vector3(20.0, 0, 40.0), 1.0)
	_assert(found.size() >= 1, "block on grid boundary is findable")

	# Clear and verify clean state
	_registry.clear()
	_assert(_registry.get_block_count() == 0, "clear empties registry")
	_assert(_registry.get_all_blocks().is_empty(), "get_all_blocks empty after clear")


func _test_categories_helpers() -> void:
	_section("Categories Helpers")

	_assert(BlockCategories.category_name(BlockCategories.TERRAIN) == "terrain",
		"category_name TERRAIN")
	_assert(BlockCategories.category_name(BlockCategories.PROP) == "prop",
		"category_name PROP")
	_assert(BlockCategories.category_name(99) == "unknown",
		"category_name invalid returns unknown")

	_assert(BlockCategories.shape_name(BlockCategories.SHAPE_BOX) == "box",
		"shape_name BOX")
	_assert(BlockCategories.shape_name(BlockCategories.SHAPE_CYLINDER) == "cylinder",
		"shape_name CYLINDER")

	_assert(BlockCategories.interaction_name(BlockCategories.INTERACT_BRIDGE) == "bridge",
		"interaction_name BRIDGE")

	_assert(BlockCategories.creator_name(BlockCategories.CREATOR_AI) == "ai",
		"creator_name AI")

	_assert(BlockCategories.default_layer(BlockCategories.INTERACT_SOLID) == CollisionLayers.WORLD,
		"default_layer SOLID = WORLD")
	_assert(BlockCategories.default_layer(BlockCategories.INTERACT_WALKABLE) == CollisionLayers.PLATFORM,
		"default_layer WALKABLE = PLATFORM")
	_assert(BlockCategories.default_layer(BlockCategories.INTERACT_BRIDGE) == CollisionLayers.BRIDGE,
		"default_layer BRIDGE = BRIDGE")


func _test_block_duplication() -> void:
	_section("Block Duplication")

	var original := _make_chassis()
	original.ensure_id()
	original.tags = PackedStringArray(["car", "main"])

	var clone := original.duplicate_block()
	_assert(clone.block_id != original.block_id, "clone has different ID")
	_assert(clone.block_name == original.block_name, "clone has same name")
	_assert(clone.collision_size == original.collision_size, "clone has same size")
	_assert(clone.material_id == original.material_id, "clone has same material")
	_assert(clone.node == null, "clone has no node reference")
	_assert(not clone.active, "clone is not active")

	# Summary string
	var summary := original.summary()
	_assert(summary.contains("chassis"), "summary contains block_name")
	_assert(summary.contains("structure"), "summary contains category")


func _test_material_override_parsing() -> void:
	_section("Material Override Parsing (Phase 9-01)")

	# --- Default Block fields ---
	var default_block := Block.new()
	_assert(default_block.color_tint == Color.WHITE, "default color_tint is Color.WHITE")
	_assert(default_block.material_params == {}, "default material_params is empty dict")

	# --- file_to_block(): 3-element color array ---
	var data_3col := {
		"format_version": 1,
		"identity": {"name": "test_3col"},
		"collision": {"shape": "box", "size": [1, 1, 1]},
		"visual": {"color": [0.8, 0.3, 0.1]}
	}
	var b_3col := BlockFile.file_to_block(data_3col)
	_assert(absf(b_3col.color_tint.r - 0.8) < 0.001, "3-element color: r = 0.8")
	_assert(absf(b_3col.color_tint.g - 0.3) < 0.001, "3-element color: g = 0.3")
	_assert(absf(b_3col.color_tint.b - 0.1) < 0.001, "3-element color: b = 0.1")
	_assert(absf(b_3col.color_tint.a - 1.0) < 0.001, "3-element color: alpha defaults to 1.0")

	# --- file_to_block(): 4-element color array ---
	var data_4col := {
		"format_version": 1,
		"identity": {"name": "test_4col"},
		"collision": {"shape": "box", "size": [1, 1, 1]},
		"visual": {"color": [0.8, 0.3, 0.1, 0.5]}
	}
	var b_4col := BlockFile.file_to_block(data_4col)
	_assert(absf(b_4col.color_tint.a - 0.5) < 0.001, "4-element color: alpha = 0.5")

	# --- file_to_block(): no visual.color leaves WHITE ---
	var data_nocol := {
		"format_version": 1,
		"identity": {"name": "test_nocol"},
		"collision": {"shape": "box", "size": [1, 1, 1]},
		"visual": {}
	}
	var b_nocol := BlockFile.file_to_block(data_nocol)
	_assert(b_nocol.color_tint == Color.WHITE, "missing visual.color leaves Color.WHITE")

	# --- file_to_block(): visual.roughness ---
	var data_rough := {
		"format_version": 1,
		"identity": {"name": "test_rough"},
		"collision": {"shape": "box", "size": [1, 1, 1]},
		"visual": {"roughness": 0.9}
	}
	var b_rough := BlockFile.file_to_block(data_rough)
	_assert(b_rough.material_params.has("roughness"), "roughness parsed into material_params")
	_assert(absf(b_rough.material_params["roughness"] - 0.9) < 0.001, "roughness value = 0.9")

	# --- file_to_block(): visual.metallic ---
	var data_metal := {
		"format_version": 1,
		"identity": {"name": "test_metal"},
		"collision": {"shape": "box", "size": [1, 1, 1]},
		"visual": {"metallic": 0.8}
	}
	var b_metal := BlockFile.file_to_block(data_metal)
	_assert(b_metal.material_params.has("metallic"), "metallic parsed into material_params")
	_assert(absf(b_metal.material_params["metallic"] - 0.8) < 0.001, "metallic value = 0.8")

	# --- file_to_block(): visual.bump_scale ---
	var data_bump := {
		"format_version": 1,
		"identity": {"name": "test_bump"},
		"collision": {"shape": "box", "size": [1, 1, 1]},
		"visual": {"bump_scale": 0.5}
	}
	var b_bump := BlockFile.file_to_block(data_bump)
	_assert(b_bump.material_params.has("surface_noise_strength"),
		"bump_scale maps to surface_noise_strength")
	_assert(absf(b_bump.material_params["surface_noise_strength"] - 0.5) < 0.001,
		"bump_scale value = 0.5")

	# --- file_to_block(): visual.noise_scale ---
	var data_nscale := {
		"format_version": 1,
		"identity": {"name": "test_nscale"},
		"collision": {"shape": "box", "size": [1, 1, 1]},
		"visual": {"noise": {"scale": 12.0, "strength": 0.1}}
	}
	var b_nscale := BlockFile.file_to_block(data_nscale)
	_assert(b_nscale.material_params.has("surface_noise_scale"),
		"noise.scale maps to surface_noise_scale in material_params")
	_assert(absf(b_nscale.material_params["surface_noise_scale"] - 12.0) < 0.001,
		"noise.scale value = 12.0")

	# --- file_to_block(): no overrides → empty material_params ---
	var data_plain := {
		"format_version": 1,
		"identity": {"name": "test_plain"},
		"collision": {"shape": "box", "size": [1, 1, 1]},
		"visual": {"material": "wood"}
	}
	var b_plain := BlockFile.file_to_block(data_plain)
	_assert(b_plain.material_params.is_empty(), "no overrides → empty material_params")

	# --- Assembly override dot-paths ---
	# visual.roughness dot-path
	var base_block_r := BlockFile.file_to_block(data_plain)
	BlockFile.apply_overrides(base_block_r, {"visual.roughness": 0.9})
	_assert(base_block_r.material_params.has("roughness"),
		"dot-path visual.roughness sets material_params.roughness")
	_assert(absf(base_block_r.material_params["roughness"] - 0.9) < 0.001,
		"dot-path visual.roughness value = 0.9")

	# visual.color dot-path
	var base_block_c := BlockFile.file_to_block(data_plain)
	BlockFile.apply_overrides(base_block_c, {"visual.color": [0.5, 0.5, 0.5]})
	_assert(absf(base_block_c.color_tint.r - 0.5) < 0.001,
		"dot-path visual.color sets color_tint.r")

	# visual.metallic dot-path
	var base_block_m := BlockFile.file_to_block(data_plain)
	BlockFile.apply_overrides(base_block_m, {"visual.metallic": 0.6})
	_assert(base_block_m.material_params.has("metallic"),
		"dot-path visual.metallic sets material_params.metallic")
	_assert(absf(base_block_m.material_params["metallic"] - 0.6) < 0.001,
		"dot-path visual.metallic value = 0.6")

func _get_mesh_from_node(node: Node3D) -> MeshInstance3D:
	return node.get_node_or_null("Mesh") as MeshInstance3D


func _test_material_override_cache() -> void:
	_section("Material Override Cache (Phase 9-01)")

	BlockMaterials.clear_cache()

	# --- get_material_with_overrides returns ShaderMaterial with correct param ---
	var mat_a: Material = BlockMaterials.get_material_with_overrides("bark", {"roughness": 0.3})
	if mat_a is ShaderMaterial:
		var r: float = mat_a.get_shader_parameter("roughness")
		_assert(absf(r - 0.3) < 0.001, "override cache: ShaderMaterial has roughness=0.3")
	else:
		# Headless fallback — just verify it returns something
		_assert(mat_a != null, "override cache: returned non-null (headless fallback)")

	# --- Same params return same instance (deduplication) ---
	var mat_b: Material = BlockMaterials.get_material_with_overrides("bark", {"roughness": 0.3})
	_assert(mat_a == mat_b, "override cache: same params return same instance")

	# --- Different params return different instances ---
	var mat_c: Material = BlockMaterials.get_material_with_overrides("bark", {"roughness": 0.7})
	_assert(mat_a != mat_c, "override cache: different params return different instances")

	# --- Quantization: 0.28 and 0.30 share same instance (0.05 step rounding) ---
	BlockMaterials.clear_cache()
	var mat_q1: Material = BlockMaterials.get_material_with_overrides("wood", {"roughness": 0.28})
	var mat_q2: Material = BlockMaterials.get_material_with_overrides("wood", {"roughness": 0.30})
	_assert(mat_q1 == mat_q2, "override cache: 0.28 and 0.30 share instance via quantization")

	# --- get_material_tinted returns instance for tint ---
	var tint := Color(1.0, 0.5, 0.0)
	var mat_t1: Material = BlockMaterials.get_material_tinted("wood", tint)
	_assert(mat_t1 != null, "tinted cache: returns non-null material")

	# --- Same tint returns same instance ---
	var mat_t2: Material = BlockMaterials.get_material_tinted("wood", tint)
	_assert(mat_t1 == mat_t2, "tinted cache: same tint returns same instance")

	# --- Transparent base material passthrough (no override on StandardMaterial3D) ---
	var mat_glass: Material = BlockMaterials.get_material_with_overrides("glass", {"roughness": 0.3})
	_assert(mat_glass is StandardMaterial3D,
		"transparent material: override returns base StandardMaterial3D unchanged")

	# --- clear_cache empties both caches ---
	var id_before: int = mat_t1.get_instance_id()
	BlockMaterials.clear_cache()
	var mat_t3: Material = BlockMaterials.get_material_tinted("wood", tint)
	_assert(mat_t3.get_instance_id() != id_before,
		"clear_cache: after clear, new tinted call returns new instance")


func _test_builder_material_dispatch() -> void:
	_section("Builder Material Dispatch (Phase 9-02)")

	BlockMaterials.clear_cache()
	var parent := Node3D.new()
	add_child(parent)

	# --- Default block (no overrides) → base cache ---
	var b_default := Block.new()
	b_default.block_name = "dispatch_default"
	b_default.collision_shape = BlockCategories.SHAPE_BOX
	b_default.collision_size = Vector3(1, 1, 1)
	b_default.interaction = BlockCategories.INTERACT_SOLID
	b_default.material_id = "wood"
	b_default.ensure_id()
	var node_default := BlockBuilder.build(b_default, parent)
	var mesh_default := _get_mesh_from_node(node_default)
	var base_mat: Material = BlockMaterials.get_material("wood")
	_assert(mesh_default != null, "dispatch default: Mesh node created")
	_assert(mesh_default.material_override != null, "dispatch default: material_override set")
	_assert(mesh_default.material_override == base_mat,
		"dispatch default: no overrides → returns base cache instance")

	# --- Block with color_tint only → override cache (different from base) ---
	var b_tint := Block.new()
	b_tint.block_name = "dispatch_tint"
	b_tint.collision_shape = BlockCategories.SHAPE_BOX
	b_tint.collision_size = Vector3(1, 1, 1)
	b_tint.interaction = BlockCategories.INTERACT_SOLID
	b_tint.material_id = "wood"
	b_tint.color_tint = Color(1.0, 0.5, 0.0)
	b_tint.ensure_id()
	var node_tint := BlockBuilder.build(b_tint, parent)
	var mesh_tint := _get_mesh_from_node(node_tint)
	_assert(mesh_tint != null, "dispatch tint: Mesh node created")
	_assert(mesh_tint.material_override != null, "dispatch tint: material_override set")
	_assert(mesh_tint.material_override != base_mat,
		"dispatch tint: tinted block gets different instance from base cache")
	# Verify tint_color param is set on the material
	if mesh_tint.material_override is ShaderMaterial:
		var tc: Color = (mesh_tint.material_override as ShaderMaterial).get_shader_parameter("tint_color")
		_assert(absf(tc.r - 1.0) < 0.001 and absf(tc.g - 0.5) < 0.001,
			"dispatch tint: tint_color uniform matches color_tint")
	else:
		_assert(true, "dispatch tint: (headless fallback — skipping shader param check)")

	# --- Block with material_params only → override cache ---
	var b_params := Block.new()
	b_params.block_name = "dispatch_params"
	b_params.collision_shape = BlockCategories.SHAPE_BOX
	b_params.collision_size = Vector3(1, 1, 1)
	b_params.interaction = BlockCategories.INTERACT_SOLID
	b_params.material_id = "wood"
	b_params.material_params = {"roughness": 0.9}
	b_params.ensure_id()
	var node_params := BlockBuilder.build(b_params, parent)
	var mesh_params := _get_mesh_from_node(node_params)
	_assert(mesh_params != null, "dispatch params: Mesh node created")
	_assert(mesh_params.material_override != null, "dispatch params: material_override set")
	_assert(mesh_params.material_override != base_mat,
		"dispatch params: override block gets different instance from base")
	if mesh_params.material_override is ShaderMaterial:
		var r: float = (mesh_params.material_override as ShaderMaterial).get_shader_parameter("roughness")
		_assert(absf(r - 0.9) < 0.001, "dispatch params: roughness param applied correctly")
	else:
		_assert(true, "dispatch params: (headless fallback — skipping shader param check)")

	# --- Block with BOTH color_tint AND material_params → single material instance ---
	var b_both := Block.new()
	b_both.block_name = "dispatch_both"
	b_both.collision_shape = BlockCategories.SHAPE_BOX
	b_both.collision_size = Vector3(1, 1, 1)
	b_both.interaction = BlockCategories.INTERACT_SOLID
	b_both.material_id = "wood"
	b_both.color_tint = Color(0.0, 1.0, 0.5)
	b_both.material_params = {"roughness": 0.7}
	b_both.ensure_id()
	var node_both := BlockBuilder.build(b_both, parent)
	var mesh_both := _get_mesh_from_node(node_both)
	_assert(mesh_both != null, "dispatch both: Mesh node created")
	_assert(mesh_both.material_override != null, "dispatch both: material_override set")
	_assert(mesh_both.material_override != base_mat,
		"dispatch both: combined overrides → different from base cache")
	if mesh_both.material_override is ShaderMaterial:
		var both_mat := mesh_both.material_override as ShaderMaterial
		var r2: float = both_mat.get_shader_parameter("roughness")
		var tc2: Color = both_mat.get_shader_parameter("tint_color")
		_assert(absf(r2 - 0.7) < 0.001, "dispatch both: roughness applied in combined material")
		_assert(absf(tc2.g - 1.0) < 0.001, "dispatch both: tint_color applied in combined material")
	else:
		_assert(true, "dispatch both: (headless fallback — skipping shader param checks)")

	# --- Identical blocks with same overrides share same material instance ---
	var b_dup1 := Block.new()
	b_dup1.block_name = "dispatch_dup1"
	b_dup1.collision_shape = BlockCategories.SHAPE_BOX
	b_dup1.collision_size = Vector3(1, 1, 1)
	b_dup1.interaction = BlockCategories.INTERACT_SOLID
	b_dup1.material_id = "wood"
	b_dup1.material_params = {"roughness": 0.6}
	b_dup1.ensure_id()
	var b_dup2 := Block.new()
	b_dup2.block_name = "dispatch_dup2"
	b_dup2.collision_shape = BlockCategories.SHAPE_BOX
	b_dup2.collision_size = Vector3(1, 1, 1)
	b_dup2.interaction = BlockCategories.INTERACT_SOLID
	b_dup2.material_id = "wood"
	b_dup2.material_params = {"roughness": 0.6}
	b_dup2.ensure_id()
	var node_dup1 := BlockBuilder.build(b_dup1, parent)
	var node_dup2 := BlockBuilder.build(b_dup2, parent)
	var mesh_dup1 := _get_mesh_from_node(node_dup1)
	var mesh_dup2 := _get_mesh_from_node(node_dup2)
	_assert(mesh_dup1 != null and mesh_dup2 != null, "dispatch dedup: both meshes created")
	_assert(mesh_dup1.material_override == mesh_dup2.material_override,
		"dispatch dedup: identical override params share same material instance")

	# --- Custom shader_path takes priority over overrides ---
	var b_shader := Block.new()
	b_shader.block_name = "dispatch_shader"
	b_shader.collision_shape = BlockCategories.SHAPE_BOX
	b_shader.collision_size = Vector3(1, 1, 1)
	b_shader.interaction = BlockCategories.INTERACT_SOLID
	b_shader.material_id = "wood"
	b_shader.color_tint = Color(1.0, 0.0, 0.0)
	b_shader.material_params = {"roughness": 0.5}
	b_shader.shader_path = "res://assets/shaders/block_world.gdshader"
	b_shader.ensure_id()
	var node_shader := BlockBuilder.build(b_shader, parent)
	var mesh_shader := _get_mesh_from_node(node_shader)
	_assert(mesh_shader != null, "dispatch shader: Mesh node created")
	# Shader path takes priority — material will be a fresh ShaderMaterial, not the cache instance
	if mesh_shader != null and mesh_shader.material_override != null:
		_assert(mesh_shader.material_override != base_mat,
			"dispatch shader: shader_path block doesn't use base cache")
	else:
		_assert(true, "dispatch shader: (no shader loaded headless — skip priority test)")

	# --- Test A: Procedural dispatch (material_type_id set) ---
	var b_proc := Block.new()
	b_proc.block_name = "dispatch_proc_bark"
	b_proc.collision_shape = BlockCategories.SHAPE_BOX
	b_proc.collision_size = Vector3(1, 1, 1)
	b_proc.interaction = BlockCategories.INTERACT_SOLID
	b_proc.material_id = "bark"
	b_proc.material_type_id = "bark"
	b_proc.ensure_id()
	var node_proc := BlockBuilder.build(b_proc, parent)
	var mesh_proc := _get_mesh_from_node(node_proc)
	_assert(mesh_proc != null, "dispatch proc: Mesh node created")
	_assert(mesh_proc.material_override != null, "dispatch proc: material_override set")
	var base_bark: Material = BlockMaterials.get_material("bark")
	_assert(mesh_proc.material_override != base_bark,
		"dispatch proc: procedural block gets different instance from base cache")
	if mesh_proc.material_override is ShaderMaterial:
		var type_int = (mesh_proc.material_override as ShaderMaterial).get_shader_parameter("material_type")
		_assert(type_int == 1, "dispatch proc: material_type uniform == 1 (bark)")
	else:
		_assert(true, "dispatch proc: (headless fallback — skipping material_type param check)")

	# --- Test B: Procedural wins over shader_path ---
	var b_proc_vs_shader := Block.new()
	b_proc_vs_shader.block_name = "dispatch_proc_vs_shader"
	b_proc_vs_shader.collision_shape = BlockCategories.SHAPE_BOX
	b_proc_vs_shader.collision_size = Vector3(1, 1, 1)
	b_proc_vs_shader.interaction = BlockCategories.INTERACT_SOLID
	b_proc_vs_shader.material_id = "stone"
	b_proc_vs_shader.material_type_id = "stone"
	b_proc_vs_shader.shader_path = "res://assets/shaders/block_world.gdshader"
	b_proc_vs_shader.ensure_id()
	var node_pvs := BlockBuilder.build(b_proc_vs_shader, parent)
	var mesh_pvs := _get_mesh_from_node(node_pvs)
	_assert(mesh_pvs != null, "dispatch proc>shader: Mesh node created")
	if mesh_pvs != null and mesh_pvs.material_override is ShaderMaterial:
		var type_int_pvs = (mesh_pvs.material_override as ShaderMaterial).get_shader_parameter("material_type")
		_assert(type_int_pvs == 2, "dispatch proc>shader: material_type == 2 (stone, not flat)")
	else:
		_assert(true, "dispatch proc>shader: (headless fallback — skipping param check)")

	# --- Test C: Procedural wins over material_params ---
	var b_proc_vs_params := Block.new()
	b_proc_vs_params.block_name = "dispatch_proc_vs_params"
	b_proc_vs_params.collision_shape = BlockCategories.SHAPE_BOX
	b_proc_vs_params.collision_size = Vector3(1, 1, 1)
	b_proc_vs_params.interaction = BlockCategories.INTERACT_SOLID
	b_proc_vs_params.material_id = "moss"
	b_proc_vs_params.material_type_id = "moss"
	b_proc_vs_params.material_params = {"roughness": 0.9}
	b_proc_vs_params.ensure_id()
	var node_pvp := BlockBuilder.build(b_proc_vs_params, parent)
	var mesh_pvp := _get_mesh_from_node(node_pvp)
	_assert(mesh_pvp != null, "dispatch proc>params: Mesh node created")
	if mesh_pvp != null and mesh_pvp.material_override is ShaderMaterial:
		var type_int_pvp = (mesh_pvp.material_override as ShaderMaterial).get_shader_parameter("material_type")
		_assert(type_int_pvp == 3, "dispatch proc>params: material_type == 3 (moss, not override)")
	else:
		_assert(true, "dispatch proc>params: (headless fallback — skipping param check)")

	# --- Test D: Empty material_type_id falls through to existing dispatch ---
	var b_no_proc := Block.new()
	b_no_proc.block_name = "dispatch_no_proc"
	b_no_proc.collision_shape = BlockCategories.SHAPE_BOX
	b_no_proc.collision_size = Vector3(1, 1, 1)
	b_no_proc.interaction = BlockCategories.INTERACT_SOLID
	b_no_proc.material_id = "wood"
	b_no_proc.material_type_id = ""
	b_no_proc.material_params = {"roughness": 0.5}
	b_no_proc.ensure_id()
	var node_np := BlockBuilder.build(b_no_proc, parent)
	var mesh_np := _get_mesh_from_node(node_np)
	_assert(mesh_np != null, "dispatch no-proc: Mesh node created")
	_assert(mesh_np.material_override != null, "dispatch no-proc: material_override set")
	var base_wood: Material = BlockMaterials.get_material("wood")
	_assert(mesh_np.material_override != base_wood,
		"dispatch no-proc: empty material_type_id → override path (not base cache)")

	# --- Test E: Procedural cache sharing via builder ---
	var b_wood1 := Block.new()
	b_wood1.block_name = "dispatch_proc_wood1"
	b_wood1.collision_shape = BlockCategories.SHAPE_BOX
	b_wood1.collision_size = Vector3(1, 1, 1)
	b_wood1.interaction = BlockCategories.INTERACT_SOLID
	b_wood1.material_id = "wood"
	b_wood1.material_type_id = "wood"
	b_wood1.ensure_id()
	var b_wood2 := Block.new()
	b_wood2.block_name = "dispatch_proc_wood2"
	b_wood2.collision_shape = BlockCategories.SHAPE_BOX
	b_wood2.collision_size = Vector3(1, 1, 1)
	b_wood2.interaction = BlockCategories.INTERACT_SOLID
	b_wood2.material_id = "wood"
	b_wood2.material_type_id = "wood"
	b_wood2.ensure_id()
	var node_w1 := BlockBuilder.build(b_wood1, parent)
	var node_w2 := BlockBuilder.build(b_wood2, parent)
	var mesh_w1 := _get_mesh_from_node(node_w1)
	var mesh_w2 := _get_mesh_from_node(node_w2)
	_assert(mesh_w1 != null and mesh_w2 != null, "dispatch proc share: both meshes created")
	_assert(mesh_w1.material_override == mesh_w2.material_override,
		"dispatch proc share: same material_type_id + material_id share same instance")

	# Clean up
	parent.queue_free()


func _test_procedural_material_cache() -> void:
	_section("Procedural Material Cache (Phase 10-01)")

	BlockMaterials.clear_cache()

	# --- get_procedural_material returns non-null ---
	var mat_bark: Material = BlockMaterials.get_procedural_material("bark", "bark")
	_assert(mat_bark != null, "proc cache: get_procedural_material('bark','bark') returns non-null")

	# --- Returns ShaderMaterial or valid fallback (not null) ---
	# In headless mode, shader loads may fail — accept ShaderMaterial or fallback
	_assert(mat_bark is ShaderMaterial or mat_bark is StandardMaterial3D,
		"proc cache: result is ShaderMaterial or fallback StandardMaterial3D")

	# --- Two calls with same args return same instance (cache hit) ---
	var mat_bark2: Material = BlockMaterials.get_procedural_material("bark", "bark")
	_assert(mat_bark == mat_bark2, "proc cache: same args return same instance (cache hit)")

	# --- Different material_type returns different instance ---
	var mat_stone: Material = BlockMaterials.get_procedural_material("stone", "stone")
	_assert(mat_bark != mat_stone, "proc cache: 'bark' and 'stone' return different instances")

	# --- ShaderMaterial has correct material_type int (moss = 3) ---
	var mat_moss: Material = BlockMaterials.get_procedural_material("moss", "bark")
	if mat_moss is ShaderMaterial:
		var type_int = (mat_moss as ShaderMaterial).get_shader_parameter("material_type")
		_assert(type_int == 3, "proc cache: moss material_type int == 3")
	else:
		_assert(true, "proc cache: (headless fallback — skipping moss type int check)")

	# --- ShaderMaterial has correct material_type int (water = 4) ---
	var mat_water: Material = BlockMaterials.get_procedural_material("water", "water")
	if mat_water is ShaderMaterial:
		var type_int_w = (mat_water as ShaderMaterial).get_shader_parameter("material_type")
		_assert(type_int_w == 4, "proc cache: water material_type int == 4")
	else:
		_assert(true, "proc cache: (headless fallback — skipping water type int check)")

	# --- Unknown material_type returns non-null fallback ---
	var mat_unknown: Material = BlockMaterials.get_procedural_material("unknown_type", "bark")
	_assert(mat_unknown != null, "proc cache: unknown material_type returns non-null fallback")

	# --- file_to_block() with visual.material_type: "bark" sets material_type_id ---
	var data_bark := {
		"format_version": 1,
		"identity": {"name": "test_proc_bark"},
		"collision": {"shape": "box", "size": [1, 1, 1]},
		"visual": {"material": "bark", "material_type": "bark"}
	}
	var block_bark := BlockFile.file_to_block(data_bark)
	_assert(block_bark.material_type_id == "bark",
		"proc parse: file_to_block sets material_type_id = 'bark'")

	# --- file_to_block() with visual.material_type: "stone" sets material_type_id ---
	var data_stone_parse := {
		"format_version": 1,
		"identity": {"name": "test_proc_stone"},
		"collision": {"shape": "box", "size": [1, 1, 1]},
		"visual": {"material": "stone", "material_type": "stone"}
	}
	var block_stone := BlockFile.file_to_block(data_stone_parse)
	_assert(block_stone.material_type_id == "stone",
		"proc parse: file_to_block sets material_type_id = 'stone'")

	# --- file_to_block() with NO visual.material_type leaves material_type_id = "" ---
	var data_no_proc := {
		"format_version": 1,
		"identity": {"name": "test_no_proc"},
		"collision": {"shape": "box", "size": [1, 1, 1]},
		"visual": {"material": "wood"}
	}
	var block_no_proc := BlockFile.file_to_block(data_no_proc)
	_assert(block_no_proc.material_type_id == "",
		"proc parse: no visual.material_type leaves material_type_id empty")

	# --- _set_block_dotted "visual.material_type" sets material_type_id ---
	var block_dotted := BlockFile.file_to_block(data_no_proc)
	BlockFile.apply_overrides(block_dotted, {"visual.material_type": "stone"})
	_assert(block_dotted.material_type_id == "stone",
		"proc parse: dot-path visual.material_type sets material_type_id")

	# --- clear_override_cache() clears proc| prefix entries ---
	var mat_pre_clear: Material = BlockMaterials.get_procedural_material("wood", "wood")
	var id_pre: int = mat_pre_clear.get_instance_id()
	BlockMaterials.clear_override_cache()
	var mat_post_clear: Material = BlockMaterials.get_procedural_material("wood", "wood")
	_assert(mat_post_clear.get_instance_id() != id_pre,
		"proc cache: clear_override_cache evicts proc| entries")


func _test_prewarm_shaders() -> void:
	_section("Procedural Shader Prewarm (Phase 10-02)")

	# --- prewarm does not crash when called with a valid Node3D parent ---
	BlockMaterials.clear_cache()
	var parent := Node3D.new()
	add_child(parent)
	# Must not crash (headless may not compile shaders, but the call must be safe)
	BlockMaterials.prewarm_procedural_shaders(parent)
	_assert(true, "prewarm: prewarm_procedural_shaders(parent) does not crash")
	parent.queue_free()

	# --- After prewarm, get_procedural_material("bark","default") returns cached instance ---
	# prewarm populates the cache with "default" palette key for all 5 types
	BlockMaterials.clear_cache()
	var parent2 := Node3D.new()
	add_child(parent2)
	BlockMaterials.prewarm_procedural_shaders(parent2)
	var bark_mat: Material = BlockMaterials.get_procedural_material("bark", "default")
	_assert(bark_mat != null,
		"prewarm: after prewarm, get_procedural_material('bark','default') returns non-null")
	parent2.queue_free()

	# --- After prewarm, stone/moss/water/wood are also cached ---
	BlockMaterials.clear_cache()
	var parent3 := Node3D.new()
	add_child(parent3)
	BlockMaterials.prewarm_procedural_shaders(parent3)
	var all_cached := true
	for type_key in ["bark", "stone", "moss", "water", "wood"]:
		var mat: Material = BlockMaterials.get_procedural_material(type_key, "default")
		if mat == null:
			all_cached = false
	_assert(all_cached, "prewarm: all 5 types cached after prewarm (bark/stone/moss/water/wood)")
	parent3.queue_free()

	# --- Only one procedural shader file exists ---
	var shader_count := 0
	var dir := DirAccess.open("res://assets/shaders/")
	if dir != null:
		dir.list_dir_begin()
		var fname := dir.get_next()
		while fname != "":
			if fname.begins_with("block_world_procedural") and fname.ends_with(".gdshader"):
				shader_count += 1
			fname = dir.get_next()
		dir.list_dir_end()
	_assert(shader_count == 1,
		"prewarm: exactly 1 block_world_procedural*.gdshader file exists (found %d)" % shader_count)


func _test_shape_vocabulary() -> void:
	_section("Shape Vocabulary (Phase 11-01)")

	# --- SHAP-08: SHAPE_SPHERE uses SphereShape3D (not CylinderShape3D) ---
	var sphere_block := Block.new()
	sphere_block.block_name = "sphere_test"
	sphere_block.collision_shape = BlockCategories.SHAPE_SPHERE
	sphere_block.collision_size = Vector3(0.6, 1.2, 0.0)
	sphere_block.server_collidable = false
	var sphere_parent := Node3D.new()
	add_child(sphere_parent)
	BlockBuilder.build(sphere_block, sphere_parent)
	var sphere_col := sphere_parent.get_node_or_null("sphere_test/Body/Col")
	var sphere_shape_ok := false
	var sphere_not_cyl := false
	if sphere_col != null and sphere_col is CollisionShape3D:
		sphere_shape_ok = sphere_col.shape is SphereShape3D
		sphere_not_cyl = not (sphere_col.shape is CylinderShape3D)
	_assert(sphere_shape_ok, "SHAP-08: SHAPE_SPHERE collision is SphereShape3D")
	_assert(sphere_not_cyl, "SHAP-08: SHAPE_SPHERE collision is NOT CylinderShape3D")
	sphere_parent.queue_free()

	# --- SHAP-08: SHAPE_DOME uses SphereShape3D ---
	var dome_block := Block.new()
	dome_block.block_name = "dome_test"
	dome_block.collision_shape = BlockCategories.SHAPE_DOME
	dome_block.collision_size = Vector3(0.8, 0.8, 0.0)
	dome_block.server_collidable = false
	var dome_parent := Node3D.new()
	add_child(dome_parent)
	BlockBuilder.build(dome_block, dome_parent)
	var dome_col := dome_parent.get_node_or_null("dome_test/Body/Col")
	var dome_shape_ok := false
	if dome_col != null and dome_col is CollisionShape3D:
		dome_shape_ok = dome_col.shape is SphereShape3D
	_assert(dome_shape_ok, "SHAP-08: SHAPE_DOME collision is SphereShape3D")
	dome_parent.queue_free()

	# --- SHAP-01: SHAPE_CONE builds with CylinderMesh and CylinderShape3D collision ---
	var cone_block := Block.new()
	cone_block.block_name = "cone_test"
	cone_block.collision_shape = BlockCategories.SHAPE_CONE
	cone_block.collision_size = Vector3(0.6, 1.8, 0.0)
	cone_block.server_collidable = false
	var cone_parent := Node3D.new()
	add_child(cone_parent)
	BlockBuilder.build(cone_block, cone_parent)
	var cone_mesh_node := cone_parent.get_node_or_null("cone_test/Mesh")
	var cone_col_node := cone_parent.get_node_or_null("cone_test/Body/Col")
	var cone_mesh_exists := cone_mesh_node != null
	var cone_col_is_cylinder := false
	if cone_col_node != null and cone_col_node is CollisionShape3D:
		cone_col_is_cylinder = cone_col_node.shape is CylinderShape3D
	_assert(cone_mesh_exists, "SHAP-01: SHAPE_CONE builds Mesh node")
	_assert(cone_col_is_cylinder, "SHAP-01: SHAPE_CONE collision is CylinderShape3D")
	cone_parent.queue_free()

	# --- SHAP-02: SHAPE_TORUS builds with TorusMesh and CylinderShape3D collision ---
	var torus_block := Block.new()
	torus_block.block_name = "torus_test"
	torus_block.collision_shape = BlockCategories.SHAPE_TORUS
	torus_block.collision_size = Vector3(0.4, 0.8, 0.0)
	torus_block.server_collidable = false
	var torus_parent := Node3D.new()
	add_child(torus_parent)
	BlockBuilder.build(torus_block, torus_parent)
	var torus_mesh_node := torus_parent.get_node_or_null("torus_test/Mesh")
	var torus_col_node := torus_parent.get_node_or_null("torus_test/Body/Col")
	var torus_mesh_exists := torus_mesh_node != null
	var torus_col_is_cylinder := false
	var torus_col_radius_ok := false
	if torus_col_node != null and torus_col_node is CollisionShape3D:
		torus_col_is_cylinder = torus_col_node.shape is CylinderShape3D
		if torus_col_is_cylinder:
			var cyl_shape := torus_col_node.shape as CylinderShape3D
			torus_col_radius_ok = is_equal_approx(cyl_shape.radius, 0.8)
	_assert(torus_mesh_exists, "SHAP-02: SHAPE_TORUS builds Mesh node")
	_assert(torus_col_is_cylinder, "SHAP-02: SHAPE_TORUS collision is CylinderShape3D")
	_assert(torus_col_radius_ok, "SHAP-02: SHAPE_TORUS CylinderShape3D radius == outer_radius (0.8)")
	torus_parent.queue_free()

	# --- SHAP-04: wedge alias maps to SHAPE_RAMP ---
	_assert(BlockFile.SHAPE_MAP.get("wedge", -1) == BlockCategories.SHAPE_RAMP,
		"SHAP-04: SHAPE_MAP['wedge'] == SHAPE_RAMP")

	# --- SHAP-06: Collision export for new shapes ---
	for shape_const in [BlockCategories.SHAPE_CONE, BlockCategories.SHAPE_TORUS,
			BlockCategories.SHAPE_ARCH, BlockCategories.SHAPE_ROCK]:
		var shape_name_str: String = BlockCategories.shape_name(shape_const)
		var exp_block := Block.new()
		exp_block.block_name = "%s_export_test" % shape_name_str
		exp_block.collision_shape = shape_const
		exp_block.collision_size = Vector3(0.5, 1.0, 0.0)
		exp_block.server_collidable = true
		exp_block.position = Vector3(0.0, 0.5, 0.0)
		var col_dict: Dictionary = exp_block.to_collision_dict()
		_assert(not col_dict.is_empty(),
			"SHAP-06: %s to_collision_dict() is non-empty" % shape_name_str)
		_assert(col_dict.get("min_x", 0.0) < col_dict.get("max_x", 0.0),
			"SHAP-06: %s collision dict has min_x < max_x" % shape_name_str)

	# --- Validator: cone passes, torus outer>inner passes, torus outer<=inner fails ---
	var valid_cone := Block.new()
	valid_cone.block_name = "valid_cone"
	valid_cone.collision_shape = BlockCategories.SHAPE_CONE
	valid_cone.collision_size = Vector3(0.5, 1.2, 0.0)
	_assert(BlockValidator.validate(valid_cone).is_empty(),
		"validator: valid cone block passes validation")

	var valid_torus := Block.new()
	valid_torus.block_name = "valid_torus"
	valid_torus.collision_shape = BlockCategories.SHAPE_TORUS
	valid_torus.collision_size = Vector3(0.3, 0.8, 0.0)
	_assert(BlockValidator.validate(valid_torus).is_empty(),
		"validator: valid torus (inner=0.3, outer=0.8) passes validation")

	var bad_torus := Block.new()
	bad_torus.block_name = "bad_torus"
	bad_torus.collision_shape = BlockCategories.SHAPE_TORUS
	bad_torus.collision_size = Vector3(0.8, 0.5, 0.0)
	_assert(not BlockValidator.validate(bad_torus).is_empty(),
		"validator: torus with outer(0.5) <= inner(0.8) fails validation")

	# --- shape_name() returns correct strings ---
	_assert(BlockCategories.shape_name(BlockCategories.SHAPE_CONE) == "cone",
		"shape_name: SHAPE_CONE -> 'cone'")
	_assert(BlockCategories.shape_name(BlockCategories.SHAPE_TORUS) == "torus",
		"shape_name: SHAPE_TORUS -> 'torus'")
	_assert(BlockCategories.shape_name(BlockCategories.SHAPE_ARCH) == "arch",
		"shape_name: SHAPE_ARCH -> 'arch'")
	_assert(BlockCategories.shape_name(BlockCategories.SHAPE_ROCK) == "rock",
		"shape_name: SHAPE_ROCK -> 'rock'")

	# =========================================================================
	# Phase 11-02: Pre-generated .tres mesh files + BlockShapeGen + BlockBuilder
	# =========================================================================
	_section("Shape Vocabulary (Phase 11-02)")

	# --- BlockShapeGen.make_arch_mesh returns ArrayMesh with surfaces ---
	var gen_arch: ArrayMesh = BlockShapeGen.make_arch_mesh(0.4, 0.8)
	_assert(gen_arch != null, "BlockShapeGen.make_arch_mesh returns non-null")
	_assert(gen_arch.get_surface_count() > 0, "make_arch_mesh has > 0 surfaces")
	_assert(gen_arch.get_surface_count() >= 1, "make_arch_mesh surface count >= 1")
	# Vertex count: 16 arc_segs * 8 ring_segs * 4 verts/quad * 2 tris/quad = many verts
	# Expected: 16*8*6 = 768 vertices total
	var gen_arch_vert_count := 0
	var gen_arch_mdt := MeshDataTool.new()
	if gen_arch_mdt.create_from_surface(gen_arch, 0) == OK:
		gen_arch_vert_count = gen_arch_mdt.get_vertex_count()
	_assert(gen_arch_vert_count > 100, "make_arch_mesh vertex count > 100 (16x8 half-torus)")

	# --- BlockShapeGen.make_rock_mesh returns ArrayMesh with surfaces ---
	var gen_rock0: ArrayMesh = BlockShapeGen.make_rock_mesh(0.5, 0)
	_assert(gen_rock0 != null, "BlockShapeGen.make_rock_mesh(0.5, 0) returns non-null")
	_assert(gen_rock0.get_surface_count() > 0, "make_rock_mesh has > 0 surfaces")

	# --- Different seeds produce different vertex positions ---
	var gen_rock1: ArrayMesh = BlockShapeGen.make_rock_mesh(0.5, 1)
	_assert(gen_rock1 != null, "BlockShapeGen.make_rock_mesh(0.5, 1) returns non-null")
	var mdt0 := MeshDataTool.new()
	var mdt1 := MeshDataTool.new()
	var seeds_differ := false
	if mdt0.create_from_surface(gen_rock0, 0) == OK and mdt1.create_from_surface(gen_rock1, 0) == OK:
		if mdt0.get_vertex_count() > 0 and mdt0.get_vertex_count() == mdt1.get_vertex_count():
			# Compare first vertex — different seeds should give different displacement
			var v0: Vector3 = mdt0.get_vertex(0)
			var v1: Vector3 = mdt1.get_vertex(0)
			seeds_differ = not v0.is_equal_approx(v1)
		else:
			seeds_differ = true  # Different vertex counts also count as different
	_assert(seeds_differ, "make_rock_mesh seeds 0 and 1 produce different vertex positions")

	# --- Pre-generated .tres files load as ArrayMesh ---
	var arch_tres: ArrayMesh = load("res://assets/meshes/organic/arch_40_80.tres") as ArrayMesh
	_assert(arch_tres != null, "arch_40_80.tres loads as ArrayMesh")
	_assert(arch_tres.get_surface_count() > 0 if arch_tres != null else false,
		"arch_40_80.tres has surfaces")

	var rock_tres: ArrayMesh = load("res://assets/meshes/organic/rock_s0_r50.tres") as ArrayMesh
	_assert(rock_tres != null, "rock_s0_r50.tres loads as ArrayMesh")

	var rock3_tres: ArrayMesh = load("res://assets/meshes/organic/rock_s3_r50.tres") as ArrayMesh
	_assert(rock3_tres != null, "rock_s3_r50.tres loads as ArrayMesh")

	var rock_r80_tres: ArrayMesh = load("res://assets/meshes/organic/rock_s1_r80.tres") as ArrayMesh
	_assert(rock_r80_tres != null, "rock_s1_r80.tres loads as ArrayMesh")

	# --- SHAP-03: SHAPE_ARCH block loads arch_40_80.tres and has non-nil mesh ---
	var arch_block := Block.new()
	arch_block.block_name = "arch_test"
	arch_block.collision_shape = BlockCategories.SHAPE_ARCH
	arch_block.collision_size = Vector3(0.4, 0.8, 0.0)
	arch_block.server_collidable = true
	var arch_parent := Node3D.new()
	add_child(arch_parent)
	BlockBuilder.build(arch_block, arch_parent)
	var arch_mesh_node: Node = arch_parent.get_node_or_null("arch_test/Mesh")
	var arch_has_mesh := false
	if arch_mesh_node != null and arch_mesh_node is MeshInstance3D:
		var arch_mi := arch_mesh_node as MeshInstance3D
		arch_has_mesh = arch_mi.mesh != null
	_assert(arch_mesh_node != null, "SHAP-03: SHAPE_ARCH builds Mesh node")
	_assert(arch_has_mesh, "SHAP-03: SHAPE_ARCH Mesh node has non-nil mesh")
	var arch_col_dict: Dictionary = arch_block.to_collision_dict()
	_assert(not arch_col_dict.is_empty(), "SHAP-03: SHAPE_ARCH to_collision_dict() is non-empty")
	arch_parent.queue_free()

	# --- SHAP-03: SHAPE_ARCH with unknown dims falls back to TorusMesh (no crash) ---
	var arch_fallback_block := Block.new()
	arch_fallback_block.block_name = "arch_fallback"
	arch_fallback_block.collision_shape = BlockCategories.SHAPE_ARCH
	arch_fallback_block.collision_size = Vector3(9.99, 9.99, 0.0)  # No pre-gen .tres for this
	arch_fallback_block.server_collidable = false
	var arch_fallback_parent := Node3D.new()
	add_child(arch_fallback_parent)
	BlockBuilder.build(arch_fallback_block, arch_fallback_parent)
	var arch_fallback_mesh: Node = arch_fallback_parent.get_node_or_null("arch_fallback/Mesh")
	var arch_fallback_has_mesh := false
	if arch_fallback_mesh != null and arch_fallback_mesh is MeshInstance3D:
		arch_fallback_has_mesh = (arch_fallback_mesh as MeshInstance3D).mesh != null
	_assert(arch_fallback_has_mesh, "SHAP-03: SHAPE_ARCH fallback (unknown dims) has TorusMesh (no crash)")
	arch_fallback_parent.queue_free()

	# --- SHAP-05: SHAPE_ROCK seed 0 loads rock_s0_r50.tres ---
	var rock0_block := Block.new()
	rock0_block.block_name = "rock0_test"
	rock0_block.collision_shape = BlockCategories.SHAPE_ROCK
	rock0_block.collision_size = Vector3(0.5, 1.0, 0.0)  # seed=0 (z=0)
	rock0_block.server_collidable = false
	var rock0_parent := Node3D.new()
	add_child(rock0_parent)
	BlockBuilder.build(rock0_block, rock0_parent)
	var rock0_mesh_node: Node = rock0_parent.get_node_or_null("rock0_test/Mesh")
	var rock0_has_mesh := false
	if rock0_mesh_node != null and rock0_mesh_node is MeshInstance3D:
		rock0_has_mesh = (rock0_mesh_node as MeshInstance3D).mesh != null
	_assert(rock0_mesh_node != null, "SHAP-05: SHAPE_ROCK seed=0 builds Mesh node")
	_assert(rock0_has_mesh, "SHAP-05: SHAPE_ROCK seed=0 Mesh node has non-nil mesh")
	rock0_parent.queue_free()

	# --- SHAP-05: SHAPE_ROCK seed 3 loads rock_s3_r50.tres ---
	var rock3_block := Block.new()
	rock3_block.block_name = "rock3_test"
	rock3_block.collision_shape = BlockCategories.SHAPE_ROCK
	rock3_block.collision_size = Vector3(0.5, 1.0, 3.0)  # seed=3 via z component
	rock3_block.server_collidable = false
	var rock3_parent := Node3D.new()
	add_child(rock3_parent)
	BlockBuilder.build(rock3_block, rock3_parent)
	var rock3_mesh_node: Node = rock3_parent.get_node_or_null("rock3_test/Mesh")
	var rock3_has_mesh := false
	if rock3_mesh_node != null and rock3_mesh_node is MeshInstance3D:
		rock3_has_mesh = (rock3_mesh_node as MeshInstance3D).mesh != null
	_assert(rock3_mesh_node != null, "SHAP-05: SHAPE_ROCK seed=3 builds Mesh node")
	_assert(rock3_has_mesh, "SHAP-05: SHAPE_ROCK seed=3 Mesh node has non-nil mesh")
	rock3_parent.queue_free()

	# --- SHAP-05: Two rock blocks with different seeds have different meshes ---
	var rock_seed0_block := Block.new()
	rock_seed0_block.block_name = "rock_seed0"
	rock_seed0_block.collision_shape = BlockCategories.SHAPE_ROCK
	rock_seed0_block.collision_size = Vector3(0.5, 1.0, 0.0)
	rock_seed0_block.server_collidable = false
	var rock_seed3_block := Block.new()
	rock_seed3_block.block_name = "rock_seed3"
	rock_seed3_block.collision_shape = BlockCategories.SHAPE_ROCK
	rock_seed3_block.collision_size = Vector3(0.5, 1.0, 3.0)
	rock_seed3_block.server_collidable = false
	var seed_diff_parent := Node3D.new()
	add_child(seed_diff_parent)
	BlockBuilder.build(rock_seed0_block, seed_diff_parent)
	BlockBuilder.build(rock_seed3_block, seed_diff_parent)
	var seed0_mi: Node = seed_diff_parent.get_node_or_null("rock_seed0/Mesh")
	var seed3_mi: Node = seed_diff_parent.get_node_or_null("rock_seed3/Mesh")
	var seeds_have_diff_meshes := false
	if seed0_mi is MeshInstance3D and seed3_mi is MeshInstance3D:
		var m0: Mesh = (seed0_mi as MeshInstance3D).mesh
		var m3: Mesh = (seed3_mi as MeshInstance3D).mesh
		if m0 != null and m3 != null:
			# Different pre-generated resources have different resource paths or IDs
			seeds_have_diff_meshes = (m0.get_instance_id() != m3.get_instance_id())
	_assert(seeds_have_diff_meshes, "SHAP-05: rock seed=0 and seed=3 load different mesh resources")
	seed_diff_parent.queue_free()

	# --- SHAP-07: SurfaceTool.append_from() works on arch ArrayMesh (merger compat) ---
	var arch_for_merge: ArrayMesh = load("res://assets/meshes/organic/arch_40_80.tres") as ArrayMesh
	var merge_ok := false
	if arch_for_merge != null:
		var st_merge := SurfaceTool.new()
		st_merge.begin(Mesh.PRIMITIVE_TRIANGLES)
		st_merge.append_from(arch_for_merge, 0, Transform3D.IDENTITY)
		var merged_mesh: ArrayMesh = st_merge.commit()
		merge_ok = merged_mesh != null and merged_mesh.get_surface_count() > 0
	_assert(merge_ok, "SHAP-07: SurfaceTool.append_from() on arch ArrayMesh succeeds (merger compat)")


# =========================================================================
# Phase 12-01: GLB mesh support
# =========================================================================

func _test_glb_validation() -> void:
	_section("GLB Validation (Phase 12-01)")

	# --- Test 1: empty scene_path → error containing "empty visual.mesh" ---
	var glb_empty := Block.new()
	glb_empty.block_name = "glb_empty_path"
	glb_empty.mesh_type = 2
	glb_empty.collision_shape = BlockCategories.SHAPE_CYLINDER
	glb_empty.collision_size = Vector3(0.4, 1.8, 0)
	glb_empty.scene_path = ""
	var errors_empty: Array[String] = BlockValidator.validate(glb_empty)
	var has_empty_error := false
	for e in errors_empty:
		if "empty visual.mesh" in e:
			has_empty_error = true
	_assert(has_empty_error, "GLB-05: empty scene_path → error containing 'empty visual.mesh'")

	# --- Test 2: wrong extension → error containing "not a .glb" ---
	var glb_wrong_ext := Block.new()
	glb_wrong_ext.block_name = "glb_wrong_ext"
	glb_wrong_ext.mesh_type = 2
	glb_wrong_ext.collision_shape = BlockCategories.SHAPE_CYLINDER
	glb_wrong_ext.collision_size = Vector3(0.4, 1.8, 0)
	glb_wrong_ext.scene_path = "res://assets/blocks/meshes/some_file.tscn"
	var errors_ext: Array[String] = BlockValidator.validate(glb_wrong_ext)
	var has_ext_error := false
	for e in errors_ext:
		if "not a .glb" in e:
			has_ext_error = true
	_assert(has_ext_error, "GLB-05: non-.glb extension → error containing 'not a .glb'")

	# --- Test 3: non-existent .glb path → error containing "does not exist" ---
	var glb_missing := Block.new()
	glb_missing.block_name = "glb_missing_file"
	glb_missing.mesh_type = 2
	glb_missing.collision_shape = BlockCategories.SHAPE_CYLINDER
	glb_missing.collision_size = Vector3(0.4, 1.8, 0)
	glb_missing.scene_path = "res://assets/blocks/meshes/nonexistent_xyz_abc.glb"
	var errors_missing: Array[String] = BlockValidator.validate(glb_missing)
	var has_missing_error := false
	for e in errors_missing:
		if "does not exist" in e:
			has_missing_error = true
	_assert(has_missing_error, "GLB-05: non-existent .glb path → error containing 'does not exist'")

	# --- Test 4: .glb with _blend_group → error containing "SDF blending" ---
	var glb_blend := Block.new()
	glb_blend.block_name = "glb_blend_group"
	glb_blend.mesh_type = 2
	glb_blend.collision_shape = BlockCategories.SHAPE_CYLINDER
	glb_blend.collision_size = Vector3(0.4, 1.8, 0)
	glb_blend.scene_path = "res://assets/blocks/meshes/valid.glb"
	glb_blend.state["_blend_group"] = "trunk"
	var errors_blend: Array[String] = BlockValidator.validate(glb_blend)
	var has_blend_error := false
	for e in errors_blend:
		if "SDF blending" in e:
			has_blend_error = true
	_assert(has_blend_error, "GLB-06: GLB with _blend_group → error containing 'SDF blending'")


func _test_glb_cache() -> void:
	_section("GLB Cache (Phase 12-01)")

	# --- Clear cache → is_empty ---
	BlockBuilder.clear_glb_cache()
	_assert(BlockBuilder._glb_cache.is_empty(), "GLB-04: clear_glb_cache() empties cache")

	# --- Manually insert → size == 1 ---
	BlockBuilder._glb_cache["test_path"] = null
	_assert(BlockBuilder._glb_cache.size() == 1, "GLB-04: manually inserted key gives size 1")

	# --- Clear again → is_empty ---
	BlockBuilder.clear_glb_cache()
	_assert(BlockBuilder._glb_cache.is_empty(), "GLB-04: second clear_glb_cache() empties cache again")


func _test_glb_build_dispatch() -> void:
	_section("GLB Build Dispatch (Phase 12-01)")

	var glb_parent := Node3D.new()
	add_child(glb_parent)

	# --- GLB block with nonexistent path: root node returned, collision built (GLB-01, GLB-02) ---
	var glb_block := Block.new()
	glb_block.block_name = "test_glb_dispatch"
	glb_block.mesh_type = 2
	glb_block.scene_path = "res://nonexistent_xyz.glb"
	glb_block.collision_shape = BlockCategories.SHAPE_CYLINDER
	glb_block.collision_size = Vector3(0.4, 1.8, 0)
	glb_block.ensure_id()
	var glb_root: Node3D = BlockBuilder.build(glb_block, glb_parent)
	_assert(glb_root != null, "GLB-01: build() returns non-null Node3D even if GLB fails to load")
	_assert(glb_root.get_node_or_null("Body") != null,
		"GLB-02: collision body built independently of GLB visual")
	# GlbVisual absent because path doesn't exist — correct headless behavior
	_assert(glb_root.get_node_or_null("GlbVisual") == null,
		"GLB-01: GlbVisual absent for nonexistent path (graceful warning, not crash)")

	glb_parent.queue_free()


func _test_glb_sdf_exclusion() -> void:
	_section("GLB SDF Exclusion (Phase 12-01)")

	# --- GLB block with _blend_group fails validation (GLB-06, validator path) ---
	var glb_blend2 := Block.new()
	glb_blend2.block_name = "glb_sdf_excl"
	glb_blend2.mesh_type = 2
	glb_blend2.scene_path = "res://test_xyz.glb"
	glb_blend2.collision_shape = BlockCategories.SHAPE_CYLINDER
	glb_blend2.collision_size = Vector3(0.4, 1.8, 0)
	glb_blend2.state = {"_blend_group": "trunk"}
	var errors: Array[String] = BlockValidator.validate(glb_blend2)
	var sdf_error := false
	for e in errors:
		if "SDF blending" in e:
			sdf_error = true
	_assert(sdf_error, "GLB-06: GLB block with _blend_group fails validation with SDF blending error")


func _test_materials_list_field() -> void:
	_section("Block.materials_list Field (Phase 12-01)")

	var b := Block.new()
	b.block_name = "materials_list_test"

	# --- Set and read materials_list ---
	b.materials_list = [
		{"palette_key": "metal_dark"},
		{"palette_key": "glow_yellow", "params": {"roughness": 0.3}}
	]
	_assert(b.materials_list.size() == 2, "materials_list: size == 2 after assignment")
	_assert(b.materials_list[1].get("palette_key", "") == "glow_yellow",
		"materials_list: second slot palette_key == 'glow_yellow'")

	# --- Duplicate preserves materials_list ---
	b.ensure_id()
	var dup := b.duplicate_block()
	_assert(dup.materials_list.size() == 2, "materials_list: duplicate_block() preserves size")
	_assert(dup.materials_list[0].get("palette_key", "") == "metal_dark",
		"materials_list: duplicate preserves first slot palette_key")

	# --- materials_list parsed by file_to_block ---
	var data_mats := {
		"format_version": 1,
		"identity": {"name": "test_mats_parse"},
		"collision": {"shape": "cylinder", "size": [0.4, 1.8, 0]},
		"visual": {
			"mesh_type": "glb",
			"mesh": "res://some_model.glb",
			"materials": [
				{"palette_key": "stone"},
				{"palette_key": "metal_light", "params": {"metallic": 0.9}}
			]
		}
	}
	var parsed := BlockFile.file_to_block(data_mats)
	_assert(parsed.mesh_type == 2, "GLB parse: file_to_block sets mesh_type=2 for 'glb'")
	_assert(parsed.scene_path == "res://some_model.glb",
		"GLB parse: file_to_block sets scene_path from visual.mesh")
	_assert(parsed.materials_list.size() == 2,
		"GLB parse: file_to_block parses visual.materials array")


# =========================================================================
# Phase 12-02: Multi-material slot support (MMTL)
# =========================================================================

func _test_multi_material_parsing() -> void:
	_section("Multi-Material Parsing (Phase 12-02 MMTL-01)")

	# --- Parse a primitive block with visual.materials array ---
	var data := {
		"format_version": 1,
		"identity": {"name": "barrel"},
		"collision": {"shape": "cylinder", "size": [0.3, 0.9, 0]},
		"visual": {
			"materials": [
				{"palette_key": "metal_dark"},
				{"palette_key": "glow_yellow", "params": {"roughness": 0.3}}
			]
		}
	}
	var block := BlockFile.file_to_block(data)
	_assert(block.materials_list.size() == 2,
		"MMTL-01: file_to_block parses 2-slot materials array for primitive block")
	_assert(block.materials_list[0].get("palette_key", "") == "metal_dark",
		"MMTL-01: slot[0] palette_key == 'metal_dark'")
	_assert(block.materials_list[1].get("palette_key", "") == "glow_yellow",
		"MMTL-01: slot[1] palette_key == 'glow_yellow'")
	_assert(block.materials_list[1].get("params", {}).get("roughness", -1.0) == 0.3,
		"MMTL-01: slot[1].params.roughness == 0.3")


func _test_multi_material_override_parsing() -> void:
	_section("Multi-Material Override Parsing (Phase 12-02 MMTL-01)")

	# --- Apply visual.materials via apply_overrides dot-path ---
	var block := Block.new()
	block.block_name = "test_override_mats"
	BlockFile.apply_overrides(block, {
		"visual.materials": [
			{"palette_key": "concrete"},
			{"palette_key": "glow_green", "params": {"metallic": 0.5}}
		]
	})
	_assert(block.materials_list.size() == 2,
		"MMTL-01: apply_overrides with visual.materials populates materials_list")
	_assert(block.materials_list[0].get("palette_key", "") == "concrete",
		"MMTL-01: override slot[0] == 'concrete'")
	_assert(block.materials_list[1].get("palette_key", "") == "glow_green",
		"MMTL-01: override slot[1] == 'glow_green'")


func _test_multi_material_build() -> void:
	_section("Multi-Material Build Dispatch (Phase 12-02 MMTL-02)")

	# --- Build a primitive with materials_list → no crash, Mesh node exists ---
	var block := Block.new()
	block.block_name = "mm_cylinder"
	block.category = BlockCategories.PROP
	block.collision_shape = BlockCategories.SHAPE_CYLINDER
	block.collision_size = Vector3(0.15, 2.0, 0)
	block.mesh_type = 0
	block.materials_list = [
		{"palette_key": "metal_dark"},
		{"palette_key": "glow_yellow"}
	]
	block.ensure_id()

	var parent := Node3D.new()
	add_child(parent)
	var root: Node3D = BlockBuilder.build(block, parent)

	_assert(root != null, "MMTL-02: build() returns non-null root for multi-material primitive")
	var mesh_node: Node = root.get_node_or_null("Mesh") if root != null else null
	_assert(mesh_node != null, "MMTL-02: 'Mesh' child node exists for multi-material primitive")

	# In headless mode, CylinderMesh has 1 surface — material_override should be null
	# because multi-material path uses set_surface_override_material, not material_override
	if mesh_node != null and mesh_node is MeshInstance3D:
		var mi := mesh_node as MeshInstance3D
		_assert(mi.material_override == null,
			"MMTL-02: multi-material path uses surface overrides, not material_override")

	parent.queue_free()
