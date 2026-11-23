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
@export var pause_time := 4.0
## false = loop around the points, true = walk to the end and back again
@export var ping_pong := true
## Direction he faces at the start, and when he returns to his post.
## 0 = right, 90 = down, 180 = left, -90 = up
@export_range(-180, 180, 1, "degrees") var start_direction := 0.0
## Watch-post hunters sweep side to side continuously; others just face start_direction
@export var guard_sweeps := false
## Seconds for one full back-and-forth sweep
@export var guard_sweep_time := 5.0
## Tower hunters shouldn't climb down for a lantern
@export var ignores_lures := false

@export_group("Senses")
@export var vision_range := 320.0
## Full width of the cone, in degrees
@export var vision_angle := 60.0
## Total degrees the cone sweeps side to side while he looks around
@export var look_sweep_angle := 150.0
## Wolf must stay in the cone this long before the hunter reacts (fairness window)
@export var notice_time := 0.25
## Physics layers that block line of sight (layer 1 = walls and trees)
@export_flags_2d_physics var sight_blockers := 1

@export_group("Chase")
@export var chase_speed := 200.0
## Seconds the hunter keeps chasing after losing sight of the wolf
@export var lose_time := 3.0
@export var catch_distance := 130.0

@export_group("Investigate")
@export var investigate_speed := 110.0
@export var investigate_wait := 4.0

var state := State.PATROL
var facing := Vector2.RIGHT
var is_guard := false

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
var wait_total := 1.0
var start_facing := Vector2.RIGHT
var guard_t := 0.0
@onready var alert: Label = get_node_or_null("Alert")
@onready var nav: NavigationAgent2D = get_node_or_null("NavAgent")
var last_nav_target := Vector2.INF


func _ready() -> void:
	add_to_group("hunters")
	add_to_group("resettable")
	facing = Vector2.from_angle(deg_to_rad(start_direction))
	start_facing = facing
	wolf = get_tree().get_first_node_in_group("wolf")
	spawn_pos = global_position
	if waypoint_parent:
		for c in waypoint_parent.get_children():
			if c is Node2D:
				waypoints.append(c.global_position)
	is_guard = waypoints.size() < 2
	if waypoints.is_empty():
		waypoints.append(global_position)


func _physics_process(delta: float) -> void:
	# Touching the wolf is always a catch, even before he has noticed it
	if state != State.STUNNED and wolf and global_position.distance_to(wolf.global_position) <= catch_distance:
		velocity = Vector2.ZERO
		caught_player.emit()
		state = State.STUNNED
		stun_left = 999.0
		return
	
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
	_update_alert()

# states ----------------------------------------------------------------

func _patrol(delta: float) -> void:
	if _check_for_wolf(delta):
		return
	if is_guard:
		_guard_watch(delta)
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
	print("investigate target: ", pos, " hunter at: ", global_position)
	if state == State.CHASE or state == State.STUNNED or ignores_lures:
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
	facing = start_facing
	wp_index = 0
	wp_dir = 1
	wait_left = 0.0
	seen_time = 0.0
	arrived = false
	state = State.PATROL
	guard_t = 0.0


# helpers ----------------------------------------------------------------

func _turn_toward(dir: Vector2, delta: float) -> void:
	facing = Vector2.from_angle(lerp_angle(facing.angle(), dir.angle(), 6.0 * delta))

func _guard_watch(delta: float) -> void:
	velocity = Vector2.ZERO
	if not guard_sweeps:
		_turn_toward(start_facing, delta)
		return
	guard_t += delta
	var half := deg_to_rad(look_sweep_angle) * 0.5
	var phase := guard_t / maxf(guard_sweep_time, 0.01) * TAU
	var target := start_facing.angle() + sin(phase) * half
	# Easing toward the target means he swings smoothly back into the sweep after a chase
	facing = Vector2.from_angle(lerp_angle(facing.angle(), target, 10.0 * delta))

## Walks toward a point, going around walls. Returns true once there.
func _move_to(target: Vector2, speed: float) -> bool:
	var dest := target
	# Use the navmesh once it is ready, otherwise fall back to a straight line
	if nav and NavigationServer2D.map_get_iteration_id(nav.get_navigation_map()) > 0:
		if last_nav_target.distance_to(target) > 4.0:
			nav.target_position = target
			last_nav_target = target
		if nav.is_navigation_finished():
			velocity = Vector2.ZERO
			last_nav_target = Vector2.INF  # allows the same target to be used again
			return true
		dest = nav.get_next_path_position()
	elif global_position.distance_to(target) < 6.0:
		velocity = Vector2.ZERO
		return true

	velocity = (dest - global_position).normalized() * speed
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
	wait_total = seconds
	pause_t = 0.0
	pause_angle = facing.angle()
	velocity = Vector2.ZERO


## Sweeps the vision cone left and right while standing still
func _look_around(delta: float) -> void:
	velocity = Vector2.ZERO
	pause_t += delta
	var progress := clampf(pause_t / maxf(wait_total, 0.01), 0.0, 1.0)
	var half_sweep := deg_to_rad(look_sweep_angle) * 0.5
	facing = Vector2.from_angle(pause_angle + sin(progress * TAU) * half_sweep)


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

func _update_alert() -> void:
	if alert == null:
		return
	match state:
		State.INVESTIGATE:
			alert.text = "?"
			alert.add_theme_color_override("font_color", Color("#E8913A"))
			alert.visible = true
		State.CHASE:
			alert.text = "!"
			alert.add_theme_color_override("font_color", Color("#E04030"))
			alert.visible = true
		_:
			alert.visible = false

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
