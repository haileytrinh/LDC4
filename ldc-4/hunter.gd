extends CharacterBody2D
class_name Hunter
## Hunter AI: PATROL -> (notices wolf/lure) -> CHASE/INVESTIGATE -> (loses wolf/nothing happens) -> RETURN -> PATROL
## Tools call investigate(pos) and stun(seconds). Level listens for caught_player.

signal caught_player

enum State { PATROL, INVESTIGATE, CHASE, RETURN, STUNNED }

@export_group("Patrol")
## A Node2D whose Marker2D children are the patrol points, in order.
@export var waypoint_parent: Node2D
@export var patrol_speed := 90.0
@export var pause_time := 1.2
## false = loop around the points, true = walk to the end and back again
@export var ping_pong := true

@export_group("Senses")
@export var vision_range := 160.0
## Full width of the cone, in degrees
@export var vision_angle := 60.0
## Wolf must stay in the cone this long before the hunter reacts (fairness window)
@export var notice_time := 0.25
## Physics layers that block line of sight (layer 1 = walls and trees)
@export_flags_2d_physics var sight_blockers := 1

@export_group("Chase")
@export var chase_speed := 200.0
## Seconds the hunter keeps chasing after losing sight of the wolf
@export var lose_time := 3.0
@export var catch_distance := 14.0

@export_group("Investigate")
@export var investigate_speed := 110.0
@export var investigate_wait := 3.0

var state := State.PATROL
var facing := Vector2.RIGHT

var waypoints: Array[Vector2] = []
var wp_index := 0
var wp_dir := 1

var wolf: Node2D
var spawn_pos := Vector2.ZERO
var last_seen := Vector2.ZERO
var investigate_target := Vector2.ZERO
var arrived := false

var wait_left := 0.0
var seen_time := 0.0
var lose_left := 0.0
var stun_left := 0.0
var pause_t := 0.0
var pause_angle := 0.0


func _ready() -> void:
	add_to_group("hunters")
	wolf = get_tree().get_first_node_in_group("wolf")
	spawn_pos = global_position
	if waypoint_parent:
		for c in waypoint_parent.get_children():
			if c is Node2D:
				waypoints.append(c.global_position)
	if waypoints.is_empty():
		waypoints.append(global_position)


func _physics_process(delta: float) -> void:
	match state:
		State.PATROL: _patrol(delta)
		State.INVESTIGATE: _investigate(delta)
		State.CHASE: _chase(delta)
		State.RETURN: _return(delta)
		State.STUNNED: _stunned(delta)

	move_and_slide()

	# Turn smoothly toward the direction of travel
	if velocity.length() > 1.0:
		facing = Vector2.from_angle(lerp_angle(facing.angle(), velocity.angle(), 10.0 * delta))


func _process(_delta: float) -> void:
	queue_redraw()
	if has_node("Sprite2D"):
		$Sprite2D.flip_h = facing.x < 0.0


# states ----------------------------------------------------------------

func _patrol(delta: float) -> void:
	if _check_for_wolf(delta):
		return

	if wait_left > 0.0:
		_look_around(delta)
		wait_left -= delta
		return

	if _move_to(waypoints[wp_index], patrol_speed):
		_advance_waypoint()
		_start_wait(pause_time)


func _investigate(delta: float) -> void:
	if _check_for_wolf(delta):
		return

	if not arrived:
		if _move_to(investigate_target, investigate_speed):
			arrived = true
			_start_wait(investigate_wait)
		return

	_look_around(delta)
	wait_left -= delta
	if wait_left <= 0.0:
		_begin_return()


func _chase(delta: float) -> void:
	if _can_see_wolf():
		last_seen = wolf.global_position
		lose_left = lose_time
	else:
		lose_left -= delta
		if lose_left <= 0.0:
			_begin_return()
			return

	_move_to(last_seen, chase_speed)

	if wolf and global_position.distance_to(wolf.global_position) <= catch_distance:
		velocity = Vector2.ZERO
		caught_player.emit()
		# Freeze in place until the level calls reset()
		state = State.STUNNED
		stun_left = 999.0


func _return(delta: float) -> void:
	if _check_for_wolf(delta):
		return
	if _move_to(waypoints[wp_index], patrol_speed):
		state = State.PATROL
		wait_left = 0.0


func _stunned(delta: float) -> void:
	velocity = Vector2.ZERO
	stun_left -= delta
	if stun_left <= 0.0:
		_begin_return()


# public ----------------------------------------------------------------

## Called by lanterns and other lures. Ignored while chasing or stunned.
func investigate(pos: Vector2) -> void:
	if state == State.CHASE or state == State.STUNNED:
		return
	investigate_target = pos
	arrived = false
	state = State.INVESTIGATE


## Called by traps. Pass a huge number for a permanent catch.
func stun(seconds: float) -> void:
	state = State.STUNNED
	stun_left = seconds
	velocity = Vector2.ZERO


## Called by the level on respawn.
func reset() -> void:
	global_position = spawn_pos
	velocity = Vector2.ZERO
	wp_index = 0
	wp_dir = 1
	wait_left = 0.0
	seen_time = 0.0
	arrived = false
	state = State.PATROL


# helpers ----------------------------------------------------------------

## Walks toward a point. Returns true once there.
func _move_to(target: Vector2, speed: float) -> bool:
	var to := target - global_position
	if to.length() < 6.0:
		velocity = Vector2.ZERO
		return true
	velocity = to.normalized() * speed
	return false


func _advance_waypoint() -> void:
	if waypoints.size() < 2:
		return
	if ping_pong:
		if wp_index + wp_dir >= waypoints.size() or wp_index + wp_dir < 0:
			wp_dir *= -1
		wp_index += wp_dir
	else:
		wp_index = (wp_index + 1) % waypoints.size()


func _begin_return() -> void:
	# Head back to the nearest patrol point, then resume
	var best := 0
	var best_dist := INF
	for i in waypoints.size():
		var d := global_position.distance_to(waypoints[i])
		if d < best_dist:
			best_dist = d
			best = i
	wp_index = best
	state = State.RETURN


func _start_wait(seconds: float) -> void:
	wait_left = seconds
	pause_t = 0.0
	pause_angle = facing.angle()
	velocity = Vector2.ZERO


## Sweeps the vision cone left and right while standing still
func _look_around(delta: float) -> void:
	velocity = Vector2.ZERO
	pause_t += delta
	facing = Vector2.from_angle(pause_angle + sin(pause_t * 2.5) * 0.9)


## Returns true if the hunter just switched to CHASE
func _check_for_wolf(delta: float) -> bool:
	if _can_see_wolf():
		seen_time += delta
		if seen_time >= notice_time:
			seen_time = 0.0
			last_seen = wolf.global_position
			lose_left = lose_time
			state = State.CHASE
			return true
	else:
		seen_time = 0.0
	return false


func _can_see_wolf() -> bool:
	if wolf == null:
		return false
	var to := wolf.global_position - global_position
	if to.length() > vision_range:
		return false
	var half_cone := deg_to_rad(vision_angle) * 0.5
	if absf(angle_difference(facing.angle(), to.angle())) > half_cone:
		return false
	# Line of sight: anything on the blocker layers between us counts as cover
	var query := PhysicsRayQueryParameters2D.create(
		global_position, wolf.global_position, sight_blockers, [get_rid(), wolf.get_rid()]
	)
	return get_world_2d().direct_space_state.intersect_ray(query).is_empty()


# visuals ----------------------------------------------------------------

func _draw() -> void:
	var half_cone := deg_to_rad(vision_angle) * 0.5
	var points := PackedVector2Array([Vector2.ZERO])
	var steps := 12
	for i in range(steps + 1):
		var a := facing.angle() - half_cone + (half_cone * 2.0) * float(i) / float(steps)
		points.append(Vector2.from_angle(a) * vision_range)

	var color := Color("#E8913A", 0.28)  # warm orange = human = danger
	if state == State.CHASE:
		color = Color("#E04030", 0.38)
	elif state == State.STUNNED:
		color = Color("#E8913A", 0.08)
	draw_colored_polygon(points, color)
