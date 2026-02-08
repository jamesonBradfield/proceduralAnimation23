# Spider Locomotion Fixes Applied

## Summary of Changes to `Scripts/gait_controller.gd`

### 1. Boat Rowing Fix (Symmetry Breaking)

**Problem**: Middle legs on left and right sides step simultaneously because:
- Both legs accumulate "error" at the same rate
- Without opposite leg links, they don't inhibit each other
- Both reach step threshold simultaneously and step in unison

**Solutions Applied**:

#### A. Opposite Leg Hardlink (`_link_opposite_legs()`)
Added after `_setup_neighbors()`:
```gdscript
func _link_opposite_legs() -> void:
	for limb in _limbs:
		var limb_name = str(limb.target.name)
		var opposite_name = ""
		
		# Handle various naming conventions:
		# Leg_L_2 <-> Leg_R_2
		# LeftLeg <-> RightLeg
		# L1 <-> R1
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
		
		# Link as neighbors
		for other in _limbs:
			if str(other.target.name) == opposite_name:
				if not limb.neighbors.has(other):
					limb.neighbors.append(other)
```

This ensures left and right legs alternate - they cannot step simultaneously.

#### B. Step Distance Variance (`_setup_symmetry_breaking()`)
Added random variance to each limb's threshold:
```gdscript
func _setup_symmetry_breaking() -> void:
	for limb in _limbs:
		var variance = randf_range(0.95, 1.05)  # 5% variance
		limb.step_distance_variant = step_distance * variance
```

This prevents mathematically perfect synchronization.

#### C. Limb Class Addition
Added to the `Limb` class:
```gdscript
var step_distance_variant: float = 0.5
```

---

### 2. Indecision Fix (Threshold Smoothing)

**Problem**: Original code had threshold snap:
```gdscript
var is_stationary = controller_velocity.length() < 0.2
var current_threshold = 0.15 if is_stationary else step_distance
```

This caused stuttering:
- At speed 0.19: threshold = 0.15 ("STEP!")
- At speed 0.21: threshold = 0.50 ("WAIT!")
- Velocity fluctuations caused rapid-fire steps/aborts

**Solution**: Smooth threshold using limb's variant:
```gdscript
# REMOVED:
# var is_stationary = controller_velocity.length() < 0.2
# var current_threshold = 0.15 if is_stationary else step_distance

# ADDED:
var current_threshold = limb.step_distance_variant
```

---

### 3. Max Moving Limbs Fix

**Changed**: Default value increased
```gdscript
# OLD:
@export var max_moving_limbs: int = 1

# NEW:
@export var max_moving_limbs: int = 3
```

- `1` was too restrictive (only 1 leg moves at a time)
- `3` allows tripod gait: (L0, R1, L2) and (R0, L1, R2)

---

### 4. Debug Visualization

Added debug functions:
```gdscript
func debug_draw_neighbors() -> void
func get_limb_debug_info() -> Dictionary
```

**Usage**: Call `debug_draw_neighbors()` in `_process()` to see red lines between connected limbs.

---

## Configuration (In Godot Inspector)

### Essential Settings:
| Property | Recommended Value | Notes |
|----------|-------------------|-------|
| `max_moving_limbs` | 3 | For tripod gait |
| `apply_symmetry_breaking` | ☑️ | Enable variance |
| `step_distance` | 0.5 | Distance before stepping |
| `step_height` | 0.5 | Height of step arc |
| `step_duration` | 0.2 | Speed of step animation |

### Naming Convention:
Ensure leg targets follow L/R pattern:
- ✓ `Leg_L_0`, `Leg_L_1`, `Leg_L_2` (left)
- ✓ `Leg_R_0`, `Leg_R_1`, `Leg_R_2` (right)
- ✓ `LeftFront`, `RightFront`
- ✓ `L0`, `R0`, `L1`, `R1`

---

## Testing Checklist

1. [ ] Run scene and observe leg movement
2. [ ] Verify opposite legs don't step together (no rowing)
3. [ ] Check smooth movement at various speeds
4. [ ] Verify 3 legs can move simultaneously (tripod gait)
5. [ ] Enable debug visualization to confirm neighbor links
6. [ ] Print limb info to verify variance is applied:
   ```gdscript
   if Input.is_action_just_pressed("ui_accept"):
       print($GaitController.get_limb_debug_info())
   ```

---

## Expected Behavior After Fixes

### Before:
- Middle legs step together (rowing)
- Stuttering when accelerating from stop
- Only 1 leg moves at a time
- Looks like a peg-legged pirate

### After:
- Alternating tripod gait (3 legs move, then other 3)
- Smooth stepping at all velocities
- Natural spider-like movement
- No rowing synchronization
