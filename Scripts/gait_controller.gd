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
		# Standard "Disconnect Old / Connect New" boilerplate
		if leg_config != val:
			if leg_config and leg_config.changed.is_connected(_on_leg_config_changed):
				leg_config.changed.disconnect(_on_leg_config_changed)
			leg_config = val
			if leg_config:
				if not leg_config.changed.is_connected(_on_leg_config_changed):
					leg_config.changed.connect(_on_leg_config_changed)

			# If we are running, immediately rebuild the solver
			if is_node_ready():
				_on_leg_config_changed()

@export_group("Debug")
@export var debug_draw: bool = true
@export var continuous_snap: bool = false
@export var snap_to_ground_now: bool:
	set(val):
		if is_node_ready():
			cast_ground_rays(true, 2.0)
var thighs: Array[BoneAttachment3D] = []
var legs: Array[Leg] = []
var _runtime_solver: CCDIK3D  # We own this node now.
var global_cycle_time: float = 0.0


func _ready() -> void:
	# 1. DISCOVERY PHASE
	_find_skeleton_and_thighs()
	_rebuild_legs()

	# 2. START SYSTEMS
	_apply_ik_settings()  # Builds the CCDIK3D node
	apply_offsets()  # Snaps legs to config positions

	# One-shot snap to ground on start
	call_deferred("cast_ground_rays", true, 0.0)


func _find_skeleton_and_thighs() -> void:
	assert(get_child_count() >= 1, "GaitController has no children!")
	skeleton = get_child(0) as Skeleton3D
	assert(skeleton, "Child 0 is not a Skeleton3D! It is: " + get_child(0).name)

	# FIX: Use assign() to handle the type conversion from Array[Node] to Array[BoneAttachment3D]
	thighs.assign(skeleton.find_children("Thigh*", "BoneAttachment3D", true, false))

	assert(not thighs.is_empty(), "Skeleton has no 'Thigh' BoneAttachments!")


func _rebuild_legs() -> void:
	# 1. CLEANUP
	for node in find_children("Target*", "") + find_children("Leg*", ""):
		node.name = "Trash"
		node.queue_free()

	# 2. FIX: Use assign() to convert the generic Array from map() into Array[Leg]
	legs.assign(thighs.map(_create_leg_system))


# This is your "Selector" function (like .Select(x => Create(x)))
func _create_leg_system(thigh: Node3D) -> Leg:
	var suffix := thigh.name.trim_prefix("Thigh")
	# A. Create Target
	var new_target := Marker3D.new()
	new_target.name = "Target" + suffix
	new_target.top_level = true
	add_child(new_target)
	# B. Create Leg
	var new_leg := Leg.new(thigh, new_target)
	new_leg.name = "Leg" + suffix
	add_child(new_leg)

	return new_leg


func _on_leg_config_changed() -> void:
	if not is_node_ready():
		return
	_apply_ik_settings()  # <--- REBUILD THE SOLVER
	apply_offsets()


## THE NUCLEAR OPTION: Destroys and recreates the IK solver.
## This ensures new constraints (Joint Limits) are actually applied.
func _apply_ik_settings() -> void:
	# 1. STRUCTURAL INTEGRITY (The Law)
	# The Skeleton MUST exist. If it doesn't, the scene tree is broken.
	assert(skeleton != null, "GaitController: Critical Error - Skeleton node is missing.")

	# 2. STATE CHECK (The "Not Ready Yet" Guard)
	# Thighs might be empty while you are configuring the node in the Inspector.
	# We don't want to crash the editor, just exit gracefully.
	if thighs.is_empty():
		return

	# 3. DESTROY OLD SOLVER
	# We kill the old solver to clear internal caches that refuse to update constraints.
	if is_instance_valid(_runtime_solver):
		_runtime_solver.active = false
		_runtime_solver.name = "Trash_IK"  # Prevent name collision in same frame
		_runtime_solver.queue_free()

	# 4. CREATE NEW SOLVER
	_runtime_solver = CCDIK3D.new()
	_runtime_solver.name = "Runtime_CCDIK"
	# IK nodes MUST be children of the Skeleton to work reliably
	skeleton.add_child(_runtime_solver)

	# EDITOR HYGIENE: This node is invisible to the Scene Dock.
	# It will NOT be saved to the .tscn file.
	_runtime_solver.owner = null

	# 5. CONFIGURE SOLVER (Implicit Binding)
	_runtime_solver.setting_count = thighs.size()
	for index in range(thighs.size()):
		var suffix := thighs[index].name.replace("Thigh", "")
		# Example: "Thigh.Fr" -> Bone "Fake.Fr" / "Foot.Fr"
		var bone_suffix := suffix.replace("_Fr", ".Fr").replace("_Bk", ".Bk")

		_runtime_solver.set_root_bone_name(index, "Fake" + bone_suffix)
		_runtime_solver.set_end_bone_name(index, "Foot" + bone_suffix)

		# Link the IK chain to the Target Marker we created in _ready
		if index < legs.size():
			_runtime_solver.set_target_node(index, legs[index].target.get_path())

	# 6. IGNITION
	_runtime_solver.active = true

	# Force an update of the skeleton to ensure the IK chain is built
	# This is critical for get_joint_count() to return > 0
	skeleton.force_update_transform()

	# 7. POST-FLIGHT CHECK (Peace of Mind)
	# If this fails, your naming convention (Thigh.L -> Foot.L) is broken.
	if _runtime_solver.active and not thighs.is_empty():
		assert(
			_runtime_solver.get_joint_count(0) > 0,
			"GaitController: IK Solver created but found 0 joints. Check bone naming (Thigh.L -> Foot.L)."
		)

	# 8. APPLY CONSTRAINTS
	# We do this AFTER start/update because get_joint_count() relies on the chain being built.
	if leg_config and leg_config.mechanical_linkage:
		for index in range(thighs.size()):
			# Re-verify joint count now that chain should be built
			var joint_count = _runtime_solver.get_joint_count(index)
			var limit_count = min(joint_count, leg_config.mechanical_linkage.size())

			for joint_index in range(limit_count):
				var link = leg_config.mechanical_linkage[joint_index]

				# These setters fail on existing nodes, which is why we nuclear-rebuild
				_runtime_solver.set_joint_rotation_axis(index, joint_index, link.rotation_axis)
				_runtime_solver.set_joint_limitation_right_axis(
					index, joint_index, link.right_rotation_axis
				)
				_runtime_solver.set_joint_limitation(index, joint_index, link.joint_limitation)


func apply_offsets() -> void:
	if not leg_config:
		return
	# If legs array is empty but we have children (script reload), try to rebuild it
	if Engine.is_editor_hint() and legs.is_empty() and get_child_count() > 0:
		# "Get all children, Keep only Legs, Assign to Array"
		legs.assign(get_children().filter(func(node): return node is Leg))

	assert(
		legs.size() == thighs.size(), "GaitController: Can't apply offsets! legs/thighs mismatch"
	)

	for index in range(legs.size()):
		var leg = legs[index]
		# Push Config to Leg
		leg.config = leg_config
		# Apply (pass the authoritative thigh reference)
		leg.apply_offsets(thighs[index])


func cast_ground_rays(snap_to_ground: bool = true, duration: float = 0.0) -> void:
	assert(legs.size() == thighs.size(), "GaitController: Can't cast rays legs/thighs mismatch")
	var space_state = get_world_3d().direct_space_state
	if not space_state:
		return
	for leg in legs:
		var result_pos = leg.scan_floor(space_state, global_transform)

		if snap_to_ground:
			leg.target.global_position = result_pos

		if debug_draw:
			leg.draw_debug(result_pos, duration)


func _physics_process(_delta: float) -> void:
	if continuous_snap or debug_draw:
		cast_ground_rays(continuous_snap, 0.0)
