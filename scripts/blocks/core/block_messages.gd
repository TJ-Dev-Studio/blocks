class_name BlockMessages
extends RefCounted
## Message type constants and payload helpers for block force propagation protocol.
##
## These message types travel over the BlockRegistry message bus:
##   BlockRegistry.send_message(target_id, BlockMessages.FORCE_PROPAGATE, data, sender_id)
##   BlockRegistry.broadcast_to_connections(sender_id, BlockMessages.FORCE_PROPAGATE, data)
##
## Payload shapes:
##   FORCE_PROPAGATE:    { "epicenter": Vector3, "magnitude": float, "hop": int, "max_hops": int }
##   DISPLACEMENT_RESULT: { "block_id": String, "displaced_position": Vector3, "hop_count": int }

# =========================================================================
# Message type constants
# =========================================================================

## Force propagation wave. Sent from epicenter outward through peer connections.
## Payload: encode_force_propagate() / decode_force_propagate()
const FORCE_PROPAGATE := "force_propagate"

## Displacement result. Block reports displaced position back to coordinator.
## Payload: encode_displacement_result() / decode_displacement_result()
const DISPLACEMENT_RESULT := "displacement_result"


# =========================================================================
# FORCE_PROPAGATE payload helpers
# =========================================================================

## Encode a FORCE_PROPAGATE payload.
##
## epicenter  — world position of the force origin
## magnitude  — impulse strength at source (attenuates per hop)
## hop        — current hop index (0 = origin block)
## max_hops   — maximum hops before wave stops
##
## Returns: { "epicenter": Vector3, "magnitude": float, "hop": int, "max_hops": int }
static func encode_force_propagate(
		epicenter: Vector3,
		magnitude: float,
		hop: int,
		max_hops: int) -> Dictionary:
	return {
		"epicenter": epicenter,
		"magnitude": magnitude,
		"hop": hop,
		"max_hops": max_hops,
	}


## Decode a FORCE_PROPAGATE payload.
## Returns a Dictionary with all expected keys, using defaults for missing/wrong-typed values.
## Callers never need to guard against missing keys.
##
## Defaults: epicenter=Vector3.ZERO, magnitude=0.0, hop=0, max_hops=0
static func decode_force_propagate(data: Dictionary) -> Dictionary:
	var epicenter: Vector3 = Vector3.ZERO
	var raw_ep = data.get("epicenter", Vector3.ZERO)
	if raw_ep is Vector3:
		epicenter = raw_ep

	var magnitude: float = 0.0
	var raw_mag = data.get("magnitude", 0.0)
	if raw_mag is float or raw_mag is int:
		magnitude = float(raw_mag)

	var hop: int = 0
	var raw_hop = data.get("hop", 0)
	if raw_hop is int:
		hop = raw_hop

	var max_hops: int = 0
	var raw_max = data.get("max_hops", 0)
	if raw_max is int:
		max_hops = raw_max

	return {
		"epicenter": epicenter,
		"magnitude": magnitude,
		"hop": hop,
		"max_hops": max_hops,
	}


# =========================================================================
# DISPLACEMENT_RESULT payload helpers
# =========================================================================

## Encode a DISPLACEMENT_RESULT payload.
##
## block_id           — ID of the block reporting its displacement
## displaced_position — world position after displacement
## hop_count          — how many hops this block received before reporting
##
## Returns: { "block_id": String, "displaced_position": Vector3, "hop_count": int }
static func encode_displacement_result(
		block_id: String,
		displaced_position: Vector3,
		hop_count: int) -> Dictionary:
	return {
		"block_id": block_id,
		"displaced_position": displaced_position,
		"hop_count": hop_count,
	}


## Decode a DISPLACEMENT_RESULT payload.
## Returns a Dictionary with all expected keys, using defaults for missing/wrong-typed values.
##
## Defaults: block_id="", displaced_position=Vector3.ZERO, hop_count=0
static func decode_displacement_result(data: Dictionary) -> Dictionary:
	var block_id: String = ""
	var raw_id = data.get("block_id", "")
	if raw_id is String:
		block_id = raw_id

	var displaced_position: Vector3 = Vector3.ZERO
	var raw_pos = data.get("displaced_position", Vector3.ZERO)
	if raw_pos is Vector3:
		displaced_position = raw_pos

	var hop_count: int = 0
	var raw_hop = data.get("hop_count", 0)
	if raw_hop is int:
		hop_count = raw_hop

	return {
		"block_id": block_id,
		"displaced_position": displaced_position,
		"hop_count": hop_count,
	}
