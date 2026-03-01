extends Node3D
## Cellular Visual Scene — for headless screenshot capture via GAK.
##
## Demonstrates cellular division, amoeba movement, and LOD adaptation
## across frames for screenshot capture:
##   Frame 3:  Single 4x4x4 cell (neutral)
##   Frame 5:  Octree division → 8 children (2x2x2 each), dividing emission
##   Frame 8:  Amoeba start — 8-block organism, green membrane
##   Frame 11: Amoeba mid-stride — front subdivided, rear merging
##   Frame 14: LOD comparison — 3 copies at LOD 0, 1, 2 side by side
##
## Capture:
##   npx tsx tools/gak/src/preview-capture.ts godot_project cellular_visual -r 1280x720 -f 3 -o cell_single.png
##   npx tsx tools/gak/src/preview-capture.ts godot_project cellular_visual -r 1280x720 -f 5 -o cell_octree.png
##   npx tsx tools/gak/src/preview-capture.ts godot_project cellular_visual -r 1280x720 -f 8 -o cell_amoeba_start.png
##   npx tsx tools/gak/src/preview-capture.ts godot_project cellular_visual -r 1280x720 -f 11 -o cell_amoeba_stride.png
##   npx tsx tools/gak/src/preview-capture.ts godot_project cellular_visual -r 1280x720 -f 14 -o cell_lod_compare.png

var _registry: BlockRegistry
var _frame := 0

# Stage tracking
var _cell_block: Block
var _octree_children: Array[Block] = []
var _amoeba_cells: Array[Block] = []
var _lod_roots: Array[Block] = []

# Regions for camera
const CELL_POS := Vector3(0, 2, 0)
const OCTREE_POS := Vector3(0, 2, 0)
const AMOEBA_POS := Vector3(20, 2, 0)
const LOD_POS := Vector3(-20, 2, 0)


func _ready() -> void:
	_registry = BlockRegistry.new()
	_registry.name = "CellularVisualRegistry"
	add_child(_registry)

	# Camera
	var cam := Camera3D.new()
	cam.name = "Camera"
	cam.position = Vector3(0, 25, 35)
	cam.rotation_degrees = Vector3(-30, 0, 0)
	add_child(cam)

	# Directional light
	var light := DirectionalLight3D.new()
	light.name = "Sun"
	light.rotation_degrees = Vector3(-45, 30, 0)
	light.shadow_enabled = true
	add_child(light)

	# Ground plane
	var ground := _make_ground()
	add_child(ground)

	# Build Stage 1: Single cell
	_build_single_cell()


func _process(_delta: float) -> void:
	_frame += 1
	match _frame:
		5:
			_stage_octree_division()
		8:
			_stage_amoeba_start()
		11:
			_stage_amoeba_stride()
		14:
			_stage_lod_compare()
		25:
			get_tree().quit(0)


# =========================================================================
# Stage 1: Single cell (Frame 3)
# =========================================================================

func _build_single_cell() -> void:
	_cell_block = _make_cell("origin_cell", Vector3(4, 4, 4), CELL_POS, "cell_membrane")
	_cell_block.ensure_id()
	_registry.register(_cell_block)
	BlockBuilder.build(_cell_block, self)
	BlockVisuals.set_emission(_cell_block, Color(0.2, 0.8, 0.3), 1.0)


# =========================================================================
# Stage 2: Octree division (Frame 5)
# =========================================================================

func _stage_octree_division() -> void:
	# Remove single cell visual
	if _cell_block.node:
		_cell_block.node.queue_free()

	# Subdivide into 8 children
	_octree_children = _registry.subdivide_block(_cell_block.block_id, -1)

	# Build and style each child
	for ch in _octree_children:
		BlockBuilder.build(ch, self)
		BlockVisuals.set_dividing(ch)


# =========================================================================
# Stage 3: Amoeba start (Frame 8)
# =========================================================================

func _stage_amoeba_start() -> void:
	# Clear octree visuals
	for ch in _octree_children:
		if ch.node:
			ch.node.queue_free()

	# Build 8-block amoeba at AMOEBA_POS
	for x in [0, 1]:
		for y in [0, 1]:
			for z in [0, 1]:
				var pos := AMOEBA_POS + Vector3(x * 2.5 - 1.25, y * 2.5 - 1.25, z * 2.5 - 1.25)
				var mat := "cell_active" if x == 1 else "cell_cytoplasm"
				var cell := _make_cell("amoeba_%d%d%d" % [x, y, z], Vector3(2, 2, 2), pos, mat)
				if x == 1:
					cell.tags = PackedStringArray(["front"])
				else:
					cell.tags = PackedStringArray(["rear"])
				cell.ensure_id()
				_registry.register(cell)
				BlockBuilder.build(cell, self)
				BlockVisuals.set_emission(cell, Color(0.2, 0.8, 0.3), 0.8)
				_amoeba_cells.append(cell)

	# Connect all as mesh
	for i in range(_amoeba_cells.size()):
		for j in range(i + 1, _amoeba_cells.size()):
			_registry.connect_blocks(_amoeba_cells[i].block_id, _amoeba_cells[j].block_id)


# =========================================================================
# Stage 4: Amoeba mid-stride (Frame 11)
# =========================================================================

func _stage_amoeba_stride() -> void:
	# Front cells subdivide
	var front_cells: Array[Block] = []
	for cell in _amoeba_cells:
		if "front" in cell.tags:
			front_cells.append(cell)

	var new_cells: Array[Block] = []
	for fc in front_cells:
		if fc.node:
			fc.node.queue_free()
		var children := _registry.subdivide_block(fc.block_id, 0)
		for ch in children:
			BlockBuilder.build(ch, self)
			BlockVisuals.set_dividing(ch)
			new_cells.append(ch)

	# Rear cells get merge emission
	for cell in _amoeba_cells:
		if "rear" in cell.tags and cell.active:
			BlockVisuals.set_merged(cell)


# =========================================================================
# Stage 5: LOD comparison (Frame 14)
# =========================================================================

func _stage_lod_compare() -> void:
	# Build 3 copies of a structure at different LOD levels
	var offsets := [LOD_POS, LOD_POS + Vector3(0, 0, -12), LOD_POS + Vector3(0, 0, -24)]
	var labels := ["LOD 0", "LOD 1", "LOD 2"]

	for level in range(3):
		var root := _make_cell("lod%d_root" % level, Vector3(4, 4, 4), offsets[level], "cell_nucleus")
		root.dna = {"axis_preference": 0}
		root.ensure_id()
		_registry.register(root)
		_lod_roots.append(root)

		if level == 0:
			# Single block
			BlockBuilder.build(root, self)
			BlockVisuals.set_emission(root, Color(0.3, 0.2, 0.5), 1.0)
		elif level == 1:
			# Subdivide once → 2 blocks
			var children := _registry.subdivide_block(root.block_id, 0)
			for ch in children:
				BlockBuilder.build(ch, self)
				BlockVisuals.set_emission(ch, Color(0.4, 0.3, 0.6), 1.5)
		else:
			# Subdivide twice → 4 blocks
			var l1 := _registry.subdivide_block(root.block_id, 0)
			for ch in l1:
				var l2 := _registry.subdivide_block(ch.block_id, 0)
				for grandchild in l2:
					BlockBuilder.build(grandchild, self)
					BlockVisuals.set_emission(grandchild, Color(0.5, 0.4, 0.7), 2.0)


# =========================================================================
# Helpers
# =========================================================================

func _make_cell(bname: String, sz: Vector3, pos: Vector3, mat: String) -> Block:
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
	b.min_size = Vector3(0.1, 0.1, 0.1)
	return b


func _make_ground() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "Ground"
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(100, 80)
	mi.mesh = mesh
	mi.position = Vector3(0, -0.5, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.12, 0.12, 0.15)
	mi.material_override = mat
	return mi
