@tool
class_name LegConfig
extends Resource

@export_group("Linkage")
@export var mechanical_linkage: Array[MechanicalLinkage]:
	set(value):
		_disconnect_linkages()
		mechanical_linkage = value
		_connect_linkages()
		emit_changed()

@export_group("Offsets")
@export var target_offset: Vector3:
	set(value):
		target_offset = value
		emit_changed()

@export var raycast_offset: Vector3:
	set(value):
		raycast_offset = value
		emit_changed()

@export var global_raycast_shift: Vector3 = Vector3.ZERO:
	set(value):
		global_raycast_shift = value
		emit_changed()

@export_group("Raycasting")
@export var ray_length: float = 3.0:
	set(value):
		ray_length = value
		emit_changed()

@export var ray_start_buffer: float = 1.0:
	set(value):
		ray_start_buffer = value
		emit_changed()
@export_flags_3d_physics var collision_mask: int = 1:
	set(value):
		collision_mask = value
		emit_changed()


func _connect_linkages() -> void:
	for link in mechanical_linkage:
		if link and not link.changed.is_connected(_on_sub_resource_changed):
			link.changed.connect(_on_sub_resource_changed)


func _disconnect_linkages() -> void:
	for link in mechanical_linkage:
		if link and link.changed.is_connected(_on_sub_resource_changed):
			link.changed.disconnect(_on_sub_resource_changed)


func _on_sub_resource_changed() -> void:
	emit_changed()
