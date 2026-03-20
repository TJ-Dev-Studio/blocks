extends SceneTree
## Test runner that executes the Cellular Block test suite headlessly.
## Usage: godot --headless --script res://addons/blocks/tests/run_cellular_tests.gd

func _init() -> void:
	var test_scene := load("res://addons/blocks/tests/test_cellular.tscn")
	if test_scene == null:
		print("ERROR: Could not load cellular test scene")
		quit(1)
		return

	var instance: Node = test_scene.instantiate()
	root.add_child(instance)
