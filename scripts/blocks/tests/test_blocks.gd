extends Node3D
## Block Library Test Suite
##
## Builds a Car from Block primitives and stress-tests the entire system:
## creation, validation, registry, parent-child links, block-to-block
## communication, builder output, collision export, lifecycle, materials,
## and edge cases.
##
## Run headless:
##   godot --headless --path godot_project --scene-path res://scripts/blocks/tests/test_blocks.tscn

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
	b4.collision_size = Vector3(300, 1, 1)
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
	_assert(mat1.albedo_color == BlockMaterials.PALETTE["wood"], "wood color correct")

	# Different IDs return different instances
	var mat3 := BlockMaterials.get_material("metal_dark")
	_assert(mat3 != mat1, "different material_id returns different instance")

	# Unknown ID returns default with warning
	var mat4 := BlockMaterials.get_material("nonexistent_material_xyz")
	_assert(mat4.albedo_color == BlockMaterials.PALETTE["default"],
		"unknown material returns default color")

	# Color-based material
	var color := Color(0.42, 0.69, 0.13)
	var mat5 := BlockMaterials.get_material_from_color(color)
	var mat6 := BlockMaterials.get_material_from_color(color)
	_assert(mat5 == mat6, "same color returns same cached instance")
	_assert(mat5.albedo_color == color, "color matches request")

	# Transparent material
	var glass := BlockMaterials.get_material("glass")
	_assert(glass.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA,
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
