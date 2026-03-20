extends SceneTree
## Test runner that executes the Block test suite headlessly.
## Usage: godot --headless --path godot_project --script res://addons/blocks/tests/run_tests.gd

func _init() -> void:
	# Load and run the test scene
	var test_scene := load("res://addons/blocks/tests/test_blocks.tscn")
	if test_scene == null:
		print("ERROR: Could not load test scene")
		quit(1)
		return

	var instance: Node = test_scene.instantiate()
	root.add_child(instance)
