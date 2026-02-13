@tool
class_name Leg
extends Node

var target: Node3D
var thigh: Node3D
var raycast_origin: Vector3  # Baked local position relative to the body

# Config (Resource)
var config: LegConfig

# State
var is_grounded: bool = false
var ground_normal: Vector3 = Vector3.UP
var ground_point: Vector3 = Vector3.ZERO
var last_ray_origin: Vector3 = Vector3.ZERO
var last_ray_end: Vector3 = Vector3.ZERO


func _init(_thigh: Node3D, _target: Node3D) -> void:
	thigh = _thigh
	target = _target


#NOTE: need more early returns/errors.
func apply_offsets(current_thigh: Node3D = null) -> void:
	assert(config, "Leg: " + str(name) + " has no config")

	# Recovery: If thigh was lost (editor reload), update it
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
				# Use the global rest pose of the bone
				reference_transform = (
					skeleton.global_transform * skeleton.get_bone_global_rest(bone_idx)
				)
			else:
				push_warning(
					(
						"Leg: "
						+ str(name)
						+ " bone '"
						+ bone_attach.bone_name
						+ "' not found, using runtime transform"
					)
				)

	# 1. Visual Target (Initial Guess)
	target.global_position = reference_transform * config.target_offset

	# 2. BAKE RAYCAST ORIGIN
	var leg_relative_pos := reference_transform * config.raycast_offset
	raycast_origin = body_node.to_local(leg_relative_pos)


## Casts a ray from the body's current position to find the floor.
## Returns the hit position or the ray's end point if nothing was hit.
func scan_floor(
	space_state: PhysicsDirectSpaceState3D, global_body_transform: Transform3D
) -> Vector3:
	if not config:
		return target.global_position  # Fallback?

	# 1. Calculate Global Ray Start
	var baked_origin_global := global_body_transform * raycast_origin
	var hip_center := baked_origin_global + config.global_raycast_shift

	var up_vec := global_body_transform.basis.y
	var ray_origin := hip_center + (up_vec * config.ray_start_buffer)
	var ray_end := hip_center - (up_vec * config.ray_length)

	# Store for debug drawing
	last_ray_origin = ray_origin
	last_ray_end = ray_end

	# 2. Cast
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	var result := space_state.intersect_ray(query)
	if config:
		query.collision_mask = config.collision_mask
	if result:
		is_grounded = true
		ground_point = result.position
		ground_normal = result.normal
		return result.position
	else:
		is_grounded = false
		ground_point = ray_end
		ground_normal = up_vec
		return ray_end


## Draws debug visualization for this leg's raycast and target.
func draw_debug(result_pos: Vector3, duration: float) -> void:
	if not config:
		return

	var body_node := get_parent() as Node3D
	if not body_node:
		return

	var color := Color.GREEN if is_grounded else Color.RED
	var hip_center := body_node.to_global(raycast_origin) + config.global_raycast_shift

	DebugDraw3D.draw_line(last_ray_origin, result_pos, color, duration)
	if is_grounded:
		DebugDraw3D.draw_sphere(result_pos, 0.1, Color.CYAN, duration)

	# Baked Origin Axis â€” proves it rotates with the body
	DebugDraw3D.draw_sphere(hip_center, 0.1, Color.ORANGE_RED, duration)

	# Actual target position (where the foot currently is)
	DebugDraw3D.draw_sphere(target.global_position, 0.15, Color.MAGENTA, duration)
