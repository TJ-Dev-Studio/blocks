extends SceneTree
## Test runner that executes the Pattern Expansion test suite headlessly.
## Usage: godot --headless --path godot_project --script res://scripts/blocks/tests/run_pattern_tests.gd

func _init() -> void:
	var test_scene := load("res://scripts/blocks/tests/test_patterns.tscn")
	if test_scene == null:
		print("ERROR: Could not load test scene")
		quit(1)
		return

	var instance: Node = test_scene.instantiate()
	root.add_child(instance)
