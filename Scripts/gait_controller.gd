# ==============================================================================
# GAIT CONTROLLER — Architecture Rationale
# ==============================================================================
#
# 1. NAMING CONVENTION = IMPLICIT BINDING
#    "Thigh.L" -> "Target.L" -> "Foot.L". No drag-and-drop wiring needed.
#
# 2. RUNTIME GENERATION
#    All targets/solvers are built in _ready(). Nothing saved to .tscn,
#    so no stale transforms or accidental editor edits.
#
# 3. TOTAL DATA OWNERSHIP
#    This script OWNS foot state — we tell the scene tree where the foot
#    is, not the other way around. Enables hot-swapping gaits and speeds.
#
# Creature-agnostic: biped, quadruped, centipede — just add "Thigh*"
# BoneAttachment3D nodes and the loop handles the rest.
#
# ==============================================================================
@tool
class_name GaitController
extends Node3D

@export_group("Setup")
var skeleton: Skeleton3D
@export var leg_config: LegConfig:
	set(val):
		if leg_config != val:
			if leg_config and leg_config.changed.is_connected(_on_leg_config_changed):
				leg_config.changed.disconnect(_on_leg_config_changed)
			leg_config = val
			if leg_config:
				if not leg_config.changed.is_connected(_on_leg_config_changed):
					leg_config.changed.connect(_on_leg_config_changed)
			if is_node_ready():
				_on_leg_config_changed()

@export_group("Gait System")
@export var gait_solver: GaitSolver
@export var follow_target: Node3D
@export var motion_profile: DynamicsProfile
@export_group("Debug")
@export var debug_draw: bool = true
@export var continuous_snap: bool = false
@export var snap_to_ground_now: bool:
	set(val):
		if is_node_ready():
			cast_ground_rays(true, 2.0)

var thighs: Array[BoneAttachment3D] = []
var legs: Array[Leg] = []
var _runtime_solver: CCDIK3D
var master_phase: float = 0.0
var leg_offsets: Array[float] = []

# Dynamics State
var _position_solver: SecondOrderDynamics
var _smoothed_velocity: Vector3 = Vector3.ZERO
var is_trotting_state: bool = false


func _ready() -> void:
	_find_skeleton_and_thighs()
	_rebuild_legs()
	_apply_ik_settings()
	apply_offsets()

	leg_offsets.resize(legs.size())
	leg_offsets.fill(0.0)

	# Initialize smoothed velocity to prevent null errors
	_smoothed_velocity = Vector3.ZERO

	call_deferred("cast_ground_rays", true, 0.0)

	# Initialize Dynamics Solver
	if motion_profile:
		_position_solver = SecondOrderDynamics.new(
			motion_profile.frequency,
			motion_profile.damping,
			motion_profile.response,
			global_position
		)


func _physics_process(delta: float) -> void:
	var current_velocity = Vector3.ZERO

	if follow_target:
		var raw_velocity = Vector3.ZERO
		if follow_target is CharacterBody3D:
			raw_velocity = follow_target.velocity
		_smoothed_velocity = _smoothed_velocity.lerp(raw_velocity, 0.2)
		if _smoothed_velocity.length() < 0.1:
			_smoothed_velocity = Vector3.ZERO
		current_velocity = _smoothed_velocity
		global_position = follow_target.global_position
		global_rotation.y = follow_target.global_rotation.y
	else:
		current_velocity = Vector3.ZERO
	if not gait_solver:
		return
	var speed = current_velocity.length()
	var solution = gait_solver.solve_for_velocity(speed)
	var phase_increment = delta / solution.cycle_time
	master_phase = fmod(master_phase + phase_increment, 1.0)
	_update_gait_offsets(solution.duty_factor)
	var space_state = get_world_3d().direct_space_state
	if not space_state:
		return
	for i in range(legs.size()):
		var leg = legs[i]
		leg.scan_floor(space_state, global_transform)
		leg.process_gait(
			master_phase,
			leg_offsets[i],
			solution.duty_factor,
			current_velocity,
			solution.cycle_time
		)
		if debug_draw:
			leg.draw_debug(leg.ground_point, 0.0)
		if Time.get_ticks_msec() % 500 < 20:
			print(
				(
					"Leg %d: target=%s | state=%d | ground=%s"
					% [i, leg.target.global_position, leg.current_state, leg.ground_point]
				)
			)
	if debug_draw and (Time.get_ticks_msec() % 500 < 20):
		print("Speed: %.2f | Beta: %.2f" % [speed, solution.duty_factor])


func _find_skeleton_and_thighs() -> void:
	assert(get_child_count() >= 1, "GaitController has no children!")
	skeleton = get_child(0) as Skeleton3D
	assert(skeleton, "Child 0 is not a Skeleton3D! It is: " + get_child(0).name)
	thighs.assign(skeleton.find_children("Thigh*", "BoneAttachment3D", true, false))
	assert(not thighs.is_empty(), "Skeleton has no 'Thigh' BoneAttachments!")


func _rebuild_legs() -> void:
	for node in find_children("Target*", "") + find_children("Leg*", ""):
		node.name = "Trash"
		node.queue_free()
	legs.assign(thighs.map(_create_leg_system))


func _create_leg_system(thigh: Node3D) -> Leg:
	var suffix := thigh.name.trim_prefix("Thigh")
	var new_target := Marker3D.new()
	new_target.name = "Target" + suffix
	new_target.top_level = true
	add_child(new_target)
	var new_leg := Leg.new(thigh, new_target)
	new_leg.name = "Leg" + suffix
	add_child(new_leg)
	return new_leg


func _on_leg_config_changed() -> void:
	if not is_node_ready():
		return
	_apply_ik_settings()
	apply_offsets()


func _apply_ik_settings() -> void:
	if not skeleton or thighs.is_empty():
		return
	if is_instance_valid(_runtime_solver):
		_runtime_solver.active = false
		_runtime_solver.name = "Trash_IK"
		_runtime_solver.queue_free()
	_runtime_solver = CCDIK3D.new()
	_runtime_solver.name = "Runtime_CCDIK"
	skeleton.add_child(_runtime_solver)
	_runtime_solver.owner = null
	_runtime_solver.setting_count = thighs.size()
	for index in range(thighs.size()):
		var suffix := thighs[index].name.replace("Thigh", "")
		var bone_suffix := suffix.replace("_Fr", ".Fr").replace("_Bk", ".Bk")
		_runtime_solver.set_root_bone_name(index, "Fake" + bone_suffix)
		_runtime_solver.set_end_bone_name(index, "Foot" + bone_suffix)
		if index < legs.size():
			_runtime_solver.set_target_node(index, legs[index].target.get_path())
	_runtime_solver.active = true
	skeleton.force_update_transform()
	if leg_config and leg_config.mechanical_linkage:
		for index in range(thighs.size()):
			var joint_count = _runtime_solver.get_joint_count(index)
			var limit_count = min(joint_count, leg_config.mechanical_linkage.size())
			for joint_index in range(limit_count):
				var link = leg_config.mechanical_linkage[joint_index]
				_runtime_solver.set_joint_rotation_axis(index, joint_index, link.rotation_axis)
				_runtime_solver.set_joint_limitation_right_axis(
					index, joint_index, link.right_rotation_axis
				)
				_runtime_solver.set_joint_limitation(index, joint_index, link.joint_limitation)


func apply_offsets() -> void:
	if not leg_config:
		return
	if Engine.is_editor_hint() and legs.is_empty() and get_child_count() > 0:
		legs.assign(get_children().filter(func(node): return node is Leg))
	if legs.size() != thighs.size():
		return
	for index in range(legs.size()):
		var leg = legs[index]
		leg.config = leg_config
		leg.apply_offsets(thighs[index])


func cast_ground_rays(snap_to_ground: bool = true, duration: float = 0.0) -> void:
	var space_state = get_world_3d().direct_space_state
	if not space_state:
		return
	for leg in legs:
		var result_pos = leg.scan_floor(space_state, global_transform)
		if snap_to_ground:
			leg.target.global_position = result_pos
		if debug_draw:
			leg.draw_debug(result_pos, duration)


## Determines the "Rhythm" of the walk with Hysteresis (Memory).
func _update_gait_offsets(duty_factor: float) -> void:
	# HYSTERESIS CHECK
	# We only switch modes if we cross a "safe" threshold.

	# CASE A: We are currently Walking (Wave)
	if not is_trotting_state:
		# We must go FAST (beta < 0.6) to switch to Trot.
		if duty_factor < 0.6:
			is_trotting_state = true
			# Optional: Print to confirm switch
			if debug_draw:
				print("Gait Switch: -> TROT")

	# CASE B: We are currently Trotting
	else:
		# We must go SLOW (beta > 0.8) to switch back to Wave.
		# This 0.2 gap prevents the flickering!
		if duty_factor > 0.8:
			is_trotting_state = false
			if debug_draw:
				print("Gait Switch: -> WAVE")

	# Apply Offsets based on the stable state
	for i in range(legs.size()):
		if is_trotting_state:
			# TROT: Diagonal pairs (good for fast movement)
			leg_offsets[i] = 0.0 if (i % 2 == 0) else 0.5
		else:
			# WAVE: Rolling sequence (good for stability/slow)
			leg_offsets[i] = float(i) / float(legs.size())
