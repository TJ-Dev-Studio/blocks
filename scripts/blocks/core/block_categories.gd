class_name BlockCategories
## Enum constants for the Block primitive system.
##
## Categories define what kind of object a block represents.
## Shapes define collision geometry. Interactions define how
## entities interact with the block. Creators track provenance.

# --- Categories ---
const TERRAIN := 0
const PROP := 1
const STRUCTURE := 2
const CREATURE := 3
const EFFECT := 4
const TRIGGER_CAT := 5
const FURNISHING := 6
const TREE_CAT := 7

# --- Collision shapes ---
const SHAPE_BOX := 0
const SHAPE_CYLINDER := 1
const SHAPE_CAPSULE := 2
const SHAPE_NONE := 3
const SHAPE_SPHERE := 4
const SHAPE_RAMP := 5
const SHAPE_DOME := 6
const SHAPE_CONE := 7
const SHAPE_TORUS := 8
const SHAPE_ARCH := 9
const SHAPE_ROCK := 10

# --- Interaction types ---
const INTERACT_SOLID := 0
const INTERACT_WALKABLE := 1
const INTERACT_CLIMBABLE := 2
const INTERACT_TRIGGER := 3
const INTERACT_DESTRUCTIBLE := 4
const INTERACT_WATER := 5
const INTERACT_ONE_WAY := 6
const INTERACT_BRIDGE := 7
const INTERACT_NONE := 8

# --- Creator types ---
const CREATOR_HUMAN := 0
const CREATOR_AI := 1
const CREATOR_SYSTEM := 2


## Map interaction type to its default collision layer.
static func default_layer(interaction_type: int) -> int:
	match interaction_type:
		INTERACT_SOLID: return CollisionLayers.WORLD
		INTERACT_WALKABLE: return CollisionLayers.PLATFORM
		INTERACT_CLIMBABLE: return CollisionLayers.TRUNK
		INTERACT_TRIGGER: return CollisionLayers.TRIGGER
		INTERACT_DESTRUCTIBLE: return CollisionLayers.WORLD
		INTERACT_WATER: return CollisionLayers.WATER
		INTERACT_ONE_WAY: return CollisionLayers.PLATFORM
		INTERACT_BRIDGE: return CollisionLayers.BRIDGE
		_: return CollisionLayers.WORLD


static func category_name(cat: int) -> String:
	match cat:
		TERRAIN: return "terrain"
		PROP: return "prop"
		STRUCTURE: return "structure"
		CREATURE: return "creature"
		EFFECT: return "effect"
		TRIGGER_CAT: return "trigger"
		FURNISHING: return "furnishing"
		TREE_CAT: return "tree"
		_: return "unknown"


static func shape_name(shape: int) -> String:
	match shape:
		SHAPE_BOX: return "box"
		SHAPE_CYLINDER: return "cylinder"
		SHAPE_CAPSULE: return "capsule"
		SHAPE_NONE: return "none"
		SHAPE_SPHERE: return "sphere"
		SHAPE_RAMP: return "ramp"
		SHAPE_DOME: return "dome"
		SHAPE_CONE: return "cone"
		SHAPE_TORUS: return "torus"
		SHAPE_ARCH: return "arch"
		SHAPE_ROCK: return "rock"
		_: return "unknown"


static func interaction_name(inter: int) -> String:
	match inter:
		INTERACT_SOLID: return "solid"
		INTERACT_WALKABLE: return "walkable"
		INTERACT_CLIMBABLE: return "climbable"
		INTERACT_TRIGGER: return "trigger"
		INTERACT_DESTRUCTIBLE: return "destructible"
		INTERACT_WATER: return "water"
		INTERACT_ONE_WAY: return "one_way"
		INTERACT_BRIDGE: return "bridge"
		INTERACT_NONE: return "none"
		_: return "unknown"


static func creator_name(creator: int) -> String:
	match creator:
		CREATOR_HUMAN: return "human"
		CREATOR_AI: return "ai"
		CREATOR_SYSTEM: return "system"
		_: return "unknown"
