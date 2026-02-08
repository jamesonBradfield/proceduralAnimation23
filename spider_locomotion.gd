class_name SpiderLocomotion
extends Node3D

## Spider Procedural Animation System
## Fixes applied:
## 1. SYMMETRY BREAKING: Opposite legs are linked as neighbors
## 2. THRESHOLD SMOOTHING: Removed stationary snap logic
## 3. DEBUG VISUALIZATION: Neighbor connections shown

@export var step_height: float = 0.3
@export var step_speed: float = 8.0
@export var step_distance: float = 0.5
@export var max_moving_limbs: int = 3  ## Increased to allow tripod gait
@export var neighbor_threshold: float = 1.5
@export var show_debug_lines: bool = true

var _limbs: Array[LimbData] = []
var _is_moving: bool = false

class LimbData:
	var target: Node3D
	var rest_position: Vector3
	var current_position: Vector3
	var is_stepping: bool = false
	var step_progress: float = 0.0
	var step_start: Vector3
	var step_end: Vector3
	var step_curve: Curve
	var neighbors: Array[LimbData] = []
	var step_distance_variant: float  ## For symmetry breaking

func _ready():
	_setup_limbs()
	_setup_neighbors()
	_setup_symmetry_breaking()  ## FIX: Apply variance to prevent rowing

func _setup_limbs():
	## Find all limb targets (Marker3D or similar nodes)
	for child in get_children():
		if child.is_in_group("limb_targets") or child.name.contains("Leg"):
			var limb = LimbData.new()
			limb.target = child
			limb.rest_position = child.position
			limb.current_position = child.global_position
			limb.step_curve = _create_step_curve()
			_limbs.append(limb)
	
	print("SpiderLocomotion: Found ", _limbs.size(), " limbs")

func _create_step_curve() -> Curve:
	var curve = Curve.new()
	curve.add_point(Vector2(0, 0))
	curve.add_point(Vector2(0.5, 1))
	curve.add_point(Vector2(1, 0))
	return curve

func _setup_neighbors():
	## Calculate neighbors based on distance
	for i in range(_limbs.size()):
		for j in range(i + 1, _limbs.size()):
			var limb_a = _limbs[i]
			var limb_b = _limbs[j]
			var distance = limb_a.rest_position.distance_to(limb_b.rest_position)
			
			if distance < neighbor_threshold:
				limb_a.neighbors.append(limb_b)
				limb_b.neighbors.append(limb_a)
	
	## FIX #1: Force opposite legs to be neighbors (Symmetry Breaking)
	_link_opposite_legs()
	
	## Print neighbor info for debugging
	for limb in _limbs:
		print(limb.target.name, " has ", limb.neighbors.size(), " neighbors")

func _link_opposite_legs():
	## Links legs on opposite sides as neighbors to prevent "rowing"
	## This forces alternating steps between left and right sides
	for limb in _limbs:
		var limb_name = limb.target.name
		var opposite_name = ""
		
		## Handle naming conventions like "Leg_L_2" <-> "Leg_R_2"
		if "_L_" in limb_name:
			opposite_name = limb_name.replace("_L_", "_R_")
		elif "_R_" in limb_name:
			opposite_name = limb_name.replace("_R_", "_L_")
		elif "Left" in limb_name:
			opposite_name = limb_name.replace("Left", "Right")
		elif "Right" in limb_name:
			opposite_name = limb_name.replace("Right", "Left")
		elif limb_name.begins_with("L"):
			opposite_name = "R" + limb_name.substr(1)
		elif limb_name.begins_with("R"):
			opposite_name = "L" + limb_name.substr(1)
		
		if opposite_name.is_empty():
			continue
			
		## Find the opposite leg and link as neighbors
		for other in _limbs:
			if other.target.name == opposite_name:
				if not limb.neighbors.has(other):
					limb.neighbors.append(other)
					print("Linked ", limb_name, " <-> ", opposite_name, " (opposite leg)")
				break

func _setup_symmetry_breaking():
	## FIX #2: Add tiny random variance to step distances
	## This prevents mathematically perfect synchronization (rowing)
	for limb in _limbs:
		var variance = randf_range(0.95, 1.05)  ## 5% variance
		limb.step_distance_variant = step_distance * variance
		print(limb.target.name, " step_distance: ", limb.step_distance_variant)

func update_locomotion(delta: float, velocity: Vector3, is_stationary: bool = false):
	_is_moving = velocity.length() > 0.01
	
	## Process each limb
	for limb in _limbs:
		if limb.is_stepping:
			_process_step(limb, delta)
		else:
			_check_step_needed(limb, velocity, is_stationary)
	
	## Update visual positions
	_update_limb_positions()

func _check_step_needed(limb: LimbData, velocity: Vector3, is_stationary: bool):
	## Calculate desired foot position based on velocity
	var velocity_2d = Vector2(velocity.x, velocity.z)
	var look_ahead = velocity_2d.length() * 0.5  ## Look ahead based on speed
	
	var desired_local_pos = limb.rest_position + Vector3(
		velocity.normalized().x * look_ahead,
		0,
		velocity.normalized().z * look_ahead
	)
	
	var desired_global_pos = global_transform * desired_local_pos
	var current_error = limb.current_position.distance_to(desired_global_pos)
	
	## FIX #3: Smooth threshold - removed stationary snap logic
	## Always use the variant step distance for consistency
	var current_threshold = limb.step_distance_variant
	
	## Check if we should step
	if current_error > current_threshold:
		## Check neighbors - don't step if neighbors are stepping
		var can_step = _can_limb_step(limb)
		
		## Check global step limit
		var stepping_count = _get_stepping_count()
		if can_step and stepping_count < max_moving_limbs:
			_start_step(limb, desired_global_pos)

func _can_limb_step(limb: LimbData) -> bool:
	## Check if any neighbor is currently stepping
	for neighbor in limb.neighbors:
		if neighbor.is_stepping:
			return false
	return true

func _get_stepping_count() -> int:
	var count = 0
	for limb in _limbs:
		if limb.is_stepping:
			count += 1
	return count

func _start_step(limb: LimbData, target_position: Vector3):
	limb.is_stepping = true
	limb.step_progress = 0.0
	limb.step_start = limb.current_position
	limb.step_end = target_position

func _process_step(limb: LimbData, delta: float):
	limb.step_progress += delta * step_speed
	
	if limb.step_progress >= 1.0:
		limb.step_progress = 1.0
		limb.is_stepping = false
		limb.current_position = limb.step_end
		return
	
	## Interpolate position with arc
	var t = limb.step_progress
	var base_pos = limb.step_start.lerp(limb.step_end, t)
	var height_offset = limb.step_curve.sample(t) * step_height
	
	limb.current_position = base_pos + Vector3(0, height_offset, 0)

func _update_limb_positions():
	for limb in _limbs:
		limb.target.global_position = limb.current_position

func _process(delta):
	## FIX #4: Debug visualization of neighbor connections
	if show_debug_lines and Engine.is_editor_hint() == false:
		_debug_draw_neighbors()

func _debug_draw_neighbors():
	## Visualize neighbor connections as red lines
	## Every leg should have connections to adjacent legs AND across from it
	for limb in _limbs:
		for neighbor in limb.neighbors:
			## Draw line only once per pair (avoid duplicates)
			if limb.target.get_instance_id() < neighbor.target.get_instance_id():
				DebugDraw3D.draw_line(
					limb.target.global_position,
					neighbor.target.global_position,
					Color.RED,
					0.016  ## Duration (one frame at 60fps)
				)

## Public API for external control

func set_limb_targets(targets: Array[Node3D]):
	_limbs.clear()
	for target in targets:
		var limb = LimbData.new()
		limb.target = target
		limb.rest_position = target.position
		limb.current_position = target.global_position
		limb.step_curve = _create_step_curve()
		_limbs.append(limb)
	_setup_neighbors()
	_setup_symmetry_breaking()

func force_step(limb_index: int):
	## Force a specific limb to step (useful for testing)
	if limb_index >= 0 and limb_index < _limbs.size():
		var limb = _limbs[limb_index]
		var step_dir = Vector3(randf() - 0.5, 0, randf() - 0.5).normalized()
		_start_step(limb, limb.current_position + step_dir * step_distance)

func get_limb_info() -> Dictionary:
	## Returns debug info about each limb
	var info = {}
	for i in range(_limbs.size()):
		var limb = _limbs[i]
		info[limb.target.name] = {
			"is_stepping": limb.is_stepping,
			"neighbor_count": limb.neighbors.size(),
			"step_distance": limb.step_distance_variant
		}
	return info
