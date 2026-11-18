extends Area2D
## A hunter who walks over it is pinned for stun_time seconds. One use per attempt.


@export var stun_time := 8.0
## Placeholder visuals: tints the Sprite2D. Swap for frames once real art is in.
@export var armed_color := Color(0.85, 0.85, 0.9)
@export var sprung_color := Color(0.4, 0.4, 0.45)

var armed := true


func _ready() -> void:
	add_to_group("resettable")
	body_entered.connect(_on_body_entered)
	_show_state()


func _on_body_entered(body: Node) -> void:
	if not armed:
		return
	if body.is_in_group("hunters"):
		_spring()
		body.stun(stun_time)
	elif body.is_in_group("wolf"):
		_spring()
		get_tree().call_group("level", "_on_caught")
	# TODO: play trap snap sound here


func _spring() -> void:
	armed = false
	_show_state()
	if has_node("SnapSound"):
		$SnapSound.play()
	if has_node("Sprite2D"):
		# Quick squash-and-recover so the snap reads even without art
		var s: Sprite2D = $Sprite2D
		var t := create_tween()
		t.tween_property(s, "scale", s.scale * 1.25, 0.05)
		t.tween_property(s, "scale", s.scale, 0.1)


## Called by the level on respawn.
func reset() -> void:
	armed = true
	_show_state()


func _show_state() -> void:
	if has_node("Sprite2D"):
		$Sprite2D.modulate = armed_color if armed else sprung_color
