extends CharacterBody2D


@export var speed := 240


func _physics_process(_delta):
	var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = dir * speed
	move_and_slide()

func _unhandled_input(event):
	if event.is_action_pressed("interact"):
		for area in $"Interact Zone".get_overlapping_areas():
			if area.has_method("interact"):
				area.interact()
				break
