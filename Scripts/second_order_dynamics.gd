class_name SecondOrderDynamics
extends RefCounted

# Parameters
var xp: Vector3
var y: Vector3 
var yd: Vector3

# Constants 
var k1: float
var k2: float
var k3: float

func _init(f: float, z: float, r: float, x0: Vector3):
    # SAFETY GUARD 1: Prevent frequency from being 0
    if f <= 0.0: f = 0.001 
    
    var PI = 3.14159
    k1 = z / (PI * f)
    k2 = 1.0 / ((2 * PI * f) * (2 * PI * f))
    k3 = r * z / (2 * PI * f)
    
    xp = x0
    y = x0
    yd = Vector3.ZERO

func update(T: float, x: Vector3, xd: Vector3 = Vector3.INF) -> Vector3:
    # SAFETY GUARD 2: If time hasn't passed, do not update
    if T <= 0.00001: 
        return y 

    if xd == Vector3.INF:
        xd = (x - xp) / T
        xp = x
        
    var k2_stable = max(k2, 1.1 * (T*T/4 + T*k1/2))
    
    y = y + T * yd
    yd = yd + T * (x + k3*xd - y - k1*yd) / k2_stable
    
    return y
