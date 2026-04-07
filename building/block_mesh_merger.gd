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
				# Selective copy — skip triangles facing blocked directions
				total_faces_culled += _append_with_culling(
					st, entry["mesh"], entry["transform"], culled_faces[i])
			else:
				# No faces to cull — use fast path
				st.append_from(entry["mesh"], 0, entry["transform"])

		# Do NOT call generate_normals() — source meshes already have correct
		# per-face normals (flat shading). Regenerating would smooth-average 90°
		# box corners, creating visible shading gradients on every face.
		st.generate_tangents()
		var merged_mesh: ArrayMesh = st.commit()

		var merged_inst := MeshInstance3D.new()
		var name_suffix := ("_c" + chunk_id) if is_chunk else ""
		merged_inst.name = "Merged_%d%s" % [merged_count, name_suffix]
		merged_inst.mesh = merged_mesh
		merged_inst.material_override = group["material"]
		merged_inst.cast_shadow = group["shadow"] as GeometryInstance3D.ShadowCastingSetting

		# Chunked merges get visibility_range — small AABB makes distance culling safe.
		# Non-chunked merges (small assemblies) rely on frustum culling only.
		if is_chunk:
			merged_inst.visibility_range_end = CHUNK_VIS_RANGE
			merged_inst.visibility_range_end_margin = 2.0
			merged_inst.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED

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
static func _find_culled_faces(meshes: Array) -> Dictionary:
	# culled[entry_index] = Array[Vector3] of blocked normal directions
	var culled: Dictionary = {}

	# Pre-compute AABB data for box entries only
	# aabb_data[i] = {min: Vector3, max: Vector3} or null if not a box
	var aabb_data: Array = []
	aabb_data.resize(meshes.size())

	for i: int in range(meshes.size()):
		var entry: Dictionary = meshes[i]
		if entry["shape"] != BlockCategories.SHAPE_BOX:
			aabb_data[i] = null
			continue
		var mesh: Mesh = entry["mesh"]
		if not mesh is BoxMesh:
			aabb_data[i] = null
			continue
		var box_mesh: BoxMesh = mesh as BoxMesh
		var half_size: Vector3 = box_mesh.size * 0.5
		var origin: Vector3 = entry["transform"].origin
		aabb_data[i] = {
			"min": origin - half_size,
			"max": origin + half_size,
		}

	# Check all pairs of box entries
	for i: int in range(meshes.size()):
		if aabb_data[i] == null:
			continue
		var a_min: Vector3 = aabb_data[i]["min"]
		var a_max: Vector3 = aabb_data[i]["max"]

		for j: int in range(i + 1, meshes.size()):
			if aabb_data[j] == null:
				continue
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
					# Only cull A's face if B covers enough of it
					if a_covered:
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
					if b_covered:
						if not culled.has(j):
							culled[j] = []
						culled[j].append(normal_pos)
					if a_covered:
						if not culled.has(i):
							culled[i] = []
						culled[i].append(normal_neg)

	return culled


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
