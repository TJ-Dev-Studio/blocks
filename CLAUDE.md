# Blocks — Composable Block Primitive Library for Godot 4

Declarative JSON → validated Block Resources → Node3D scene tree. A generic, game-agnostic library for building worlds from composable block primitives.

## Architecture

This library is structured into 8 domains with strict dependency rules. No domain depends on another at the same level — dependencies only flow inward toward `core/`.

```
addons/blocks/  (or repo root)
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
│   ├── block_materials.gd      Material cache + register_materials() seam (headless; game supplies palette/textures/shaders)
│   ├── block_visuals.gd        Runtime emission/color + color chain animation
│   ├── block_mesh_merger.gd    Same-material mesh merging (draw call reduction) — see output contract below
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

## Merger Output Contract — merged meshes carry vertex colours

`BlockMeshMerger` writes an `ARRAY_COLOR` onto every merged surface. **A consumer of this library must not use vertex colours on block geometry for anything else, and must not enable `vertex_color_use_as_albedo` on a block material** — it would read this data as paint.

| channel | meaning |
|---------|---------|
| `r` | per-block seed, 0..1. Stable across runs and machines, so bakes match |
| `g` | reserved, always 0.0 |
| `b` | `sqrt(block's middle world extent / 4.0)` — decode by squaring, `BlockMeshMerger.decode_size()` |
| `a` | `0.0` marks "stamped". Unstamped geometry defaults to opaque white, so `a == 1.0` means "no data" |

Why it exists: merging collapses N block nodes into ONE `MeshInstance3D`, so any shader keyed on node position resolves a whole merged group to a single value. A per-block quantity has to travel with the geometry. Per-instance shader parameters cannot substitute — they share one fixed global buffer (GL Compatibility caps at 4096 instances).

Two rules for anyone extending this:
- **Every channel must be placement-invariant.** The consuming game may dedup meshes by comparing `surface_get_arrays()`, which includes `ARRAY_COLOR`. A channel derived from anything placement-specific (node names are auto-uniquified for siblings) silently prevents identical meshes from collapsing.
- **Derive from the same transform that produces the vertices** (`rel_xform`), so the stamp stays a pure function of the mesh contents.

Cost is 4 bytes per vertex on merged surfaces, paid whether or not the game's shader reads it.

### Tint rides in `ARRAY_CUSTOM0`, not in the material (GC-91)

**Per-block `color_tint` used to fork the material.** `get_material_with_overrides(id, {tint_color})` minted a distinct `ShaderMaterial` per (id, tint) — `bark_dark|tint_color=bababa`, `bark_dark|tint_color=cdcfd1`, … — and the merger groups by material instance, so every tint was its own merge group and its own draw call. Censused on the FrogMog hub bake (2026-08-16): 9,348 mesh outputs, **1,462 distinct material keys, 6,067 of the outputs (65%) tint forks**. Collapsing tint into the base material leaves **146 keys**.

So a merged surface carries the tint as a second vertex attribute:

| attribute | channel | meaning |
|-----------|---------|---------|
| `ARRAY_CUSTOM0` (RGBA8 unorm) | `rgb` | the block's `color_tint`, linear 0..1 |
| | `a` | `1.0` marks "tint stamped". Unstamped geometry reads `a == 0.0` (custom attributes default to zero) |

`block_world.gdshader` multiplies albedo by `CUSTOM0.rgb` when `CUSTOM0.a > 0.5`, else by the `tint_color` uniform — so unmerged geometry (studio, live placement, neurons, scene visuals) keeps the uniform path unchanged, and a material that carries other overrides too (roughness, metallic, noise) still forks and still works. `EMISSION` uses the same resolved tint.

Rules:
- **Tint-only overrides merge under the BASE material.** The merger asks `BlockMaterials.tint_only_base(mat)`: if the mesh's material was minted from `base + {tint_color}` and nothing else, the group key is the base material and the tint goes into CUSTOM0. Anything else keeps its own group.
- **Placement-invariant, like every stamped channel.** Tint is block CONTENT (from JSON), never derived from a node name or position, so two placements of one assembly stay byte-identical and the compiler's mesh dedup still collapses them.
- **The albedo pre-multiply is gone for merged geometry.** The forked material also pre-multiplied `albedo_color` by the tint "so the base color is correct even without the tint uniform"; a merged surface uses the base material's `albedo_color` and applies the tint once, in the shader. Same result, one place.

Cost: 4 more bytes per vertex on merged surfaces. Every cache level mixes `STYLE_VERSION` and merged meshes key on `WORLD_CACHE_VERSION`; both bump.

## Collision Merger Contract — one body per group, shapes without nodes (GC-91)

`BlockCollisionMerger` is the physics twin of `BlockMeshMerger`, and it exists because the mesh merger only ever did half the job. Merging collapses N blocks into one `MeshInstance3D`, but every block still carried its own `StaticBody3D` + `CollisionShape3D` (+ the `Node3D` root that owns them). Measured on the FrogMog hub, 2026-08-16: 141,475 scene nodes for 8,888 meshes — 34,556 bodies + 34,556 shapes + 61,892 containers — and a **68 ms frame floor that survived hiding the entire world**, because Godot's main thread pays per NODE (transform propagation, physics-server sync) whether or not anything is drawn. Draw calls were never the cost.

What it does: for a set of already-built blocks under one root, group every **eligible** block's static body by `(collision_layer, collision_mask)`, create ONE `StaticBody3D` per group, and add each block's shape to it through `PhysicsServer3D.body_add_shape` **with the shape's world transform relative to the merged body** — no `CollisionShape3D` children. Then free the per-block body (and its shape node). Physics behaviour is unchanged: same shapes, same transforms, same layers/masks; a compound static body is how Godot expects level geometry to be built.

Eligible = `StaticBody3D` whose block is not a neuron, not a trigger (`Area3D` never merges), and whose body has no children besides its `CollisionShape3D`s. Anything a system needs to address individually — springs, levers, cannons, triggers, terrain the loader treats specially — is left alone by construction, because those carry a neuron or are areas.

Contract for consumers:
- **`merged_body.get_meta("merged_collision") == true`** marks a compound body.
- **`merged_body.get_meta("shape_block_ids")`** is a `PackedStringArray` indexed by shape index. A raycast/shape-cast result's `shape` field indexes it: `block_id = merged_body.get_meta("shape_block_ids")[result.shape]`. `BlockCollisionMerger.block_id_at(body, shape_idx)` wraps this and returns `""` for non-merged bodies.
- **The per-block `Node3D` root survives** (it still owns the block's mesh, if unmerged, and its `block_id` meta) — only the body/shape pair under it goes. Code that walks `collider.get_parent()` looking for `block_id` meta finds a merged body's parent is the assembly root, not a block: that is correct for walls, and every such caller today only wants springs/triggers, which never merge.
- **The Design Studio must not merge.** Its picker raycasts bodies and needs one per block; `WorldCacheLoader.keep_collision_for_editor(true)` already governs this and the merger honours the same flag.
- **Deleting a block at runtime** (studio god-mode delete, `deleted_children`) removes its shape via `BlockCollisionMerger.remove_block(body, block_id)` (`body_remove_shape` + compact the id map). Freeing the block's root no longer frees any collision.

Where it runs: **load time, in `WorldCacheLoader`, in the same pass that decides per-block whether collision is kept** — the loader has just reconstructed each `Block` (id, layer, size, interaction), which is exactly the input the merger needs, and the bake stays byte-identical (the compiler still serialises per-block bodies, so an old loader keeps working). It does not run in `BlocksFactory` live builds (studio/dev placement) — those want per-block bodies.

Rules for anyone extending this:
- **Grouping key must include everything the physics server distinguishes**: layer, mask, and `PhysicsMaterial` if a block ever gets one. Two blocks with different masks in one body would give one of them the wrong mask.
- **Shape transforms are relative to the merged body's global transform.** Place the merged body at the group's first shape's global position (or the root's), and compute every `body_add_shape` transform as `merged.global_transform.affine_inverse() * shape.global_transform`. Getting this backwards moves every wall in the group.
- **Never merge scaled bodies naively** — a scaled parent scales the shape; bake the scale into the shape transform.

## How To Add New Components

### New Shape Type
1. Add constant to `core/block_categories.gd`
2. Handle in `building/block_builder.gd` `_create_collision_shape()` + `_create_mesh()`
3. Handle in `core/block.gd` `to_collision_dict()` + `_valid_split_axes()`
4. Run tests

### New Material
The library is **headless** — it ships no game art. A game registers its material
identity once at startup (before any block builds). To add a material:
1. Add it to your **game's** material library and pass it through
   `BlockMaterials.register_materials({...})` (palette / roughness / textured /
   shaders / material_type_map). In FrogMog that's `scripts/autoload/block_style.gd`.
2. For a one-off **library default** (e.g. a new demo/test material used by the
   suites in `tests/`), add it to the generic baseline `PALETTE`/`ROUGHNESS` in
   `building/block_materials.gd`.
3. For a per-map runtime tweak, set `BlockMaterials.palette_override["my_mat"] = Color(...)`.
4. Use the `material_id` key in block JSON.

### Game-Specific Style (the headless seam)
The library ships only a generic demo baseline + diagnostics. A game injects its
full visual identity through `BlockMaterials`, from an autoload that runs **before
BlocksFactory** (FrogMog: `scripts/autoload/block_style.gd`):
- `register_materials({palette, roughness, textured, triplanar, local_space,`
  `scale_overrides, aspect_overrides, material_type_map, shader_path,`
  `proc_shader_path})` — the **primary seam**. Merges the game's palette/roughness
  onto the baseline, supplies the hand-painted texture set + its tiling tuning, and
  registers the block-world shaders. Calls `clear_caches()` so it's hot-reload safe.
- `BlockBuilder.organic_mesh_dir` — directory of pre-baked arch/rock `.tres` meshes
  (empty → procedural torus/sphere fallback). Also injected, no asset paths in the engine.
- `palette_override` / `roughness_override` — per-map runtime overrides, checked
  *before* the registered palette (e.g. a map recoloring `stone` for its biome).
- `shader_param_injector` — Callable to inject textures/uniforms into every ShaderMaterial.
- `material_post_processor` — Callable to add next_pass (outlines), replace materials, etc.
See README.md for a full example.

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
| Block appears wrong color / default gray | Check the game's `register_materials()` (FrogMog: `block_style.gd`) — the engine only ships generic demo defaults; production palette/textures are injected |
| Validation rejects block | `registry/block_validator.gd` — check which stage fails |
| Block not found by query | `registry/block_registry.gd` — check spatial grid cell |
| Connections not forming | `rules/block_auto_connector.gd` or specific rule in `rules/` |
| Spring physics wrong | `physics/block_spring.gd` — check spring_k, damping values |
| LOD not updating | `lod/block_lod_controller.gd` — check camera_pos input |
| Zone not loading | `io/block_zone_loader.gd` + `io/block_file.gd` |
| Mesh merging skipped | `building/block_mesh_merger.gd` — check extent/block count |
| Merged blocks all render one flat colour | Expected without the vertex-colour stamp below — a merged group is ONE node, so any shader keyed on node position gives it ONE value |
| Neuron not reacting | `neurons/block_neuron.gd` — check state bindings |
| Textures "blink" / "settle" after camera stops on Nvidia (not Mac) | MSAA. Set `msaa_3d: 0` in `render_quality.gd` for the affected tier. Apple's GPU hides this; Nvidia exposes it. See `docs/gotchas.md` → "MSAA Nvidia per-fragment aliasing" for full diagnostic history — don't rebuild the false-lead chain. |

## Test Commands

```bash
# Car assembly suite (157 tests — hierarchy, validation, builder, collision export)
godot --headless --script res://addons/blocks/tests/run_tests.gd

# Power grid suite (394 tests — connections, BFS, cascade failures, visual states)
godot --headless --script res://addons/blocks/tests/run_power_grid_tests.gd

# Cellular suite (subdivision, merge, LOD, DNA, amoeba movement)
godot --headless --script res://addons/blocks/tests/run_cellular_tests.gd
```

**Always run tests after modifying any file in this directory.**
