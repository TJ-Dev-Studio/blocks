extends SceneTree
## Test runner for BlockSdfBlender test suite.
## Usage: godot --headless --path godot_project --script res://scripts/blocks/tests/run_sdf_blender_tests.gd

func _init() -> void:
	var test_scene := load("res://scripts/blocks/tests/test_sdf_blender.tscn")
	if test_scene == null:
		print("ERROR: Could not load test_sdf_blender.tscn")
		quit(1)
		return

	var instance: Node = test_scene.instantiate()
	root.add_child(instance)
