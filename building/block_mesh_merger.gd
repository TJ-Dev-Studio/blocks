class_name BlockMeshMerger
## Merges same-material MeshInstance3D nodes in an assembly into combined meshes.
##
## Reduces draw calls from N (one per block) to ~M (one per unique material).
## Collision nodes are untouched. Blocks with neurons are skipped (need individual updates).
## Small assemblies (≤MAX_MERGE_EXTENT) merge all blocks together.
## Large assemblies are split into CHUNK_SIZE spatial buckets and merged per-chunk,
## keeping each chunk's AABB small enough for visibility_range culling.
##
## Face culling: before merging, detects axis-aligned BoxMesh pairs that share a
## touching face and removes the internal (invisible) triangles from both sides.
## This saves GPU fill rate on dense structures (e.g. 84-block store in FrogTown).

## Minimum block count to trigger mesh merging in an assembly.
## 2 is the minimum useful — merging 2 meshes into 1 halves draw calls.
const MIN_MERGE_BLOCKS := 2

## Maximum spatial extent (meters) for an assembly to be merge-eligible.
## Assemblies spanning more than this have their merged mesh AABB center far from
## the player, causing visibility_range culling to hide the entire assembly.
## Large assemblies (terrain, perimeter, forest rings) keep per-block vis culling.
const MAX_MERGE_EXTENT := 40.0

## Tolerance for "touching" face detection (meters). Blocks may not perfectly align.
const FACE_TOUCH_TOLERANCE := 0.05

## Minimum fraction of a face's extent that must be covered before culling it.
## Prevents a tiny baseboard (0.3m) from culling an entire 6m wall face.
const MIN_FACE_COVERAGE := 0.75

## Dot product threshold for matching a triangle normal to a blocked direction.
const NORMAL_DOT_THRESHOLD := 0.9

## Spatial chunk size (meters) for merging large assemblies.
## Each chunk's merged AABB stays small enough for visibility_range culling.
const CHUNK_SIZE := 16.0

## Bucket edge (meters) for the face-cull pair spatial hash (TL-42). Boxes are
## bucketed by their tolerance-inflated AABBs; only same-bucket pairs are
## tested for touching faces. Sized around typical block edge lengths — bigger
## buckets test more non-touching pairs, smaller ones insert big boxes into
## more buckets.
const PAIR_HASH_CELL := 4.0

## Visibility range for chunked merged meshes. Safe because chunk AABBs are ≤16m.
const CHUNK_VIS_RANGE := 80.0


## Merge same-material meshes under an assembly root node.
## blocks: Array of Block resources belonging to this assembly.
## Small assemblies (extent <= MAX_MERGE_EXTENT) merge all blocks together.
## Large assemblies are split into CHUNK_SIZE spatial buckets and merged per-chunk,
## enabling terrain, perimeter, and forest ring assemblies to benefit from merging
## while keeping each chunk's AABB small enough for visibility_range culling.
static func merge(asm_root: Node3D, blocks: Array) -> void:
	# Compute spatial extent
	var min_x := INF
	var max_x := -INF
	var min_z := INF
	var max_z := -INF
	for block in blocks:
		var p: Vector3 = block.get_meta("local_position", block.position)
		min_x = minf(min_x, p.x)
		max_x = maxf(max_x, p.x)
		min_z = minf(min_z, p.z)
		max_z = maxf(max_z, p.z)
	var extent := maxf(max_x - min_x, max_z - min_z)

	if extent <= MAX_MERGE_EXTENT:
		# Small assembly — merge all blocks into one group (existing behavior)
		_merge_group(asm_root, blocks, "", extent)
		return

	# Large assembly — bucket blocks into spatial chunks and merge each independently
	var chunks := _bucket_by_chunk(blocks, CHUNK_SIZE)
	var chunks_merged := 0
	for chunk_key: String in chunks:
		var chunk_blocks: Array = chunks[chunk_key]
		if chunk_blocks.size() >= MIN_MERGE_BLOCKS:
			chunks_merged += _merge_group(asm_root, chunk_blocks, chunk_key, CHUNK_SIZE)
	if chunks_merged > 0:
		print("[BlockMeshMerger] Chunked merge: %d chunks merged in '%s' (extent=%.0fm, %d chunks total)" % [
			chunks_merged, asm_root.name, extent, chunks.size()])


## Bucket blocks into spatial chunks by their XZ position on a grid.
## Returns Dictionary of "cx_cz" -> Array[Block].
static func _bucket_by_chunk(blocks: Array, chunk_size: float) -> Dictionary:
	var chunks: Dictionary = {}
	for block in blocks:
		var p: Vector3 = block.get_meta("local_position", block.position)
		var cx := int(floorf(p.x / chunk_size))
		var cz := int(floorf(p.z / chunk_size))
		var key := "%d_%d" % [cx, cz]
		if not chunks.has(key):
			chunks[key] = []
		chunks[key].append(block)
	return chunks


## Core merge logic for a group of blocks (full assembly or single chunk).
## Returns 1 if any meshes were merged, 0 otherwise.
static func _merge_group(asm_root: Node3D, blocks: Array, chunk_id: String, extent: float) -> int:
	var is_chunk := not chunk_id.is_empty()

	# Identify blocks with neurons (skip merging — they need per-block visual updates)
	var neuron_ids: Dictionary = {}
	for block in blocks:
		if block.neuron != null:
			neuron_ids[block.block_id] = true

	# Collect mergeable meshes grouped by material
	# Key: material instance ID + shadow mode
	var groups: Dictionary = {}  # key -> {material, shadow, meshes: [{mesh, xform, node}]}
	var mesh_count := 0

	for block in blocks:
		if block.node == null or not is_instance_valid(block.node):
			continue
		if neuron_ids.has(block.block_id):
			continue
		if block.mesh_type != 0:
			continue  # skip scene visuals — only merge primitives
		if not block.materials_list.is_empty():
			continue  # multi-material blocks rendered individually — cannot merge different surface materials
		# WALKABLE blocks used to be excluded here outright. The recorded symptom
		# was "vanishing into the merged mesh while their collision survived →
		# walkable-but-invisible", and the ban covered TWO mechanisms at once:
		# merging AND face-culling. Only one of them can delete a visible surface.
		#
		# Merging concatenates triangles; it cannot remove the face a player is
		# looking at. _find_culled_faces CAN — it drops triangles whose direction
		# is blocked by a touching neighbour, and a landing slab sandwiched between
		# other boxes is exactly the shape that loses its top face that way.
		#
		# So walkable blocks now MERGE (they are marked below and excluded from
		# face-culling instead). Measured cost of the wider ban: 12,228 drawable
		# walkable blocks forming only 1,074 (assembly x material) groups —
		# 11,154 avoidable draw calls, 91% of all walkable geometry.

		var mesh_inst := block.node.get_node_or_null("Mesh") as MeshInstance3D
		if mesh_inst == null or mesh_inst.mesh == null:
			continue

		var mat = mesh_inst.material_override
		if mat == null:
			continue

		var shadow_mode: int = mesh_inst.cast_shadow
		var key := "%d_%d" % [mat.get_instance_id(), shadow_mode]

		if not groups.has(key):
			groups[key] = {"material": mat, "shadow": shadow_mode, "meshes": []}

		# Transform: block node global transform * mesh local transform, then
		# convert to asm_root-local space. Using global_transform accounts for
		# the full parent chain (assembly container, structure container, etc.)
		# which is critical for zone-level merging where asm_root is the zone
		# node, not the block's immediate parent.
		var rel_xform: Transform3D = asm_root.global_transform.affine_inverse() * block.node.global_transform * mesh_inst.transform
		groups[key]["meshes"].append({
			"mesh": mesh_inst.mesh,
			"transform": rel_xform,
			"node": mesh_inst,
			"shape": block.collision_shape,
			# Does surface 0 carry UVs? generate_tangents() below is a hard ERROR
			# without them, and a failed commit yields an invalid merged mesh —
			# geometry that silently does not render while its collision survives.
			# That is almost certainly the original "walkable-but-invisible"
			# defect: walkable geometry includes UV-less meshes, so merging them
			# broke tangent generation for the whole group.
			"has_uv": _surface_has_uv(mesh_inst.mesh),
			# Walkable surfaces merge but must NEVER be a face-cull source or
			# target — see the note above the WALKABLE branch in the collect loop.
			"walkable": block.interaction == BlockCategories.INTERACT_WALKABLE,
		})
		mesh_count += 1

	if mesh_count < MIN_MERGE_BLOCKS:
		return 0

	var merged_count := 0
	var removed_count := 0
	var total_faces_culled := 0

	for key: String in groups:
		var group: Dictionary = groups[key]
		var meshes: Array = group["meshes"]
		if meshes.size() < 2:
			continue  # not worth merging a single mesh

		# Detect shared internal faces between touching BoxMesh pairs
		var culled_faces: Dictionary = _find_culled_faces(meshes)

		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)

		for i: int in range(meshes.size()):
			var entry: Dictionary = meshes[i]
			if culled_faces.has(i):
				# Selective copy — skip triangles facing blocked directions.
				#
				# The surviving triangles MUST go through their own SurfaceTool
				# and re-enter `st` via append_from. Feeding add_vertex() calls
				# into a SurfaceTool that has already ingested indexed geometry
				# via append_from() leaves those vertices ORPHANED — they land in
				# ARRAY_VERTEX but no triangle index ever references them, so the
				# whole entry silently vanishes from the render while its
				# collision survives (store walls invisible-but-solid, 2026-07-03).
				var sub := SurfaceTool.new()
				sub.begin(Mesh.PRIMITIVE_TRIANGLES)
				total_faces_culled += _append_with_culling(
					sub, entry["mesh"], entry["transform"], culled_faces[i])
				# index() converts the raw add_vertex stream to an indexed
				# surface — append_from() only splices sources whose indexing
				# matches the destination tool (BoxMesh surfaces are indexed);
				# a non-indexed source gets its vertices copied but no indices,
				# recreating the orphaning this block exists to avoid.
				sub.index()
				var sub_mesh: ArrayMesh = sub.commit()
				if sub_mesh != null and sub_mesh.get_surface_count() > 0:
					# Vertices were already transformed by _append_with_culling.
					st.append_from(sub_mesh, 0, Transform3D.IDENTITY)
			else:
				# No faces to cull — use fast path
				st.append_from(entry["mesh"], 0, entry["transform"])

		# Do NOT call generate_normals() — source meshes already have correct
		# per-face normals (flat shading). Regenerating would smooth-average 90°
		# box corners, creating visible shading gradients on every face.
		#
		# generate_tangents() is a HARD ERROR ("UVs are required to generate
		# tangents") if ANY appended surface lacks UVs, and the resulting commit
		# is an invalid mesh — geometry that never renders while its collision
		# survives. Skip it for mixed groups rather than losing the whole group:
		# tangents only matter for normal-mapped materials, and a group containing
		# UV-less primitives is not one of those.
		var all_have_uv := true
		for e: Dictionary in meshes:
			if not bool(e.get("has_uv", true)):
				all_have_uv = false
				break
		if all_have_uv:
			st.generate_tangents()
		var merged_mesh: ArrayMesh = st.commit()

		var merged_inst := MeshInstance3D.new()
		var name_suffix := ("_c" + chunk_id) if is_chunk else ""
		merged_inst.name = "Merged_%d%s" % [merged_count, name_suffix]
		merged_inst.mesh = merged_mesh
		merged_inst.material_override = group["material"]
		merged_inst.cast_shadow = group["shadow"] as GeometryInstance3D.ShadowCastingSetting

		# Zone-level merging places chunks at the merge root's origin, but vertices
		# span the full map. Visibility range culling measures distance from the
		# node origin — unusable when origin ≠ chunk center. Rely on frustum
		# culling instead (Godot auto-culls off-screen AABBs).
		# Assembly-level chunks (asm_root != zone) keep vis range since their
		# origin IS near their vertices.

		asm_root.add_child(merged_inst)
		merged_count += 1

		# Remove original mesh nodes immediately (not queue_free) so that
		# post-merge cleanup can detect empty block roots via get_child_count()==0.
		# Safe because we're done reading from meshes and the merged mesh is committed.
		for entry in meshes:
			(entry["node"] as Node3D).free()
			removed_count += 1

	if merged_count > 0 and not is_chunk:
		var cull_info := ""
		if total_faces_culled > 0:
			cull_info = ", %d internal faces culled" % total_faces_culled
		print("[BlockMeshMerger] Mesh merge: %d meshes → %d draws in '%s' (extent=%.0fm%s)" % [
			removed_count, merged_count, asm_root.name, extent, cull_info])

	return 1 if merged_count > 0 else 0


## Detect shared internal faces between touching axis-aligned BoxMesh pairs.
##
## For each pair of BoxMesh entries in the same material group, computes AABBs
## from the transform origin + box size, then checks each axis for touching faces
## with overlap on the other two axes. Returns a Dictionary mapping entry index
## to an Array of blocked normal directions (Vector3) for that entry.
##
## Only processes SHAPE_BOX entries — cylinders, spheres, ramps are skipped.
## True when the basis maps each local axis onto a world axis (axis-aligned box).
## Rotated boxes get a wrong origin±half_size AABB, so face-culling must skip them
## or they falsely cull a neighbour's visible face (collidable-but-invisible blocks).
static func _basis_is_axis_aligned(b: Basis) -> bool:
	var o: Basis = b.orthonormalized()
	for v: Vector3 in [o.x, o.y, o.z]:
		var a: Vector3 = v.abs()
		if maxf(a.x, maxf(a.y, a.z)) < 0.9995:
			return false
	return true


static func _find_culled_faces(meshes: Array) -> Dictionary:
	# culled[entry_index] = Array[Vector3] of blocked normal directions
	var culled: Dictionary = {}

	# Pre-compute AABB data for box entries only
	# aabb_data[i] = {min: Vector3, max: Vector3} or null if not a box
	var aabb_data: Array = []
	aabb_data.resize(meshes.size())

	for i: int in range(meshes.size()):
		var entry: Dictionary = meshes[i]
		# Walkable surfaces are never a cull source OR target. Face-culling is the
		# only part of merging that can delete a face the player is looking at, and
		# a landing slab boxed in by neighbours is precisely the shape that loses
		# its top face — the "walkable-but-invisible" defect. Merging them is safe;
		# culling them is not, so only the culling half is refused here.
		if bool(entry.get("walkable", false)):
			aabb_data[i] = null
			continue
		if entry["shape"] != BlockCategories.SHAPE_BOX:
			aabb_data[i] = null
			continue
		var mesh: Mesh = entry["mesh"]
		if not mesh is BoxMesh:
			aabb_data[i] = null
			continue
		# Rotation guard: the AABB below is origin ± half_size, which is valid ONLY
		# for axis-aligned boxes. A rotated box (e.g. a ramp landing slab authored at
		# 26.565°) gets a WRONG AABB and can falsely cull a neighbour's *visible* face,
		# leaving collidable-but-invisible geometry. Skip culling for non-axis-aligned
		# boxes — treat like a non-box: never a cull source or target.
		if not _basis_is_axis_aligned(entry["transform"].basis):
			aabb_data[i] = null
			continue
		var box_mesh: BoxMesh = mesh as BoxMesh
		var half_size: Vector3 = box_mesh.size * 0.5
		var origin: Vector3 = entry["transform"].origin
		aabb_data[i] = {
			"min": origin - half_size,
			"max": origin + half_size,
		}

	# Candidate pairs via a spatial hash instead of the all-pairs sweep.
	# All-pairs is O(N²): a 628-block assembly is ~197k pair tests × 3 axes in
	# GDScript — the bulk of an 11.2s main-thread stall on hot reload (TL-42).
	# Face culling only ever applies to TOUCHING boxes, so bucketing AABBs on a
	# coarse grid and testing only same-bucket pairs is exact, not approximate:
	# every touching pair shares at least one bucket once each AABB is inflated
	# by the touch tolerance.
	var buckets: Dictionary = {}  # Vector3i cell -> Array[int] (entry indices)
	for i: int in range(meshes.size()):
		if aabb_data[i] == null:
			continue
		var bmin: Vector3 = aabb_data[i]["min"] - Vector3.ONE * FACE_TOUCH_TOLERANCE
		var bmax: Vector3 = aabb_data[i]["max"] + Vector3.ONE * FACE_TOUCH_TOLERANCE
		for cx in range(int(floorf(bmin.x / PAIR_HASH_CELL)), int(floorf(bmax.x / PAIR_HASH_CELL)) + 1):
			for cy in range(int(floorf(bmin.y / PAIR_HASH_CELL)), int(floorf(bmax.y / PAIR_HASH_CELL)) + 1):
				for cz in range(int(floorf(bmin.z / PAIR_HASH_CELL)), int(floorf(bmax.z / PAIR_HASH_CELL)) + 1):
					var cell := Vector3i(cx, cy, cz)
					if not buckets.has(cell):
						buckets[cell] = []
					buckets[cell].append(i)

	var tested: Dictionary = {}  # packed pair key -> true
	for cell_key: Vector3i in buckets:
		var bucket: Array = buckets[cell_key]
		for bi: int in range(bucket.size()):
			for bj: int in range(bi + 1, bucket.size()):
				var i: int = bucket[bi]
				var j: int = bucket[bj]
				var pair_key: int = i * meshes.size() + j
				if tested.has(pair_key):
					continue
				tested[pair_key] = true
				_cull_touching_pair(i, j, aabb_data, culled)

	return culled


## Test one candidate box pair for touching faces and record culled directions.
## Body unchanged from the original all-pairs loop — only the pair enumeration
## moved to the spatial hash above.
static func _cull_touching_pair(i: int, j: int, aabb_data: Array, culled: Dictionary) -> void:
	var a_min: Vector3 = aabb_data[i]["min"]
	var a_max: Vector3 = aabb_data[i]["max"]
	var b_min: Vector3 = aabb_data[j]["min"]
	var b_max: Vector3 = aabb_data[j]["max"]

	# Check each axis for touching faces
	# Axis X: A's +X face touches B's -X face (or vice versa)
	# Axis Y: A's +Y face touches B's -Y face (or vice versa)
	# Axis Z: A's +Z face touches B's -Z face (or vice versa)
	for axis: int in range(3):
		# Get the two perpendicular axes
		var perp1: int = (axis + 1) % 3
		var perp2: int = (axis + 2) % 3

		# Check overlap on perpendicular axes (both must overlap)
		var overlap1 := minf(a_max[perp1], b_max[perp1]) - maxf(a_min[perp1], b_min[perp1])
		var overlap2 := minf(a_max[perp2], b_max[perp2]) - maxf(a_min[perp2], b_min[perp2])
		if overlap1 < FACE_TOUCH_TOLERANCE or overlap2 < FACE_TOUCH_TOLERANCE:
			continue  # no meaningful overlap on perpendicular axes

		# Per-block face extents on perpendicular axes
		var a_extent1 := a_max[perp1] - a_min[perp1]
		var a_extent2 := a_max[perp2] - a_min[perp2]
		var b_extent1 := b_max[perp1] - b_min[perp1]
		var b_extent2 := b_max[perp2] - b_min[perp2]

		# Coverage ratio: how much of each face is covered by the overlap
		var a_cov1 := overlap1 / a_extent1 if a_extent1 > 0.001 else 1.0
		var a_cov2 := overlap2 / a_extent2 if a_extent2 > 0.001 else 1.0
		var b_cov1 := overlap1 / b_extent1 if b_extent1 > 0.001 else 1.0
		var b_cov2 := overlap2 / b_extent2 if b_extent2 > 0.001 else 1.0
		var a_covered := a_cov1 >= MIN_FACE_COVERAGE and a_cov2 >= MIN_FACE_COVERAGE
		var b_covered := b_cov1 >= MIN_FACE_COVERAGE and b_cov2 >= MIN_FACE_COVERAGE

		# Check if A's max face touches B's min face on this axis
		if absf(a_max[axis] - b_min[axis]) < FACE_TOUCH_TOLERANCE:
			var normal_pos := Vector3.ZERO
			normal_pos[axis] = 1.0
			var normal_neg := Vector3.ZERO
			normal_neg[axis] = -1.0
			# Only cull A's face if B covers enough of it — but NEVER cull an
			# upward (+Y) face. Walkable platforms/landings/decks rest flush
			# against neighbours; culling their top leaves them collidable but
			# invisible (the horde ramp/landing slabs vanished this way).
			if a_covered and axis != 1:
				if not culled.has(i):
					culled[i] = []
				culled[i].append(normal_pos)
			# Only cull B's face if A covers enough of it
			if b_covered:
				if not culled.has(j):
					culled[j] = []
				culled[j].append(normal_neg)

		# Check if B's max face touches A's min face on this axis
		elif absf(b_max[axis] - a_min[axis]) < FACE_TOUCH_TOLERANCE:
			var normal_pos := Vector3.ZERO
			normal_pos[axis] = 1.0
			var normal_neg := Vector3.ZERO
			normal_neg[axis] = -1.0
			# NEVER cull an upward (+Y) face — see note above.
			if b_covered and axis != 1:
				if not culled.has(j):
					culled[j] = []
				culled[j].append(normal_pos)
			if a_covered:
				if not culled.has(i):
					culled[i] = []
				culled[i].append(normal_neg)


## Append mesh triangles to a SurfaceTool, skipping triangles whose face normal
## matches any of the blocked directions.
##
## Returns the number of triangles (faces) that were culled.
static func _append_with_culling(
	st: SurfaceTool, mesh: Mesh, xform: Transform3D,
	blocked_normals: Array
) -> int:
	if mesh.get_surface_count() == 0:
		return 0

	var arrays: Array = mesh.surface_get_arrays(0)
	if arrays.is_empty():
		return 0

	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	# Normals may not exist yet — compute face normals from triangle winding
	var has_normals := arrays[Mesh.ARRAY_NORMAL] != null and (arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array).size() > 0
	var mesh_normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if has_normals else PackedVector3Array()

	var indices: PackedInt32Array
	if arrays[Mesh.ARRAY_INDEX] != null:
		indices = arrays[Mesh.ARRAY_INDEX]
	else:
		# No index buffer — vertices are already in triangle order
		indices = PackedInt32Array()
		for k in range(verts.size()):
			indices.append(k)

	# Check for UVs (invariant across all triangles)
	var has_uvs := arrays[Mesh.ARRAY_TEX_UV] != null and (arrays[Mesh.ARRAY_TEX_UV] as PackedVector2Array).size() > 0
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if has_uvs else PackedVector2Array()

	var tri_count := indices.size() / 3
	var culled_count := 0

	for t: int in range(tri_count):
		var idx0 := indices[t * 3]
		var idx1 := indices[t * 3 + 1]
		var idx2 := indices[t * 3 + 2]

		var v0: Vector3 = verts[idx0]
		var v1: Vector3 = verts[idx1]
		var v2: Vector3 = verts[idx2]

		# Compute face normal in local mesh space
		var face_normal: Vector3
		if has_normals:
			# Use average of vertex normals (for flat-shaded BoxMesh, all 3 are identical)
			face_normal = ((mesh_normals[idx0] + mesh_normals[idx1] + mesh_normals[idx2]) / 3.0).normalized()
		else:
			face_normal = (v1 - v0).cross(v2 - v0).normalized()

		# Check if this face normal matches any blocked direction
		var is_blocked := false
		for blocked: Vector3 in blocked_normals:
			if face_normal.dot(blocked) > NORMAL_DOT_THRESHOLD:
				is_blocked = true
				break

		if is_blocked:
			culled_count += 1
			continue

		# Transform vertices and normals to assembly-local space
		var tv0: Vector3 = xform * v0
		var tv1: Vector3 = xform * v1
		var tv2: Vector3 = xform * v2
		# Transform normals using the basis (rotation only, no translation)
		var xform_basis: Basis = xform.basis
		var tn: Vector3
		if has_normals:
			tn = (xform_basis * mesh_normals[idx0]).normalized()
		else:
			tn = (tv1 - tv0).cross(tv2 - tv0).normalized()

		st.set_normal(tn)
		if has_uvs:
			st.set_uv(uvs[idx0])
		st.add_vertex(tv0)

		if has_normals:
			tn = (xform_basis * mesh_normals[idx1]).normalized()
		st.set_normal(tn)
		if has_uvs:
			st.set_uv(uvs[idx1])
		st.add_vertex(tv1)

		if has_normals:
			tn = (xform_basis * mesh_normals[idx2]).normalized()
		st.set_normal(tn)
		if has_uvs:
			st.set_uv(uvs[idx2])
		st.add_vertex(tv2)

	return culled_count


## Does surface 0 of `mesh` carry UVs?
##
## SurfaceTool.generate_tangents() raises "UVs are required to generate tangents"
## and produces an invalid commit if any appended surface lacks them. Checking up
## front is cheaper than losing a merged group to a failed commit — and a failed
## commit is invisible geometry with live collision, which is exactly the class of
## defect that got whole block categories banned from merging.
static func _surface_has_uv(mesh: Mesh) -> bool:
	if mesh == null or mesh.get_surface_count() == 0:
		return false
	var arrays: Array = mesh.surface_get_arrays(0)
	if arrays.is_empty() or arrays.size() <= Mesh.ARRAY_TEX_UV:
		return false
	var uv = arrays[Mesh.ARRAY_TEX_UV]
	return uv != null and (uv as PackedVector2Array).size() > 0
