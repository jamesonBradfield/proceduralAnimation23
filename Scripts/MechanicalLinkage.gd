class_name MechanicalLinkage
extends Resource

@export_group("Ik Constraints")
@export var joint_limitation: JointLimitationCone3D:
	set(value):
		if joint_limitation and joint_limitation.changed.is_connected(_on_sub_resource_changed):
			joint_limitation.changed.disconnect(_on_sub_resource_changed)
		joint_limitation = value
		if joint_limitation and not joint_limitation.changed.is_connected(_on_sub_resource_changed):
			joint_limitation.changed.connect(_on_sub_resource_changed)
		emit_changed()

@export var rotation_axis: SkeletonModifier3D.RotationAxis:
	set(value):
		rotation_axis = value
		emit_changed()

@export var right_rotation_axis: SkeletonModifier3D.SecondaryDirection:
	set(value):
		right_rotation_axis = value
		emit_changed()


func _on_sub_resource_changed() -> void:
	emit_changed()
