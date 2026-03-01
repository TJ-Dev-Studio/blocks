class_name BlockVisuals
## Runtime visual state changes for built blocks.
##
## Modifies MeshInstance3D materials on already-built block nodes.
## Use for: power-on glow, damage flashes, highlight selection, etc.
## Always duplicates materials to avoid shared-cache side effects.

## Set emission color and intensity on a block's mesh.
## Returns true if the mesh was found and modified.
static func set_emission(block: Block, color: Color, energy: float = 1.0) -> bool:
	if block.node == null:
		return false
	var mesh := block.node.get_node_or_null("Mesh") as MeshInstance3D
	if mesh == null:
		return false

	# Clone material to avoid shared-material side effects
	var mat: StandardMaterial3D
	if mesh.material_override is StandardMaterial3D:
		mat = mesh.material_override.duplicate() as StandardMaterial3D
	else:
		mat = StandardMaterial3D.new()
		mat.albedo_color = BlockMaterials.PALETTE.get(block.material_id,
			BlockMaterials.PALETTE["default"])

	mat.emission_enabled = energy > 0.0
	mat.emission = color
	mat.emission_energy_multiplier = energy
	mesh.material_override = mat
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

	var mat: StandardMaterial3D
	if mesh.material_override is StandardMaterial3D:
		mat = mesh.material_override.duplicate() as StandardMaterial3D
	else:
		mat = StandardMaterial3D.new()

	mat.albedo_color = color
	mesh.material_override = mat
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
