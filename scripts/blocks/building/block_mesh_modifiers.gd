class_name BlockMeshModifiers
## Post-merge geometry modifications.
##
## Runs on merged ArrayMesh instances after BlockMeshMerger combines faces.
## Each pass takes a MeshInstance3D and modifies its mesh vertices.
## Collision shapes are NOT affected — only visual meshes.


## Apply noise vertex displacement to a MeshInstance3D.
## strength: max displacement distance along normal (0 = disabled)
## scale: noise sampling frequency (lower = smoother hills, higher = rougher)
## seed_val: deterministic noise seed
static func apply_noise(mesh_inst: MeshInstance3D, strength: float, scale: float = 0.5, seed_val: int = 0) -> void:
	if mesh_inst == null or mesh_inst.mesh == null:
		return
	if strength <= 0.0:
		return
	if mesh_inst.mesh.get_surface_count() == 0:
		return

	var mdt := MeshDataTool.new()
	var err := mdt.create_from_surface(mesh_inst.mesh, 0)
	if err != OK:
		return  # Some mesh types not supported by MeshDataTool

	for i: int in range(mdt.get_vertex_count()):
		var pos: Vector3 = mdt.get_vertex(i)
		var normal: Vector3 = mdt.get_vertex_normal(i)

		# Sample in assembly-local space for coherent noise across the whole merged mesh
		var sample: Vector3 = pos * scale

		# Hash-based noise -> bipolar offset along normal
		var n: float = _hash_noise_3d(sample, seed_val)
		var offset: float = (n - 0.5) * 2.0 * strength

		mdt.set_vertex(i, pos + normal * offset)

	# Commit modified data back to the mesh
	var mesh: ArrayMesh = mesh_inst.mesh as ArrayMesh
	if mesh == null:
		return  # Not an ArrayMesh — can't clear and recommit
	mesh.clear_surfaces()
	mdt.commit_to_surface(mesh)


## Apply corner rounding to merged box meshes.
## static func apply_corner_radius(...) -> void:
##     # Future: subdivide edges, lerp toward sphere at corners


## Apply edge wear/chipping to exterior edges.
## static func apply_wear(...) -> void:
##     # Future: detect edge vertices, displace inward


## Simple hash-based 3D noise. Returns 0.0..1.0.
## Deterministic for any given position + seed — same inputs always produce same output.
## Not smooth (no interpolation between cells) — suitable for vertex-level roughness,
## not terrain generation.
static func _hash_noise_3d(p: Vector3, seed_val: int) -> float:
	# Use large primes to hash the 3 coordinates + seed into a pseudo-random value.
	# The fractional-sine trick gives good distribution without needing a full PRNG.
	var h: float = p.x * 127.1 + p.y * 311.7 + p.z * 74.7 + float(seed_val) * 53.3
	return absf(fmod(sin(h) * 43758.5453, 1.0))
