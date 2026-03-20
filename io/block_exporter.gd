class_name BlockExporter
## Generates server-compatible collision data from registered blocks.
##
## Replaces the manual triple-duplication of collision boxes across
## GDScript world scripts, frog_physics.gd, and TypeScript server files.

## Export registered blocks as TypeScript ObstacleBox array string.
## Ready to paste into a server map file.
static func export_typescript(registry: BlockRegistry) -> String:
	var boxes := registry.export_collision_boxes()
	if boxes.is_empty():
		return "const OBSTACLES: ObstacleBox[] = [];\n"

	var lines := PackedStringArray()
	lines.append("const OBSTACLES: ObstacleBox[] = [")
	for box in boxes:
		var parts := "  { minX: %.1f, maxX: %.1f, minZ: %.1f, maxZ: %.1f, height: %.1f" % [
			box["min_x"], box["max_x"], box["min_z"], box["max_z"], box["height"]]
		if box.get("one_way", false):
			parts += ", oneWay: true"
		if box.get("bridge", false):
			parts += ", bridge: true"
		parts += " },"
		lines.append(parts)
	lines.append("];")
	return "\n".join(lines)


## Export registered blocks as GDScript ObstacleBox array string.
## Ready to paste into a physics prediction file.
static func export_gdscript(registry: BlockRegistry) -> String:
	var boxes := registry.export_collision_boxes()
	if boxes.is_empty():
		return "static var obstacle_boxes: Array = []\n"

	var lines := PackedStringArray()
	lines.append("static var obstacle_boxes: Array = [")
	for box in boxes:
		var ow := "true" if box.get("one_way", false) else "false"
		var br := "true" if box.get("bridge", false) else "false"
		lines.append("\t{\"min_x\": %.1f, \"max_x\": %.1f, \"min_z\": %.1f, \"max_z\": %.1f, \"height\": %.1f, \"one_way\": %s, \"bridge\": %s}," % [
			box["min_x"], box["max_x"], box["min_z"], box["max_z"],
			box["height"], ow, br])
	lines.append("]")
	return "\n".join(lines)


## Export as a simple Dictionary array (for passing between systems).
static func export_dicts(registry: BlockRegistry) -> Array[Dictionary]:
	return registry.export_collision_boxes()
