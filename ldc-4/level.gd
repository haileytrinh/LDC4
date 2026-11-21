extends Node2D


## Drag your Wolf node here in the Inspector
@export var wolf: CharacterBody2D
## Drag a full-screen black ColorRect (inside a CanvasLayer) here
@export var fade: ColorRect
@export var fade_time := 0.4
## Camera won't scroll past this rectangle (x, y, width, height in world pixels)
@export var camera_bounds := Rect2(-872, -690, 1860, 1373)

var checkpoint_pos := Vector2.ZERO
var respawning := false

## Which scene to load when the wolf reaches the exit
@export_file("*.tscn") var next_level: String
var finished := false

func _ready() -> void:
	var cam: Camera2D = wolf.get_node("Camera2D")
	cam.limit_left = int(camera_bounds.position.x)
	cam.limit_top = int(camera_bounds.position.y)
	cam.limit_right = int(camera_bounds.end.x)
	cam.limit_bottom = int(camera_bounds.end.y)
	
	add_to_group("level")
	checkpoint_pos = wolf.global_position  # the start of the level is the first checkpoint
	fade.color.a = 1.0
	create_tween().tween_property(fade, "color:a", 0.0, fade_time)
	fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for h in get_tree().get_nodes_in_group("hunters"):
		h.caught_player.connect(_on_caught)


## Called by checkpoint.gd
func set_checkpoint(pos: Vector2) -> void:
	checkpoint_pos = pos


func _on_caught() -> void:
	if respawning:
		return  # two hunters catching the wolf on the same frame
	respawning = true
	wolf.frozen = true

	var t = create_tween()
	t.tween_property(fade, "color:a", 1.0, fade_time)
	await t.finished

	wolf.global_position = checkpoint_pos
	wolf.velocity = Vector2.ZERO
	get_tree().call_group("resettable", "reset")
	await get_tree().create_timer(0.2).timeout

	t = create_tween()
	t.tween_property(fade, "color:a", 0.0, fade_time)
	await t.finished

	wolf.frozen = false
	respawning = false

func finish_level() -> void:
	if finished or respawning:
		return
	finished = true
	wolf.frozen = true
	var t = create_tween()
	t.tween_property(fade, "color:a", 1.0, fade_time)
	await t.finished
	if next_level.is_empty():
		push_warning("No next_level set on this level")
		return
	get_tree().change_scene_to_file(next_level)
