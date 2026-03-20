extends Node3D
## Test suite for Sdf — SDF smooth-union mesh generation via Marching Cubes.
##
## Tests cover:
##   - Single element: sphere, box, cylinder produce valid mesh
##   - Two-sphere blend: hard union (k=0) vs smooth union (k>0)
##   - Mesh validity: ArrayMesh with vertices, normals, correct winding
##   - Resolution scaling: 16 vs 32 vs 64 produce progressively more triangles
##   - Empty/null inputs: graceful handling
##   - Blend radius effects: k=0 produces hard edges, large k produces smooth

## Preload the SDF blender since it may not be in global class cache yet.
const Sdf = preload("res://addons/blocks/building/block_sdf_blender.gd")
##   - SDF primitives: sphere, box, cylinder distance functions are correct
##   - Rotation: elements with rotation_y produce valid mesh
##   - AABB computation: padding and bounds are correct
##   - Edge cases: overlapping elements, zero-size, far-apart elements

var _pass_count := 0
var _fail_count := 0
var _test_count := 0


func _ready() -> void:
	print("")
	print("=" .repeat(60))
	print("  SDF BLENDER TEST SUITE")
	print("=" .repeat(60))

	_test_sdf_primitives()
	_test_smooth_union_math()
	_test_single_sphere()
	_test_single_box()
	_test_single_cylinder()
	_test_two_sphere_hard_union()
	_test_two_sphere_smooth_union()
	_test_blend_spheres_convenience()
	_test_resolution_scaling()
	_test_empty_inputs()
	_test_rotation()
	_test_aabb_computation()
	_test_overlapping_elements()
	_test_far_apart_elements()
	_test_blend_k_range()
	_test_mixed_shapes()
	_test_mesh_validity()

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


## Helper: count triangles in an ArrayMesh.
func _tri_count(mesh: ArrayMesh) -> int:
	if mesh == null or mesh.get_surface_count() == 0:
		return 0
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices = arrays[Mesh.ARRAY_INDEX]
	if indices != null and (indices as PackedInt32Array).size() > 0:
		return (indices as PackedInt32Array).size() / 3
	return verts.size() / 3


## Helper: get vertex count.
func _vert_count(mesh: ArrayMesh) -> int:
	if mesh == null or mesh.get_surface_count() == 0:
		return 0
	var arrays := mesh.surface_get_arrays(0)
	return (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()


## Helper: compute AABB of mesh vertices.
func _mesh_aabb(mesh: ArrayMesh) -> AABB:
	if mesh == null or mesh.get_surface_count() == 0:
		return AABB()
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	if verts.is_empty():
		return AABB()
	var mn := verts[0]
	var mx := verts[0]
	for v in verts:
		mn = mn.min(v)
		mx = mx.max(v)
	return AABB(mn, mx - mn)


# =========================================================================
# SDF Primitive Accuracy
# =========================================================================

func _test_sdf_primitives() -> void:
	_section("SDF Primitive Functions")

	# Sphere SDF: distance from center minus radius
	var sphere_elem := Sdf.SdfElement.new(
		"sphere", Vector3(0, 0, 0), Vector3(1.0, 0, 0))

	# Point at center → should be -radius (-1.0)
	var d_center := Sdf._element_sdf(Vector3.ZERO, sphere_elem)
	_assert(is_equal_approx(d_center, -1.0), "sphere SDF at center = -radius")

	# Point on surface → should be 0
	var d_surface := Sdf._element_sdf(Vector3(1, 0, 0), sphere_elem)
	_assert(absf(d_surface) < 0.01, "sphere SDF on surface ≈ 0")

	# Point outside → should be positive
	var d_outside := Sdf._element_sdf(Vector3(2, 0, 0), sphere_elem)
	_assert(is_equal_approx(d_outside, 1.0), "sphere SDF 1m outside = +1.0")

	# Box SDF: Inigo Quilez box distance
	var box_elem := Sdf.SdfElement.new(
		"box", Vector3(0, 0, 0), Vector3(1, 1, 1))  # half-extents = 1m

	# Point at center → should be -1.0 (deepest inside)
	var db_center := Sdf._element_sdf(Vector3.ZERO, box_elem)
	_assert(db_center < 0.0, "box SDF at center is negative (inside)")

	# Point on face center → should be ≈ 0
	var db_face := Sdf._element_sdf(Vector3(1, 0, 0), box_elem)
	_assert(absf(db_face) < 0.01, "box SDF on face center ≈ 0")

	# Point outside corner → should be positive
	var db_corner := Sdf._element_sdf(Vector3(2, 2, 2), box_elem)
	_assert(db_corner > 0.0, "box SDF outside corner is positive")

	# Cylinder SDF
	var cyl_elem := Sdf.SdfElement.new(
		"cylinder", Vector3(0, 0, 0), Vector3(1.0, 2.0, 0))  # r=1, half_h=2

	var dc_center := Sdf._element_sdf(Vector3.ZERO, cyl_elem)
	_assert(dc_center < 0.0, "cylinder SDF at center is negative (inside)")

	var dc_side := Sdf._element_sdf(Vector3(1, 0, 0), cyl_elem)
	_assert(absf(dc_side) < 0.01, "cylinder SDF on side surface ≈ 0")

	var dc_top := Sdf._element_sdf(Vector3(0, 2, 0), cyl_elem)
	_assert(absf(dc_top) < 0.01, "cylinder SDF on top cap ≈ 0")


func _test_smooth_union_math() -> void:
	_section("Smooth Union Math")

	# Two spheres with hard union (k=0) → result is min(d1, d2)
	var elems: Array = [
		Sdf.SdfElement.new("sphere", Vector3(-1, 0, 0), Vector3(1.0, 0, 0)),
		Sdf.SdfElement.new("sphere", Vector3(1, 0, 0), Vector3(1.0, 0, 0)),
	]

	# At origin (equidistant from both sphere centers at distance 1, radius 1)
	# d1 = |(-1,0,0) - (0,0,0)| - 1 = 0
	# d2 = |(1,0,0) - (0,0,0)| - 1 = 0
	var d_hard := Sdf._scene_sdf(Vector3.ZERO, elems, 0.0)
	_assert(is_equal_approx(d_hard, 0.0), "hard union at equidistant point = 0")

	# With smooth union (k=0.5) → result should be <= min(d1, d2)
	var d_smooth := Sdf._scene_sdf(Vector3.ZERO, elems, 0.5)
	_assert(d_smooth <= d_hard + 0.01, "smooth union ≤ hard union (smoothing fills gap)")

	# Smooth union at point deep inside one sphere → close to hard union
	var d_inside_hard := Sdf._scene_sdf(Vector3(-1, 0, 0), elems, 0.0)
	var d_inside_smooth := Sdf._scene_sdf(Vector3(-1, 0, 0), elems, 0.5)
	_assert(absf(d_inside_hard - d_inside_smooth) < 0.3,
		"smooth union deep inside ≈ hard union (blend only near surface)")


# =========================================================================
# Single Element Blends
# =========================================================================

func _test_single_sphere() -> void:
	_section("Single Sphere Blend")

	var elements: Array = [
		Sdf.SdfElement.new("sphere", Vector3(0, 0, 0), Vector3(1.0, 0, 0)),
	]

	var mesh := Sdf.blend(elements, 0.0, 16)
	_assert(mesh != null, "single sphere produces non-null mesh")
	_assert(mesh is ArrayMesh, "single sphere produces ArrayMesh")

	var tris := _tri_count(mesh)
	_assert(tris > 0, "single sphere has triangles (%d)" % tris)

	# Mesh should roughly enclose a unit sphere — check AABB
	var aabb := _mesh_aabb(mesh)
	_assert(aabb.size.x > 1.5, "sphere AABB width > 1.5m (diameter ~2m)")
	_assert(aabb.size.y > 1.5, "sphere AABB height > 1.5m")


func _test_single_box() -> void:
	_section("Single Box Blend")

	var elements: Array = [
		Sdf.SdfElement.new("box", Vector3(0, 0, 0), Vector3(1, 1, 1)),
	]

	var mesh := Sdf.blend(elements, 0.0, 16)
	_assert(mesh != null, "single box produces non-null mesh")

	var tris := _tri_count(mesh)
	_assert(tris > 0, "single box has triangles (%d)" % tris)

	var aabb := _mesh_aabb(mesh)
	_assert(aabb.size.x > 1.5, "box AABB width > 1.5m (half-extents 1m)")


func _test_single_cylinder() -> void:
	_section("Single Cylinder Blend")

	var elements: Array = [
		Sdf.SdfElement.new("cylinder", Vector3(0, 0, 0), Vector3(1.0, 2.0, 0)),
	]

	var mesh := Sdf.blend(elements, 0.0, 16)
	_assert(mesh != null, "single cylinder produces non-null mesh")

	var tris := _tri_count(mesh)
	_assert(tris > 0, "single cylinder has triangles (%d)" % tris)


# =========================================================================
# Two-Sphere Blends
# =========================================================================

func _test_two_sphere_hard_union() -> void:
	_section("Two Spheres — Hard Union (k=0)")

	var elements: Array = [
		Sdf.SdfElement.new("sphere", Vector3(-1, 0, 0), Vector3(1.0, 0, 0)),
		Sdf.SdfElement.new("sphere", Vector3(1, 0, 0), Vector3(1.0, 0, 0)),
	]

	var mesh := Sdf.blend(elements, 0.0, 32)
	_assert(mesh != null, "hard union of 2 spheres produces mesh")

	var aabb := _mesh_aabb(mesh)
	# Two spheres: centers at (-1,0,0) and (1,0,0), radius 1
	# Total X range: [-2, 2] → width ≈ 4m
	_assert(aabb.size.x > 3.0, "hard union AABB width > 3m (two spheres span ~4m)")

	var tris := _tri_count(mesh)
	_assert(tris > 20, "hard union has reasonable triangle count (%d)" % tris)


func _test_two_sphere_smooth_union() -> void:
	_section("Two Spheres — Smooth Union (k=0.3)")

	var elements: Array = [
		Sdf.SdfElement.new("sphere", Vector3(-1, 0, 0), Vector3(1.0, 0, 0)),
		Sdf.SdfElement.new("sphere", Vector3(1, 0, 0), Vector3(1.0, 0, 0)),
	]

	var mesh_smooth := Sdf.blend(elements, 0.3, 32)
	_assert(mesh_smooth != null, "smooth union of 2 spheres produces mesh")

	# Smooth union should produce slightly larger mesh (blend fills gap)
	var mesh_hard := Sdf.blend(elements, 0.0, 32)

	if mesh_smooth != null and mesh_hard != null:
		var aabb_smooth := _mesh_aabb(mesh_smooth)
		var aabb_hard := _mesh_aabb(mesh_hard)
		# Smooth union fills the gap between spheres → Y extent should be >= hard union
		_assert(aabb_smooth.size.y >= aabb_hard.size.y - 0.1,
			"smooth union Y extent ≥ hard union (blend fills gap)")


func _test_blend_spheres_convenience() -> void:
	_section("blend_spheres() Convenience Method")

	var mesh := Sdf.blend_spheres(
		Vector3(-1, 0, 0), 1.0,
		Vector3(1, 0, 0), 1.0,
		0.2, 32)

	_assert(mesh != null, "blend_spheres() returns non-null mesh")

	# Verify it matches calling blend() directly
	var elements: Array = [
		Sdf.SdfElement.new("sphere", Vector3(-1, 0, 0), Vector3(1.0, 0, 0)),
		Sdf.SdfElement.new("sphere", Vector3(1, 0, 0), Vector3(1.0, 0, 0)),
	]
	var mesh_direct := Sdf.blend(elements, 0.2, 32)

	if mesh != null and mesh_direct != null:
		var tris_conv := _tri_count(mesh)
		var tris_direct := _tri_count(mesh_direct)
		_assert(tris_conv == tris_direct,
			"blend_spheres() matches blend() triangle count (%d vs %d)" % [tris_conv, tris_direct])


# =========================================================================
# Resolution Scaling
# =========================================================================

func _test_resolution_scaling() -> void:
	_section("Resolution Scaling")

	var elements: Array = [
		Sdf.SdfElement.new("sphere", Vector3(0, 0, 0), Vector3(1.0, 0, 0)),
	]

	var mesh_16 := Sdf.blend(elements, 0.0, 16)
	var mesh_32 := Sdf.blend(elements, 0.0, 32)
	var mesh_64 := Sdf.blend(elements, 0.0, 64)

	_assert(mesh_16 != null, "resolution 16 produces mesh")
	_assert(mesh_32 != null, "resolution 32 produces mesh")
	_assert(mesh_64 != null, "resolution 64 produces mesh")

	if mesh_16 != null and mesh_32 != null and mesh_64 != null:
		var t16 := _tri_count(mesh_16)
		var t32 := _tri_count(mesh_32)
		var t64 := _tri_count(mesh_64)

		_assert(t32 > t16, "res 32 (%d tris) > res 16 (%d tris)" % [t32, t16])
		_assert(t64 > t32, "res 64 (%d tris) > res 32 (%d tris)" % [t64, t32])

		# Resolution 64 should have significantly more detail
		_assert(t64 > t16 * 3, "res 64 has >3x triangles vs res 16")


# =========================================================================
# Edge Cases
# =========================================================================

func _test_empty_inputs() -> void:
	_section("Empty / Null Inputs")

	# Empty array
	var mesh := Sdf.blend([], 0.0, 32)
	_assert(mesh == null, "empty element array → null mesh")

	# Unknown shape type → falls back to sphere approximation
	var unknown := Sdf.SdfElement.new(
		"banana", Vector3(0, 0, 0), Vector3(1.0, 1.0, 1.0))
	var mesh_unknown := Sdf.blend([unknown], 0.0, 16)
	_assert(mesh_unknown != null, "unknown shape type → fallback to sphere, produces mesh")


func _test_rotation() -> void:
	_section("Element Rotation")

	# A box with 45° Y rotation should produce a differently oriented mesh
	var box_no_rot := Sdf.SdfElement.new(
		"box", Vector3(0, 0, 0), Vector3(2, 1, 0.5))  # elongated on X

	var box_rotated := Sdf.SdfElement.new(
		"box", Vector3(0, 0, 0), Vector3(2, 1, 0.5), PI / 2.0)  # 90° rotation

	var mesh_no_rot := Sdf.blend([box_no_rot], 0.0, 16)
	var mesh_rotated := Sdf.blend([box_rotated], 0.0, 16)

	_assert(mesh_no_rot != null, "unrotated box produces mesh")
	_assert(mesh_rotated != null, "90° rotated box produces mesh")

	if mesh_no_rot != null and mesh_rotated != null:
		var aabb_no_rot := _mesh_aabb(mesh_no_rot)
		var aabb_rotated := _mesh_aabb(mesh_rotated)
		# 90° rotation swaps X and Z extents
		_assert(absf(aabb_no_rot.size.x - aabb_rotated.size.z) < 0.5,
			"90° rotation swaps X and Z extents (within 0.5m tolerance)")


func _test_aabb_computation() -> void:
	_section("AABB Computation")

	# Single sphere at origin, radius 1
	var elements: Array = [
		Sdf.SdfElement.new("sphere", Vector3(5, 3, -2), Vector3(1.0, 0, 0)),
	]

	# AABB should be centered around (5, 3, -2) with padding
	var aabb := Sdf._compute_aabb(elements, 0.3)
	_assert(aabb.position.x < 5.0, "AABB min.x < sphere center x")
	_assert(aabb.position.y < 3.0, "AABB min.y < sphere center y")
	_assert(aabb.end.x > 5.0, "AABB max.x > sphere center x")
	_assert(aabb.end.y > 3.0, "AABB max.y > sphere center y")

	# Two spheres far apart → AABB should encompass both
	var far_elements: Array = [
		Sdf.SdfElement.new("sphere", Vector3(-10, 0, 0), Vector3(1.0, 0, 0)),
		Sdf.SdfElement.new("sphere", Vector3(10, 0, 0), Vector3(1.0, 0, 0)),
	]
	var far_aabb := Sdf._compute_aabb(far_elements, 0.3)
	_assert(far_aabb.size.x > 20.0, "far-apart spheres AABB width > 20m")


func _test_overlapping_elements() -> void:
	_section("Overlapping Elements")

	# Two spheres at exact same position → should produce valid mesh
	var elements: Array = [
		Sdf.SdfElement.new("sphere", Vector3(0, 0, 0), Vector3(1.0, 0, 0)),
		Sdf.SdfElement.new("sphere", Vector3(0, 0, 0), Vector3(1.0, 0, 0)),
	]

	var mesh := Sdf.blend(elements, 0.2, 16)
	_assert(mesh != null, "two overlapping spheres → valid mesh")

	# One inside the other
	var nested: Array = [
		Sdf.SdfElement.new("sphere", Vector3(0, 0, 0), Vector3(2.0, 0, 0)),
		Sdf.SdfElement.new("sphere", Vector3(0, 0, 0), Vector3(0.5, 0, 0)),
	]

	var mesh_nested := Sdf.blend(nested, 0.2, 16)
	_assert(mesh_nested != null, "nested spheres (one inside other) → valid mesh")

	# The resulting mesh should be approximately the size of the larger sphere
	if mesh_nested != null:
		var aabb := _mesh_aabb(mesh_nested)
		_assert(aabb.size.x > 3.0, "nested result ≈ size of larger sphere")


func _test_far_apart_elements() -> void:
	_section("Far Apart Elements")

	# Two spheres 20m apart with small blend radius
	# They should produce two disconnected surfaces
	var elements: Array = [
		Sdf.SdfElement.new("sphere", Vector3(-10, 0, 0), Vector3(1.0, 0, 0)),
		Sdf.SdfElement.new("sphere", Vector3(10, 0, 0), Vector3(1.0, 0, 0)),
	]

	var mesh := Sdf.blend(elements, 0.2, 32)
	_assert(mesh != null, "far-apart spheres produce mesh")

	if mesh != null:
		var tris := _tri_count(mesh)
		_assert(tris > 10, "far-apart spheres have reasonable triangle count (%d)" % tris)

		# AABB should span the full distance
		var aabb := _mesh_aabb(mesh)
		_assert(aabb.size.x > 18.0, "far-apart mesh AABB spans both spheres")


func _test_blend_k_range() -> void:
	_section("Blend K Range")

	var elements: Array = [
		Sdf.SdfElement.new("sphere", Vector3(-1, 0, 0), Vector3(1.0, 0, 0)),
		Sdf.SdfElement.new("sphere", Vector3(1, 0, 0), Vector3(1.0, 0, 0)),
	]

	# Very small k → almost hard union
	var mesh_tiny := Sdf.blend(elements, 0.01, 32)
	_assert(mesh_tiny != null, "tiny blend k (0.01) → valid mesh")

	# Very large k → very smooth, almost spherical
	var mesh_large := Sdf.blend(elements, 0.8, 32)
	_assert(mesh_large != null, "large blend k (0.8) → valid mesh")

	# Negative k → should behave like hard union (k clamped or treated as 0)
	var mesh_neg := Sdf.blend(elements, -0.5, 32)
	_assert(mesh_neg != null, "negative blend k → valid mesh (treated as hard union)")

	# All FM-relative blend constants should produce valid meshes
	var fm_values := [0.0, 0.10, 0.15, 0.20, 0.30, 0.60, 1.20]
	for k in fm_values:
		var mesh := Sdf.blend(elements, k, 16)
		_assert(mesh != null, "FM blend constant k=%.2f → valid mesh" % k)


func _test_mixed_shapes() -> void:
	_section("Mixed Shape Blends")

	# Box + Sphere blend
	var box_sphere: Array = [
		Sdf.SdfElement.new("box", Vector3(0, 0, 0), Vector3(1, 1, 1)),
		Sdf.SdfElement.new("sphere", Vector3(1.5, 0, 0), Vector3(1.0, 0, 0)),
	]
	var mesh_bs := Sdf.blend(box_sphere, 0.3, 16)
	_assert(mesh_bs != null, "box + sphere blend → valid mesh")

	# Cylinder + Sphere (tree trunk + canopy)
	var trunk_canopy: Array = [
		Sdf.SdfElement.new("cylinder", Vector3(0, 0, 0), Vector3(0.5, 2.0, 0)),
		Sdf.SdfElement.new("sphere", Vector3(0, 2.5, 0), Vector3(1.5, 0, 0)),
	]
	var mesh_tree := Sdf.blend(trunk_canopy, 0.3, 16)
	_assert(mesh_tree != null, "cylinder trunk + sphere canopy blend → valid mesh")

	if mesh_tree != null:
		var aabb := _mesh_aabb(mesh_tree)
		_assert(aabb.size.y > 3.0, "tree blend spans trunk + canopy height")

	# Three shapes: box base + cylinder trunk + sphere top
	var complex: Array = [
		Sdf.SdfElement.new("box", Vector3(0, -1, 0), Vector3(1.5, 0.5, 1.5)),
		Sdf.SdfElement.new("cylinder", Vector3(0, 1, 0), Vector3(0.5, 1.5, 0)),
		Sdf.SdfElement.new("sphere", Vector3(0, 3, 0), Vector3(1.0, 0, 0)),
	]
	var mesh_complex := Sdf.blend(complex, 0.2, 16)
	_assert(mesh_complex != null, "3-shape complex blend → valid mesh")


func _test_mesh_validity() -> void:
	_section("Mesh Validity Deep Checks")

	var elements: Array = [
		Sdf.SdfElement.new("sphere", Vector3(0, 0, 0), Vector3(1.0, 0, 0)),
	]

	var mesh := Sdf.blend(elements, 0.0, 32)
	_assert(mesh != null, "validity test mesh is non-null")

	if mesh == null:
		return

	# Check surface count
	_assert(mesh.get_surface_count() == 1, "mesh has exactly 1 surface")

	# Check arrays
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	_assert(verts.size() > 0, "mesh has vertices (%d)" % verts.size())

	# Check normals exist
	var normals = arrays[Mesh.ARRAY_NORMAL]
	_assert(normals != null and (normals as PackedVector3Array).size() > 0,
		"mesh has normals")

	# Check that indices exist (SurfaceTool.index() was called)
	var indices = arrays[Mesh.ARRAY_INDEX]
	_assert(indices != null and (indices as PackedInt32Array).size() > 0,
		"mesh has index buffer (SurfaceTool.index() was called)")

	# Verify triangle count is reasonable for a sphere at res 32
	var tris := _tri_count(mesh)
	_assert(tris > 50, "sphere at res 32 has >50 triangles (%d)" % tris)
	_assert(tris < 10000, "sphere at res 32 has <10k triangles (%d)" % tris)

	# No degenerate triangles (zero-area)
	if indices != null:
		var idx_arr: PackedInt32Array = indices as PackedInt32Array
		var degen_count := 0
		for t in range(idx_arr.size() / 3):
			var i0 := idx_arr[t * 3]
			var i1 := idx_arr[t * 3 + 1]
			var i2 := idx_arr[t * 3 + 2]
			if i0 < verts.size() and i1 < verts.size() and i2 < verts.size():
				var v0 := verts[i0]
				var v1 := verts[i1]
				var v2 := verts[i2]
				var area := (v1 - v0).cross(v2 - v0).length() * 0.5
				if area < 1e-8:
					degen_count += 1
		_assert(degen_count == 0, "no degenerate (zero-area) triangles found (%d degenerate)" % degen_count)
