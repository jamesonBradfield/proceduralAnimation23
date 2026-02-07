class_name GaitController
extends Node3D

# TODO: RE-COMMENT THIS YOURSELF YOU LAZY DEV. EXPLAIN DYNAMICS AND RAYCAST LOGIC.
class Limb:
	var target: Node3D
	var raycast: Node3D
	var solver: SecondOrderDynamics
	
	func _init(t: Node3D, r: Node3D, s: SecondOrderDynamics) -> void:
		target = t
		raycast = r
		solver = s

@export_group("References")
@export var ghost_target: Node3D
@export var target_parent: Node3D
@export var raycast_parent: Node3D

@export_group("Dynamics Profiles")
@export var ghost_profile: DynamicsProfile
@export var leg_profile: DynamicsProfile

@export_group("Raycast Parameters")
@export var ray_length: float = 2.0
@export var target_dir: Vector3 = Vector3.DOWN
@export var lead_distance: float = 0.0

var controller_velocity: Vector3
var _limbs: Array[Limb] = []
var _ghost_solver: SecondOrderDynamics
var _ray_query: PhysicsRayQueryParameters3D

func _ready() -> void:
	_ray_query = PhysicsRayQueryParameters3D.new()
	_ray_query.collision_mask = 1
	if ghost_target and ghost_profile:
		_ghost_solver = SecondOrderDynamics.new(
			ghost_profile.frequency, 
			ghost_profile.damping, 
			ghost_profile.response, 
			global_position
		)
	
	if target_parent and raycast_parent and leg_profile:
		_setup_limbs()

func _setup_limbs() -> void:
	_limbs.clear()
	
	for target in target_parent.get_children():
		if not target is Node3D: continue
		
		var ray_name = str(target.name).replace("Target", "Raycast")
		var raycast = raycast_parent.get_node_or_null(ray_name)
		
		if raycast:
			_limbs.append(Limb.new(
				target, 
				raycast, 
				SecondOrderDynamics.new(
					leg_profile.frequency, 
					leg_profile.damping, 
					leg_profile.response, 
					target.global_position
				)
			))

func _physics_process(delta: float) -> void:
	if _ghost_solver:
		global_position = _ghost_solver.update(delta, ghost_target.global_position)

	if _limbs.is_empty(): return
	var space_state = get_world_3d().direct_space_state
	for limb in _limbs:
		_ray_query.from = limb.raycast.global_position + (controller_velocity * lead_distance)
		_ray_query.to = _ray_query.from + (target_dir * ray_length)	
		var result = space_state.intersect_ray(_ray_query)
		if result:
				limb.target.global_position = limb.solver.update(delta, result["position"])
