# Blocks — Composable Block Primitive Library for Godot 4

Declarative JSON → validated Block Resources → Node3D scene tree. A generic, game-agnostic library for building worlds from composable block primitives.

## Architecture

This library is structured into 8 domains with strict dependency rules. No domain depends on another at the same level — dependencies only flow inward toward `core/`.

```
scripts/blocks/
├── core/                       Entity + value objects (domain primitives)
│   ├── block.gd                Block Resource — identity, collision, visual, placement
│   ├── block_categories.gd     Shape/category/interaction enums
│   └── block_messages.gd       Message type constants for neuron communication
│
├── io/                         Serialization, file I/O, streaming
│   ├── block_file.gd           JSON parsing, path resolution, assembly composition
│   ├── block_exporter.gd       Server collision data export (TypeScript/GDScript)
│   ├── block_zone_loader.gd    Proximity-based zone streaming
│   └── block_pattern_expander.gd  Pattern expansion (ring, grid, line, scatter)
│
├── registry/                   Repository + quality gate
│   ├── block_registry.gd       Spatial grid, queries, peer connections, BFS routing
│   └── block_validator.gd      9-stage validation pipeline
│
├── building/                   Block Resource → Node3D subtree
│   ├── block_builder.gd        Mesh + collision shape factory
│   ├── block_materials.gd      Material palette + cache (38 colors)
│   ├── block_visuals.gd        Runtime emission/color + color chain animation
│   ├── block_mesh_merger.gd    Same-material mesh merging (draw call reduction)
│   ├── block_mesh_modifiers.gd Vertex displacement (noise, organic shaping)
│   ├── block_sdf_blender.gd    SDF smooth-union blending between blocks
│   └── block_shape_gen.gd      Pre-generated organic meshes (dome, ramp)
│
├── rules/                      Placement constraints + connection logic
│   ├── block_placement_rule.gd Base class + static factory
│   ├── block_auto_connector.gd Spatial-grid auto-connection for assemblies
│   ├── endpoint_snap_rule.gd   Chain adjacency validation
│   ├── vertical_stack_rule.gd  Vertical stacking validation
│   └── placement_rule_stack.gd Rule composition (intersection of positions)
│
├── physics/                    Spring dynamics
│   ├── block_physics_state.gd  State schema constants
│   ├── block_spring.gd         Per-block spring oscillator
│   └── block_spring_system.gd  System update loop + impulse propagation
│
├── neurons/                    Behavior + reactive state binding
│   └── block_neuron.gd         State bindings, peer connections, BFS propagation
│
├── lod/                        Distance-based detail levels
│   └── block_lod_controller.gd Cellular LOD 0-3 (runs every 0.5s)
│
└── tests/                      Automated test suites (551 tests)
```

## Dependency Rules

```
core/         ← depends on nothing (except Godot builtins)
io/           ← depends on core/
registry/     ← depends on core/
building/     ← depends on core/ (BlockMaterials, BlockCategories)
rules/        ← depends on core/ (Block, BlockCategories)
physics/      ← depends on core/ (Block, BlockCategories)
neurons/      ← depends on core/ (Block)
lod/          ← depends on registry/ (BlockRegistry)
```

**No circular dependencies.** Each domain only looks inward/down, never sideways.

## Circular Dependency Prevention

- **`preload()`** only for scripts that DON'T have `class_name` dependencies on each other.
- **`class_name`** (global) for all cross-domain references in method bodies. These resolve at call time when the cache is populated.
- **`load()`** (runtime) for scripts that extend each other within the same domain. See `block_placement_rule.gd` loading `endpoint_snap_rule.gd`.

## How To Add New Components

### New Shape Type
1. Add constant to `core/block_categories.gd`
2. Handle in `building/block_builder.gd` `_create_collision_shape()` + `_create_mesh()`
3. Handle in `core/block.gd` `to_collision_dict()` + `_valid_split_axes()`
4. Run tests

### New Material
1. Add to `PALETTE` dictionary in `building/block_materials.gd`
2. Use `material_id` key in block JSON

### New Placement Rule
1. Create `rules/my_rule.gd` extending `BlockPlacementRule`
2. Override `check_connection()` and/or `get_snap_positions()`
3. Register in `rules/block_placement_rule.gd` `_ensure_registry()`
4. Run tests

### New Physics Behavior
1. Add state keys to `physics/block_physics_state.gd`
2. Handle in `physics/block_spring.gd` `step()` or create a new system

### New Neuron Behavior
1. Add options/bindings in `neurons/block_neuron.gd`
2. Set via `"neuron"` section in block JSON

## Debugging Guide

| Symptom | Domain to check |
|---------|----------------|
| Block doesn't appear | `building/block_builder.gd` — check shape/material |
| Block appears wrong color | `building/block_materials.gd` — check PALETTE key |
| Validation rejects block | `registry/block_validator.gd` — check which stage fails |
| Block not found by query | `registry/block_registry.gd` — check spatial grid cell |
| Connections not forming | `rules/block_auto_connector.gd` or specific rule in `rules/` |
| Spring physics wrong | `physics/block_spring.gd` — check spring_k, damping values |
| LOD not updating | `lod/block_lod_controller.gd` — check camera_pos input |
| Zone not loading | `io/block_zone_loader.gd` + `io/block_file.gd` |
| Mesh merging skipped | `building/block_mesh_merger.gd` — check extent/block count |
| Neuron not reacting | `neurons/block_neuron.gd` — check state bindings |

## Test Commands

```bash
# Car assembly suite (157 tests — hierarchy, validation, builder, collision export)
godot --headless --script res://scripts/blocks/tests/run_tests.gd

# Power grid suite (394 tests — connections, BFS, cascade failures, visual states)
godot --headless --script res://scripts/blocks/tests/run_power_grid_tests.gd

# Cellular suite (subdivision, merge, LOD, DNA, amoeba movement)
godot --headless --script res://scripts/blocks/tests/run_cellular_tests.gd
```

**Always run tests after modifying any file in this directory.**
