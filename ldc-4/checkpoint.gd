extends Area2D


var activated := false


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node) -> void:
	if activated or not body.is_in_group("wolf"):
		return
	activated = true
	get_tree().call_group("level", "set_checkpoint", global_position)
