@tool
class_name GaitSolver
extends Resource

## The maximum length of a stride in meters.
@export var max_stride_length: float = 1.5
## The minimum time (in seconds) the leg must be in the air (swing phase).
@export var min_swing_time: float = 0.3
const STOPPED_STATE = {"duty_factor": 1.0, "cycle_time": 1.0}


func solve_for_velocity(velocity: float) -> Dictionary:
	if is_zero_approx(velocity):
		return STOPPED_STATE

	# 1. Calculate Cycle Time
	# T = L / v
	var cycle_time = max_stride_length / abs(velocity)

	# FIX: Ensure Cycle Time is always large enough to support the Swing Time.
	# If T < min_swing, Beta becomes negative.
	# We force T to be at least 1.25x the swing time (ensuring ~20% stance minimum).
	var safe_cycle_time = max(cycle_time, min_swing_time * 1.25)

	# 2. Calculate Duty Factor
	var duty_factor = (safe_cycle_time - min_swing_time) / safe_cycle_time

	# Clamp just in case, though the math above safeguards it.
	duty_factor = clamp(duty_factor, 0.1, 1.0)  # <--- Min 0.1 keeps feet on ground

	return {"duty_factor": duty_factor, "cycle_time": safe_cycle_time}
