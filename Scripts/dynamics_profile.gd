class_name DynamicsProfile
extends Resource

## Defines the movement characteristics for Second Order Dynamics.

@export_range(0.1, 20.0) var frequency: float = 2.0
@export_range(0.1, 5.0) var damping: float = 0.65
@export_range(-5.0, 5.0) var response: float = 0.0
