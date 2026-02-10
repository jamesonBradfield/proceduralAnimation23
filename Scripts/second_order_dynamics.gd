class_name SecondOrderDynamics
extends RefCounted

## A helper for smooth, bouncy movement (procedural animation).
## Based on \"Second-Order Dynamics\" which simulates a spring-like system.

# Internal State
var _prev_target_pos: Vector3
var _current_pos: Vector3
var _current_vel: Vector3

# Calculated Constants (Internal Math)
var _k1: float
var _k2: float
var _k3: float


## Initialize the dynamics.
## frequency: How fast it moves. Higher = faster.
## damping: How it settles. 0 = never stops bouncing, 1 = no bounce, >1 = sluggish.
## initial_response: How it reacts to a target moving.
##   - 0: Smooth startup.
##   - 1: Immediate reaction.
##   - >1: Overshoots/Springy.
## initial_pos: Starting position.
func _init(frequency: float, damping: float, initial_response: float, initial_pos: Vector3):
	# Prevent frequency from being 0 to avoid division by zero
	if frequency <= 0.0:
		frequency = 0.001

	_k1 = damping / (PI * frequency)
	_k2 = 1.0 / ((2.0 * PI * frequency) * (2.0 * PI * frequency))
	_k3 = initial_response * damping / (2.0 * PI * frequency)

	_prev_target_pos = initial_pos
	_current_pos = initial_pos
	_current_vel = Vector3.ZERO


## Updates the system state and returns the new position.
## delta: Time since last frame (usually 'delta' in _process).
## target_pos: Where you want the object to go.
## target_vel: (Optional) How fast the target is moving. If not provided, it's calculated automatically.
func update(delta: float, target_pos: Vector3, target_vel: Vector3 = Vector3.INF) -> Vector3:
	# If no time passed, don't change anything
	if delta <= 0.00001:
		return _current_pos

	# Calculate target velocity automatically if not provided
	if target_vel == Vector3.INF:
		target_vel = (target_pos - _prev_target_pos) / delta
		_prev_target_pos = target_pos

	# Math safety: Prevent jittering when delta is large
	var k2_stable = max(_k2, 1.1 * (delta * delta / 4.0 + delta * _k1 / 2.0))

	# Update position and velocity
	_current_pos = _current_pos + delta * _current_vel
	_current_vel = (
		_current_vel
		+ delta * (target_pos + _k3 * target_vel - _current_pos - _k1 * _current_vel) / k2_stable
	)

	return _current_pos
