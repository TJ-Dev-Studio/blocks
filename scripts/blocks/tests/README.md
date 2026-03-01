# Block Library Test Suite

Two test suites validate the Block primitive system: a Car assembly (157 tests) and a Power Grid (394 tests). Together they cover block creation, validation, registration, parent-child hierarchies, peer-to-peer connections, message passing, power propagation, visual state changes, cascade failures, collision export, and stress testing.

**551 total tests. All passing.**

---

## Power Grid Test

Builds an electrical power grid from **28 blocks** to stress-test the framework beyond simple parent-child trees. The grid uses peer-to-peer connections, BFS message propagation, runtime state tracking, and visual emission changes.

### Block Inventory

| Block(s) | Count | Category | Shape | Material |
|----------|-------|----------|-------|----------|
| Generator | 1 | STRUCTURE | BOX 3x4x3 | generator_yellow |
| Transformers | 3 | STRUCTURE | BOX 2x3x2 | transformer_gray |
| Power Lines | 8 | PROP | BOX 0.15x0.15x6 | wire_copper |
| Houses | 6 | STRUCTURE | BOX 4x3x4 | house_beige / house_blue |
| Street Lights | 8 | EFFECT | CYL r=0.2 h=4 | light_pole |
| Control Tower | 1 | TRIGGER | BOX 2x5x2 | blue_metal |
| Water Tower | 1 | STRUCTURE | CYL r=2 h=6 | metal_light |

### Connection Topology

```
                [Control Tower]
                      |
                [Generator]
               /      |      \
       [Trans_N]  [Trans_S]  [Trans_E]
        /   \       /   \       /   \
    [H0] [H1]   [H2] [H3]   [H4] [H5]
     |   / \      |     |    / \     |
    L0  L1 L2    L3    L4  L5 L6   L7

    [Water Tower]  (isolated — never powered)
```

27 blocks connected via bidirectional peer edges. 1 block (Water Tower) intentionally isolated.

### Screenshots

#### Grid Unpowered
All blocks built with base materials. Red emission indicates no power flowing.

![Unpowered](screenshots/grid_unpowered.png)

#### Power Propagating
Generator and transformers lit green. Houses and street lights still dark — power hasn't reached them yet.

![Propagating](screenshots/grid_propagating.png)

#### Fully Powered
Entire connected grid glowing green with bloom. Water tower remains dark (isolated, never receives power).

![Powered](screenshots/grid_powered.png)

### Test Groups (394 tests)

| # | Group | Tests | Description |
|---|-------|-------|-------------|
| 1 | Block State | 14 | Runtime `state` dict: CRUD, types, reset on duplicate |
| 2 | Connections Basic | 20 | Peer connection add/remove, bidirectional via registry |
| 3 | Message Passing | 18 | Signal delivery, broadcast, BFS propagation, cycle safety |
| 4 | Visual State | 15 | Emission, color, powered/warning states, material isolation |
| 5 | Connection Validation | 12 | Self-connect, empty ID, duplicate rejection |
| 6 | Grid Construction | 35 | All 28 blocks with correct properties |
| 7 | Grid Registration | 20 | Category/tag queries across 28 blocks |
| 8 | Peer Topology | 25 | Connection graph edges, bidirectionality, degree counts |
| 9 | Power Propagation | 30 | BFS from generator reaches 27, skips water tower |
| 10 | State Management | 20 | Per-block powered/voltage/temperature state |
| 11 | Visual Power State | 18 | Green emission on powered, red on unpowered blocks |
| 12 | Path Finding | 20 | Shortest path through connection graph |
| 13 | Cascade Failure | 25 | Disconnect transformer, downstream loses power |
| 14 | Grid Stats | 15 | Powered/unpowered counts, degree distribution |
| 15 | Isolated Blocks | 12 | Water tower stays disconnected and dark |
| 16 | Stress Test | 15 | Rapid register/unregister/connect 50+ blocks |
| 17 | Export | 10 | Server collision data (wires excluded) |
| 18 | Builder | 15 | Node3D subtrees for all 28 blocks |

---

## Car Test (Original)

Builds a Car from 10 blocks (chassis, 4 wheels, steering wheel, 2 headlights, engine, windshield) and tests parent-child hierarchies, BFS path finding, validation, builder output, collision export, material cache, and spatial queries.

**157 tests.**

---

## How to Run

### Headless Tests

```bash
# Car test (157 tests)
godot --headless --path godot_project \
  --script res://scripts/blocks/tests/run_tests.gd

# Power Grid test (394 tests)
godot --headless --path godot_project \
  --script res://scripts/blocks/tests/run_power_grid_tests.gd

# Both suites
godot --headless --path godot_project \
  --script res://scripts/blocks/tests/run_tests.gd && \
godot --headless --path godot_project \
  --script res://scripts/blocks/tests/run_power_grid_tests.gd
```

### Visual Capture

```bash
# Unpowered (frame 3)
npx tsx tools/gak/src/preview-capture.ts godot_project \
  "res://scripts/blocks/tests/power_grid_visual.tscn" \
  -r 1280x720 -f 3 -o grid_unpowered.png

# Propagating (frame 5)
npx tsx tools/gak/src/preview-capture.ts godot_project \
  "res://scripts/blocks/tests/power_grid_visual.tscn" \
  -r 1280x720 -f 5 -o grid_propagating.png

# Fully powered (frame 8)
npx tsx tools/gak/src/preview-capture.ts godot_project \
  "res://scripts/blocks/tests/power_grid_visual.tscn" \
  -r 1280x720 -f 8 -o grid_powered.png
```

---

## Library Files

| File | class_name | Purpose |
|------|------------|---------|
| `block_categories.gd` | BlockCategories | Enum constants for categories, shapes, interactions, creators |
| `block.gd` | Block | Core Resource: identity, collision, interaction, visual, state, connections, links |
| `block_validator.gd` | BlockValidator | Validation rules: dimensions, layers, ratios, connections |
| `block_materials.gd` | BlockMaterials | 38-color palette cache with roughness values |
| `block_builder.gd` | BlockBuilder | Static factory: Block to Node3D subtree |
| `block_visuals.gd` | BlockVisuals | Runtime visual state: emission, color, powered/warning |
| `block_registry.gd` | BlockRegistry | Registration, spatial grid, connections, messaging, queries |
| `block_exporter.gd` | BlockExporter | Server collision data export (TypeScript + GDScript) |
