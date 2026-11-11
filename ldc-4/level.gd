extends Node2D


## Drag your Wolf node here in the Inspector
@export var wolf: CharacterBody2D
## Drag a full-screen black ColorRect (inside a CanvasLayer) here
@export var fade: ColorRect
@export var fade_time := 0.4

var checkpoint_pos := Vector2.ZERO
var respawning := false


func _ready() -> void:
	add_to_group("level")
	checkpoint_pos = wolf.global_position  # the start of the level is the first checkpoint
	fade.color.a = 0.0
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
