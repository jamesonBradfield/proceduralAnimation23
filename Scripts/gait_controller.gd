# ==============================================================================
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
class_name GaitController
extends Node3D

@export var thighs : Array[Node3D]
@export var target_offset : Vector3:
	set(new_value):
		target_offset = new_value
		apply_offsets()
@export var raycast_offset : Vector3:
	set(new_value):
		raycast_offset = new_value
		apply_offsets()
@export var ik_solver : CCDIK3D
@export var mechanical_linkage : Array[MechanicalLinkage]

var targets : Array[Node3D]
var raycasts : Array[Vector3]

func _ready() -> void:
	ik_solver.setting_count = thighs.size()
	
	# create suffix arrays to loop logically through every thing.
	var suffixes : Array[String]
	var bone_suffixes : Array[String]
	
	# strings/names
	for index in range(0,thighs.size()):
		var suffix := thighs[index].name.replace("Thigh","")
		suffixes.append(suffix)
		var bone_suffix = suffix.replace("_Fr",".Fr")
		bone_suffix = bone_suffix.replace("_Bk",".Bk")
		bone_suffixes.append(bone_suffix)
		
	# nodes
	for index in range(0,suffixes.size()):
		var suffix = suffixes[index]
		var new_target := Marker3D.new()
		new_target.name = "Target" + suffix
		self.add_child(new_target)
		new_target.top_level = true
		targets.append(new_target)
		raycasts.append(Vector3.ZERO)
		ik_solver.set_target_node(index,new_target.get_path())
		
	# bones
	for index in range(0,bone_suffixes.size()):
		var bone_suffix = bone_suffixes[index]
		ik_solver.set_root_bone_name(index,"Fake" + bone_suffix)
		ik_solver.set_end_bone_name(index,"Foot" + bone_suffix)
		
		var limit_count = min(ik_solver.get_joint_count(index), mechanical_linkage.size())
		for joint_index in range(0, limit_count):
			ik_solver.set_joint_rotation_axis(index,joint_index,mechanical_linkage[joint_index].rotation_axis)
			ik_solver.set_joint_limitation_right_axis(index,joint_index,mechanical_linkage[joint_index].right_rotation_axis)
			ik_solver.set_joint_limitation(index,joint_index,mechanical_linkage[joint_index].joint_limitation)
			
	apply_offsets()
	

func apply_offsets() -> void:
	if not targets.size() == thighs.size() or not raycasts.size() == thighs.size():
		return
	for index in range(0,targets.size()):
		targets[index].global_position = thighs[index].to_global(target_offset)
		raycasts[index] = to_local(thighs[index].to_global(raycast_offset))
