class_name BlockShapeGen
## Pre-generates organic shape meshes (arch, rock) as .tres files.
## Run generate_all() from the editor console or a headless runner script to
## regenerate meshes. NOT called at runtime — meshes are loaded from .tres.
##
## Usage (headless):
##   godot --headless --path godot_project --script res://addons/blocks/building/run_shape_gen.gd

const _BlockMeshModifiers = preload("res://addons/blocks/building/block_mesh_modifiers.gd")


## Make a half-torus (arch) ArrayMesh.
## inner_r: inner radius of the tube centre path
## outer_r: outer radius of the tube centre path
## ring_segs: cross-section resolution (tube radial subdivisions)
## arc_segs: arc resolution (how many quads around the 180-degree arc)
static func make_arch_mesh(inner_r: float, outer_r: float,
		ring_segs: int = 8, arc_segs: int = 16) -> ArrayMesh:
	var tube_r := (outer_r - inner_r) * 0.5
	var mid_r  := inner_r + tube_r

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for i: int in range(arc_segs):
		var a0 := PI * float(i) / float(arc_segs)        # arc angle start (0..PI)
		var a1 := PI * float(i + 1) / float(arc_segs)    # arc angle end

		for j: int in range(ring_segs):
			var b0 := TAU * float(j) / float(ring_segs)       # ring angle start
			var b1 := TAU * float(j + 1) / float(ring_segs)   # ring angle end

			var v0 := _torus_vertex(mid_r, tube_r, a0, b0)
			var v1 := _torus_vertex(mid_r, tube_r, a1, b0)
			var v2 := _torus_vertex(mid_r, tube_r, a1, b1)
			var v3 := _torus_vertex(mid_r, tube_r, a0, b1)

			# Front face — CCW winding (outward normals)
			st.add_vertex(v0)
			st.add_vertex(v1)
			st.add_vertex(v2)

			st.add_vertex(v0)
			st.add_vertex(v2)
			st.add_vertex(v3)

			# Back face — CW winding (inward normals, visible from inside)
			st.add_vertex(v2)
			st.add_vertex(v1)
			st.add_vertex(v0)

			st.add_vertex(v3)
			st.add_vertex(v2)
			st.add_vertex(v0)

	st.generate_normals()
	return st.commit()


## Make a noise-displaced sphere (rock) ArrayMesh.
## radius: base sphere radius
## seed_val: deterministic displacement seed (different seeds = different rock shapes)
## radial_segments / ring_segments: sphere tessellation
static func make_rock_mesh(radius: float, seed_val: int,
		radial_segments: int = 12, ring_segments: int = 8) -> ArrayMesh:
	# 1. Build a SphereMesh at the right resolution
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = radial_segments
	sphere.rings = ring_segments

	# 2. Convert SphereMesh to ArrayMesh via SurfaceTool
	var st := SurfaceTool.new()
	st.append_from(sphere, 0, Transform3D.IDENTITY)
	var array_mesh: ArrayMesh = st.commit()

	# 3. Apply noise displacement using existing BlockMeshModifiers pattern
	var mi_temp := MeshInstance3D.new()
	mi_temp.mesh = array_mesh
	_BlockMeshModifiers.apply_noise(mi_temp, radius * 0.25, 2.5, seed_val)

	return mi_temp.mesh as ArrayMesh


## Generate all organic mesh .tres files and save to res://assets/meshes/organic/.
## Call once from editor or headless runner — not at runtime.
static func generate_all() -> void:
	var base_path := "res://assets/meshes/organic"

	# 3 arch sizes: inner_r, outer_r → filename suffix {inner*100}_{outer*100}
	var arch_sizes: Array[Array] = [
		[0.4, 0.8],
		[0.6, 1.2],
		[0.8, 1.6],
	]
	for spec: Array in arch_sizes:
		var inner: float = spec[0]
		var outer: float = spec[1]
		var mesh: ArrayMesh = make_arch_mesh(inner, outer)
		var path := "%s/arch_%d_%d.tres" % [base_path, int(inner * 100), int(outer * 100)]
		var err := ResourceSaver.save(mesh, path)
		if err == OK:
			print("[BlockShapeGen] Saved: %s" % path)
		else:
			push_error("[BlockShapeGen] Failed to save: %s (error %d)" % [path, err])

	# 5 rock seeds at radius 0.5
	for seed_val: int in range(5):
		var mesh: ArrayMesh = make_rock_mesh(0.5, seed_val)
		var path := "%s/rock_s%d_r50.tres" % [base_path, seed_val]
		var err := ResourceSaver.save(mesh, path)
		if err == OK:
			print("[BlockShapeGen] Saved: %s" % path)
		else:
			push_error("[BlockShapeGen] Failed to save: %s (error %d)" % [path, err])

	# 2 rock seeds at radius 0.8
	for seed_val: int in range(2):
		var mesh: ArrayMesh = make_rock_mesh(0.8, seed_val)
		var path := "%s/rock_s%d_r80.tres" % [base_path, seed_val]
		var err := ResourceSaver.save(mesh, path)
		if err == OK:
			print("[BlockShapeGen] Saved: %s" % path)
		else:
			push_error("[BlockShapeGen] Failed to save: %s (error %d)" % [path, err])


## Helper: compute a point on a torus surface.
## mid_r: distance from torus centre to tube centre
## tube_r: tube cross-section radius
## arc_angle: angle around the arch arc (0..PI for half-torus)
## ring_angle: angle around the tube cross-section (0..TAU)
## Arc sweeps in the XY plane (vertical arch). Feet sit at Y=0.
static func _torus_vertex(mid_r: float, tube_r: float, arc_angle: float, ring_angle: float) -> Vector3:
	var cos_arc := cos(arc_angle)
	var sin_arc := sin(arc_angle)
	var cos_ring := cos(ring_angle)
	var sin_ring := sin(ring_angle)

	# Centre of the tube traces a half-circle in XY (vertical)
	var cx := mid_r * cos_arc
	var cy := mid_r * sin_arc

	# Tube cross-section offset (radial outward in XY + depth in Z)
	var rx := cos_arc * (tube_r * cos_ring)
	var ry := sin_arc * (tube_r * cos_ring)
	var rz := tube_r * sin_ring

	return Vector3(cx + rx, cy + ry, rz)
