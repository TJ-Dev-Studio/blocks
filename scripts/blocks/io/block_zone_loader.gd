class_name BlockZoneLoader
extends RefCounted
## Manages loading/unloading of block zones based on player proximity.
##
## Zones are defined by a center point and activation radius.
## When the player enters the radius, the zone loads.
## When they leave (with hysteresis), it unloads.
## This prevents mobile memory pressure from having all zones resident.

## Extra distance buffer before unload triggers (prevents thrashing).
const HYSTERESIS_BUFFER := 10.0

## Minimum time between zone check updates (seconds).
const CHECK_INTERVAL := 1.0

## Zone definition: center, radius, path, and current load state.
var _zone_defs: Dictionary = {}  # zone_name -> {center, radius, path, loaded}

## Reference to the factory.
var _factory = null  # BlocksFactory

var _last_check_time: float = 0.0


## Initialize with factory reference.
func init(factory) -> void:
	_factory = factory


## Register a zone that should load/unload based on proximity.
## center: World position of the zone center.
## radius: Distance at which the zone activates.
## zone_path: Path to the .zone.json file.
func register_zone(zone_name: String, center: Vector3, radius: float, zone_path: String) -> void:
	_zone_defs[zone_name] = {
		"center": center,
		"radius": radius,
		"path": zone_path,
		"loaded": false,
	}


## Remove a zone definition.
func unregister_zone(zone_name: String) -> void:
	if _zone_defs.has(zone_name):
		if _zone_defs[zone_name]["loaded"] and _factory:
			_factory.unload_zone(zone_name)
		_zone_defs.erase(zone_name)


## Check player position and load/unload zones as needed.
## Call from _process() or at regular intervals.
func update(player_pos: Vector3) -> void:
	if not _factory:
		return

	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_check_time < CHECK_INTERVAL:
		return
	_last_check_time = now

	for zone_name: String in _zone_defs:
		var zone_def: Dictionary = _zone_defs[zone_name]
		var center: Vector3 = zone_def["center"]
		var radius: float = zone_def["radius"]
		var loaded: bool = zone_def["loaded"]

		var dx := player_pos.x - center.x
		var dz := player_pos.z - center.z
		var dist := sqrt(dx * dx + dz * dz)

		if not loaded and dist <= radius:
			# Player entered zone — load async to avoid main-thread stall.
			# load_zone (synchronous) freezes the render thread for the entire
			# duration of node construction — 60+ms on Quest 2 for large zones.
			_factory.load_zone_async(zone_def["path"])
			zone_def["loaded"] = true

		elif loaded and dist > radius + HYSTERESIS_BUFFER:
			# Player left zone (with buffer) — unload
			_factory.unload_zone(zone_name)
			zone_def["loaded"] = false


## Check if a specific zone is currently loaded.
func is_zone_loaded(zone_name: String) -> bool:
	if not _zone_defs.has(zone_name):
		return false
	return _zone_defs[zone_name]["loaded"]


## Get all registered zone names.
func get_zone_names() -> PackedStringArray:
	return PackedStringArray(_zone_defs.keys())


## Get only the names of zones that are currently loaded (player is nearby).
## Used by wrist palette zone label to show the active zone, not all registered zones.
func get_loaded_zone_names() -> PackedStringArray:
	var loaded: PackedStringArray = []
	for zone_name: String in _zone_defs:
		if _zone_defs[zone_name]["loaded"]:
			loaded.append(zone_name)
	return loaded


## Force-load a zone regardless of player position.
func force_load(zone_name: String) -> void:
	if not _zone_defs.has(zone_name) or not _factory:
		return
	var zone_def: Dictionary = _zone_defs[zone_name]
	if not zone_def["loaded"]:
		_factory.load_zone(zone_def["path"])
		zone_def["loaded"] = true


## Force-unload a zone regardless of player position.
func force_unload(zone_name: String) -> void:
	if not _zone_defs.has(zone_name) or not _factory:
		return
	var zone_def: Dictionary = _zone_defs[zone_name]
	if zone_def["loaded"]:
		_factory.unload_zone(zone_name)
		zone_def["loaded"] = false
