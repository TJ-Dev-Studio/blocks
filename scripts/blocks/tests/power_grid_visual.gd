extends Node3D
## Power Grid Visual Scene — for headless screenshot capture via GAK.
##
## Builds the full 28-block power grid, then stages 3 visual states
## across frames for screenshot capture:
##   Frame 3:  All blocks RED (unpowered)
##   Frame 5:  Generator + transformers GREEN, rest RED (propagating)
##   Frame 8:  All connected blocks GREEN, water tower RED (fully powered)
##
## Capture:
##   npx tsx tools/gak/src/preview-capture.ts godot_project power_grid_visual -r 1280x720 -f 3 -o grid_unpowered.png
##   npx tsx tools/gak/src/preview-capture.ts godot_project power_grid_visual -r 1280x720 -f 5 -o grid_propagating.png
##   npx tsx tools/gak/src/preview-capture.ts godot_project power_grid_visual -r 1280x720 -f 8 -o grid_powered.png

var _registry: BlockRegistry
var _grid_blocks: Dictionary = {}
var _frame := 0


func _ready() -> void:
	_registry = BlockRegistry.new()
	_registry.name = "VisualRegistry"
	add_child(_registry)

	_build_grid()
	_build_all_nodes()
	_set_all_unpowered()


func _process(_delta: float) -> void:
	_frame += 1
	match _frame:
		5:
			_propagate_partial()
		8:
			_propagate_full()
		20:
			get_tree().quit(0)


# =========================================================================
# Grid construction (mirrors test_power_grid.gd layout)
# =========================================================================

func _build_grid() -> void:
	# Generator — top center
	_reg("generator", _box("generator", Vector3(3, 4, 3), Vector3(0, 2, -20), "generator_yellow"))

	# Transformers — middle row
	_reg("trans_n", _box("trans_n", Vector3(2, 3, 2), Vector3(-15, 1.5, -8), "transformer_gray"))
	_reg("trans_s", _box("trans_s", Vector3(2, 3, 2), Vector3(0, 1.5, -8), "transformer_gray"))
	_reg("trans_e", _box("trans_e", Vector3(2, 3, 2), Vector3(15, 1.5, -8), "transformer_gray"))

	# Power lines — thin wires connecting
	for i in range(8):
		var bname := "line_%d" % i
		var x := -14.0 + i * 4.0
		_reg(bname, _wire(bname, Vector3(x, 4.0, -14.0)))

	# Houses — bottom row
	var hx := [-24.0, -14.0, -4.0, 6.0, 16.0, 26.0]
	var hmats := ["house_beige", "house_blue", "house_beige", "house_blue", "house_beige", "house_blue"]
	for i in range(6):
		var bname := "house_%d" % i
		_reg(bname, _box(bname, Vector3(4, 3, 4), Vector3(hx[i], 1.5, 5), hmats[i]))

	# Street lights — in front of houses
	for i in range(8):
		var bname := "light_%d" % i
		var x := -18.0 + i * 5.0
		_reg(bname, _cyl(bname, Vector3(0.2, 4, 0), Vector3(x, 2, 12), "light_pole"))

	# Control tower — behind generator
	var ct := Block.new()
	ct.block_name = "control"
	ct.category = BlockCategories.TRIGGER_CAT
	ct.collision_shape = BlockCategories.SHAPE_BOX
	ct.collision_size = Vector3(2, 5, 2)
	ct.position = Vector3(-8, 2.5, -24)
	ct.interaction = BlockCategories.INTERACT_TRIGGER
	ct.collision_layer = CollisionLayers.TRIGGER
	ct.trigger_radius = 10.0
	ct.material_id = "blue_metal"
	_reg("control", ct)

	# Water tower — far right, isolated
	_reg("water", _cyl("water", Vector3(2, 6, 0), Vector3(35, 3, -5), "metal_light"))

	# --- Connections ---
	var gen := "generator"
	_conn(gen, "trans_n")
	_conn(gen, "trans_s")
	_conn(gen, "trans_e")
	for i in range(3):
		_conn(gen, "line_%d" % i)
	for i in range(3, 6):
		_conn("trans_n", "line_%d" % i)
	for i in range(6, 8):
		_conn("trans_s", "line_%d" % i)

	_conn("trans_n", "house_0")
	_conn("trans_n", "house_1")
	_conn("trans_s", "house_2")
	_conn("trans_s", "house_3")
	_conn("trans_e", "house_4")
	_conn("trans_e", "house_5")

	_conn("house_0", "light_0")
	_conn("house_1", "light_1")
	_conn("house_1", "light_2")
	_conn("house_2", "light_3")
	_conn("house_3", "light_4")
	_conn("house_4", "light_5")
	_conn("house_4", "light_6")
	_conn("house_5", "light_7")

	_conn("control", gen)


func _build_all_nodes() -> void:
	for bname in _grid_blocks:
		var block: Block = _grid_blocks[bname]
		BlockBuilder.build(block, self)


func _set_all_unpowered() -> void:
	for bname in _grid_blocks:
		BlockVisuals.set_powered(_grid_blocks[bname], false)


func _propagate_partial() -> void:
	for bname in ["generator", "trans_n", "trans_s", "trans_e"]:
		if _grid_blocks.has(bname):
			BlockVisuals.set_powered(_grid_blocks[bname], true)


func _propagate_full() -> void:
	for bname in _grid_blocks:
		if bname != "water":
			BlockVisuals.set_powered(_grid_blocks[bname], true)


# =========================================================================
# Helpers
# =========================================================================

func _box(bname: String, sz: Vector3, pos: Vector3, mat: String) -> Block:
	var b := Block.new()
	b.block_name = bname
	b.category = BlockCategories.STRUCTURE
	b.collision_shape = BlockCategories.SHAPE_BOX
	b.collision_size = sz
	b.position = pos
	b.interaction = BlockCategories.INTERACT_SOLID
	b.material_id = mat
	b.collision_layer = CollisionLayers.WORLD
	b.cast_shadow = true
	return b


func _cyl(bname: String, sz: Vector3, pos: Vector3, mat: String) -> Block:
	var b := Block.new()
	b.block_name = bname
	b.category = BlockCategories.EFFECT
	b.collision_shape = BlockCategories.SHAPE_CYLINDER
	b.collision_size = sz
	b.position = pos
	b.interaction = BlockCategories.INTERACT_SOLID
	b.material_id = mat
	b.collision_layer = CollisionLayers.WORLD
	b.cast_shadow = true
	return b


func _wire(bname: String, pos: Vector3) -> Block:
	var b := Block.new()
	b.block_name = bname
	b.category = BlockCategories.PROP
	b.collision_shape = BlockCategories.SHAPE_BOX
	b.collision_size = Vector3(0.15, 0.15, 6.0)
	b.position = pos
	b.interaction = BlockCategories.INTERACT_SOLID
	b.material_id = "wire_copper"
	b.collision_layer = CollisionLayers.WORLD
	b.server_collidable = false
	return b


func _reg(bname: String, block: Block) -> void:
	block.ensure_id()
	_registry.register(block)
	_grid_blocks[bname] = block


func _conn(a_name: String, b_name: String) -> void:
	var a: Block = _grid_blocks[a_name]
	var b: Block = _grid_blocks[b_name]
	_registry.connect_blocks(a.block_id, b.block_id)
