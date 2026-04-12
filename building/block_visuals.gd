class_name BlockVisuals
## Runtime visual state changes for built blocks.
##
## Modifies MeshInstance3D materials on already-built block nodes.
## Use for: power-on glow, damage flashes, highlight selection, etc.
## Clones material once per block, then modifies in-place on subsequent calls.

## Metadata key used to track whether a MeshInstance3D's material_override
## has already been cloned for per-instance modification.
const _OWNED_META := &"bv_owned"


## Get or create a per-instance StandardMaterial3D for a block's mesh.
## First call clones the shared material; subsequent calls return the
## existing clone for in-place modification (no allocation).
static func _ensure_owned_material(mesh: MeshInstance3D, block: Block) -> StandardMaterial3D:
	if mesh.has_meta(_OWNED_META) and mesh.material_override is StandardMaterial3D:
		return mesh.material_override as StandardMaterial3D
	var mat: StandardMaterial3D
	if mesh.material_override is StandardMaterial3D:
		mat = mesh.material_override.duplicate() as StandardMaterial3D
	else:
		mat = StandardMaterial3D.new()
		mat.albedo_color = BlockMaterials.PALETTE.get(block.material_id,
			BlockMaterials.PALETTE["default"])
	mesh.material_override = mat
	mesh.set_meta(_OWNED_META, true)
	return mat


## Set emission color and intensity on a block's mesh.
## Returns true if the mesh was found and modified.
static func set_emission(block: Block, color: Color, energy: float = 1.0) -> bool:
	if block.node == null:
		return false
	var mesh := block.node.get_node_or_null("Mesh") as MeshInstance3D
	if mesh == null:
		return false

	var mat: StandardMaterial3D = _ensure_owned_material(mesh, block)
	mat.emission_enabled = energy > 0.0
	mat.emission = color
	mat.emission_energy_multiplier = energy
	return true


## Clear emission (turn off glow) on a block's mesh.
static func clear_emission(block: Block) -> bool:
	return set_emission(block, Color.BLACK, 0.0)


## Set albedo color on a block's mesh (change base color at runtime).
static func set_color(block: Block, color: Color) -> bool:
	if block.node == null:
		return false
	var mesh := block.node.get_node_or_null("Mesh") as MeshInstance3D
	if mesh == null:
		return false

	var mat: StandardMaterial3D = _ensure_owned_material(mesh, block)
	mat.albedo_color = color
	return true


## Convenience: set "powered" visual state (green emission).
static func set_powered(block: Block, powered: bool) -> bool:
	if powered:
		return set_emission(block, Color(0.0, 1.0, 0.2), 2.0)
	else:
		return set_emission(block, Color(1.0, 0.1, 0.0), 0.5)


## Convenience: set "warning" visual state (orange emission).
static func set_warning(block: Block) -> bool:
	return set_emission(block, Color(1.0, 0.6, 0.0), 1.5)


## Convenience: set "dividing" visual state (yellow emission pulse).
static func set_dividing(block: Block) -> bool:
	return set_emission(block, Color(0.9, 0.7, 0.2), 2.5)


## Convenience: set "merged" visual state (green emission flash).
static func set_merged(block: Block) -> bool:
	return set_emission(block, Color(0.2, 0.8, 0.3), 2.0)


## Walk the connection chain starting from a block, coloring each sequentially.
## For a linear chain (each block has ≤2 connections), this walks from start
## to end, applying a rainbow hue gradient. Returns the ordered chain.
##
## registry: BlockRegistry instance for block lookups.
## world_root: Node3D to create the tween on.
## callback: Optional callable(block, index, total) invoked per step.
## delay: seconds between each color step (default 0.08 = ~5 seconds for 58 blocks)
static func run_color_chain(start_block_id: String, registry, world_root: Node3D, callback: Callable = Callable(), delay: float = 0.08) -> Array:
	var chain: Array = []
	var visited := {}
	var current_id := start_block_id

	# Walk the chain sequentially (each block has ≤2 connections in a line)
	while current_id != "" and not visited.has(current_id):
		visited[current_id] = true
		var block = registry.get_block(current_id)
		if block == null:
			break
		chain.append(block)

		# Find next unvisited connection
		current_id = ""
		for conn_id in block.connections:
			if not visited.has(conn_id):
				current_id = conn_id
				break

	# Animate color through chain using tween
	if not chain.is_empty() and world_root:
		var tween := world_root.create_tween()
		for i in range(chain.size()):
			var b = chain[i]
			var hue: float = float(i) / float(chain.size())
			var color := Color.from_hsv(hue, 0.8, 1.0)
			var idx := i
			var total := chain.size()
			tween.tween_callback(func():
				BlockVisuals.set_color(b, color)
				if callback.is_valid():
					callback.call(b, idx, total)
			)
			tween.tween_interval(delay)

	return chain
