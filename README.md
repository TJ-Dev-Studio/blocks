# Blocks

A composable Block primitive library for Godot 4. Blocks are lightweight `Resource` objects that define geometry, collision, materials, interaction rules, parent-child hierarchies, peer-to-peer connections, cellular division, LOD adaptation, and DNA-encoded behavior rules.

## Vision

Blocks are cells and neurons simultaneously. They divide like biological cells, connect like neural networks, and recombine like amoebas. A single block can subdivide into smaller blocks for higher detail, merge back together for lower detail, and encode division rules in DNA that propagate through generations.

This enables:
- **Adaptive LOD** — blocks subdivide on powerful hardware, stay coarse on weak hardware
- **Emergent movement** — organisms move by dividing at the front and merging at the rear
- **Self-assembling structures** — DNA rules guide how blocks split and what properties children inherit
- **Neural signal cascades** — messages propagate through connection graphs, triggering subdivision chains

## What's a Block?

A `Block` is a single Godot `Resource` with:

- **Identity** — unique `block_id`, human-readable `block_name`, tags
- **Geometry** — shape type (BOX, SPHERE, CYLINDER, CAPSULE), dimensions
- **Collision** — layer/mask bits, server-collidable flag
- **Material** — color from a named palette (40+ colors), roughness, metallic
- **Interaction** — category (STRUCTURE, PROP, TRIGGER, EFFECT), interactable flag, trigger zones
- **Links** — parent/child hierarchy via `parent_id` and `child_ids`
- **Connections** — peer-to-peer edges for arbitrary topologies (power grids, networks)
- **State** — runtime mutable dictionary for dynamic properties (powered, voltage, temperature)
- **Cellular** — `lod_level`, `parent_lod_id`, `child_lod_ids`, `min_size`, `dna`, `active`

## Cellular System

Blocks can divide and recombine like living cells.

### Subdivision

```
         [4x4x4]              Split X          [2x4x4] [2x4x4]
         LOD 0         ──────────────────►       LOD 1    LOD 1

         [4x4x4]            Octree split       [2x2x2] x 8
         LOD 0         ──────────────────►       LOD 1
```

- `block.can_subdivide(axis)` — checks if dimension >= min_size * 2
- `block.subdivide(axis)` — splits into 2 children (single axis) or up to 8 (all axes for BOX)
- `block.merge_with(other)` — combines two blocks, infers merge axis from position delta
- Children inherit material, tags, interaction, collision, DNA per inheritance rules

### LOD Hierarchy

```
                    [Root LOD 0]
                   /            \
          [Child LOD 1]    [Child LOD 1]
          /          \
  [Leaf LOD 2]  [Leaf LOD 2]
```

- `registry.adapt_lod(block_ids, target_level)` — recursively subdivide or merge to reach target
- `registry.get_active_blocks()` — returns only leaf blocks (parents deactivated on split)
- `registry.get_subdivision_tree(id)` — returns full LOD hierarchy as nested dictionary

### DNA

Blocks encode division rules in a `dna` dictionary:

| Key | Type | Effect |
|-----|------|--------|
| `axis_preference` | int (-1 to 2) | Preferred split axis (-1 = auto) |
| `child_count` | int (2, 4, 8) | Expected children per division |
| `inherit_tags` | bool | Whether children inherit parent tags |
| `property_overrides` | Dictionary | Properties to override on children |

## Library Files

| File | Purpose |
|------|---------|
| `block.gd` | Core `Block` resource — properties, connections, subdivide, merge |
| `block_categories.gd` | Category/shape/interaction enums + collision presets |
| `block_materials.gd` | Named color palette (40+ colors) + roughness values |
| `block_validator.gd` | Validates blocks — geometry, collision, links, connections, LOD, DNA |
| `block_registry.gd` | Runtime registry — register/query/message/connect/subdivide/merge/adapt |
| `block_builder.gd` | Converts blocks to Node3D scene trees with MeshInstance3D + CollisionShape3D |
| `block_exporter.gd` | Exports server-collidable blocks as AABB dictionaries |
| `block_visuals.gd` | Runtime visual state — emission, color, powered/warning/dividing/merged |

## Tests

**811 tests across 3 suites, all passing.**

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

### Cellular System (260 tests)
Tests subdivision, merge, LOD adaptation, DNA inheritance, connection transfer, shape support, and two novel integration tests:

- **Amoeba Movement** — 8-block organism moves by subdividing front cells and merging rear cells, shifting center of mass forward
- **Neural Cascade** — signal propagation through connection graphs triggers subdivision chains in branching network topologies

Stress test: 50 blocks subdivided to LOD 3 (750 total, 400 active leaves), validated, merged back, with spatial and category queries.

```bash
godot --headless --script res://scripts/blocks/tests/run_cellular_tests.gd
```

### Screenshots

**Power Grid** — three visual states:

| Unpowered | Propagating | Fully Powered |
|-----------|-------------|---------------|
| ![Unpowered](scripts/blocks/tests/screenshots/grid_unpowered.png) | ![Propagating](scripts/blocks/tests/screenshots/grid_propagating.png) | ![Powered](scripts/blocks/tests/screenshots/grid_powered.png) |

**Cellular System** — division, amoeba, LOD:

| Single Cell | Octree Division | LOD Comparison |
|-------------|-----------------|----------------|
| ![Cell](scripts/blocks/tests/screenshots/cellular/01_single_cell.png) | ![Octree](scripts/blocks/tests/screenshots/cellular/02_octree_division.png) | ![LOD](scripts/blocks/tests/screenshots/cellular/05_lod_compare.png) |

See [`scripts/blocks/tests/README.md`](scripts/blocks/tests/README.md) for full test documentation with topology diagrams.

## Quick Start

```gdscript
# Create a block
var wall := Block.new()
wall.block_name = "Stone Wall"
wall.collision_shape = BlockCategories.SHAPE_BOX
wall.collision_size = Vector3(4, 3, 0.5)
wall.collision_layer = CollisionLayers.WORLD
wall.material_id = "stone_gray"

# Register and build
var registry := BlockRegistry.new()
registry.register(wall)
var node := BlockBuilder.build(wall, self)

# Connect two blocks
registry.connect_blocks(wall.block_id, "light_01")

# Send a message through connections
registry.send_message("light_01", "power_on", {"voltage": 120})

# Subdivide a block into children
var children := registry.subdivide_block(wall.block_id, 0)  # split along X

# Adapt all blocks to LOD level 2
registry.adapt_lod([wall.block_id], 2)

# Get only active (leaf) blocks
var leaves := registry.get_active_blocks()
```

## Requirements

- Godot 4.4+
- No external dependencies
