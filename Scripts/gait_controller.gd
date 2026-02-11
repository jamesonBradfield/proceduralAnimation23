#==============================================================================
# THE "NO-NONSENSE" GAIT CONTROLLER MANIFESTO
# ==============================================================================
#
# DEAR FUTURE JAMIE:
#
# If you are reading this, you are probably tempted to refactor this into
# "manageable components" or add "helper nodes" in the editor.
#
# STOP. READ THIS FIRST.
#
# This system was built this way for 7 very specific reasons.
# Do not touch it unless you understand WHY it exists.
#
# 1. THE NAMING CONVENTION IS LAW.
#    - We rely on implicit binding. "Thigh.L" -> "Target.L" -> "Raycast.L".
#    - There is no "Drag and Drop" hell. If the bone exists, the leg works.
#
# 2. INFINITE SCALABILITY.
#    - This script doesn't know what a "Biped" or "Quadruped" is.
#    - It just knows "Thighs".
#    - Want a centipede? Add bones to the array. The loop handles the rest.
#
# 3. EDITOR HYGIENE.
#    - The Scene Tree in the editor is clean.
#    - No "Leg_01", "Target_01", "Solver_01" cluttering the view.
#    - We avoid the "Godot Node Sprawl" that makes levels unreadable.
#
# 4. RUNTIME GENERATION.
#    - The Scene Tree is constructed at runtime (`_ready()`).
#    - This ensures a fresh state every launch. No "stale transforms" saved
#      accidentally in the .tscn file.
#
# 5. IDIOT-PROOFING (EDITOR SAFETY).
#    - You cannot accidentally move a Target Node in the editor because
#      THEY DON'T EXIST in the editor.
#    - The logic is locked in code. You cannot break the rig by clicking wrong.
#
# 6. TOTAL DATA OWNERSHIP (THE HOLY GRAIL).
#    - Because we generate the targets programmatically, this script OWNS the state.
#    - We don't ask the scene tree "Where is the foot?". We TELL it.
#    - This allows us to swap Gaits, Math Profiles, and Speeds instantly
#      without fighting the physics engine or node hierarchy.
#
# 7. CONCLUSION.
#    - This code rocks. It is efficient, modular, and clean.
#    - If you broke it, that's a skill issue.
#    - F*** you, future self. You're welcome.
#
# ==============================================================================
#endregion
@tool
class_name GaitController
extends Node3D

@export var thighs: Array[Node3D]
@export var target_offset: Vector3:
	set(new_value):
		target_offset = new_value
		if is_node_ready():
			apply_offsets()
@export var raycast_offset: Vector3:
	set(new_value):
		raycast_offset = new_value
		if is_node_ready():
			apply_offsets()
@export var global_raycast_shift: Vector3 = Vector3.ZERO
@export var ik_solver: CCDIK3D
@export var mechanical_linkage: Array[MechanicalLinkage]

@export_group("Body Dynamics")
@export var follow_target: Node3D
@export var frequency: float = 2.5
@export var damping: float = 0.5
@export var response: float = 0.0

@export_group("Physics & Debug")

@export var ray_length: float = 3.0
@export var ray_start_buffer: float = 1.0
@export var debug_draw: bool = true
@export var continuous_snap: bool = false
@export var snap_to_ground_now: bool:
	set(val):
		if is_node_ready():
			cast_ground_rays(true, 2.0)

var targets: Array[Node3D]

var _body_sod: SecondOrderDynamics
var raycasts: Array[Vector3]

var global_cycle_time: float = 0.0


func _ready() -> void:
	if not ik_solver:
		return
	ik_solver.setting_count = thighs.size()

	if follow_target:
		_body_sod = SecondOrderDynamics.new(frequency, damping, response, global_position)
		set_as_top_level(true)

	var suffixes: Array[String] = []

	var bone_suffixes: Array[String] = []

	# strings/names
	for index in range(thighs.size()):
		var suffix := thighs[index].name.replace("Thigh", "")
		suffixes.append(suffix)
		bone_suffixes.append(suffix.replace("_Fr", ".Fr").replace("_Bk", ".Bk"))

	# nodes
	for index in range(suffixes.size()):
		var suffix = suffixes[index]
		var new_target := Marker3D.new()
		new_target.name = "Target" + suffix
		add_child(new_target)
		new_target.top_level = true
		targets.append(new_target)
		raycasts.append(Vector3.ZERO)
		ik_solver.set_target_node(index, new_target.get_path())

	# bones
	for index in range(bone_suffixes.size()):
		var bone_suffix = bone_suffixes[index]
		ik_solver.set_root_bone_name(index, "Fake" + bone_suffix)
		ik_solver.set_end_bone_name(index, "Foot" + bone_suffix)

		var limit_count = min(ik_solver.get_joint_count(index), mechanical_linkage.size())
		for joint_index in range(limit_count):
			var link = mechanical_linkage[joint_index]
			ik_solver.set_joint_rotation_axis(index, joint_index, link.rotation_axis)
			ik_solver.set_joint_limitation_right_axis(index, joint_index, link.right_rotation_axis)
			ik_solver.set_joint_limitation(index, joint_index, link.joint_limitation)

	apply_offsets()
	# One-shot snap to ground on start
	call_deferred("cast_ground_rays", true, 2.0)


func apply_offsets() -> void:
	if targets.size() != thighs.size() or raycasts.size() != thighs.size():
		return

	for index in range(targets.size()):
		# 1. Visual Target (Initial Guess)
		targets[index].global_position = thighs[index].to_global(target_offset)

		# 2. BAKE RAYCAST ORIGIN
		var leg_relative_pos := thighs[index].to_global(raycast_offset)
		raycasts[index] = to_local(leg_relative_pos)


func cast_ground_rays(snap_to_ground: bool = true, duration: float = 0.0) -> void:
	if targets.size() != thighs.size():
		return
	var space_state = get_world_3d().direct_space_state
	if not space_state:
		return

	for index in range(targets.size()):
		# 1. Retrieve Baked Origin (Rotates with Body)
		var baked_origin := to_global(raycasts[index])

		# 2. Apply the NEW Global Shift
		var hip_center := baked_origin + global_raycast_shift

		# 3. Sky Hook (Start High, Shoot Low) using the shifted center
		var up_vec := global_transform.basis.y
		var ray_origin := hip_center + (up_vec * ray_start_buffer)
		var ray_end := hip_center - (up_vec * ray_length)

		# 4. Cast
		var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
		var result := space_state.intersect_ray(query)

		if snap_to_ground:
			if result:
				targets[index].global_position = result.position
			else:
				targets[index].global_position = ray_end

		# 5. Debug
		if debug_draw:
			var color := Color.GREEN if result else Color.RED
			DebugDraw3D.draw_line(
				ray_origin, result.position if result else ray_end, color, duration
			)
			if result:
				DebugDraw3D.draw_sphere(result.position, 0.1, Color.CYAN, duration)

			# Draw the Baked Origin Axis to prove it rotates with the body
			var origin_transform := Transform3D(global_transform.basis, hip_center)
			DebugDraw3D.draw_sphere(origin_transform.origin, 0.1, Color.ORANGE_RED, duration)

			# Draw the ACTUAL target position (where the foot currently is)
			DebugDraw3D.draw_sphere(targets[index].global_position, 0.15, Color.MAGENTA, duration)


func _physics_process(delta: float) -> void:
	if follow_target and _body_sod:
		global_position = _body_sod.update(delta, follow_target.global_position)

	if targets.size() != thighs.size():
		return

	if continuous_snap or debug_draw:
		cast_ground_rays(continuous_snap, 0.0)
