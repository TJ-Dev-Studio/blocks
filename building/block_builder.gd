class_name BlockBuilder
## Factory that converts a Block definition into a Godot Node3D subtree.
##
## Takes a validated Block → produces Node3D with collision body + visual mesh.
## Handles StaticBody3D vs Area3D selection, collision layer bitmasks,
## shape creation, material application, and metadata tagging.

## Build a Node3D subtree from a Block definition and attach to parent.
## Returns the root Node3D.
static func build(block: Block, parent: Node3D) -> Node3D:
	# Skip subdivided parents — they've been replaced by child blocks
	if not block.child_lod_ids.is_empty() and not block.active:
		return null

	var root := Node3D.new()
	root.name = block.block_name if not block.block_name.is_empty() else block.block_id
	root.position = block.position
	root.rotation.y = block.rotation_y
	if not is_equal_approx(block.scale_factor, 1.0):
		root.scale = Vector3.ONE * block.scale_factor

	parent.add_child(root)

	# Collision
	if block.collision_shape != BlockCategories.SHAPE_NONE \
			and block.interaction != BlockCategories.INTERACT_NONE:
		_build_collision(root, block)

	# Visual
	if block.mesh_type == 0 and block.collision_shape != BlockCategories.SHAPE_NONE:
		_build_primitive_visual(root, block)
	elif block.mesh_type == 1 and not block.scene_path.is_empty():
		_build_scene_visual(root, block)
	elif block.mesh_type == 2 and not block.scene_path.is_empty():
		_build_glb_visual(root, block)

	# Light
	if not block.light_config.is_empty():
		_build_light(root, block)

	# Tag with block_id for reverse lookup
	root.set_meta("block_id", block.block_id)

	# Store reference
	block.node = root

	# Initialize neuron if present
	if block.neuron != null:
		block.neuron.activate()

	return root


## Build an OmniLight3D or SpotLight3D child from block.light_config.
## Adds the light node to a group named "block_{group}" for day cycle discovery.
static func _build_light(root: Node3D, block: Block) -> void:
	var config: Dictionary = block.light_config
	var light_type: String = config.get("type", "omni")
	var light: Light3D

	if light_type == "spot":
		var spot := SpotLight3D.new()
		spot.spot_angle = config.get("spot_angle", 45.0)
		light = spot
	else:
		light = OmniLight3D.new()

	light.name = "BlockLight"

	# Color — use config color or fall back to material palette color
	if config.has("color"):
		light.light_color = config["color"]
	else:
		light.light_color = BlockMaterials.get_color(block.material_id)

	light.light_energy = config.get("energy", 1.0)

	if light is OmniLight3D:
		light.omni_range = config.get("range", 4.0)
	elif light is SpotLight3D:
		(light as SpotLight3D).spot_range = config.get("range", 4.0)

	# Shadows off by default (expensive on mobile)
	light.shadow_enabled = config.get("shadow", false)

	# Position at collision offset (same as mesh center)
	light.position = block.collision_offset

	# Add to group for day cycle discovery
	var group_name: String = "block_%s" % config.get("group", "steady")
	light.add_to_group(group_name)

	# Store base energy as metadata for animation systems
	light.set_meta("base_energy", light.light_energy)

	root.add_child(light)


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
			cyl.radial_segments = 8  # 8 is enough for stylized look; saves 33% verts vs 12
			mi.mesh = cyl
		BlockCategories.SHAPE_CAPSULE:
			var cap := CapsuleMesh.new()
			cap.radius = dims.x
			cap.height = dims.y
			mi.mesh = cap
		BlockCategories.SHAPE_SPHERE:
			var sphere := SphereMesh.new()
			sphere.radius = dims.x
			sphere.height = dims.y
			mi.mesh = sphere
		BlockCategories.SHAPE_DOME:
			var dome := SphereMesh.new()
			dome.radius = dims.x
			dome.height = dims.y
			dome.is_hemisphere = true
			mi.mesh = dome
		BlockCategories.SHAPE_RAMP:
			mi.mesh = _make_ramp_mesh(dims)
		BlockCategories.SHAPE_CONE:
			var cone := CylinderMesh.new()
			cone.top_radius = 0.0
			cone.bottom_radius = dims.x
			cone.height = dims.y
			cone.radial_segments = 8
			mi.mesh = cone
		BlockCategories.SHAPE_TORUS:
			var torus := TorusMesh.new()
			torus.inner_radius = dims.x
			torus.outer_radius = dims.y
			torus.rings = 16
			torus.ring_segments = 8
			mi.mesh = torus
		BlockCategories.SHAPE_ARCH:
			# Load pre-generated half-torus mesh (STATE.md: no runtime SurfaceTool)
			var arch_key := "arch_%d_%d" % [int(dims.x * 100), int(dims.y * 100)]
			var arch_path := "res://assets/meshes/organic/%s.tres" % arch_key
			var arch_mesh: Mesh = load(arch_path) as Mesh
			if arch_mesh:
				mi.mesh = arch_mesh
			else:
				push_warning("[BlockBuilder] Arch mesh not found: %s — fallback to torus" % arch_path)
				var torus_fallback := TorusMesh.new()
				torus_fallback.inner_radius = dims.x
				torus_fallback.outer_radius = dims.y
				torus_fallback.rings = 16
				torus_fallback.ring_segments = 8
				mi.mesh = torus_fallback
		BlockCategories.SHAPE_ROCK:
			# Load pre-generated noise-displaced sphere (STATE.md: no runtime SurfaceTool)
			# size convention: (radius, height, seed) — seed is int in z component
			var rock_seed := int(dims.z) if dims.z > 0.0 else 0
			var rock_radius := int(dims.x * 100)
			var rock_key := "rock_s%d_r%d" % [rock_seed, rock_radius]
			var rock_path := "res://assets/meshes/organic/%s.tres" % rock_key
			var rock_mesh: Mesh = load(rock_path) as Mesh
			if rock_mesh:
				mi.mesh = rock_mesh
			else:
				push_warning("[BlockBuilder] Rock mesh not found: %s — fallback to sphere" % rock_path)
				var sphere_fallback := SphereMesh.new()
				sphere_fallback.radius = dims.x
				sphere_fallback.height = dims.y
				mi.mesh = sphere_fallback

	# Position mesh at collision offset (visual matches collision)
	mi.position = block.collision_offset

	# Multi-material: apply per-surface materials and skip single-material dispatch
	if not block.materials_list.is_empty():
		_apply_multi_material(mi, block)
		if not block.cast_shadow:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = 100.0
		mi.visibility_range_end_margin = 10.0
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		root.add_child(mi)
		return

	# Material — four-tier dispatch based on block override fields:
	# 1. Procedural (material_type_id set) → uber-shader with material_type int uniform
	# 2. Custom shader (shader_path set) → raw ShaderMaterial from path
	# 3. Override (material_params or color_tint) → override cache
	# 4. Base → base palette cache
	if not block.material_type_id.is_empty():
		# Procedural material — uber-shader with material_type integer
		# Highest priority: procedural wins over shader_path, material_params, and tint
		mi.material_override = BlockMaterials.get_procedural_material(
				block.material_type_id, block.material_id)
	elif not block.shader_path.is_empty():
		# Custom shader takes second priority — used for special visual effects
		var shader: Shader = load(block.shader_path) as Shader
		if shader:
			var shader_mat := ShaderMaterial.new()
			shader_mat.shader = shader
			mi.material_override = shader_mat
	elif not block.material_params.is_empty() or block.color_tint != Color.WHITE:
		# Has overrides — merge into single get_material_with_overrides call
		var params: Dictionary = block.material_params.duplicate()
		if block.color_tint != Color.WHITE:
			# Tint applied via tint_color uniform only — shader handles albedo * tint_color
			params["tint_color"] = block.color_tint
		mi.material_override = BlockMaterials.get_material_with_overrides(
				block.material_id, params)
	else:
		# Default — base cache (no overrides)
		mi.material_override = BlockMaterials.get_material(block.material_id)

	# Shadow
	if not block.cast_shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# Distance culling for un-merged blocks (large assemblies like terrain/forest).
	# Merged assemblies (<40m extent) use frustum culling only — no vis range needed.
	# 100m keeps terrain ground visible across most of the 200m world while still
	# culling blocks at the far edges. The mesh merge system (3350→264 draws)
	# handles the main draw call reduction; this is supplemental GPU savings.
	mi.visibility_range_end = 100.0
	mi.visibility_range_end_margin = 10.0
	mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED

	root.add_child(mi)


## Build custom scene visual.
static func _build_scene_visual(root: Node3D, block: Block) -> void:
	var scene: PackedScene = load(block.scene_path) as PackedScene
	if scene:
		var instance: Node = scene.instantiate()
		instance.name = "SceneVisual"
		root.add_child(instance)
	else:
		push_warning("[BlockBuilder] Missing scene: %s — showing placeholder" % block.scene_path)
		_build_placeholder(root, block)


## GLB PackedScene cache — keyed by path, cleared on zone unload.
static var _glb_cache: Dictionary = {}


## Clear GLB cache (call on zone unload alongside BlockMaterials.clear_override_cache).
static func clear_glb_cache() -> void:
	_glb_cache.clear()


## Build GLB visual from pre-imported .glb PackedScene.
## Collision is handled independently by _build_collision() — fully decoupled (GLB-02).
static func _build_glb_visual(root: Node3D, block: Block) -> void:
	var scene: PackedScene
	if _glb_cache.has(block.scene_path):
		scene = _glb_cache[block.scene_path]
	else:
		scene = load(block.scene_path) as PackedScene
		if scene == null:
			push_warning("[BlockBuilder] Missing GLB: %s — showing placeholder" % block.scene_path)
			_build_placeholder(root, block)
			return
		_glb_cache[block.scene_path] = scene

	var instance: Node = scene.instantiate()
	if instance == null:
		push_warning("[BlockBuilder] Failed to instantiate GLB: %s" % block.scene_path)
		return
	instance.name = "GlbVisual"
	root.add_child(instance)
	_apply_glb_materials(instance, block)


## Apply material overrides to all MeshInstance3D nodes in a GLB instance.
static func _apply_glb_materials(instance: Node, block: Block) -> void:
	var mesh_instances: Array = instance.find_children("*", "MeshInstance3D", true, false)
	if mesh_instances.is_empty() and instance is MeshInstance3D:
		mesh_instances = [instance]
	for mi: Node in mesh_instances:
		if not mi is MeshInstance3D:
			continue
		var mesh_inst: MeshInstance3D = mi as MeshInstance3D
		if block.materials_list.is_empty():
			# Single material: apply palette + overrides via existing pipeline
			var params: Dictionary = block.material_params.duplicate()
			if block.color_tint != Color.WHITE:
				params["tint_color"] = block.color_tint
			if not params.is_empty():
				mesh_inst.material_override = BlockMaterials.get_material_with_overrides(
					block.material_id, params)
			elif not block.material_id.is_empty() and block.material_id != "default":
				mesh_inst.material_override = BlockMaterials.get_material(block.material_id)
			# else: leave GLB's own materials intact
		else:
			_apply_multi_material(mesh_inst, block)


## Apply visual.materials array as per-surface material overrides.
static func _apply_multi_material(mi: MeshInstance3D, block: Block) -> void:
	var surface_count: int = mi.get_surface_override_material_count()
	for i in range(mini(block.materials_list.size(), surface_count)):
		var slot: Dictionary = block.materials_list[i]
		var palette_key: String = slot.get("palette_key", block.material_id)
		var params: Dictionary = slot.get("params", {})
		var mat: Material
		if not params.is_empty():
			mat = BlockMaterials.get_material_with_overrides(palette_key, params)
		else:
			mat = BlockMaterials.get_material(palette_key)
		mi.set_surface_override_material(i, mat)


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
		BlockCategories.SHAPE_SPHERE:
			var sph := SphereShape3D.new()
			sph.radius = block.collision_size.x
			return sph
		BlockCategories.SHAPE_DOME:
			var dome_col := SphereShape3D.new()
			dome_col.radius = block.collision_size.x
			return dome_col
		BlockCategories.SHAPE_RAMP:
			return _make_ramp_collision(block.collision_size)
		BlockCategories.SHAPE_CONE:
			var cyl := CylinderShape3D.new()
			cyl.radius = block.collision_size.x
			cyl.height = block.collision_size.y
			return cyl
		BlockCategories.SHAPE_TORUS:
			var cyl := CylinderShape3D.new()
			cyl.radius = block.collision_size.y  # outer_radius
			var ring_diameter := (block.collision_size.y - block.collision_size.x) * 2.0
			cyl.height = ring_diameter
			return cyl
		BlockCategories.SHAPE_ARCH:
			var cyl := CylinderShape3D.new()
			cyl.radius = block.collision_size.y  # outer_radius
			var ring_diameter := (block.collision_size.y - block.collision_size.x) * 2.0
			cyl.height = ring_diameter
			return cyl
		BlockCategories.SHAPE_ROCK:
			var cyl := CylinderShape3D.new()
			cyl.radius = block.collision_size.x
			cyl.height = block.collision_size.y
			return cyl
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


## Create a ConvexPolygonShape3D wedge for ramp collision.
## size = [width, height, depth]. Ramp rises from Y=-H/2 at +Z to Y=+H/2 at -Z.
## Players walk up the slope from the low (+Z) end to the high (-Z) end.
static func _make_ramp_collision(size: Vector3) -> ConvexPolygonShape3D:
	var hw := size.x / 2.0  # half width
	var hh := size.y / 2.0  # half height
	var hd := size.z / 2.0  # half depth
	var shape := ConvexPolygonShape3D.new()
	shape.points = PackedVector3Array([
		# Bottom face (rectangle at Y = -hh)
		Vector3(-hw, -hh, -hd),
		Vector3( hw, -hh, -hd),
		Vector3( hw, -hh,  hd),
		Vector3(-hw, -hh,  hd),
		# Top edge (line at Y = +hh, Z = -hd — the high end)
		Vector3(-hw,  hh, -hd),
		Vector3( hw,  hh, -hd),
	])
	return shape


## Create an ArrayMesh wedge for ramp visual.
## Same geometry as the collision shape — a triangular prism (wedge).
static func _make_ramp_mesh(size: Vector3) -> ArrayMesh:
	var hw := size.x / 2.0
	var hh := size.y / 2.0
	var hd := size.z / 2.0

	# 6 vertices of the wedge
	var v0 := Vector3(-hw, -hh, -hd)  # back-left bottom
	var v1 := Vector3( hw, -hh, -hd)  # back-right bottom
	var v2 := Vector3( hw, -hh,  hd)  # front-right bottom
	var v3 := Vector3(-hw, -hh,  hd)  # front-left bottom
	var v4 := Vector3(-hw,  hh, -hd)  # back-left top
	var v5 := Vector3( hw,  hh, -hd)  # back-right top

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Bottom face (normal down)
	_add_tri(st, v0, v2, v1, Vector3.DOWN)
	_add_tri(st, v0, v3, v2, Vector3.DOWN)

	# Back face (normal -Z)
	_add_tri(st, v0, v1, v5, Vector3.BACK)
	_add_tri(st, v0, v5, v4, Vector3.BACK)

	# Ramp surface (slope from front-bottom to back-top)
	var ramp_normal := Vector3(0, size.z, size.y).normalized()
	_add_tri(st, v3, v5, v2, ramp_normal)
	_add_tri(st, v3, v4, v5, ramp_normal)

	# Left side triangle (normal -X)
	_add_tri(st, v0, v4, v3, Vector3.LEFT)

	# Right side triangle (normal +X)
	_add_tri(st, v1, v2, v5, Vector3.RIGHT)

	return st.commit()


## Helper: add a triangle with explicit normal.
static func _add_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3) -> void:
	st.set_normal(n)
	st.add_vertex(a)
	st.set_normal(n)
	st.add_vertex(b)
	st.set_normal(n)
	st.add_vertex(c)


## Build a bright magenta placeholder box for missing/broken assets.
## Like a browser's broken-image icon — shows something went wrong without crashing.
static func _build_placeholder(root: Node3D, block: Block) -> void:
	var mi := MeshInstance3D.new()
	mi.name = "Placeholder"
	var box := BoxMesh.new()
	var sz: Vector3 = block.collision_size if block.collision_size.length() > 0.01 else Vector3(0.5, 0.5, 0.5)
	box.size = sz
	mi.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.0, 1.0, 0.7)  # Bright magenta
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.0, 1.0)
	mat.emission_energy_multiplier = 2.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	root.add_child(mi)
