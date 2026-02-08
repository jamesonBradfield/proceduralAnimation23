class_name SpiderController
extends CharacterBody3D

## Spider Controller - Uses SpiderLocomotion for procedural animation
## Attach this to your spider's root CharacterBody3D node

@export var move_speed: float = 3.0
@export var rotation_speed: float = 5.0
@export var acceleration: float = 8.0
@export var locomotion_system: NodePath

@onready var _locomotion: SpiderLocomotion

var _input_vector: Vector2 = Vector2.ZERO
var _target_velocity: Vector3 = Vector3.ZERO

func _ready():
	## Find locomotion system
	if not locomotion_system.is_empty():
		_locomotion = get_node(locomotion_system)
	else:
		## Auto-find SpiderLocomotion child
		for child in get_children():
			if child is SpiderLocomotion:
				_locomotion = child
				break
	
	if _locomotion == null:
		push_error("SpiderController: No SpiderLocomotion found!")

func _input(event):
	## Handle input
	_input_vector = Input.get_vector("move_left", "move_right", "move_forward", "move_back")

func _physics_process(delta):
	## Calculate desired velocity
	var direction = Vector3(_input_vector.x, 0, _input_vector.y).normalized()
	
	## Rotate towards movement direction
	if direction.length() > 0.01:
		var target_rotation = atan2(direction.x, direction.z)
		rotation.y = lerp_angle(rotation.y, target_rotation, rotation_speed * delta)
	
	## Smooth velocity changes (prevents threshold flickering)
	var desired_velocity = direction * move_speed
	velocity = velocity.lerp(desired_velocity, acceleration * delta)
	
	## Move the character
	move_and_slide()
	
	## Update locomotion system
	if _locomotion:
		var is_stationary = velocity.length() < 0.1
		_locomotion.update_locomotion(delta, velocity, is_stationary)

func _process(_delta):
	## Debug info
	if Input.is_action_just_pressed("ui_accept"):
		print_limb_info()

func print_limb_info():
	if _locomotion:
		var info = _locomotion.get_limb_info()
		print("=== Limb Info ===")
		for limb_name in info.keys():
			var data = info[limb_name]
			print(limb_name, ": stepping=", data.is_stepping, 
				", neighbors=", data.neighbor_count,
				", threshold=", "%.2f" % data.step_distance)
