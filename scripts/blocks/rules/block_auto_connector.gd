class_name BlockAutoConnector
## Auto-connects blocks in an assembly based on spatial proximity + validators.
##
## For blocks with placement rules: uses validated connections (endpoint checks).
## Skips blocks with SHAPE_NONE (assembly root containers).
##
## Optimized: uses a spatial grid to only check nearby blocks — O(n) instead of O(n²).
## Blocks can only connect if their surfaces are within MAX_CONNECT_DIST of each other.

const MAX_CONNECT_DIST := 2.0  ## Max center-to-center distance for connection candidates
const GRID_CELL_SIZE := 3.0    ## Spatial grid cell size (slightly larger than MAX_CONNECT_DIST)


## Connect nearby blocks that have placement rules (validators).
## Returns the number of connections made.
static func connect_nearby(blocks: Array, registry) -> int:
	if blocks.size() < 2:
		return 0

	# Build spatial grid: bucket blocks by grid cell for O(1) neighbor lookup.
	var grid := {}  # Dictionary of Vector3i -> Array
	var grid_keys := []  # Separate key list for safe iteration
	for i in range(blocks.size()):
		var block = blocks[i]
		if block.collision_shape == BlockCategories.SHAPE_NONE:
			continue
		var cx := int(floor(block.position.x / GRID_CELL_SIZE))
		var cy := int(floor(block.position.y / GRID_CELL_SIZE))
		var cz := int(floor(block.position.z / GRID_CELL_SIZE))
		var cell := Vector3i(cx, cy, cz)
		if not grid.has(cell):
			grid[cell] = []
			grid_keys.append(cell)
		grid[cell].append(block)

	# For each cell, only check blocks in the same cell + 26 neighbors.
	var connected := 0
	var checked_pairs := {}
	var max_dist_sq := MAX_CONNECT_DIST * MAX_CONNECT_DIST

	for ki in range(grid_keys.size()):
		var cell = grid_keys[ki]
		var cell_blocks = grid[cell]
		# Check against this cell + all 26 neighbors
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				for dz in range(-1, 2):
					var neighbor_cell := Vector3i(cell.x + dx, cell.y + dy, cell.z + dz)
					if not grid.has(neighbor_cell):
						continue
					var neighbor_blocks = grid[neighbor_cell]
					for ai in range(cell_blocks.size()):
						var a = cell_blocks[ai]
						for bi in range(neighbor_blocks.size()):
							var b = neighbor_blocks[bi]
							# Skip self
							if a.block_id == b.block_id:
								continue
							# Skip already checked (order-independent key)
							var pair_key: String
							if a.block_id < b.block_id:
								pair_key = a.block_id + ":" + b.block_id
							else:
								pair_key = b.block_id + ":" + a.block_id
							if checked_pairs.has(pair_key):
								continue
							checked_pairs[pair_key] = true
							# Distance pre-filter — skip if too far apart
							var dist_sq: float = a.position.distance_squared_to(b.position)
							if dist_sq > max_dist_sq:
								continue
							# Skip already connected
							if a.is_connected_to(b.block_id):
								continue
							# Validated connection
							var result: Dictionary = registry.connect_blocks_validated(a.block_id, b.block_id)
							if result.get("valid", false):
								connected += 1
	return connected
