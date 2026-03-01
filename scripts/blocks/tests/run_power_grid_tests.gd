extends SceneTree
## Test runner for the Power Grid test suite.
## Usage: godot --headless --path godot_project --script res://scripts/blocks/tests/run_power_grid_tests.gd

func _init() -> void:
	var test_scene := load("res://scripts/blocks/tests/test_power_grid.tscn")
	if test_scene == null:
		print("ERROR: Could not load power grid test scene")
		quit(1)
		return
	var instance: Node = test_scene.instantiate()
	root.add_child(instance)
