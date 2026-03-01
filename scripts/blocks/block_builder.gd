class_name BlockBuilder
## Factory that converts a Block definition into a Godot Node3D subtree.
##
## Takes a validated Block → produces Node3D with collision body + visual mesh.
## Handles StaticBody3D vs Area3D selection, collision layer bitmasks,
## shape creation, material application, and metadata tagging.

## Build a Node3D subtree from a Block definition and attach to parent.
## Returns the root Node3D.
static func build(block: Block, parent: Node3D) -> Node3D:
	var root := Node3D.new()
	root.name = block.block_name if not block.block_name.is_empty() else block.block_id
	root.position = block.position
	root.rotation.y = block.rotation_y
	if not is_equal_approx(block.scale_factor, 1.0):
		root.scale = Vector3.ONE * block.scale_factor

	parent.add_child(root)

	# Collision
	if block.collision_shape != BlockCategories.SHAPE_NONE:
		_build_collision(root, block)

	# Visual
	if block.mesh_type == 0 and block.collision_shape != BlockCategories.SHAPE_NONE:
		_build_primitive_visual(root, block)
	elif block.mesh_type == 1 and not block.scene_path.is_empty():
		_build_scene_visual(root, block)

	# Tag with block_id for reverse lookup
	root.set_meta("block_id", block.block_id)

	# Store reference
	block.node = root

	return root


## Build collision subtree.
static func _build_collision(root: Node3D, block: Block) -> void:
	var is_trigger := block.interaction == BlockCategories.INTERACT_TRIGGER
	var body: Node3D

	if is_trigger:
		var area := Area3D.new()
		area.name = "TriggerArea"
		area.collision_layer = CollisionLayers.to_bit(block.collision_layer)
		area.collision_mask = _compute_mask(block)
		if area.collision_mask == 0:
			# Triggers should at least detect players by default
			area.collision_mask = CollisionLayers.trigger_mask()
		body = area
	else:
		var static_body := StaticBody3D.new()
		static_body.name = "Body"
		static_body.collision_layer = CollisionLayers.to_bit(block.collision_layer)
		static_body.collision_mask = _compute_mask(block)
		body = static_body

	var col := CollisionShape3D.new()
	col.name = "Col"
	col.shape = _make_shape(block)
	col.position = block.collision_offset

	body.add_child(col)
	root.add_child(body)


## Build primitive mesh.
static func _build_primitive_visual(root: Node3D, block: Block) -> void:
	var dims := block.mesh_size if block.mesh_size != Vector3.ZERO else block.collision_size
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"

	match block.collision_shape:
		BlockCategories.SHAPE_BOX:
			var box_mesh := BoxMesh.new()
			box_mesh.size = dims
			mi.mesh = box_mesh
		BlockCategories.SHAPE_CYLINDER:
			var cyl := CylinderMesh.new()
			cyl.top_radius = dims.x
			cyl.bottom_radius = dims.x
			cyl.height = dims.y
			cyl.radial_segments = 12
			mi.mesh = cyl
		BlockCategories.SHAPE_CAPSULE:
			var cap := CapsuleMesh.new()
			cap.radius = dims.x
			cap.height = dims.y
			mi.mesh = cap

	# Position mesh at collision offset (visual matches collision)
	mi.position = block.collision_offset

	# Material
	if not block.shader_path.is_empty():
		var shader: Shader = load(block.shader_path) as Shader
		if shader:
			var shader_mat := ShaderMaterial.new()
			shader_mat.shader = shader
			mi.material_override = shader_mat
	else:
		mi.material_override = BlockMaterials.get_material(block.material_id)

	# Shadow
	if not block.cast_shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	root.add_child(mi)


## Build custom scene visual.
static func _build_scene_visual(root: Node3D, block: Block) -> void:
	var scene: PackedScene = load(block.scene_path) as PackedScene
	if scene:
		var instance: Node = scene.instantiate()
		instance.name = "SceneVisual"
		root.add_child(instance)
	else:
		push_warning("[BlockBuilder] Failed to load scene: %s" % block.scene_path)


## Create a Shape3D from block spec.
static func _make_shape(block: Block) -> Shape3D:
	match block.collision_shape:
		BlockCategories.SHAPE_BOX:
			var box := BoxShape3D.new()
			box.size = block.collision_size
			return box
		BlockCategories.SHAPE_CYLINDER:
			var cyl := CylinderShape3D.new()
			cyl.radius = block.collision_size.x
			cyl.height = block.collision_size.y
			return cyl
		BlockCategories.SHAPE_CAPSULE:
			var cap := CapsuleShape3D.new()
			cap.radius = block.collision_size.x
			cap.height = block.collision_size.y
			return cap
	# Fallback
	var fallback := BoxShape3D.new()
	fallback.size = Vector3.ONE
	return fallback


## Compute collision mask bitmask from block's mask_layers array.
static func _compute_mask(block: Block) -> int:
	if block.collision_mask_layers.is_empty():
		return 0
	var mask := 0
	for layer in block.collision_mask_layers:
		mask |= CollisionLayers.to_bit(layer)
	return mask
