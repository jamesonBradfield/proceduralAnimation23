class_name Limb
extends Node
# ok so restarting we want legs to be able to be defined in the editor, and a global clock sin wave setup by the controller.
# each leg needs to create its ik target on startup for now we will be creating the leg nodes programatically on ready.
# assuming we have a CCDIK3D node, we will need to create these Limbs, then define a separate "connection/ready signal" for connecting them to the ik3d node.
# I'm not sure the flow of this code, thinking we need to create a ccdik3d node that will act as the go between for this ans a gait controller that defined the specific ik body gait/legs/constraints etc...
var target: Node3D
var solver: SecondOrderDynamics
var raycast_origin : Vector3


func _init(_target : Node3D, _solver : SecondOrderDynamics, _raycast_origin : Vector3) -> void:
	target = _target
	solver = _solver
	raycast_origin = _raycast_origin
