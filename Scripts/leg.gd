extends Node3D
class_name IKStepTrigger

## OLD: const RAY_LENGTH = 1000
## OLD: signal can_step(horizontal_plane_target_position,horizontal_plane_next_position,group)

# NEW: Scalable parameters
const RAY_LENGTH = 1000 # Kept your length, though 1000 is very long!
signal request_step(step_data: Dictionary) # Passing a Dict is safer for future upgrades

@export var target : Node3D
# OLD: @export var step_value : float
@export var step_threshold : float = 1.0 # Renamed for clarity, logic is the same

@export var group : int # 0 or 1 (A or B)

# NEW: Helper to offset ray so it doesn't clip inside the spider body mesh
@export var ray_origin_offset: Vector3 = Vector3(0, 0, 0)

func _physics_process(_delta):
	# SAFETY: Don't crash if target isn't assigned
	if not target: return

	var space_state = get_world_3d().direct_space_state

	## --- RAYCAST SETUP ---
	# NEW: Use Global Coordinates.
	# 'to_global' ensures the ray moves WITH the parent node.
	# '-global_transform.basis.y' ensures the ray points "Down" relative to the spider (allows wall walking).
	var ray_origin = to_global(ray_origin_offset)
	var ray_direction = -global_transform.basis.y * RAY_LENGTH
	var ray_end = ray_origin + ray_direction
	
	var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_end)

	var result = space_state.intersect_ray(query)
	
	## --- RESULT PARSING ---
	
	if not result:
		return

	var next_pos = result.get("position")
	var next_normal = result.get("normal") # We grab normal now too

	# NEW: Calculate 3D distance in Global Space. 
	# This automatically handles slopes/walls without needing to "flatten" to (x,0,z).
	var current_dist = target.global_position.distance_to(next_pos)
	
	## --- TRIGGER LOGIC ---
	# NEW: Check distance and pack data
	if current_dist < step_threshold:
		return

	var step_data = {
		"sender": self,         # Reference to this script
		"group": group,         # Leg Group (A or B)
		"target_pos": next_pos, # The raycast hit point
		"target_normal": next_normal, # The angle of the floor
		"urgency": current_dist # How far past the limit are we?
	}
	emit_signal("request_step", step_data)
