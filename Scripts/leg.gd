@tool
class_name Leg
extends Node

enum State { STANCE, SWING }

var target: Node3D
var thigh: Node3D
var raycast_origin: Vector3  # Baked local position relative to the body

# Config (Resource)
var config: LegConfig

# State Data
var current_state: State = State.STANCE
var is_grounded: bool = false
var ground_normal: Vector3 = Vector3.UP
var ground_point: Vector3 = Vector3.ZERO  # The point directly under the HIP (raycast result)

# Debug Data
var last_ray_origin: Vector3 = Vector3.ZERO
var last_ray_end: Vector3 = Vector3.ZERO

# Swing Logic Data
var step_start_pos: Vector3 = Vector3.ZERO
var step_end_pos: Vector3 = Vector3.ZERO


func _init(_thigh: Node3D, _target: Node3D) -> void:
	thigh = _thigh
	target = _target


func apply_offsets(current_thigh: Node3D = null) -> void:
	assert(config, "Leg: " + str(name) + " has no config")

	if current_thigh:
		thigh = current_thigh

	assert(thigh, "Leg: " + str(name) + " has no thigh")

	var body_node := get_parent() as Node3D
	if not body_node:
		return

	# Determine the Transform to use (Prefer Rest Pose if possible)
	var reference_transform := thigh.global_transform

	if thigh is BoneAttachment3D:
		var bone_attach := thigh as BoneAttachment3D
		var skeleton: Skeleton3D

		if bone_attach.use_external_skeleton:
			skeleton = bone_attach.get_node_or_null(bone_attach.external_skeleton) as Skeleton3D
		else:
			skeleton = bone_attach.get_parent() as Skeleton3D

		if skeleton:
			var bone_idx := skeleton.find_bone(bone_attach.bone_name)
			if bone_idx != -1:
				reference_transform = (
					skeleton.global_transform * skeleton.get_bone_global_rest(bone_idx)
				)
			else:
				push_warning("Leg: " + str(name) + " bone not found, using runtime transform")

	# 1. Visual Target (Initial Guess)
	target.global_position = reference_transform * config.target_offset

	# 2. BAKE RAYCAST ORIGIN
	var leg_relative_pos := reference_transform * config.raycast_offset
	raycast_origin = body_node.to_local(leg_relative_pos)


func process_gait(
	master_phase: float,
	leg_offset: float,
	duty_factor: float,
	body_velocity: Vector3,
	cycle_time: float
) -> void:
	var leg_phase = fmod(master_phase + leg_offset, 1.0)

	# Safety: Ensure duty_factor never hits exactly 1.0 during math
	# to prevent divide-by-zero errors in the swing calculation.
	var safe_duty_factor = min(duty_factor, 0.99)

	if leg_phase < safe_duty_factor:
		if current_state == State.SWING:
			_enter_stance()
		_process_stance()
	else:
		if current_state == State.STANCE:
			_enter_swing(body_velocity, cycle_time)

		# Use safe_duty_factor here to guarantee denominator is > 0.01
		var swing_t = (leg_phase - safe_duty_factor) / (1.0 - safe_duty_factor)
		_process_swing(swing_t)


func _enter_stance() -> void:
	current_state = State.STANCE
	# On contact, we could spawn dust particles or play a sound here.
	# The target position remains "pinned" to the ground from the end of the swing.


func _process_stance() -> void:
	# In Stance, we DO NOT move the target. It is planted.
	# However, we can optionally snap it to the ground height if we are sliding
	# or if we want to glue it to a moving platform.
	pass


func _enter_swing(velocity: Vector3, cycle_time: float) -> void:
	current_state = State.SWING
	step_start_pos = target.global_position

	# PREDICTION: Calculate a STABLE landing target
	# Capture ground_point at the moment we enter swing (don't let it shift during swing)
	var stable_ground_pos = ground_point

	# How far ahead to step: velocity * time
	# Use minimum velocity to ensure we always step somewhere (prevents zero-length steps)
	var min_step_dist = 0.1  # Minimum step distance
	var effective_velocity = velocity
	if velocity.length() < min_step_dist / (cycle_time * 0.5):
		# If nearly stopped, use a small default step based on body orientation
		effective_velocity = -thigh.global_transform.basis.z * min_step_dist / (cycle_time * 0.5)

	var prediction_dist = effective_velocity * (cycle_time * 0.5)

	# Landing target: current ground position + forward prediction
	step_end_pos = stable_ground_pos + prediction_dist


func _process_swing(t: float) -> void:
	# 1. Horizontal Move (Lerp)
	var base_pos = step_start_pos.lerp(step_end_pos, t)

	# 2. Vertical Arc (Sine)
	# sin(t * PI) gives a curve that is 0 at start, 1 at midpoint, 0 at end.
	var vertical_offset = Vector3.UP * config.step_height * sin(t * PI)

	target.global_position = base_pos + vertical_offset


## Casts a ray from the body's current position to find the floor.
## Updates 'ground_point' which acts as the sensor for the next step.
func scan_floor(
	space_state: PhysicsDirectSpaceState3D, global_body_transform: Transform3D
) -> Vector3:
	if not config:
		return target.global_position

	# 1. Calculate Global Ray Start
	var baked_origin_global := global_body_transform * raycast_origin
	var hip_center := baked_origin_global + config.global_raycast_shift

	var up_vec := global_body_transform.basis.y
	var ray_origin := hip_center + (up_vec * config.ray_start_buffer)
	var ray_end := hip_center - (up_vec * config.ray_length)

	last_ray_origin = ray_origin
	last_ray_end = ray_end

	# 2. Cast
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	if config:
		query.collision_mask = config.collision_mask

	var result := space_state.intersect_ray(query)

	if result:
		is_grounded = true
		ground_point = result.position  # Sensor update
		ground_normal = result.normal
		return result.position
	else:
		is_grounded = false
		ground_point = ray_end  # Fallback: Step to max extension
		ground_normal = up_vec
		return ray_end


func draw_debug(result_pos: Vector3, duration: float) -> void:
	if not config:
		return
	var body_node := get_parent() as Node3D
	if not body_node:
		return

	# Draw Ray
	var color := Color.GREEN if is_grounded else Color.RED
	DebugDraw3D.draw_line(last_ray_origin, ground_point, color, duration)  # Draw to hit point

	# Draw State Info
	var state_color = Color.BLUE if current_state == State.STANCE else Color.YELLOW
	DebugDraw3D.draw_sphere(target.global_position, 0.1, state_color, duration)

	# Draw Projected Landing Spot (only visible during swing usually, but good for debug)
	if current_state == State.SWING:
		DebugDraw3D.draw_sphere(step_end_pos, 0.05, Color.MAGENTA, duration)
