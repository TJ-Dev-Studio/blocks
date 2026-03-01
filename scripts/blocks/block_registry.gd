class_name BlockRegistry
extends Node
## Central registry for all Block instances in the world.
##
## Validates blocks on registration, maintains spatial index for
## proximity queries, tracks by category, and exports collision data
## for server sync. Designed as an autoload singleton.

signal block_added(block: Block)
signal block_removed(block: Block)
signal block_updated(block: Block)
signal message_received(target_block: Block, msg_type: String, data: Dictionary, sender_id: String)

# --- Storage ---

## All registered blocks by ID.
var _blocks: Dictionary = {}

## Blocks indexed by category.
var _by_category: Dictionary = {}

## Spatial grid for proximity queries.
var _grid: Dictionary = {}
const GRID_CELL_SIZE := 20.0

## Last validation errors (from most recent register() call that failed).
var _last_errors: Array[String] = []


func _ready() -> void:
	# Initialize category buckets
	for cat in [BlockCategories.TERRAIN, BlockCategories.PROP,
				BlockCategories.STRUCTURE, BlockCategories.CREATURE,
				BlockCategories.EFFECT, BlockCategories.TRIGGER_CAT]:
		_by_category[cat] = [] as Array[Block]
	print("[BlockRegistry] Ready")


# =========================================================================
# Registration
# =========================================================================

## Register a block. Validates first; returns true if valid and registered.
func register(block: Block) -> bool:
	block.ensure_id()

	var errors := BlockValidator.validate(block)
	if not errors.is_empty():
		_last_errors = errors
		push_warning("[BlockRegistry] Block '%s' (%s) failed validation: %s" % [
			block.block_name, block.block_id, ", ".join(errors)])
		return false

	# Prevent duplicate registration
	if _blocks.has(block.block_id):
		push_warning("[BlockRegistry] Block '%s' already registered" % block.block_id)
		return false

	_blocks[block.block_id] = block
	block.active = true
	block.instantiated_at = int(Time.get_unix_time_from_system())

	# Category index
	if _by_category.has(block.category):
		_by_category[block.category].append(block)

	# Spatial index
	_grid_insert(block)

	# Wire parent-child links if parent exists
	if block.has_parent() and _blocks.has(block.parent_id):
		var parent_block: Block = _blocks[block.parent_id]
		parent_block.add_child_link(block.block_id)

	block_added.emit(block)
	_last_errors = []
	return true


## Unregister a block and remove from all indices.
func unregister(block_id: String) -> void:
	if not _blocks.has(block_id):
		return

	var block: Block = _blocks[block_id]
	block.active = false
	block.destroyed_at = int(Time.get_unix_time_from_system())

	# Remove from parent's child list
	if block.has_parent() and _blocks.has(block.parent_id):
		var parent_block: Block = _blocks[block.parent_id]
		parent_block.remove_child_link(block_id)

	# Remove peer connections (bidirectional cleanup)
	for conn_id in block.connections:
		var peer := get_block(conn_id)
		if peer != null:
			peer.remove_connection(block_id)

	# Remove from category index
	if _by_category.has(block.category):
		_by_category[block.category].erase(block)

	# Remove from spatial index
	_grid_remove(block)

	_blocks.erase(block_id)
	block_removed.emit(block)


## Update a block's position (re-indexes spatially).
func update_position(block_id: String, new_pos: Vector3) -> void:
	if not _blocks.has(block_id):
		return
	var block: Block = _blocks[block_id]
	_grid_remove(block)
	block.position = new_pos
	_grid_insert(block)
	block_updated.emit(block)


# =========================================================================
# Queries
# =========================================================================

## Get a block by ID (null if not found).
func get_block(block_id: String) -> Block:
	return _blocks.get(block_id)


## Get all blocks in a category.
func get_blocks_by_category(category: int) -> Array:
	return _by_category.get(category, [])


## Get blocks matching a tag.
func get_blocks_by_tag(tag: String) -> Array[Block]:
	var result: Array[Block] = []
	for block in _blocks.values():
		if tag in block.tags:
			result.append(block)
	return result


## Get all blocks near a position within radius (XZ distance).
func get_blocks_near(pos: Vector3, radius: float) -> Array[Block]:
	var result: Array[Block] = []
	var r_sq := radius * radius
	var min_gx := int(floor((pos.x - radius) / GRID_CELL_SIZE))
	var max_gx := int(floor((pos.x + radius) / GRID_CELL_SIZE))
	var min_gz := int(floor((pos.z - radius) / GRID_CELL_SIZE))
	var max_gz := int(floor((pos.z + radius) / GRID_CELL_SIZE))

	for gx in range(min_gx, max_gx + 1):
		for gz in range(min_gz, max_gz + 1):
			var key := "%d_%d" % [gx, gz]
			if _grid.has(key):
				for block: Block in _grid[key]:
					var dx := block.position.x - pos.x
					var dz := block.position.z - pos.z
					if dx * dx + dz * dz <= r_sq:
						result.append(block)
	return result


## Get all children of a block (resolved from child_ids).
func get_child_blocks(block_id: String) -> Array[Block]:
	var result: Array[Block] = []
	var block := get_block(block_id)
	if block == null:
		return result
	for cid in block.child_ids:
		var child := get_block(cid)
		if child != null:
			result.append(child)
	return result


## Get the parent block (null if no parent or not found).
func get_parent_block(block_id: String) -> Block:
	var block := get_block(block_id)
	if block == null or not block.has_parent():
		return null
	return get_block(block.parent_id)


## Walk up the parent chain to the root block.
func get_root(block_id: String) -> Block:
	var block := get_block(block_id)
	if block == null:
		return null
	var visited := {}  # Cycle detection
	while block.has_parent() and _blocks.has(block.parent_id):
		if visited.has(block.block_id):
			push_warning("[BlockRegistry] Cycle detected in parent chain at '%s'" % block.block_id)
			return block
		visited[block.block_id] = true
		block = _blocks[block.parent_id]
	return block


## Walk the full tree of descendants (BFS).
func get_descendants(block_id: String) -> Array[Block]:
	var result: Array[Block] = []
	var queue: Array[String] = [block_id]
	var visited := {}

	while not queue.is_empty():
		var current_id: String = queue.pop_front()
		if visited.has(current_id):
			continue
		visited[current_id] = true
		var block := get_block(current_id)
		if block == null:
			continue
		if current_id != block_id:  # Don't include self
			result.append(block)
		for cid in block.child_ids:
			if not visited.has(cid):
				queue.append(cid)

	return result


## Find a path between two blocks through parent/child links (BFS).
## Returns array of block_ids forming the path, or empty if no path exists.
func find_path(from_id: String, to_id: String) -> Array[String]:
	if from_id == to_id:
		return [from_id]
	if not _blocks.has(from_id) or not _blocks.has(to_id):
		return []

	# BFS through parent + child links
	var queue: Array[String] = [from_id]
	var came_from: Dictionary = {}  # block_id -> previous block_id
	came_from[from_id] = ""

	while not queue.is_empty():
		var current_id: String = queue.pop_front()
		var current := get_block(current_id)
		if current == null:
			continue

		# Collect all neighbors (parent + children + peer connections)
		var neighbors: Array[String] = []
		if current.has_parent():
			neighbors.append(current.parent_id)
		for cid in current.child_ids:
			neighbors.append(cid)
		for conn_id in current.connections:
			neighbors.append(conn_id)

		for neighbor_id in neighbors:
			if came_from.has(neighbor_id):
				continue
			came_from[neighbor_id] = current_id
			if neighbor_id == to_id:
				# Reconstruct path
				var path: Array[String] = []
				var step := to_id
				while step != "":
					path.append(step)
					step = came_from[step]
				path.reverse()
				return path
			queue.append(neighbor_id)

	return []  # No path found


## Get all registered blocks.
func get_all_blocks() -> Array:
	return _blocks.values()


## Get count of registered blocks.
func get_block_count() -> int:
	return _blocks.size()


## Get last validation errors from a failed register().
func get_last_errors() -> Array[String]:
	return _last_errors


# =========================================================================
# Peer Connections
# =========================================================================

## Connect two blocks bidirectionally.
func connect_blocks(block_id_a: String, block_id_b: String) -> bool:
	var a := get_block(block_id_a)
	var b := get_block(block_id_b)
	if a == null or b == null:
		return false
	a.add_connection(block_id_b)
	b.add_connection(block_id_a)
	return true


## Disconnect two blocks bidirectionally.
func disconnect_blocks(block_id_a: String, block_id_b: String) -> void:
	var a := get_block(block_id_a)
	var b := get_block(block_id_b)
	if a != null:
		a.remove_connection(block_id_b)
	if b != null:
		b.remove_connection(block_id_a)


## Get all blocks connected to a given block (resolved from connections).
func get_connected_blocks(block_id: String) -> Array[Block]:
	var result: Array[Block] = []
	var block := get_block(block_id)
	if block == null:
		return result
	for conn_id in block.connections:
		var peer := get_block(conn_id)
		if peer != null:
			result.append(peer)
	return result


## Get connection IDs for a block.
func get_connections(block_id: String) -> PackedStringArray:
	var block := get_block(block_id)
	if block == null:
		return PackedStringArray()
	return block.connections


# =========================================================================
# Message Passing
# =========================================================================

## Send a message to a specific block. Emits message_received signal.
## Returns true if the target block exists.
func send_message(target_id: String, msg_type: String, data: Dictionary = {},
		sender_id: String = "") -> bool:
	var target := get_block(target_id)
	if target == null:
		return false
	message_received.emit(target, msg_type, data, sender_id)
	return true


## Broadcast a message to all blocks connected to sender.
## Returns count of messages sent.
func broadcast_to_connections(sender_id: String, msg_type: String,
		data: Dictionary = {}) -> int:
	var sender := get_block(sender_id)
	if sender == null:
		return 0
	var count := 0
	for conn_id in sender.connections:
		if send_message(conn_id, msg_type, data, sender_id):
			count += 1
	return count


## Propagate a message through the entire connection graph using BFS.
## Returns all blocks reached (including start).
func propagate_through_connections(start_id: String, msg_type: String,
		data: Dictionary = {}) -> Array[Block]:
	var reached: Array[Block] = []
	if not _blocks.has(start_id):
		return reached

	var queue: Array[String] = [start_id]
	var visited := {}

	while not queue.is_empty():
		var current_id: String = queue.pop_front()
		if visited.has(current_id):
			continue
		visited[current_id] = true

		var block := get_block(current_id)
		if block == null:
			continue

		reached.append(block)
		send_message(current_id, msg_type, data, start_id)

		for conn_id in block.connections:
			if not visited.has(conn_id):
				queue.append(conn_id)

	return reached


# =========================================================================
# Server Collision Export
# =========================================================================

## Export all server-collidable blocks as collision box dictionaries.
func export_collision_boxes() -> Array[Dictionary]:
	var boxes: Array[Dictionary] = []
	for block: Block in _blocks.values():
		var dict := block.to_collision_dict()
		if not dict.is_empty():
			boxes.append(dict)
	return boxes


# =========================================================================
# Bulk operations
# =========================================================================

## Unregister all blocks. Useful for scene transitions.
func clear() -> void:
	var ids := _blocks.keys().duplicate()
	for block_id in ids:
		unregister(block_id)
	_grid.clear()
	_last_errors.clear()


# =========================================================================
# Spatial Grid (private)
# =========================================================================

func _grid_key(pos: Vector3) -> String:
	var gx := int(floor(pos.x / GRID_CELL_SIZE))
	var gz := int(floor(pos.z / GRID_CELL_SIZE))
	return "%d_%d" % [gx, gz]


func _grid_insert(block: Block) -> void:
	var key := _grid_key(block.position)
	if not _grid.has(key):
		_grid[key] = []
	_grid[key].append(block)


func _grid_remove(block: Block) -> void:
	var key := _grid_key(block.position)
	if _grid.has(key):
		_grid[key].erase(block)
		if _grid[key].is_empty():
			_grid.erase(key)
