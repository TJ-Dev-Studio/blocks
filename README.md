# Blocks

A composable Block primitive library for Godot 4. Blocks are lightweight `Resource` objects that define geometry, collision, materials, interaction rules, parent-child hierarchies, peer-to-peer connections, and runtime state — everything needed to build complex structures from simple parts.

## What's a Block?

A `Block` is a single Godot `Resource` with:

- **Identity** — unique `block_id`, human-readable `block_name`, tags
- **Geometry** — shape type (BOX, SPHERE, CYLINDER, CAPSULE), dimensions
- **Collision** — layer/mask bits, server-collidable flag
- **Material** — color from a named palette, roughness, metallic
- **Interaction** — category (STRUCTURE, PROP, TRIGGER, EFFECT), interactable flag, trigger zones
- **Links** — parent/child hierarchy via `parent_block_id` and `child_block_ids`
- **Connections** — peer-to-peer edges for arbitrary topologies (power grids, networks)
- **State** — runtime mutable dictionary for dynamic properties (powered, voltage, temperature)

## Library Files

| File | Purpose |
|------|---------|
| `block.gd` | Core `Block` resource — all properties and connection methods |
| `block_categories.gd` | Category enum (STRUCTURE, PROP, TRIGGER, EFFECT) + collision presets |
| `block_materials.gd` | Named color palette (30+ colors) + roughness values |
| `block_validator.gd` | Validates blocks — geometry, collision, links, connections |
| `block_registry.gd` | Runtime registry — register/query/message/connect blocks |
| `block_builder.gd` | Converts blocks to Node3D scene trees with MeshInstance3D + CollisionShape3D |
| `block_exporter.gd` | Exports server-collidable blocks as AABB dictionaries |
| `block_visuals.gd` | Runtime visual state — emission, color, powered/warning indicators |

## Tests

**551 tests across 2 suites, all passing.**

### Car Assembly (157 tests)
Builds a 12-block car (chassis, wheels, windows, headlights, exhaust) to test creation, validation, hierarchy, queries, collision export, and builder output.

```bash
godot --headless --script res://scripts/blocks/tests/run_tests.gd
```

### Power Grid (394 tests)
Builds a 28-block electrical grid (generator, transformers, power lines, houses, street lights) to stress-test peer connections, BFS message propagation, runtime state, visual emission, cascade failures, and isolated components.

```bash
godot --headless --script res://scripts/blocks/tests/run_power_grid_tests.gd
```

### Power Grid Screenshots

Three visual states captured from the Power Grid scene:

| Unpowered | Propagating | Fully Powered |
|-----------|-------------|---------------|
| ![Unpowered](scripts/blocks/tests/screenshots/grid_unpowered.png) | ![Propagating](scripts/blocks/tests/screenshots/grid_propagating.png) | ![Powered](scripts/blocks/tests/screenshots/grid_powered.png) |

See [`scripts/blocks/tests/README.md`](scripts/blocks/tests/README.md) for full test documentation with topology diagrams.

## Quick Start

```gdscript
# Create a block
var wall := Block.new()
wall.block_id = "wall_01"
wall.block_name = "Stone Wall"
wall.shape_type = Block.ShapeType.BOX
wall.dimensions = Vector3(4, 3, 0.5)
wall.color = BlockMaterials.get_color("stone_gray")

# Register and build
var registry := BlockRegistry.new()
registry.register(wall)
var node := BlockBuilder.build(wall)
add_child(node)

# Connect two blocks
registry.connect_blocks("wall_01", "light_01")

# Send a message through connections
registry.send_message("light_01", "power_on", {"voltage": 120})
```

## Requirements

- Godot 4.4+
- No external dependencies
