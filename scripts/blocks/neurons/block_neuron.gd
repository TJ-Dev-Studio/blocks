class_name BlockNeuron
extends RefCounted
## Runtime "brain" that connects declarative block-file definitions to runtime behavior.
##
## Handles:
## - Options from block-file (configuration values)
## - State bindings (reactive connections to app state like GameState)
## - Connection management (peer-to-peer block links)
## - Data layer transfer (propagating state changes through block graph)

## The block this neuron belongs to.
var block_id: String = ""

## Static configuration from the block-file's neuron.options.
var options: Dictionary = {}

## State binding expressions (key -> expression string).
## Example: {"is_lobby": "match_phase == NONE"}
var state_bindings: Dictionary = {}

## Connection references to wire up.
var connection_refs: PackedStringArray = PackedStringArray()

## Lifecycle handler names.
var on_activate_handler: String = ""
var on_deactivate_handler: String = ""

## Whether this neuron is currently active.
var _active: bool = false

## Reference to the factory for state queries (set by bind_to_state).
var _factory = null  # BlocksFactory (avoid cyclic typed reference)

## Cached bound state values.
var _bound_values: Dictionary = {}


## Initialize from the neuron section of a block-file.
func init_from_file(neuron_data: Dictionary, b_id: String) -> void:
	block_id = b_id
	options = neuron_data.get("options", {})
	state_bindings = neuron_data.get("state_bindings", {})
	var conns: Array = neuron_data.get("connections", [])
	connection_refs = PackedStringArray(conns)
	on_activate_handler = neuron_data.get("on_activate", "")
	on_deactivate_handler = neuron_data.get("on_deactivate", "")


## Bind this neuron to the factory's state system.
## Wires up state_bindings so they react to factory state changes.
func bind_to_state(factory) -> void:
	_factory = factory
	if _factory and _factory.has_signal("state_changed"):
		if not _factory.state_changed.is_connected(_on_factory_state_changed):
			_factory.state_changed.connect(_on_factory_state_changed)

	# Evaluate initial state
	_evaluate_bindings()


## Activate this neuron (called when the block is built).
func activate() -> void:
	_active = true


## Deactivate this neuron (called when the block is destroyed).
func deactivate() -> void:
	_active = false
	if _factory and _factory.has_signal("state_changed"):
		if _factory.state_changed.is_connected(_on_factory_state_changed):
			_factory.state_changed.disconnect(_on_factory_state_changed)
	_factory = null


## Read an option value with a default fallback.
func get_option(key: String, default_value = null):
	return options.get(key, default_value)


## Set an option value at runtime (overrides the block-file default).
func set_option(key: String, value) -> void:
	options[key] = value


## Check if a specific option exists.
func has_option(key: String) -> bool:
	return options.has(key)


## Get the current evaluated value of a state binding.
func get_bound_value(key: String, default_value = null):
	return _bound_values.get(key, default_value)


## Push a state change to all connected blocks through the registry.
## Gracefully handles missing peers — logs and continues instead of crashing.
func push_state(key: String, value, registry) -> void:
	if not registry:
		push_warning("[BlockNeuron:%s] Cannot push state — no registry" % block_id)
		return
	if block_id.is_empty():
		push_warning("[BlockNeuron] Cannot push state — no block_id set")
		return
	var data := {"key": key, "value": value}
	registry.broadcast_to_connections(block_id, "state_update", data)


## Handle incoming state from a connected block.
func on_state_received(msg_type: String, data: Dictionary, _sender_id: String) -> void:
	if msg_type == "state_update" and data.has("key") and data.has("value"):
		_bound_values[data["key"]] = data["value"]


# =========================================================================
# Internal
# =========================================================================

func _on_factory_state_changed(key: String, value) -> void:
	if not _active:
		return
	# Re-evaluate bindings when factory state changes
	_evaluate_bindings()


## Evaluate all state bindings against current factory state.
func _evaluate_bindings() -> void:
	if not _factory:
		return
	for binding_key: String in state_bindings:
		var expr: String = state_bindings[binding_key]
		_bound_values[binding_key] = _evaluate_expression(expr)


## Simple expression evaluator for state bindings.
## Supports: "key == value", "key != value", "key" (truthy check).
## Returns null on malformed expressions instead of crashing.
func _evaluate_expression(expr: String) -> Variant:
	if not _factory:
		return null

	if expr.strip_edges().is_empty():
		push_warning("[BlockNeuron:%s] Empty binding expression" % block_id)
		return null

	# Handle equality: "some_key == some_value"
	if "==" in expr:
		var parts := expr.split("==")
		if parts.size() == 2:
			var key := parts[0].strip_edges()
			var val_str := parts[1].strip_edges()
			if key.is_empty():
				push_warning("[BlockNeuron:%s] Malformed expression: %s" % [block_id, expr])
				return null
			var actual = _factory.get_state(key)
			return str(actual) == val_str

	# Handle inequality: "some_key != some_value"
	if "!=" in expr:
		var parts := expr.split("!=")
		if parts.size() == 2:
			var key := parts[0].strip_edges()
			var val_str := parts[1].strip_edges()
			if key.is_empty():
				push_warning("[BlockNeuron:%s] Malformed expression: %s" % [block_id, expr])
				return null
			var actual = _factory.get_state(key)
			return str(actual) != val_str

	# Simple truthy: "some_key"
	var key := expr.strip_edges()
	var val = _factory.get_state(key)
	if val is bool:
		return val
	return val != null
