extends CharacterBody2D


@export var speed := 240

var frozen := false

func _ready():
	add_to_group("wolf")

func _physics_process(_delta):
	if frozen:
		velocity = Vector2.ZERO
		return
	var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = dir * speed
	move_and_slide()

func _unhandled_input(event):
	if frozen:
		return
	if event.is_action_pressed("interact"):
		for area in $"Interact Zone".get_overlapping_areas():
			if area.has_method("interact"):
				area.interact()
				break
