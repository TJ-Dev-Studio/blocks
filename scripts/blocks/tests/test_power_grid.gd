extends Node3D
## Power Grid Test Suite — 300+ tests
##
## Builds an electrical grid from 28 blocks and stress-tests:
## runtime state, peer connections, message passing, visual state,
## power propagation, cascade failures, path finding, and more.
##
## Run headless:
##   godot --headless --path godot_project --script res://scripts/blocks/tests/run_power_grid_tests.gd

var _pass_count := 0
var _fail_count := 0
var _test_count := 0
var _registry: BlockRegistry
var _grid_blocks: Dictionary = {}  # name -> Block
var _messages_received: Array[Dictionary] = []  # for signal tracking


func _ready() -> void:
	print("")
	print("=" .repeat(60))
	print("  POWER GRID TEST SUITE")
	print("=" .repeat(60))
	print("")

	_registry = BlockRegistry.new()
	_registry.name = "PowerGridTestRegistry"
	add_child(_registry)

	# Connect message signal for tracking
	_registry.message_received.connect(_on_message_received)

	# Run all test groups
	_test_block_state()
	_test_connections_basic()
	_test_message_passing()
	_test_visual_state()
	_test_connection_validation()
	_test_grid_construction()
	_test_grid_registration()
	_test_grid_peer_topology()
	_test_power_propagation()
	_test_state_management()
	_test_visual_power_state()
	_test_path_finding_connections()
	_test_cascade_failure()
	_test_grid_stats()
	_test_isolated_blocks()
	_test_stress()
	_test_export_grid()
	_test_builder_grid()

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


func _section(name: String) -> void:
	print("")
	print("--- %s ---" % name)


func _on_message_received(target_block: Block, msg_type: String,
		data: Dictionary, sender_id: String) -> void:
	_messages_received.append({
		"target": target_block,
		"msg_type": msg_type,
		"data": data,
		"sender_id": sender_id,
	})


# =========================================================================
# Block factory helpers
# =========================================================================

func _make_generator() -> Block:
	var b := Block.new()
	b.block_name = "generator"
	b.category = BlockCategories.STRUCTURE
	b.collision_shape = BlockCategories.SHAPE_BOX
	b.collision_size = Vector3(3.0, 4.0, 3.0)
	b.position = Vector3(0, 2.0, -30)
	b.interaction = BlockCategories.INTERACT_SOLID
	b.material_id = "generator_yellow"
	b.collision_layer = CollisionLayers.WORLD
	b.tags = PackedStringArray(["power_source", "grid"])
	b.cast_shadow = true
	return b


func _make_transformer(bname: String, pos: Vector3) -> Block:
	var b := Block.new()
	b.block_name = bname
	b.category = BlockCategories.STRUCTURE
	b.collision_shape = BlockCategories.SHAPE_BOX
	b.collision_size = Vector3(2.0, 3.0, 2.0)
	b.position = pos
	b.interaction = BlockCategories.INTERACT_SOLID
	b.material_id = "transformer_gray"
	b.collision_layer = CollisionLayers.WORLD
	b.tags = PackedStringArray(["transformer", "grid"])
	b.cast_shadow = true
	return b


func _make_power_line(bname: String, pos: Vector3, rot_y: float = 0.0) -> Block:
	var b := Block.new()
	b.block_name = bname
	b.category = BlockCategories.PROP
	b.collision_shape = BlockCategories.SHAPE_BOX
	b.collision_size = Vector3(0.1, 0.1, 8.0)
	b.position = pos
	b.rotation_y = rot_y
	b.interaction = BlockCategories.INTERACT_SOLID
	b.material_id = "wire_copper"
	b.collision_layer = CollisionLayers.WORLD
	b.server_collidable = false
	b.tags = PackedStringArray(["wire", "grid"])
	return b


func _make_house(bname: String, pos: Vector3, material: String = "house_beige") -> Block:
	var b := Block.new()
	b.block_name = bname
	b.category = BlockCategories.STRUCTURE
	b.collision_shape = BlockCategories.SHAPE_BOX
	b.collision_size = Vector3(4.0, 3.0, 4.0)
	b.position = pos
	b.interaction = BlockCategories.INTERACT_SOLID
	b.material_id = material
	b.collision_layer = CollisionLayers.WORLD
	b.tags = PackedStringArray(["house", "consumer", "grid"])
	b.cast_shadow = true
	return b


func _make_street_light(bname: String, pos: Vector3) -> Block:
	var b := Block.new()
	b.block_name = bname
	b.category = BlockCategories.EFFECT
	b.collision_shape = BlockCategories.SHAPE_CYLINDER
	b.collision_size = Vector3(0.15, 4.0, 0)
	b.position = pos
	b.interaction = BlockCategories.INTERACT_SOLID
	b.material_id = "light_pole"
	b.collision_layer = CollisionLayers.WORLD
	b.tags = PackedStringArray(["light", "consumer", "grid"])
	b.cast_shadow = true
	return b


func _make_control_tower() -> Block:
	var b := Block.new()
	b.block_name = "control_tower"
	b.category = BlockCategories.TRIGGER_CAT
	b.collision_shape = BlockCategories.SHAPE_BOX
	b.collision_size = Vector3(2.0, 5.0, 2.0)
	b.position = Vector3(0, 2.5, -35)
	b.interaction = BlockCategories.INTERACT_TRIGGER
	b.collision_layer = CollisionLayers.TRIGGER
	b.trigger_radius = 10.0
	b.material_id = "blue_metal"
	b.tags = PackedStringArray(["control", "grid"])
	return b


func _make_water_tower() -> Block:
	var b := Block.new()
	b.block_name = "water_tower"
	b.category = BlockCategories.STRUCTURE
	b.collision_shape = BlockCategories.SHAPE_CYLINDER
	b.collision_size = Vector3(2.0, 6.0, 0)
	b.position = Vector3(40, 3.0, 0)
	b.interaction = BlockCategories.INTERACT_SOLID
	b.material_id = "metal_light"
	b.collision_layer = CollisionLayers.WORLD
	b.tags = PackedStringArray(["isolated", "water"])
	b.cast_shadow = true
	return b


func _register_grid(bname: String, block: Block) -> void:
	block.ensure_id()
	var ok := _registry.register(block)
	if not ok:
		push_warning("Failed to register grid block: %s — %s" % [
			bname, ", ".join(_registry.get_last_errors())])
	_grid_blocks[bname] = block


func _build_full_grid() -> void:
	_registry.clear()
	_grid_blocks.clear()

	# Generator (1)
	_register_grid("generator", _make_generator())

	# Transformers (3)
	_register_grid("transformer_north", _make_transformer("transformer_north", Vector3(-15, 1.5, -15)))
	_register_grid("transformer_south", _make_transformer("transformer_south", Vector3(0, 1.5, 0)))
	_register_grid("transformer_east", _make_transformer("transformer_east", Vector3(15, 1.5, -15)))

	# Power lines (8)
	for i in range(8):
		var bname := "power_line_%d" % i
		var pos := Vector3(-12.0 + i * 4.0, 3.0, -22.0 + (i % 3) * 5.0)
		_register_grid(bname, _make_power_line(bname, pos, 0.0 if i % 2 == 0 else PI / 4.0))

	# Houses (6)
	var house_positions := [
		Vector3(-20, 1.5, 10), Vector3(-10, 1.5, 10),
		Vector3(0, 1.5, 15), Vector3(10, 1.5, 10),
		Vector3(20, 1.5, 10), Vector3(15, 1.5, 20),
	]
	var house_mats := ["house_beige", "house_blue", "house_beige", "house_blue", "house_beige", "house_blue"]
	for i in range(6):
		var bname := "house_%d" % i
		_register_grid(bname, _make_house(bname, house_positions[i], house_mats[i]))

	# Street lights (8)
	for i in range(8):
		var bname := "street_light_%d" % i
		var pos := Vector3(-14.0 + i * 4.0, 2.0, 8)
		_register_grid(bname, _make_street_light(bname, pos))

	# Control tower (1)
	_register_grid("control_tower", _make_control_tower())

	# Water tower (1) — ISOLATED
	_register_grid("water_tower", _make_water_tower())

	# --- Wire up connections ---
	var gen: Block = _grid_blocks["generator"]
	var t1: Block = _grid_blocks["transformer_north"]
	var t2: Block = _grid_blocks["transformer_south"]
	var t3: Block = _grid_blocks["transformer_east"]

	# Generator -> transformers
	_registry.connect_blocks(gen.block_id, t1.block_id)
	_registry.connect_blocks(gen.block_id, t2.block_id)
	_registry.connect_blocks(gen.block_id, t3.block_id)

	# Generator -> first 3 power lines
	for i in range(3):
		_registry.connect_blocks(gen.block_id, _grid_blocks["power_line_%d" % i].block_id)

	# Transformer_north -> power lines 3,4,5
	for i in range(3, 6):
		_registry.connect_blocks(t1.block_id, _grid_blocks["power_line_%d" % i].block_id)

	# Transformer_south -> power lines 6,7
	for i in range(6, 8):
		_registry.connect_blocks(t2.block_id, _grid_blocks["power_line_%d" % i].block_id)

	# Transformer_north -> houses 0,1
	_registry.connect_blocks(t1.block_id, _grid_blocks["house_0"].block_id)
	_registry.connect_blocks(t1.block_id, _grid_blocks["house_1"].block_id)

	# Transformer_south -> houses 2,3
	_registry.connect_blocks(t2.block_id, _grid_blocks["house_2"].block_id)
	_registry.connect_blocks(t2.block_id, _grid_blocks["house_3"].block_id)

	# Transformer_east -> houses 4,5
	_registry.connect_blocks(t3.block_id, _grid_blocks["house_4"].block_id)
	_registry.connect_blocks(t3.block_id, _grid_blocks["house_5"].block_id)

	# Houses -> street lights
	_registry.connect_blocks(_grid_blocks["house_0"].block_id, _grid_blocks["street_light_0"].block_id)
	_registry.connect_blocks(_grid_blocks["house_1"].block_id, _grid_blocks["street_light_1"].block_id)
	_registry.connect_blocks(_grid_blocks["house_1"].block_id, _grid_blocks["street_light_2"].block_id)
	_registry.connect_blocks(_grid_blocks["house_2"].block_id, _grid_blocks["street_light_3"].block_id)
	_registry.connect_blocks(_grid_blocks["house_3"].block_id, _grid_blocks["street_light_4"].block_id)
	_registry.connect_blocks(_grid_blocks["house_4"].block_id, _grid_blocks["street_light_5"].block_id)
	_registry.connect_blocks(_grid_blocks["house_4"].block_id, _grid_blocks["street_light_6"].block_id)
	_registry.connect_blocks(_grid_blocks["house_5"].block_id, _grid_blocks["street_light_7"].block_id)

	# Control tower -> generator
	_registry.connect_blocks(_grid_blocks["control_tower"].block_id, gen.block_id)

	# Water tower is NOT connected to anything


# =========================================================================
# Test Group 1: Block State
# =========================================================================

func _test_block_state() -> void:
	_section("Block State")

	var b := Block.new()
	b.block_name = "state_test"
	b.collision_size = Vector3(1, 1, 1)
	_assert(b.state.is_empty(), "state starts empty")

	# Set various types
	b.state["powered"] = true
	_assert(b.state["powered"] == true, "state bool works")

	b.state["voltage"] = 240
	_assert(b.state["voltage"] == 240, "state int works")

	b.state["temperature"] = 72.5
	_assert(is_equal_approx(b.state["temperature"], 72.5), "state float works")

	b.state["label"] = "main_gen"
	_assert(b.state["label"] == "main_gen", "state String works")

	b.state["outputs"] = [1, 2, 3]
	_assert(b.state["outputs"].size() == 3, "state Array works")

	b.state["meta"] = {"key": "val"}
	_assert(b.state["meta"]["key"] == "val", "state nested Dictionary works")

	_assert(b.state.size() == 6, "state has 6 keys")

	# State persists across reads
	_assert(b.state["powered"] == true, "state persists across reads")

	# Clear state
	b.state.clear()
	_assert(b.state.is_empty(), "state clearable")

	# State reset on duplicate
	b.state["powered"] = true
	b.ensure_id()
	var clone := b.duplicate_block()
	_assert(clone.state.is_empty(), "duplicate_block clears state")

	# State doesn't leak between instances
	var a := Block.new()
	a.block_name = "a"
	a.collision_size = Vector3(1, 1, 1)
	a.state["x"] = 1
	var b2 := Block.new()
	b2.block_name = "b"
	b2.collision_size = Vector3(1, 1, 1)
	_assert(not b2.state.has("x"), "state doesn't leak between instances")

	# Overwrite state value
	b.state["powered"] = false
	_assert(b.state["powered"] == false, "state value overwritable")

	# Erase specific key
	b.state["temp"] = 100
	b.state.erase("temp")
	_assert(not b.state.has("temp"), "state key erasable")


# =========================================================================
# Test Group 2: Connections Basic
# =========================================================================

func _test_connections_basic() -> void:
	_section("Connections Basic")

	var b := Block.new()
	b.block_name = "conn_test"
	b.collision_size = Vector3(1, 1, 1)
	b.ensure_id()

	_assert(b.connections.is_empty(), "connections starts empty")
	_assert(not b.has_peer_connections(), "has_peer_connections false when empty")
	_assert(not b.is_connected_to("fake_id"), "is_connected_to false for non-existent")

	# Add connection
	b.add_connection("peer_1")
	_assert(b.connections.size() == 1, "add_connection adds peer")
	_assert(b.has_peer_connections(), "has_peer_connections true after add")
	_assert(b.is_connected_to("peer_1"), "is_connected_to true for added peer")

	# Idempotent
	b.add_connection("peer_1")
	_assert(b.connections.size() == 1, "add_connection is idempotent")

	# Multiple connections
	b.add_connection("peer_2")
	b.add_connection("peer_3")
	_assert(b.connections.size() == 3, "multiple connections added")

	# Remove connection
	b.remove_connection("peer_2")
	_assert(b.connections.size() == 2, "remove_connection removes peer")
	_assert(not b.is_connected_to("peer_2"), "removed peer not found")
	_assert(b.is_connected_to("peer_1"), "other peers remain")

	# Remove non-existent is safe
	b.remove_connection("not_there")
	_assert(b.connections.size() == 2, "remove non-existent is safe")

	# Connections reset on duplicate
	var clone := b.duplicate_block()
	_assert(clone.connections.is_empty(), "duplicate clears connections")

	# Registry connect_blocks (bidirectional)
	_registry.clear()
	var x := Block.new()
	x.block_name = "block_x"
	x.collision_size = Vector3(1, 1, 1)
	var y := Block.new()
	y.block_name = "block_y"
	y.collision_size = Vector3(1, 1, 1)
	_registry.register(x)
	_registry.register(y)

	var ok := _registry.connect_blocks(x.block_id, y.block_id)
	_assert(ok, "connect_blocks returns true")
	_assert(x.is_connected_to(y.block_id), "x connects to y")
	_assert(y.is_connected_to(x.block_id), "y connects to x (bidirectional)")

	# get_connected_blocks
	var x_peers := _registry.get_connected_blocks(x.block_id)
	_assert(x_peers.size() == 1, "get_connected_blocks returns 1 peer")
	_assert(x_peers[0].block_id == y.block_id, "peer is y")

	# get_connections
	var x_conns := _registry.get_connections(x.block_id)
	_assert(x_conns.size() == 1, "get_connections returns 1")

	# disconnect_blocks
	_registry.disconnect_blocks(x.block_id, y.block_id)
	_assert(not x.is_connected_to(y.block_id), "x disconnected from y")
	_assert(not y.is_connected_to(x.block_id), "y disconnected from x")

	# connect to non-existent returns false
	var bad := _registry.connect_blocks(x.block_id, "nonexistent")
	_assert(not bad, "connect_blocks to nonexistent returns false")

	# Unregister cleans up connections
	_registry.connect_blocks(x.block_id, y.block_id)
	_registry.unregister(x.block_id)
	_assert(not y.is_connected_to(x.block_id), "unregister cleans up peer connections")

	_registry.clear()


# =========================================================================
# Test Group 3: Message Passing
# =========================================================================

func _test_message_passing() -> void:
	_section("Message Passing")

	_registry.clear()
	_messages_received.clear()

	var a := Block.new()
	a.block_name = "msg_a"
	a.collision_size = Vector3(1, 1, 1)
	var b := Block.new()
	b.block_name = "msg_b"
	b.collision_size = Vector3(1, 1, 1)
	var c := Block.new()
	c.block_name = "msg_c"
	c.collision_size = Vector3(1, 1, 1)
	_registry.register(a)
	_registry.register(b)
	_registry.register(c)

	# Send message
	_messages_received.clear()
	var ok := _registry.send_message(b.block_id, "power_on", {"voltage": 240}, a.block_id)
	_assert(ok, "send_message returns true")
	_assert(_messages_received.size() == 1, "message_received signal emitted once")
	_assert(_messages_received[0]["target"] == b, "target is block b")
	_assert(_messages_received[0]["msg_type"] == "power_on", "msg_type is power_on")
	_assert(_messages_received[0]["data"]["voltage"] == 240, "data carries voltage")
	_assert(_messages_received[0]["sender_id"] == a.block_id, "sender_id is a")

	# Send to non-existent
	var bad := _registry.send_message("nonexistent", "test", {})
	_assert(not bad, "send_message to nonexistent returns false")

	# Broadcast to connections
	_registry.connect_blocks(a.block_id, b.block_id)
	_registry.connect_blocks(a.block_id, c.block_id)
	_messages_received.clear()
	var count := _registry.broadcast_to_connections(a.block_id, "pulse", {"val": 1})
	_assert(count == 2, "broadcast_to_connections sends to 2 peers")
	_assert(_messages_received.size() == 2, "2 messages received from broadcast")

	# Broadcast from non-existent
	var bad_count := _registry.broadcast_to_connections("nonexistent", "test")
	_assert(bad_count == 0, "broadcast from nonexistent returns 0")

	# Propagate through connections (BFS)
	# a -- b -- c (linear chain)
	_registry.disconnect_blocks(a.block_id, c.block_id)
	_registry.connect_blocks(b.block_id, c.block_id)
	# Now: a--b--c
	_messages_received.clear()
	var reached := _registry.propagate_through_connections(a.block_id, "flood", {"depth": 0})
	_assert(reached.size() == 3, "propagation reaches all 3 blocks")
	_assert(_messages_received.size() == 3, "3 messages emitted during propagation")

	# Propagation visits each block only once (no cycles)
	# Create a cycle: a--b--c--a
	_registry.connect_blocks(c.block_id, a.block_id)
	_messages_received.clear()
	var reached2 := _registry.propagate_through_connections(a.block_id, "cycle_test")
	_assert(reached2.size() == 3, "propagation with cycle still visits 3 (no dupes)")
	_assert(_messages_received.size() == 3, "3 messages even with cycle")

	# Propagate from isolated block
	var iso := Block.new()
	iso.block_name = "isolated"
	iso.collision_size = Vector3(1, 1, 1)
	_registry.register(iso)
	_messages_received.clear()
	var iso_reached := _registry.propagate_through_connections(iso.block_id, "lonely")
	_assert(iso_reached.size() == 1, "isolated block propagation reaches only itself")

	# Propagate from non-existent
	var none_reached := _registry.propagate_through_connections("nonexistent", "test")
	_assert(none_reached.is_empty(), "propagate from nonexistent returns empty")

	_registry.clear()


# =========================================================================
# Test Group 4: Visual State
# =========================================================================

func _test_visual_state() -> void:
	_section("Visual State")

	# Build a block with a Mesh child
	var b := Block.new()
	b.block_name = "vis_test"
	b.collision_shape = BlockCategories.SHAPE_BOX
	b.collision_size = Vector3(1, 1, 1)
	b.material_id = "metal_dark"
	b.collision_layer = CollisionLayers.WORLD
	b.ensure_id()
	var node := BlockBuilder.build(b, self)

	# set_emission
	var ok := BlockVisuals.set_emission(b, Color(0, 1, 0), 2.0)
	_assert(ok, "set_emission returns true on built block")

	var mesh := node.get_node("Mesh") as MeshInstance3D
	var mat := mesh.material_override as StandardMaterial3D
	_assert(mat.emission_enabled, "emission is enabled")
	_assert(mat.emission == Color(0, 1, 0), "emission color is green")
	_assert(is_equal_approx(mat.emission_energy_multiplier, 2.0), "emission energy is 2.0")

	# clear_emission
	BlockVisuals.clear_emission(b)
	mat = mesh.material_override as StandardMaterial3D
	_assert(not mat.emission_enabled, "emission disabled after clear")

	# set_powered(true) — green
	BlockVisuals.set_powered(b, true)
	mat = mesh.material_override as StandardMaterial3D
	_assert(mat.emission_enabled, "powered=true enables emission")
	_assert(mat.emission.g > mat.emission.r, "powered=true is green-dominant")

	# set_powered(false) — red
	BlockVisuals.set_powered(b, false)
	mat = mesh.material_override as StandardMaterial3D
	_assert(mat.emission_enabled, "powered=false still has emission")
	_assert(mat.emission.r > mat.emission.g, "powered=false is red-dominant")

	# set_color
	var col_ok := BlockVisuals.set_color(b, Color(0.5, 0.0, 0.5))
	_assert(col_ok, "set_color returns true")
	mat = mesh.material_override as StandardMaterial3D
	_assert(mat.albedo_color == Color(0.5, 0.0, 0.5), "albedo color changed")

	# set_warning
	BlockVisuals.set_warning(b)
	mat = mesh.material_override as StandardMaterial3D
	_assert(mat.emission.r > 0.5 and mat.emission.g > 0.3, "warning is orange-ish")

	# Returns false on block with no node
	var no_node := Block.new()
	no_node.block_name = "no_node"
	no_node.collision_size = Vector3(1, 1, 1)
	no_node.ensure_id()
	_assert(not BlockVisuals.set_emission(no_node, Color.RED), "set_emission false on no-node block")
	_assert(not BlockVisuals.set_color(no_node, Color.RED), "set_color false on no-node block")
	_assert(not BlockVisuals.set_powered(no_node, true), "set_powered false on no-node block")

	# Returns false on SHAPE_NONE block (no Mesh child)
	var no_mesh := Block.new()
	no_mesh.block_name = "no_mesh"
	no_mesh.collision_shape = BlockCategories.SHAPE_NONE
	no_mesh.collision_size = Vector3.ZERO
	no_mesh.ensure_id()
	var nm_node := BlockBuilder.build(no_mesh, self)
	_assert(not BlockVisuals.set_emission(no_mesh, Color.RED), "set_emission false on SHAPE_NONE")

	# Material isolation — changing one block doesn't affect another
	var b2 := Block.new()
	b2.block_name = "vis_test_2"
	b2.collision_shape = BlockCategories.SHAPE_BOX
	b2.collision_size = Vector3(1, 1, 1)
	b2.material_id = "metal_dark"
	b2.collision_layer = CollisionLayers.WORLD
	b2.ensure_id()
	var node2 := BlockBuilder.build(b2, self)

	BlockVisuals.set_emission(b, Color.GREEN, 3.0)
	var mat2 := (node2.get_node("Mesh") as MeshInstance3D).material_override as StandardMaterial3D
	_assert(not mat2.emission_enabled, "changing b emission doesn't affect b2")

	# Clean up
	node.queue_free()
	nm_node.queue_free()
	node2.queue_free()


# =========================================================================
# Test Group 5: Connection Validation
# =========================================================================

func _test_connection_validation() -> void:
	_section("Connection Validation")

	# Self-connection
	var b1 := Block.new()
	b1.block_name = "self_conn"
	b1.block_id = "self_001"
	b1.collision_size = Vector3(1, 1, 1)
	b1.connections = PackedStringArray(["self_001"])
	var e1 := BlockValidator.validate(b1)
	_assert(not e1.is_empty(), "self-connection fails validation")
	var has_self_err := false
	for e in e1:
		if e.contains("itself"):
			has_self_err = true
	_assert(has_self_err, "error mentions connecting to itself")

	# Empty connection ID
	var b2 := Block.new()
	b2.block_name = "empty_conn"
	b2.collision_size = Vector3(1, 1, 1)
	b2.connections = PackedStringArray([""])
	var e2 := BlockValidator.validate(b2)
	_assert(not e2.is_empty(), "empty connection ID fails")

	# Duplicate connection
	var b3 := Block.new()
	b3.block_name = "dup_conn"
	b3.collision_size = Vector3(1, 1, 1)
	b3.connections = PackedStringArray(["peer_a", "peer_b", "peer_a"])
	var e3 := BlockValidator.validate(b3)
	_assert(not e3.is_empty(), "duplicate connection fails")
	var has_dup_err := false
	for e in e3:
		if e.contains("duplicate"):
			has_dup_err = true
	_assert(has_dup_err, "error mentions duplicate")

	# Valid connections pass
	var b4 := Block.new()
	b4.block_name = "valid_conn"
	b4.collision_size = Vector3(1, 1, 1)
	b4.connections = PackedStringArray(["peer_a", "peer_b", "peer_c"])
	_assert(BlockValidator.is_valid(b4), "valid connections pass")

	# No connections passes
	var b5 := Block.new()
	b5.block_name = "no_conn"
	b5.collision_size = Vector3(1, 1, 1)
	_assert(BlockValidator.is_valid(b5), "no connections passes validation")

	# Multiple errors at once
	var b6 := Block.new()
	b6.block_name = "multi_err"
	b6.block_id = "multi_001"
	b6.collision_size = Vector3(1, 1, 1)
	b6.connections = PackedStringArray(["multi_001", "", "peer_a", "peer_a"])
	var e6 := BlockValidator.validate(b6)
	_assert(e6.size() >= 3, "multiple connection errors caught: %d" % e6.size())

	# Large connection list passes if valid
	var b7 := Block.new()
	b7.block_name = "many_conn"
	b7.collision_size = Vector3(1, 1, 1)
	var many := PackedStringArray()
	for i in range(50):
		many.append("peer_%d" % i)
	b7.connections = many
	_assert(BlockValidator.is_valid(b7), "50 valid connections passes")


# =========================================================================
# Test Group 6: Grid Construction
# =========================================================================

func _test_grid_construction() -> void:
	_section("Grid Construction")

	_build_full_grid()

	# Total count
	_assert(_grid_blocks.size() == 28, "grid has 28 blocks")
	_assert(_registry.get_block_count() == 28, "registry has 28 blocks")

	# All blocks pass validation
	var all_valid := true
	for bname in _grid_blocks:
		if not BlockValidator.is_valid(_grid_blocks[bname]):
			all_valid = false
			print("    Invalid: %s" % bname)
	_assert(all_valid, "all 28 grid blocks pass validation")

	# Generator
	var gen: Block = _grid_blocks["generator"]
	_assert(gen.block_name == "generator", "generator name correct")
	_assert(gen.category == BlockCategories.STRUCTURE, "generator is STRUCTURE")
	_assert(gen.collision_shape == BlockCategories.SHAPE_BOX, "generator is BOX")
	_assert(gen.collision_size == Vector3(3, 4, 3), "generator size correct")
	_assert(gen.material_id == "generator_yellow", "generator material correct")
	_assert("power_source" in gen.tags, "generator tagged power_source")
	_assert("grid" in gen.tags, "generator tagged grid")
	_assert(gen.cast_shadow, "generator casts shadow")

	# Transformers
	for tname in ["transformer_north", "transformer_south", "transformer_east"]:
		var t: Block = _grid_blocks[tname]
		_assert(t.category == BlockCategories.STRUCTURE, "%s is STRUCTURE" % tname)
		_assert(t.collision_size == Vector3(2, 3, 2), "%s size correct" % tname)
		_assert(t.material_id == "transformer_gray", "%s material correct" % tname)
		_assert("transformer" in t.tags, "%s tagged transformer" % tname)

	# Power lines
	for i in range(8):
		var pl: Block = _grid_blocks["power_line_%d" % i]
		_assert(pl.category == BlockCategories.PROP, "power_line_%d is PROP" % i)
		_assert(not pl.server_collidable, "power_line_%d not server_collidable" % i)
		_assert("wire" in pl.tags, "power_line_%d tagged wire" % i)

	# Houses
	for i in range(6):
		var h: Block = _grid_blocks["house_%d" % i]
		_assert(h.category == BlockCategories.STRUCTURE, "house_%d is STRUCTURE" % i)
		_assert(h.collision_size == Vector3(4, 3, 4), "house_%d size correct" % i)
		_assert("consumer" in h.tags, "house_%d tagged consumer" % i)

	# Street lights
	for i in range(8):
		var sl: Block = _grid_blocks["street_light_%d" % i]
		_assert(sl.category == BlockCategories.EFFECT, "street_light_%d is EFFECT" % i)
		_assert(sl.collision_shape == BlockCategories.SHAPE_CYLINDER, "street_light_%d is CYLINDER" % i)
		_assert("light" in sl.tags, "street_light_%d tagged light" % i)

	# Control tower
	var ct: Block = _grid_blocks["control_tower"]
	_assert(ct.category == BlockCategories.TRIGGER_CAT, "control_tower is TRIGGER_CAT")
	_assert(ct.interaction == BlockCategories.INTERACT_TRIGGER, "control_tower is TRIGGER interaction")
	_assert(ct.collision_layer == CollisionLayers.TRIGGER, "control_tower on TRIGGER layer")
	_assert(is_equal_approx(ct.trigger_radius, 10.0), "control_tower trigger_radius is 10")

	# Water tower
	var wt: Block = _grid_blocks["water_tower"]
	_assert(wt.category == BlockCategories.STRUCTURE, "water_tower is STRUCTURE")
	_assert(wt.collision_shape == BlockCategories.SHAPE_CYLINDER, "water_tower is CYLINDER")
	_assert("isolated" in wt.tags, "water_tower tagged isolated")


# =========================================================================
# Test Group 7: Grid Registration
# =========================================================================

func _test_grid_registration() -> void:
	_section("Grid Registration")

	# Category counts
	# STRUCTURE: 1 gen + 3 trans + 6 houses + 1 water = 11
	var structures := _registry.get_blocks_by_category(BlockCategories.STRUCTURE)
	_assert(structures.size() == 11, "11 STRUCTURE blocks (got %d)" % structures.size())

	# PROP: 8 power lines
	var props := _registry.get_blocks_by_category(BlockCategories.PROP)
	_assert(props.size() == 8, "8 PROP blocks (got %d)" % props.size())

	# EFFECT: 8 street lights
	var effects := _registry.get_blocks_by_category(BlockCategories.EFFECT)
	_assert(effects.size() == 8, "8 EFFECT blocks (got %d)" % effects.size())

	# TRIGGER_CAT: 1 control tower
	var triggers := _registry.get_blocks_by_category(BlockCategories.TRIGGER_CAT)
	_assert(triggers.size() == 1, "1 TRIGGER block (got %d)" % triggers.size())

	# Tag queries
	var grid_tagged := _registry.get_blocks_by_tag("grid")
	_assert(grid_tagged.size() == 27, "27 blocks tagged 'grid' (not water tower, got %d)" % grid_tagged.size())

	var consumers := _registry.get_blocks_by_tag("consumer")
	_assert(consumers.size() == 14, "14 blocks tagged 'consumer' (6 houses + 8 lights, got %d)" % consumers.size())

	var power_sources := _registry.get_blocks_by_tag("power_source")
	_assert(power_sources.size() == 1, "1 block tagged 'power_source' (got %d)" % power_sources.size())

	var transformers := _registry.get_blocks_by_tag("transformer")
	_assert(transformers.size() == 3, "3 blocks tagged 'transformer' (got %d)" % transformers.size())

	var wires := _registry.get_blocks_by_tag("wire")
	_assert(wires.size() == 8, "8 blocks tagged 'wire' (got %d)" % wires.size())

	var lights := _registry.get_blocks_by_tag("light")
	_assert(lights.size() == 8, "8 blocks tagged 'light' (got %d)" % lights.size())

	var houses := _registry.get_blocks_by_tag("house")
	_assert(houses.size() == 6, "6 blocks tagged 'house' (got %d)" % houses.size())

	var isolated := _registry.get_blocks_by_tag("isolated")
	_assert(isolated.size() == 1, "1 block tagged 'isolated' (got %d)" % isolated.size())

	# All blocks are active
	var all_active := true
	for bname in _grid_blocks:
		if not _grid_blocks[bname].active:
			all_active = false
	_assert(all_active, "all 28 blocks are active")

	# All have instantiated_at set
	var all_ts := true
	for bname in _grid_blocks:
		if _grid_blocks[bname].instantiated_at == 0:
			all_ts = false
	_assert(all_ts, "all blocks have instantiated_at > 0")

	# Spatial query near generator
	var near_gen := _registry.get_blocks_near(Vector3(0, 0, -30), 10.0)
	_assert(near_gen.size() >= 1, "at least 1 block near generator position")

	# Spatial query near houses
	var near_houses := _registry.get_blocks_near(Vector3(0, 0, 10), 25.0)
	_assert(near_houses.size() >= 6, "at least 6 blocks near house area")


# =========================================================================
# Test Group 8: Peer Topology
# =========================================================================

func _test_grid_peer_topology() -> void:
	_section("Grid Peer Topology")

	var gen: Block = _grid_blocks["generator"]
	var t1: Block = _grid_blocks["transformer_north"]
	var t2: Block = _grid_blocks["transformer_south"]
	var t3: Block = _grid_blocks["transformer_east"]
	var ct: Block = _grid_blocks["control_tower"]
	var wt: Block = _grid_blocks["water_tower"]

	# Generator connections: 3 trans + 3 lines + control tower = 7
	_assert(gen.connections.size() == 7, "generator has 7 connections (got %d)" % gen.connections.size())

	# Transformer_north: gen + 3 lines + 2 houses = 6
	_assert(t1.connections.size() == 6, "transformer_north has 6 connections (got %d)" % t1.connections.size())

	# Transformer_south: gen + 2 lines + 2 houses = 5
	_assert(t2.connections.size() == 5, "transformer_south has 5 connections (got %d)" % t2.connections.size())

	# Transformer_east: gen + 2 houses = 3
	_assert(t3.connections.size() == 3, "transformer_east has 3 connections (got %d)" % t3.connections.size())

	# Control tower: gen = 1
	_assert(ct.connections.size() == 1, "control_tower has 1 connection")

	# Water tower: 0
	_assert(wt.connections.size() == 0, "water_tower has 0 connections")
	_assert(not wt.has_peer_connections(), "water_tower has_peer_connections false")

	# Houses have 2-3 connections (transformer + 1-2 lights)
	var h0: Block = _grid_blocks["house_0"]
	_assert(h0.connections.size() == 2, "house_0 has 2 connections (trans + 1 light, got %d)" % h0.connections.size())
	var h1: Block = _grid_blocks["house_1"]
	_assert(h1.connections.size() == 3, "house_1 has 3 connections (trans + 2 lights, got %d)" % h1.connections.size())
	var h4: Block = _grid_blocks["house_4"]
	_assert(h4.connections.size() == 3, "house_4 has 3 connections (trans + 2 lights, got %d)" % h4.connections.size())

	# Street lights have exactly 1 connection (to their house)
	for i in range(8):
		var sl: Block = _grid_blocks["street_light_%d" % i]
		_assert(sl.connections.size() == 1, "street_light_%d has 1 connection (got %d)" % [i, sl.connections.size()])

	# Power lines have exactly 1 connection each
	for i in range(8):
		var pl: Block = _grid_blocks["power_line_%d" % i]
		_assert(pl.connections.size() == 1, "power_line_%d has 1 connection (got %d)" % [i, pl.connections.size()])

	# Bidirectionality: if gen connects to t1, t1 connects to gen
	_assert(gen.is_connected_to(t1.block_id), "gen -> t1 connected")
	_assert(t1.is_connected_to(gen.block_id), "t1 -> gen connected (bidirectional)")
	_assert(gen.is_connected_to(t2.block_id), "gen -> t2 connected")
	_assert(gen.is_connected_to(t3.block_id), "gen -> t3 connected")
	_assert(gen.is_connected_to(ct.block_id), "gen -> control_tower connected")
	_assert(not gen.is_connected_to(wt.block_id), "gen NOT connected to water_tower")

	# Verify get_connected_blocks returns correct objects
	var gen_peers := _registry.get_connected_blocks(gen.block_id)
	_assert(gen_peers.size() == 7, "get_connected_blocks returns 7 for generator")

	var wt_peers := _registry.get_connected_blocks(wt.block_id)
	_assert(wt_peers.is_empty(), "get_connected_blocks returns empty for water_tower")


# =========================================================================
# Test Group 9: Power Propagation
# =========================================================================

func _test_power_propagation() -> void:
	_section("Power Propagation")

	_messages_received.clear()

	# Propagate from generator
	var gen: Block = _grid_blocks["generator"]
	var reached := _registry.propagate_through_connections(gen.block_id, "power_on", {"voltage": 240})

	# Should reach all connected blocks (27) but NOT water tower
	_assert(reached.size() == 27, "propagation reaches 27 blocks (got %d)" % reached.size())

	# Verify water tower NOT in reached
	var wt: Block = _grid_blocks["water_tower"]
	var wt_reached := false
	for block in reached:
		if block.block_id == wt.block_id:
			wt_reached = true
	_assert(not wt_reached, "water_tower NOT reached by propagation")

	# Generator IS in reached (propagation includes start)
	var gen_reached := false
	for block in reached:
		if block.block_id == gen.block_id:
			gen_reached = true
	_assert(gen_reached, "generator IS in reached (includes start)")

	# All transformers reached
	for tname in ["transformer_north", "transformer_south", "transformer_east"]:
		var t: Block = _grid_blocks[tname]
		var found := false
		for block in reached:
			if block.block_id == t.block_id:
				found = true
		_assert(found, "%s reached by propagation" % tname)

	# All houses reached
	for i in range(6):
		var h: Block = _grid_blocks["house_%d" % i]
		var found := false
		for block in reached:
			if block.block_id == h.block_id:
				found = true
		_assert(found, "house_%d reached by propagation" % i)

	# All street lights reached
	for i in range(8):
		var sl: Block = _grid_blocks["street_light_%d" % i]
		var found := false
		for block in reached:
			if block.block_id == sl.block_id:
				found = true
		_assert(found, "street_light_%d reached by propagation" % i)

	# All power lines reached
	for i in range(8):
		var pl: Block = _grid_blocks["power_line_%d" % i]
		var found := false
		for block in reached:
			if block.block_id == pl.block_id:
				found = true
		_assert(found, "power_line_%d reached by propagation" % i)

	# Control tower reached
	var ct_reached := false
	for block in reached:
		if block.block_id == _grid_blocks["control_tower"].block_id:
			ct_reached = true
	_assert(ct_reached, "control_tower reached by propagation")

	# Message count matches reached count
	_assert(_messages_received.size() == 27, "27 messages emitted (got %d)" % _messages_received.size())

	# Each message has correct msg_type
	var all_power_on := true
	for msg in _messages_received:
		if msg["msg_type"] != "power_on":
			all_power_on = false
	_assert(all_power_on, "all messages have type 'power_on'")

	# Propagation from a leaf (street_light_0) reaches all connected
	_messages_received.clear()
	var sl0: Block = _grid_blocks["street_light_0"]
	var leaf_reached := _registry.propagate_through_connections(sl0.block_id, "reverse_trace")
	_assert(leaf_reached.size() == 27, "propagation from leaf reaches 27 (got %d)" % leaf_reached.size())

	# Propagation from water tower reaches only itself
	_messages_received.clear()
	var wt_reached_list := _registry.propagate_through_connections(wt.block_id, "wt_test")
	_assert(wt_reached_list.size() == 1, "water_tower propagation reaches only itself")
	_assert(wt_reached_list[0].block_id == wt.block_id, "water_tower reached is itself")


# =========================================================================
# Test Group 10: State Management
# =========================================================================

func _test_state_management() -> void:
	_section("State Management")

	# Set powered state via propagation handler
	# First clear all state
	for bname in _grid_blocks:
		_grid_blocks[bname].state.clear()

	# Manually set state during propagation
	var gen: Block = _grid_blocks["generator"]
	var reached := _registry.propagate_through_connections(gen.block_id, "power_on")
	for block in reached:
		block.state["powered"] = true

	# Verify all connected blocks are powered
	for bname in _grid_blocks:
		var b: Block = _grid_blocks[bname]
		if bname == "water_tower":
			_assert(not b.state.has("powered"), "water_tower has no powered state")
		else:
			_assert(b.state.get("powered", false) == true, "%s is powered" % bname)

	# Set role-specific state
	gen.state["role"] = "source"
	gen.state["output_voltage"] = 10000
	_assert(gen.state["role"] == "source", "generator role is source")
	_assert(gen.state["output_voltage"] == 10000, "generator output_voltage is 10000")

	for tname in ["transformer_north", "transformer_south", "transformer_east"]:
		_grid_blocks[tname].state["voltage"] = 240
		_grid_blocks[tname].state["role"] = "transformer"

	_assert(_grid_blocks["transformer_north"].state["voltage"] == 240, "transformer voltage set")

	# House-specific state
	for i in range(6):
		_grid_blocks["house_%d" % i].state["occupancy"] = (i + 1) * 2
	_assert(_grid_blocks["house_0"].state["occupancy"] == 2, "house_0 occupancy is 2")
	_assert(_grid_blocks["house_5"].state["occupancy"] == 12, "house_5 occupancy is 12")

	# Street light brightness
	for i in range(8):
		_grid_blocks["street_light_%d" % i].state["brightness"] = 0.8
	_assert(is_equal_approx(_grid_blocks["street_light_0"].state["brightness"], 0.8),
		"street_light_0 brightness is 0.8")

	# State doesn't leak
	_assert(not _grid_blocks["water_tower"].state.has("voltage"), "water_tower has no voltage state")
	_assert(not _grid_blocks["water_tower"].state.has("brightness"), "water_tower has no brightness state")

	# Modify state at runtime
	_grid_blocks["house_2"].state["temperature"] = 72.0
	_assert(is_equal_approx(_grid_blocks["house_2"].state["temperature"], 72.0), "house_2 temperature set")
	_assert(not _grid_blocks["house_0"].state.has("temperature"), "house_0 has no temperature (no leak)")

	# State survives re-query from registry
	var fetched := _registry.get_block(gen.block_id)
	_assert(fetched.state["role"] == "source", "state survives registry get_block re-fetch")


# =========================================================================
# Test Group 11: Visual Power State
# =========================================================================

func _test_visual_power_state() -> void:
	_section("Visual Power State")

	# Build all grid blocks
	var built_nodes: Array[Node3D] = []
	for bname in _grid_blocks:
		var block: Block = _grid_blocks[bname]
		var node := BlockBuilder.build(block, self)
		built_nodes.append(node)

	# Set all unpowered (red)
	var red_count := 0
	for bname in _grid_blocks:
		if BlockVisuals.set_powered(_grid_blocks[bname], false):
			red_count += 1
	_assert(red_count > 0, "set_powered(false) applied to %d blocks" % red_count)

	# Verify generator mesh has red-ish emission
	var gen: Block = _grid_blocks["generator"]
	var gen_mesh := gen.node.get_node_or_null("Mesh") as MeshInstance3D
	if gen_mesh and gen_mesh.material_override is StandardMaterial3D:
		var mat := gen_mesh.material_override as StandardMaterial3D
		_assert(mat.emission.r > mat.emission.g, "generator unpowered = red emission")
	else:
		_assert(false, "generator has mesh with material")

	# Power up connected blocks
	var green_count := 0
	for bname in _grid_blocks:
		if bname != "water_tower":
			if BlockVisuals.set_powered(_grid_blocks[bname], true):
				green_count += 1
	_assert(green_count >= 20, "set_powered(true) applied to %d connected blocks" % green_count)

	# Verify generator now has green emission
	gen_mesh = gen.node.get_node("Mesh") as MeshInstance3D
	var gen_mat := gen_mesh.material_override as StandardMaterial3D
	_assert(gen_mat.emission.g > gen_mat.emission.r, "generator powered = green emission")

	# Verify a house has green
	var h0: Block = _grid_blocks["house_0"]
	var h0_mesh := h0.node.get_node_or_null("Mesh") as MeshInstance3D
	if h0_mesh and h0_mesh.material_override is StandardMaterial3D:
		var h0_mat := h0_mesh.material_override as StandardMaterial3D
		_assert(h0_mat.emission.g > h0_mat.emission.r, "house_0 powered = green emission")
	else:
		_assert(false, "house_0 has mesh with material")

	# Verify a street light has green
	var sl0: Block = _grid_blocks["street_light_0"]
	var sl0_mesh := sl0.node.get_node_or_null("Mesh") as MeshInstance3D
	if sl0_mesh and sl0_mesh.material_override is StandardMaterial3D:
		var sl0_mat := sl0_mesh.material_override as StandardMaterial3D
		_assert(sl0_mat.emission.g > sl0_mat.emission.r, "street_light_0 powered = green emission")
	else:
		_assert(false, "street_light_0 has mesh with material")

	# Verify water tower still has red emission
	var wt: Block = _grid_blocks["water_tower"]
	var wt_mesh := wt.node.get_node_or_null("Mesh") as MeshInstance3D
	if wt_mesh and wt_mesh.material_override is StandardMaterial3D:
		var wt_mat := wt_mesh.material_override as StandardMaterial3D
		_assert(wt_mat.emission.r > wt_mat.emission.g, "water_tower still red (unpowered)")
	else:
		_assert(false, "water_tower has mesh with material")

	# Material isolation: changing water tower doesn't affect generator
	BlockVisuals.set_emission(wt, Color.BLUE, 5.0)
	gen_mat = (gen.node.get_node("Mesh") as MeshInstance3D).material_override as StandardMaterial3D
	_assert(gen_mat.emission != Color.BLUE, "changing water_tower doesn't affect generator")

	# Verify transformer visual
	var t1: Block = _grid_blocks["transformer_north"]
	var t1_mesh := t1.node.get_node_or_null("Mesh") as MeshInstance3D
	if t1_mesh and t1_mesh.material_override is StandardMaterial3D:
		var t1_mat := t1_mesh.material_override as StandardMaterial3D
		_assert(t1_mat.emission_enabled, "transformer_north has emission enabled")
	else:
		_assert(false, "transformer_north has mesh with material")

	# Clean up built nodes
	for n in built_nodes:
		n.queue_free()


# =========================================================================
# Test Group 12: Path Finding Through Connections
# =========================================================================

func _test_path_finding_connections() -> void:
	_section("Path Finding Through Connections")

	var gen: Block = _grid_blocks["generator"]
	var sl0: Block = _grid_blocks["street_light_0"]
	var sl7: Block = _grid_blocks["street_light_7"]
	var wt: Block = _grid_blocks["water_tower"]
	var ct: Block = _grid_blocks["control_tower"]
	var h0: Block = _grid_blocks["house_0"]

	# Generator to street_light_0: gen -> trans_north -> house_0 -> light_0 = 4 hops
	var path1 := _registry.find_path(gen.block_id, sl0.block_id)
	_assert(not path1.is_empty(), "path from generator to street_light_0 exists")
	_assert(path1.size() == 4, "path is 4 hops (got %d)" % path1.size())
	_assert(path1[0] == gen.block_id, "path starts at generator")
	_assert(path1[path1.size() - 1] == sl0.block_id, "path ends at street_light_0")

	# Generator to water_tower: no path (disconnected)
	var path2 := _registry.find_path(gen.block_id, wt.block_id)
	_assert(path2.is_empty(), "no path from generator to water_tower")

	# Water tower to generator: no path
	var path3 := _registry.find_path(wt.block_id, gen.block_id)
	_assert(path3.is_empty(), "no path from water_tower to generator")

	# Street_light_0 to street_light_7 (cross the grid)
	var path4 := _registry.find_path(sl0.block_id, sl7.block_id)
	_assert(not path4.is_empty(), "path from light_0 to light_7 exists")
	_assert(path4.size() >= 4, "path is at least 4 hops (got %d)" % path4.size())

	# Control tower to house_0: ct -> gen -> trans_north -> house_0 = 4 hops
	var path5 := _registry.find_path(ct.block_id, h0.block_id)
	_assert(not path5.is_empty(), "path from control_tower to house_0 exists")
	_assert(path5[0] == ct.block_id, "path starts at control_tower")
	_assert(path5[path5.size() - 1] == h0.block_id, "path ends at house_0")

	# Path from block to itself
	var self_path := _registry.find_path(gen.block_id, gen.block_id)
	_assert(self_path.size() == 1, "path to self is length 1")

	# Path to non-existent block
	var bad_path := _registry.find_path(gen.block_id, "nonexistent")
	_assert(bad_path.is_empty(), "path to nonexistent is empty")

	# Path between two power lines (both connect to generator)
	var pl0: Block = _grid_blocks["power_line_0"]
	var pl1: Block = _grid_blocks["power_line_1"]
	var line_path := _registry.find_path(pl0.block_id, pl1.block_id)
	_assert(not line_path.is_empty(), "path between power_line_0 and power_line_1 exists")
	_assert(line_path.size() == 3, "path goes through generator: line0 -> gen -> line1 (got %d)" % line_path.size())

	# Path between two houses on different transformers
	var h2: Block = _grid_blocks["house_2"]
	var h4: Block = _grid_blocks["house_4"]
	var cross_path := _registry.find_path(h2.block_id, h4.block_id)
	_assert(not cross_path.is_empty(), "cross-transformer path exists")
	_assert(cross_path.size() >= 4, "cross path is at least 4 hops")

	# Verify all paths are valid (each step is connected)
	var all_valid := true
	for idx in range(path1.size() - 1):
		var curr := _registry.get_block(path1[idx])
		var next_id: String = path1[idx + 1]
		if not curr.is_connected_to(next_id) and curr.parent_id != next_id \
				and next_id not in curr.child_ids:
			all_valid = false
	_assert(all_valid, "all steps in gen->light path are valid connections")


# =========================================================================
# Test Group 13: Cascade Failure
# =========================================================================

func _test_cascade_failure() -> void:
	_section("Cascade Failure")

	# Power the full grid
	var gen: Block = _grid_blocks["generator"]
	for bname in _grid_blocks:
		_grid_blocks[bname].state["powered"] = false

	var reached := _registry.propagate_through_connections(gen.block_id, "power_on")
	for block in reached:
		block.state["powered"] = true

	_assert(_grid_blocks["house_0"].state["powered"], "house_0 powered before disconnect")
	_assert(_grid_blocks["house_1"].state["powered"], "house_1 powered before disconnect")
	_assert(_grid_blocks["street_light_0"].state["powered"], "street_light_0 powered before disconnect")

	# Disconnect transformer_north from generator
	var t1: Block = _grid_blocks["transformer_north"]
	_registry.disconnect_blocks(gen.block_id, t1.block_id)

	# Re-propagate: clear all state first
	for bname in _grid_blocks:
		_grid_blocks[bname].state["powered"] = false

	var reached2 := _registry.propagate_through_connections(gen.block_id, "power_on")
	for block in reached2:
		block.state["powered"] = true

	# Transformer_north and its downstream should be unreachable from generator
	# BUT transformer_north forms its own island (with houses 0,1 and lights 0,1,2 and power lines 3,4,5)
	_assert(not _grid_blocks["transformer_north"].state["powered"],
		"transformer_north NOT powered after disconnect from gen")

	# Houses 0,1 connect through transformer_north, which is disconnected from gen
	_assert(not _grid_blocks["house_0"].state["powered"],
		"house_0 NOT powered (downstream of disconnected trans_north)")
	_assert(not _grid_blocks["house_1"].state["powered"],
		"house_1 NOT powered (downstream of disconnected trans_north)")

	# Street lights on those houses
	_assert(not _grid_blocks["street_light_0"].state["powered"],
		"street_light_0 NOT powered (under house_0)")
	_assert(not _grid_blocks["street_light_1"].state["powered"],
		"street_light_1 NOT powered (under house_1)")
	_assert(not _grid_blocks["street_light_2"].state["powered"],
		"street_light_2 NOT powered (under house_1)")

	# But houses 2-5 and their lights should still be powered
	_assert(_grid_blocks["house_2"].state["powered"], "house_2 still powered")
	_assert(_grid_blocks["house_3"].state["powered"], "house_3 still powered")
	_assert(_grid_blocks["house_4"].state["powered"], "house_4 still powered")
	_assert(_grid_blocks["house_5"].state["powered"], "house_5 still powered")
	_assert(_grid_blocks["street_light_3"].state["powered"], "street_light_3 still powered")
	_assert(_grid_blocks["street_light_4"].state["powered"], "street_light_4 still powered")
	_assert(_grid_blocks["street_light_5"].state["powered"], "street_light_5 still powered")
	_assert(_grid_blocks["street_light_7"].state["powered"], "street_light_7 still powered")

	# Reconnect and verify full power restored
	_registry.connect_blocks(gen.block_id, t1.block_id)
	for bname in _grid_blocks:
		_grid_blocks[bname].state["powered"] = false
	var reached3 := _registry.propagate_through_connections(gen.block_id, "power_on")
	for block in reached3:
		block.state["powered"] = true

	_assert(_grid_blocks["house_0"].state["powered"], "house_0 powered after reconnect")
	_assert(_grid_blocks["house_1"].state["powered"], "house_1 powered after reconnect")
	_assert(_grid_blocks["street_light_0"].state["powered"], "street_light_0 powered after reconnect")
	_assert(reached3.size() == 27, "full propagation after reconnect reaches 27 (got %d)" % reached3.size())

	# Unregister transformer_south: downstream should lose connections
	var t2: Block = _grid_blocks["transformer_south"]
	var t2_id := t2.block_id
	_registry.unregister(t2_id)

	# gen should no longer be connected to t2
	_assert(not gen.is_connected_to(t2_id), "generator no longer connected to unregistered trans_south")

	# Re-propagate
	for bname in _grid_blocks:
		if _registry.get_block(_grid_blocks[bname].block_id) != null:
			_grid_blocks[bname].state["powered"] = false
	var reached4 := _registry.propagate_through_connections(gen.block_id, "power_on")
	for block in reached4:
		block.state["powered"] = true

	# houses 2,3 connected to trans_south should be disconnected
	# But they might have NO connections left if trans_south was their only upstream
	_assert(not _grid_blocks["house_2"].state.get("powered", false),
		"house_2 NOT powered after trans_south unregistered")
	_assert(not _grid_blocks["house_3"].state.get("powered", false),
		"house_3 NOT powered after trans_south unregistered")

	# Restore for subsequent tests by re-registering
	var new_t2 := _make_transformer("transformer_south", Vector3(0, 1.5, 0))
	new_t2.block_id = ""
	_register_grid("transformer_south", new_t2)
	_grid_blocks["transformer_south"] = new_t2
	_registry.connect_blocks(gen.block_id, new_t2.block_id)
	_registry.connect_blocks(new_t2.block_id, _grid_blocks["house_2"].block_id)
	_registry.connect_blocks(new_t2.block_id, _grid_blocks["house_3"].block_id)
	_registry.connect_blocks(new_t2.block_id, _grid_blocks["power_line_6"].block_id)
	_registry.connect_blocks(new_t2.block_id, _grid_blocks["power_line_7"].block_id)


# =========================================================================
# Test Group 14: Grid Stats
# =========================================================================

func _test_grid_stats() -> void:
	_section("Grid Stats")

	# Full power propagation
	var gen: Block = _grid_blocks["generator"]
	for bname in _grid_blocks:
		var b: Block = _grid_blocks[bname]
		if _registry.get_block(b.block_id) != null:
			b.state["powered"] = false

	var reached := _registry.propagate_through_connections(gen.block_id, "power_on")
	for block in reached:
		block.state["powered"] = true

	# Count powered
	var powered_count := 0
	var unpowered_count := 0
	for bname in _grid_blocks:
		var b: Block = _grid_blocks[bname]
		if _registry.get_block(b.block_id) == null:
			continue
		if b.state.get("powered", false):
			powered_count += 1
		else:
			unpowered_count += 1

	_assert(powered_count >= 26, "at least 26 blocks powered (got %d)" % powered_count)
	_assert(unpowered_count >= 1, "at least 1 block unpowered (water_tower, got %d)" % unpowered_count)

	# Connection degree stats
	var max_degree := 0
	var min_degree := 999
	var total_degree := 0
	for bname in _grid_blocks:
		var b: Block = _grid_blocks[bname]
		if _registry.get_block(b.block_id) == null:
			continue
		var degree := b.connections.size()
		if degree > max_degree:
			max_degree = degree
		if degree < min_degree:
			min_degree = degree
		total_degree += degree

	_assert(max_degree == 7, "max connection degree is 7 (generator, got %d)" % max_degree)
	_assert(min_degree == 0, "min connection degree is 0 (water_tower, got %d)" % min_degree)
	_assert(total_degree > 0, "total degree > 0 (got %d)" % total_degree)

	# Powered by category
	var powered_structures := 0
	var powered_effects := 0
	for bname in _grid_blocks:
		var b: Block = _grid_blocks[bname]
		if _registry.get_block(b.block_id) == null:
			continue
		if b.state.get("powered", false):
			if b.category == BlockCategories.STRUCTURE:
				powered_structures += 1
			elif b.category == BlockCategories.EFFECT:
				powered_effects += 1

	_assert(powered_structures >= 9, "at least 9 powered structures (got %d)" % powered_structures)
	_assert(powered_effects == 8, "8 powered effects (got %d)" % powered_effects)

	# Source vs consumer count
	var sources := _registry.get_blocks_by_tag("power_source")
	var consumers := _registry.get_blocks_by_tag("consumer")
	_assert(sources.size() == 1, "1 power source")
	_assert(consumers.size() == 14, "14 consumers (6 houses + 8 lights)")


# =========================================================================
# Test Group 15: Isolated Blocks
# =========================================================================

func _test_isolated_blocks() -> void:
	_section("Isolated Blocks")

	var wt: Block = _grid_blocks["water_tower"]
	_assert(_registry.get_block(wt.block_id) != null, "water_tower in registry")
	_assert(wt.connections.is_empty(), "water_tower has no connections")
	_assert(not wt.has_peer_connections(), "water_tower has_peer_connections is false")

	# Not reached by propagation
	var gen: Block = _grid_blocks["generator"]
	var reached := _registry.propagate_through_connections(gen.block_id, "check_isolated")
	var wt_found := false
	for block in reached:
		if block.block_id == wt.block_id:
			wt_found = true
	_assert(not wt_found, "water_tower not found in propagation")

	# State is not powered (either absent or false)
	_assert(not wt.state.get("powered", false), "water_tower is not powered")

	# Spatial query finds it at its position
	var near_wt := _registry.get_blocks_near(Vector3(40, 0, 0), 5.0)
	var found_spatial := false
	for block in near_wt:
		if block.block_id == wt.block_id:
			found_spatial = true
	_assert(found_spatial, "water_tower found by spatial query at its position")

	# Collision export includes it (it has a collision shape)
	var boxes := _registry.export_collision_boxes()
	var wt_in_export := false
	for box in boxes:
		# Water tower at x=40 — check for a box near there
		if box["min_x"] > 35 and box["max_x"] < 45:
			wt_in_export = true
	_assert(wt_in_export, "water_tower appears in collision export")

	# Path from water tower to anything connected is empty
	var no_path := _registry.find_path(wt.block_id, gen.block_id)
	_assert(no_path.is_empty(), "no path from water_tower to generator")

	# get_connected_blocks returns empty
	var wt_peers := _registry.get_connected_blocks(wt.block_id)
	_assert(wt_peers.is_empty(), "get_connected_blocks returns empty for water_tower")

	# Category query still includes it
	var structures := _registry.get_blocks_by_category(BlockCategories.STRUCTURE)
	var wt_in_cat := false
	for block in structures:
		if block.block_id == wt.block_id:
			wt_in_cat = true
	_assert(wt_in_cat, "water_tower in STRUCTURE category query")


# =========================================================================
# Test Group 16: Stress Test
# =========================================================================

func _test_stress() -> void:
	_section("Stress Test")

	# Save grid state
	var saved_count := _registry.get_block_count()

	# Register 50 blocks rapidly
	var stress_blocks: Array[Block] = []
	for i in range(50):
		var b := Block.new()
		b.block_name = "stress_%d" % i
		b.collision_shape = BlockCategories.SHAPE_BOX
		b.collision_size = Vector3(1, 1, 1)
		b.position = Vector3(float(i) * 2.0, 0, 50)
		b.collision_layer = CollisionLayers.WORLD
		_registry.register(b)
		stress_blocks.append(b)

	_assert(_registry.get_block_count() == saved_count + 50,
		"50 stress blocks registered (total %d)" % _registry.get_block_count())

	# Connect 25 pairs
	for i in range(25):
		_registry.connect_blocks(stress_blocks[i * 2].block_id, stress_blocks[i * 2 + 1].block_id)

	_assert(stress_blocks[0].connections.size() == 1, "stress block 0 has 1 connection")
	_assert(stress_blocks[1].connections.size() == 1, "stress block 1 has 1 connection")

	# Create a chain: 0-1, 1-2, 2-3, ...
	for i in range(49):
		_registry.connect_blocks(stress_blocks[i].block_id, stress_blocks[i + 1].block_id)

	# Propagate through chain
	_messages_received.clear()
	var reached := _registry.propagate_through_connections(stress_blocks[0].block_id, "chain_test")
	_assert(reached.size() == 50, "chain propagation reaches all 50 (got %d)" % reached.size())

	# Path from first to last
	var chain_path := _registry.find_path(stress_blocks[0].block_id, stress_blocks[49].block_id)
	_assert(not chain_path.is_empty(), "path exists in chain")
	_assert(chain_path.size() <= 50, "chain path is at most 50 hops")

	# Unregister all stress blocks
	for b in stress_blocks:
		_registry.unregister(b.block_id)

	_assert(_registry.get_block_count() == saved_count,
		"registry count restored after stress cleanup (got %d)" % _registry.get_block_count())

	# Rapid connect/disconnect
	var x := Block.new()
	x.block_name = "rapid_x"
	x.collision_size = Vector3(1, 1, 1)
	var y := Block.new()
	y.block_name = "rapid_y"
	y.collision_size = Vector3(1, 1, 1)
	_registry.register(x)
	_registry.register(y)

	for i in range(100):
		_registry.connect_blocks(x.block_id, y.block_id)
		_registry.disconnect_blocks(x.block_id, y.block_id)

	_assert(x.connections.is_empty(), "rapid connect/disconnect leaves no connections on x")
	_assert(y.connections.is_empty(), "rapid connect/disconnect leaves no connections on y")

	_registry.unregister(x.block_id)
	_registry.unregister(y.block_id)

	_assert(_registry.get_block_count() == saved_count,
		"final count matches saved count")


# =========================================================================
# Test Group 17: Export Grid
# =========================================================================

func _test_export_grid() -> void:
	_section("Export Grid")

	var boxes := _registry.export_collision_boxes()

	# Power lines are NOT server_collidable — 8 excluded
	# Water tower, generator, 3 transformers, 6 houses, 8 lights, 1 control tower = 20
	# Total collidable
	var collidable := 0
	for bname in _grid_blocks:
		var b: Block = _grid_blocks[bname]
		if _registry.get_block(b.block_id) == null:
			continue
		if b.server_collidable and b.collision_shape != BlockCategories.SHAPE_NONE:
			collidable += 1

	_assert(boxes.size() == collidable,
		"export count (%d) matches collidable (%d)" % [boxes.size(), collidable])

	# All boxes have required keys
	var all_keys := true
	for box in boxes:
		if not (box.has("min_x") and box.has("max_x") and box.has("min_z")
				and box.has("max_z") and box.has("height")):
			all_keys = false
	_assert(all_keys, "all exported boxes have required keys")

	# TypeScript format
	var ts := BlockExporter.export_typescript(_registry)
	_assert(ts.contains("OBSTACLES"), "TS export has OBSTACLES")
	_assert(ts.contains("minX"), "TS export has minX")

	# GDScript format
	var gd := BlockExporter.export_gdscript(_registry)
	_assert(gd.contains("obstacle_boxes"), "GD export has obstacle_boxes")

	# Power lines should NOT appear (server_collidable = false)
	# Check that no box is at power line z=-22 area with tiny size
	var wire_leaked := false
	for box in boxes:
		var width: float = box["max_x"] - box["min_x"]
		var depth: float = box["max_z"] - box["min_z"]
		if width < 0.2 and depth > 7.0:
			wire_leaked = true
	_assert(not wire_leaked, "power lines not in export")


# =========================================================================
# Test Group 18: Builder Grid
# =========================================================================

func _test_builder_grid() -> void:
	_section("Builder Grid")

	var built_nodes: Array[Node3D] = []
	var build_count := 0

	for bname in _grid_blocks:
		var block: Block = _grid_blocks[bname]
		if _registry.get_block(block.block_id) == null:
			continue
		# Reset node so we build fresh
		block.node = null
		var node := BlockBuilder.build(block, self)
		built_nodes.append(node)
		build_count += 1

	_assert(build_count >= 27, "built %d blocks into Node3D trees" % build_count)

	# Check generator has StaticBody3D
	var gen: Block = _grid_blocks["generator"]
	_assert(gen.node != null, "generator has node")
	var gen_body := gen.node.get_node_or_null("Body")
	_assert(gen_body is StaticBody3D, "generator Body is StaticBody3D")
	var gen_col := gen_body.get_node_or_null("Col") as CollisionShape3D
	_assert(gen_col.shape is BoxShape3D, "generator collision is BoxShape3D")

	# Control tower has Area3D (trigger)
	var ct: Block = _grid_blocks["control_tower"]
	var ct_area := ct.node.get_node_or_null("TriggerArea")
	_assert(ct_area is Area3D, "control_tower TriggerArea is Area3D")

	# Street light has CylinderShape3D
	var sl0: Block = _grid_blocks["street_light_0"]
	var sl0_body := sl0.node.get_node_or_null("Body")
	if sl0_body:
		var sl0_col := sl0_body.get_node_or_null("Col") as CollisionShape3D
		_assert(sl0_col.shape is CylinderShape3D, "street_light_0 is CylinderShape3D")
	else:
		_assert(false, "street_light_0 has Body")

	# Water tower has CylinderShape3D
	var wt: Block = _grid_blocks["water_tower"]
	if wt.node:
		var wt_body := wt.node.get_node_or_null("Body")
		if wt_body:
			var wt_col := wt_body.get_node_or_null("Col") as CollisionShape3D
			_assert(wt_col.shape is CylinderShape3D, "water_tower is CylinderShape3D")
		else:
			_assert(false, "water_tower has Body")
	else:
		_assert(false, "water_tower has node")

	# All blocks have block_id metadata
	var all_meta := true
	for bname in _grid_blocks:
		var block: Block = _grid_blocks[bname]
		if block.node == null:
			continue
		if not block.node.has_meta("block_id"):
			all_meta = false
	_assert(all_meta, "all built blocks have block_id metadata")

	# All blocks have Mesh child (except SHAPE_NONE, but we have none of those)
	var all_mesh := true
	for bname in _grid_blocks:
		var block: Block = _grid_blocks[bname]
		if block.node == null:
			continue
		if block.node.get_node_or_null("Mesh") == null:
			all_mesh = false
	_assert(all_mesh, "all built blocks have Mesh child")

	# Power line mesh has wire_copper material
	var pl0: Block = _grid_blocks["power_line_0"]
	if pl0.node:
		var pl0_mesh := pl0.node.get_node_or_null("Mesh") as MeshInstance3D
		if pl0_mesh and pl0_mesh.material_override is StandardMaterial3D:
			var pl0_mat := pl0_mesh.material_override as StandardMaterial3D
			_assert(pl0_mat.albedo_color == BlockMaterials.PALETTE["wire_copper"],
				"power_line_0 has wire_copper material")
		else:
			_assert(false, "power_line_0 has StandardMaterial3D")
	else:
		_assert(false, "power_line_0 has node")

	# Clean up
	for n in built_nodes:
		n.queue_free()
