## Spider Procedural Animation System

This system implements procedural locomotion for multi-legged creatures (spiders, insects, robots) with fixes for common synchronization issues.

### Files

- `spider_locomotion.gd` - Core locomotion system
- `spider_controller.gd` - Character controller that uses the locomotion system

### Fixes Applied

#### 1. Boat Rowing Fix (Symmetry Breaking)

**Problem**: Middle legs on left and right sides step simultaneously because:
- Both legs accumulate "error" (distance from target) at the same rate
- If `neighbor_threshold` is too wide, they don't inhibit each other
- Both reach step threshold on the same frame and step in unison

**Solutions Applied**:

**A. Opposite Leg Hardlink** (`_link_opposite_legs()`)
- Explicitly links legs on opposite sides as neighbors
- Forces them to alternate (can't step simultaneously)
- Supports naming conventions: `Leg_L_2`/`Leg_R_2`, `LeftLeg`/`RightLeg`, `L1`/`R1`

**B. Step Distance Variance** (`_setup_symmetry_breaking()`)
- Adds 5% random variance to each leg's step distance
- Prevents mathematically perfect synchronization
- Each leg has slightly different threshold

#### 2. Indecision Fix (Threshold Smoothing)

**Problem**: The original code had:
```gdscript
var current_threshold = 0.15 if is_stationary else step_distance
```

This causes stuttering when velocity fluctuates around the threshold:
- At speed 0.19: "STEP!" (threshold = 0.15)
- At speed 0.21: "WAIT!" (threshold = 0.50)
- Legs abort, stutter, or rapid-fire steps

**Solution**: Always use the smooth step distance variant
```gdscript
var current_threshold = limb.step_distance_variant
```

This provides consistent behavior across all velocities.

#### 3. Debug Visualization

Shows red lines between connected limbs. Each leg should have:
- Connections to adjacent legs (same side)
- Connections to opposite leg (across body)

If middle legs have no connections to each other, they will row.

### Setup Instructions

1. **Create Spider Scene**:
   ```
   CharacterBody3D (root)
   ├── SpiderController (script)
   ├── SpiderLocomotion (Node3D with script)
   │   ├── Leg_L_0 (Marker3D)
   │   ├── Leg_L_1 (Marker3D)
   │   ├── Leg_L_2 (Marker3D)
   │   ├── Leg_R_0 (Marker3D)
   │   ├── Leg_R_1 (Marker3D)
   │   └── Leg_R_2 (Marker3D)
   ├── Body (MeshInstance3D)
   └── ... (other spider parts)
   ```

2. **Configure Limbs**: Ensure leg markers are named with L/R convention:
   - `Leg_L_0`, `Leg_L_1`, `Leg_L_2` (left side)
   - `Leg_R_0`, `Leg_R_1`, `Leg_R_2` (right side)

3. **Adjust Parameters** (in Inspector):
   - `max_moving_limbs`: Set to 3 for tripod gait (2 is too restrictive)
   - `neighbor_threshold`: Increase if legs aren't connecting
   - `step_distance`: How far a leg reaches before stepping
   - `step_height`: How high legs lift
   - `step_speed`: Animation speed

4. **Test**: Press Enter to print limb debug info

### Troubleshooting

| Issue | Cause | Fix |
|-------|-------|-----|
| Legs row together | Opposite legs not linked | Check `_link_opposite_legs()` naming |
| Stuttering steps | Threshold snap | Use smooth threshold (already applied) |
| Only 1 leg moves | max_moving_limbs too low | Increase to 2-3 |
| Legs too spread | neighbor_threshold too small | Increase value |
| No neighbor lines | DebugDraw3D not installed | Install addon or remove debug code |

### Dependencies

- `DebugDraw3D` addon (optional, for debug visualization)
  - If not available, set `show_debug_lines = false`

### Gait Patterns

**Tripod Gait** (recommended):
- Legs grouped: (L0, R1, L2) and (R0, L1, R2)
- max_moving_limbs = 3
- One tripod steps while other supports

**Wave Gait**:
- Legs step in sequence around body
- max_moving_limbs = 1
- More stable but slower

**Tetrapod Gait**:
- Legs step in pairs
- max_moving_limbs = 2
