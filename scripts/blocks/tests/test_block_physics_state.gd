extends Node3D
## Block Physics State + Messages Test Suite
##
## Tests: valid state init, message encode/decode, schema rejection of invalid values,
## typed accessors, and registry message integration.
##
## Run headless:
##   godot --headless --path godot_project --scene-path res://scripts/blocks/tests/test_block_physics_state.tscn

var _pass_count := 0
var _fail_count := 0
var _test_count := 0
var _registry: BlockRegistry

## Message capture for integration test
var _messages_received: Array = []


func _ready() -> void:
	print("")
	print("=".repeat(60))
	print("  BLOCK PHYSICS STATE + MESSAGES TEST SUITE")
	print("=".repeat(60))
	print("")

	# Create a local registry instance (not the autoload — standalone test)
	_registry = BlockRegistry.new()
	_registry.name = "TestPhysicsRegistry"
	add_child(_registry)

	# Run all test groups
	_test_valid_state_init()
	_test_message_encode_decode()
	_test_schema_validation_rejects_invalid()
	_test_typed_accessors()
	_test_registry_message_integration()

	# Summary
	print("")
	print("=".repeat(60))
	var total := _pass_count + _fail_count
	if _fail_count == 0:
		print("  ALL %d TESTS PASSED" % total)
	else:
		print("  %d PASSED, %d FAILED (of %d)" % [_pass_count, _fail_count, total])
	print("=".repeat(60))
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


## Make a minimal valid block for testing (bypasses BlockValidator by not registering).
func _make_test_block(bname: String = "test_block") -> Block:
	var b := Block.new()
	b.block_name = bname
	b.collision_size = Vector3(1.0, 1.0, 1.0)
	b.ensure_id()
	return b


## Make and register a valid block through the registry.
func _make_registered_block(bname: String, pos: Vector3 = Vector3.ZERO) -> Block:
	var b := Block.new()
	b.block_name = bname
	b.collision_size = Vector3(1.0, 1.0, 1.0)
	b.position = pos
	_registry.register(b)
	return b


# =========================================================================
# Test group 1: Valid state initialization
# =========================================================================

func _test_valid_state_init() -> void:
	_section("Valid State Init")

	var block := _make_test_block("init_target")

	# State should be empty before init
	_assert(block.state.is_empty(), "block.state starts empty before init")

	# Call init and verify all 6 keys are present with correct defaults
	BlockPhysicsState.init(block)

	_assert(block.state.has("force_vec"), "init creates force_vec key")
	_assert(block.state.has("velocity"), "init creates velocity key")
	_assert(block.state.has("mass"), "init creates mass key")
	_assert(block.state.has("damping"), "init creates damping key")
	_assert(block.state.has("hop_count"), "init creates hop_count key")
	_assert(block.state.has("displaced"), "init creates displaced key")

	_assert(block.state["force_vec"] == Vector3.ZERO, "force_vec default is Vector3.ZERO")
	_assert(block.state["velocity"] == Vector3.ZERO, "velocity default is Vector3.ZERO")
	_assert(block.state["mass"] == 1.0, "mass default is 1.0")
	_assert(block.state["damping"] == 0.85, "damping default is 0.85")
	_assert(block.state["hop_count"] == 0, "hop_count default is 0")
	_assert(block.state["displaced"] == false, "displaced default is false")

	# Idempotency: changing mass then calling init again should NOT overwrite it
	block.state["mass"] = 5.0
	BlockPhysicsState.init(block)
	_assert(block.state["mass"] == 5.0, "init is idempotent — does not overwrite existing mass=5.0")

	# Idempotency: all other keys still intact
	_assert(block.state["force_vec"] == Vector3.ZERO, "init idempotent — force_vec unchanged")
	_assert(block.state["hop_count"] == 0, "init idempotent — hop_count unchanged")
	_assert(block.state["displaced"] == false, "init idempotent — displaced unchanged")


# =========================================================================
# Test group 2: Message encode/decode roundtrip
# =========================================================================

func _test_message_encode_decode() -> void:
	_section("Message Encode / Decode Roundtrip")

	# --- FORCE_PROPAGATE ---
	var epicenter := Vector3(1.0, 2.0, 3.0)
	var magnitude := 10.5
	var hop := 2
	var max_hops := 5

	var encoded_fp := BlockMessages.encode_force_propagate(epicenter, magnitude, hop, max_hops)

	_assert(encoded_fp.has("epicenter"), "FORCE_PROPAGATE encoded has epicenter key")
	_assert(encoded_fp.has("magnitude"), "FORCE_PROPAGATE encoded has magnitude key")
	_assert(encoded_fp.has("hop"), "FORCE_PROPAGATE encoded has hop key")
	_assert(encoded_fp.has("max_hops"), "FORCE_PROPAGATE encoded has max_hops key")
	_assert(encoded_fp["epicenter"] == epicenter, "FORCE_PROPAGATE epicenter value correct")
	_assert(encoded_fp["magnitude"] == magnitude, "FORCE_PROPAGATE magnitude value correct")
	_assert(encoded_fp["hop"] == hop, "FORCE_PROPAGATE hop value correct")
	_assert(encoded_fp["max_hops"] == max_hops, "FORCE_PROPAGATE max_hops value correct")

	# Decode roundtrip
	var decoded_fp := BlockMessages.decode_force_propagate(encoded_fp)
	_assert(decoded_fp["epicenter"] == epicenter, "FORCE_PROPAGATE decode epicenter roundtrip")
	_assert(decoded_fp["magnitude"] == magnitude, "FORCE_PROPAGATE decode magnitude roundtrip")
	_assert(decoded_fp["hop"] == hop, "FORCE_PROPAGATE decode hop roundtrip")
	_assert(decoded_fp["max_hops"] == max_hops, "FORCE_PROPAGATE decode max_hops roundtrip")

	# Decode empty dict returns defaults without crashing
	var decoded_empty_fp := BlockMessages.decode_force_propagate({})
	_assert(decoded_empty_fp["epicenter"] == Vector3.ZERO, "FORCE_PROPAGATE decode empty -> epicenter default")
	_assert(decoded_empty_fp["magnitude"] == 0.0, "FORCE_PROPAGATE decode empty -> magnitude default")
	_assert(decoded_empty_fp["hop"] == 0, "FORCE_PROPAGATE decode empty -> hop default")
	_assert(decoded_empty_fp["max_hops"] == 0, "FORCE_PROPAGATE decode empty -> max_hops default")

	# --- DISPLACEMENT_RESULT ---
	var block_id := "test_abc"
	var displaced_position := Vector3(0.5, 0.0, 0.5)
	var hop_count := 3

	var encoded_dr := BlockMessages.encode_displacement_result(block_id, displaced_position, hop_count)

	_assert(encoded_dr.has("block_id"), "DISPLACEMENT_RESULT encoded has block_id key")
	_assert(encoded_dr.has("displaced_position"), "DISPLACEMENT_RESULT encoded has displaced_position key")
	_assert(encoded_dr.has("hop_count"), "DISPLACEMENT_RESULT encoded has hop_count key")
	_assert(encoded_dr["block_id"] == block_id, "DISPLACEMENT_RESULT block_id value correct")
	_assert(encoded_dr["displaced_position"] == displaced_position, "DISPLACEMENT_RESULT displaced_position value correct")
	_assert(encoded_dr["hop_count"] == hop_count, "DISPLACEMENT_RESULT hop_count value correct")

	# Decode roundtrip
	var decoded_dr := BlockMessages.decode_displacement_result(encoded_dr)
	_assert(decoded_dr["block_id"] == block_id, "DISPLACEMENT_RESULT decode block_id roundtrip")
	_assert(decoded_dr["displaced_position"] == displaced_position, "DISPLACEMENT_RESULT decode displaced_position roundtrip")
	_assert(decoded_dr["hop_count"] == hop_count, "DISPLACEMENT_RESULT decode hop_count roundtrip")

	# Decode empty dict returns defaults without crashing
	var decoded_empty_dr := BlockMessages.decode_displacement_result({})
	_assert(decoded_empty_dr["block_id"] == "", "DISPLACEMENT_RESULT decode empty -> block_id default")
	_assert(decoded_empty_dr["displaced_position"] == Vector3.ZERO, "DISPLACEMENT_RESULT decode empty -> displaced_position default")
	_assert(decoded_empty_dr["hop_count"] == 0, "DISPLACEMENT_RESULT decode empty -> hop_count default")

	# Constants are the expected strings
	_assert(BlockMessages.FORCE_PROPAGATE == "force_propagate", "FORCE_PROPAGATE constant is correct string")
	_assert(BlockMessages.DISPLACEMENT_RESULT == "displacement_result", "DISPLACEMENT_RESULT constant is correct string")


# =========================================================================
# Test group 3: Schema validation rejects invalid values
# =========================================================================

func _test_schema_validation_rejects_invalid() -> void:
	_section("Schema Validation — Rejects Invalid Values")

	# Valid block should pass with no errors
	var valid_block := _make_test_block("valid_one")
	BlockPhysicsState.init(valid_block)
	var errors_valid := BlockPhysicsState.validate(valid_block)
	_assert(errors_valid.is_empty(), "validate() returns empty errors for valid init'd block")

	# --- mass out of range ---
	var bad_mass := _make_test_block("bad_mass")
	BlockPhysicsState.init(bad_mass)
	bad_mass.state["mass"] = -5.0
	var errors_mass := BlockPhysicsState.validate(bad_mass)
	_assert(not errors_mass.is_empty(), "validate() returns errors for mass=-5.0")
	var mass_error_mentions_mass := false
	for e in errors_mass:
		if "mass" in e:
			mass_error_mentions_mass = true
	_assert(mass_error_mentions_mass, "mass error message mentions 'mass'")

	# --- damping out of range (above 1.0) ---
	var bad_damping := _make_test_block("bad_damping")
	BlockPhysicsState.init(bad_damping)
	bad_damping.state["damping"] = 2.0
	var errors_damping := BlockPhysicsState.validate(bad_damping)
	_assert(not errors_damping.is_empty(), "validate() returns errors for damping=2.0")
	var damping_error_mentions_damping := false
	for e in errors_damping:
		if "damping" in e:
			damping_error_mentions_damping = true
	_assert(damping_error_mentions_damping, "damping error message mentions 'damping'")

	# --- hop_count negative ---
	var bad_hop := _make_test_block("bad_hop")
	BlockPhysicsState.init(bad_hop)
	bad_hop.state["hop_count"] = -1
	var errors_hop := BlockPhysicsState.validate(bad_hop)
	_assert(not errors_hop.is_empty(), "validate() returns errors for hop_count=-1")
	var hop_error_mentions_hop := false
	for e in errors_hop:
		if "hop_count" in e:
			hop_error_mentions_hop = true
	_assert(hop_error_mentions_hop, "hop_count error message mentions 'hop_count'")

	# --- force_vec wrong type ---
	var bad_force := _make_test_block("bad_force")
	BlockPhysicsState.init(bad_force)
	bad_force.state["force_vec"] = "not_a_vector"
	var errors_force := BlockPhysicsState.validate(bad_force)
	_assert(not errors_force.is_empty(), "validate() returns errors for force_vec='not_a_vector'")
	var force_error_mentions_force := false
	for e in errors_force:
		if "force_vec" in e:
			force_error_mentions_force = true
	_assert(force_error_mentions_force, "force_vec error message mentions 'force_vec'")

	# --- fresh block with empty state — all keys missing ---
	var fresh_block := _make_test_block("fresh_no_init")
	var errors_fresh := BlockPhysicsState.validate(fresh_block)
	_assert(not errors_fresh.is_empty(), "validate() returns errors for block with no physics state")
	_assert(errors_fresh.size() >= 6, "validate() returns at least 6 errors (one per missing key)")


# =========================================================================
# Test group 4: Typed accessors
# =========================================================================

func _test_typed_accessors() -> void:
	_section("Typed Accessors")

	var block := _make_test_block("accessor_test")
	BlockPhysicsState.init(block)

	# set_force_vec / get_force_vec
	var target_force := Vector3(3.0, 0.0, -1.0)
	BlockPhysicsState.set_force_vec(block, target_force)
	_assert(BlockPhysicsState.get_force_vec(block) == target_force, "set/get force_vec roundtrip")

	# set_velocity / get_velocity
	var target_vel := Vector3(0.0, 2.5, 1.0)
	BlockPhysicsState.set_velocity(block, target_vel)
	_assert(BlockPhysicsState.get_velocity(block) == target_vel, "set/get velocity roundtrip")

	# set_mass / get_mass
	BlockPhysicsState.set_mass(block, 3.7)
	_assert(absf(BlockPhysicsState.get_mass(block) - 3.7) < 0.0001, "set/get mass roundtrip")

	# set_damping / get_damping
	BlockPhysicsState.set_damping(block, 0.5)
	_assert(absf(BlockPhysicsState.get_damping(block) - 0.5) < 0.0001, "set/get damping roundtrip")

	# set_hop_count / get_hop_count
	BlockPhysicsState.set_hop_count(block, 7)
	_assert(BlockPhysicsState.get_hop_count(block) == 7, "set/get hop_count roundtrip")

	# set_displaced / is_displaced
	BlockPhysicsState.set_displaced(block, true)
	_assert(BlockPhysicsState.is_displaced(block) == true, "set/is displaced=true roundtrip")

	BlockPhysicsState.set_displaced(block, false)
	_assert(BlockPhysicsState.is_displaced(block) == false, "set/is displaced=false roundtrip")

	# reset() restores all defaults
	BlockPhysicsState.reset(block)
	_assert(BlockPhysicsState.get_force_vec(block) == Vector3.ZERO, "reset clears force_vec to ZERO")
	_assert(BlockPhysicsState.get_velocity(block) == Vector3.ZERO, "reset clears velocity to ZERO")
	_assert(absf(BlockPhysicsState.get_mass(block) - 1.0) < 0.0001, "reset restores mass to 1.0")
	_assert(absf(BlockPhysicsState.get_damping(block) - 0.85) < 0.0001, "reset restores damping to 0.85")
	_assert(BlockPhysicsState.get_hop_count(block) == 0, "reset clears hop_count to 0")
	_assert(BlockPhysicsState.is_displaced(block) == false, "reset clears displaced to false")

	# Getter returns default when key is missing (defensive getter behavior)
	var bare_block := _make_test_block("no_state_block")
	_assert(BlockPhysicsState.get_force_vec(bare_block) == Vector3.ZERO, "get_force_vec returns ZERO when key missing")
	_assert(BlockPhysicsState.get_velocity(bare_block) == Vector3.ZERO, "get_velocity returns ZERO when key missing")
	_assert(absf(BlockPhysicsState.get_mass(bare_block) - 1.0) < 0.0001, "get_mass returns 1.0 when key missing")
	_assert(absf(BlockPhysicsState.get_damping(bare_block) - 0.85) < 0.0001, "get_damping returns 0.85 when key missing")
	_assert(BlockPhysicsState.get_hop_count(bare_block) == 0, "get_hop_count returns 0 when key missing")
	_assert(BlockPhysicsState.is_displaced(bare_block) == false, "is_displaced returns false when key missing")


# =========================================================================
# Test group 5: Registry message integration
# =========================================================================

func _on_message_received(target_block: Block, msg_type: String, data: Dictionary, sender_id: String) -> void:
	_messages_received.append({
		"target": target_block,
		"msg_type": msg_type,
		"data": data,
		"sender_id": sender_id,
	})


func _test_registry_message_integration() -> void:
	_section("Registry Message Integration")

	_registry.clear()
	_messages_received.clear()

	# Connect the signal handler
	_registry.message_received.connect(_on_message_received)

	# Create and register two blocks with peer connection
	var block_a := _make_registered_block("force_source", Vector3(0, 0, 0))
	var block_b := _make_registered_block("force_target", Vector3(2, 0, 0))

	_assert(block_a != null, "block_a registered successfully")
	_assert(block_b != null, "block_b registered successfully")

	# Connect blocks
	var connected := _registry.connect_blocks(block_a.block_id, block_b.block_id)
	_assert(connected, "connect_blocks returns true")
	_assert(block_a.is_connected_to(block_b.block_id), "block_a is connected to block_b")
	_assert(block_b.is_connected_to(block_a.block_id), "block_b is connected to block_a")

	# Send a FORCE_PROPAGATE message to block_b
	var payload := BlockMessages.encode_force_propagate(Vector3.ZERO, 5.0, 0, 3)
	var sent := _registry.send_message(
		block_b.block_id,
		BlockMessages.FORCE_PROPAGATE,
		payload,
		block_a.block_id
	)

	_assert(sent, "send_message returns true for registered target")
	_assert(_messages_received.size() == 1, "exactly 1 message received")

	if _messages_received.size() >= 1:
		var received := _messages_received[0]
		_assert(received["msg_type"] == BlockMessages.FORCE_PROPAGATE,
			"received msg_type is FORCE_PROPAGATE")
		_assert(received["sender_id"] == block_a.block_id,
			"received sender_id matches block_a")
		_assert(received["target"] == block_b,
			"received target is block_b")

		# Decode payload and verify epicenter
		var decoded := BlockMessages.decode_force_propagate(received["data"])
		_assert(decoded["epicenter"] == Vector3.ZERO, "decoded epicenter matches sent value")
		_assert(absf(decoded["magnitude"] - 5.0) < 0.0001, "decoded magnitude matches sent value (5.0)")
		_assert(decoded["hop"] == 0, "decoded hop matches sent value (0)")
		_assert(decoded["max_hops"] == 3, "decoded max_hops matches sent value (3)")

	# Verify send_message returns false for unknown target
	var not_sent := _registry.send_message("nonexistent_id", BlockMessages.FORCE_PROPAGATE, {})
	_assert(not not_sent, "send_message returns false for unknown target")

	# Disconnect signal and cleanup
	_registry.message_received.disconnect(_on_message_received)
	_registry.clear()
