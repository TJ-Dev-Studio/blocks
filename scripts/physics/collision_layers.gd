class_name CollisionLayers
## Collision layer definitions for FrogTown.
##
## Godot uses bitmask layers (1-32). Objects are ON a layer (collision_layer)
## and DETECT other layers (collision_mask).
##
## Layer Map:
##   1 — WORLD:    Ground, terrain, boundary walls
##   2 — PLATFORM: Tree platforms (solid from above)
##   3 — TRUNK:    Tree trunks, building walls, solid obstacles
##   4 — BRIDGE:   Rope bridges
##   5 — PLAYER:   Player CharacterBody3D
##   6 — NPC:      NPC frogs, creatures
##   7 — WATER:    Water surface areas
##   8 — TRIGGER:  Ladders, signs, zones (Area3D only)

const WORLD    := 1
const PLATFORM := 2
const TRUNK    := 3
const BRIDGE   := 4
const PLAYER   := 5
const NPC      := 6
const WATER    := 7
const TRIGGER  := 8

## Convert a layer number (1-32) to its bitmask value.
static func to_bit(layer: int) -> int:
	return 1 << (layer - 1)

## Combine multiple layer numbers into a single bitmask.
static func combine(layers: Array[int]) -> int:
	var mask := 0
	for l in layers:
		mask |= (1 << (l - 1))
	return mask

## Player collision mask — detects world, platforms, trunks, bridges.
static func player_mask() -> int:
	return combine([WORLD, PLATFORM, TRUNK, BRIDGE])

## Trigger mask — detects players only.
static func trigger_mask() -> int:
	return combine([PLAYER])
