extends SceneTree
## Test runner for BlockCollisionMerger test suite.
## Usage: godot --headless --path godot_project --script res://addons/blocks/tests/run_collision_merger_tests.gd

func _init() -> void:
	var test_scene := load("res://addons/blocks/tests/test_collision_merger.tscn")
	if test_scene == null:
		print("ERROR: Could not load test_collision_merger.tscn")
		quit(1)
		return

	var instance: Node = test_scene.instantiate()
	root.add_child(instance)
