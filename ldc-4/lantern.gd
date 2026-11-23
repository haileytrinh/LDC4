extends Area2D
## The wolf presses E next to it and it tips over. Depending on the settings it can
## lure nearby hunters to a spot, ignite a Fire node, or both.

## Hunters within this distance of the lantern hear it fall
@export var hear_radius := 1500.0
## Turn off for a lantern that only starts a fire
@export var lure_hunters := true
## Optional: where hunters walk to. Defaults to the lantern itself.
@export var lure_target: Node2D
## Optional: a Fire node (fire.gd) to ignite when the lantern falls
@export var fire: Node2D
## Optional: only these hunters respond. Leave empty to use Hear Radius instead.
@export var responders: Array[Node2D] = []

var used := false
var light_energy := 1.0


func _ready() -> void:
	add_to_group("resettable")
	if has_node("PointLight2D"):
		light_energy = $PointLight2D.energy


## Called by the wolf's interact key (see wolf.gd)
func interact() -> void:
	if used:
		return
	used = true
	_tip_over()
	# TODO: play lantern clatter sound here

	if fire:
		fire.ignite()

	if lure_hunters:
		var pos := lure_target.global_position if lure_target else global_position
		var listeners: Array = responders if not responders.is_empty() \
				else get_tree().get_nodes_in_group("hunters")
		for h in listeners:
			if responders.is_empty() and h.global_position.distance_to(global_position) > hear_radius:
				continue
			h.investigate(pos)


## Called by the level on respawn.
func reset() -> void:
	used = false
	if has_node("Sprite2D"):
		$Sprite2D.rotation = 0.0
	if has_node("PointLight2D"):
		$PointLight2D.energy = light_energy


func _tip_over() -> void:
	if has_node("Sprite2D"):
		$Sprite2D.rotation = deg_to_rad(90)
	if has_node("PointLight2D"):
		$PointLight2D.energy = light_energy * 0.25
