extends Node2D
## Hidden and harmless until a lantern calls ignite(). While burning, its Blocker
## (a StaticBody2D) stops hunters and the wolf, and also blocks line of sight.
## Needs a child StaticBody2D named "Blocker" with a CollisionShape2D inside it.

@export var burn_time := 12.0

@onready var blocker_shape: CollisionShape2D = $Blocker/CollisionShape2D

var burning := false
var token := 0  # invalidates old burn timers after a reset or re-ignite


func _ready() -> void:
	add_to_group("resettable")
	_set_burning(false)


func ignite() -> void:
	if burning:
		return
	_set_burning(true)
	# TODO: play fire crackle sound here
	token += 1
	var my_token := token
	await get_tree().create_timer(burn_time).timeout
	if my_token == token:
		_set_burning(false)


## Called by the level on respawn.
func reset() -> void:
	token += 1
	_set_burning(false)


func _set_burning(on: bool) -> void:
	burning = on
	visible = on
	blocker_shape.set_deferred("disabled", not on)
