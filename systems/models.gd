class_name Models
extends RefCounted
## Every model, built from chunky rounded primitives in a cartoon war style:
## saturated paint, ink outlines, star roundels, stripes, spinning props.
## All models face -Z. Static parts are baked; parts that move are marked
## "live" and returned in a dictionary.

const RED := Color(0.86, 0.14, 0.10)
const CREAM := Color(0.96, 0.90, 0.76)
const WHITE := Color(0.97, 0.96, 0.93)
const METAL := Color(0.62, 0.62, 0.60)
const DARK := Color(0.20, 0.20, 0.23)
const GLASS := Color(0.36, 0.68, 0.98)
const YELLOW := Color(1.0, 0.80, 0.10)
const OLIVE := Color(0.40, 0.45, 0.26)
const TIRE := Color(0.12, 0.12, 0.13)

const PLAYER := {"body": RED, "trim": CREAM, "ring": WHITE, "disc": RED, "mark": WHITE, "mark_kind": "star", "tip": YELLOW, "nose": RED}
const DIVER := {"body": Color(0.22, 0.3, 0.45), "trim": Color(0.95, 0.95, 0.92), "ring": Color(0.95, 0.95, 0.92), "disc": Color(0.16, 0.16, 0.17), "mark": YELLOW, "mark_kind": "diamond", "tip": YELLOW, "nose": Color(0.95, 0.95, 0.92)}
const FRIEND := {"body": Color(0.86, 0.84, 0.76), "trim": RED, "ring": RED, "disc": WHITE, "mark": RED, "mark_kind": "star", "tip": RED, "nose": RED}
const ENEMY := {"body": Color(0.40, 0.46, 0.38), "trim": Color(0.16, 0.16, 0.17), "ring": YELLOW, "disc": Color(0.16, 0.16, 0.17), "mark": YELLOW, "mark_kind": "diamond", "tip": WHITE, "nose": YELLOW}


static func _live(n: Node3D, name: String) -> Node3D:
	n.name = name
	n.set_meta("live", true)
	return n


static func pivot(parent: Node3D, name: String, pos: Vector3 = Vector3.ZERO) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	return _live(n, name)


## Roundel lying flat (facing +Y): outer ring, inner disc, and a star or diamond.
static func insignia(parent: Node3D, pal: Dictionary, r: float, pos: Vector3, rot: Vector3) -> void:
	var holder := Node3D.new()
	holder.position = pos
	holder.rotation_degrees = rot
	parent.add_child(holder)
	Toon.add(holder, Toon.can(r, r, 0.0016, 20), Toon.mat(pal.ring, 0.3, 0.0))
	Toon.add(holder, Toon.can(r * 0.8, r * 0.8, 0.0022, 20), Toon.mat(pal.disc, 0.3, 0.0))
	var shape: PackedVector2Array
	if pal.mark_kind == "star":
		shape = Toon.star(r * 0.72)
	else:
		shape = PackedVector2Array([Vector2(0, -r * 0.62), Vector2(r * 0.42, 0), Vector2(0, r * 0.62), Vector2(-r * 0.42, 0)])
	Toon.add(holder, Toon.slab(shape, 0.003), Toon.mat(pal.mark, 0.3, 0.0))


## A propeller on a live pivot: hub, blades with coloured tips and a blur disc.
static func propeller(parent: Node3D, pal: Dictionary, r: float, pos: Vector3, blades: int = 3) -> Dictionary:
	var prop := pivot(parent, "Prop", pos)
	var blade_m := Toon.mat(DARK, 0.4, 0.0015)
	var tip_m := Toon.mat(pal.tip, 0.4, 0.0)
	for i in range(blades):
		var arm := Node3D.new()
		arm.rotation.z = TAU * i / blades
		prop.add_child(arm)
		Toon.add(arm, Toon.capsule(r * 0.13, r, 10), blade_m, Vector3(0, r * 0.5, 0), Vector3(0, 25, 0), Vector3(1, 1, 0.3))
		Toon.add(arm, Toon.capsule(r * 0.13, r * 0.26, 10), tip_m, Vector3(0, r * 0.9, 0), Vector3(0, 25, 0), Vector3(1.04, 1, 0.34))
	var blur := MeshInstance3D.new()
	blur.mesh = Toon.can(r * 1.02, r * 1.02, 0.0005, 28)
	blur.rotation_degrees.x = 90
	blur.material_override = Toon.flat(Color(0.25, 0.25, 0.28, 0.0))
	blur.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(blur)
	blur.position = pos
	_live(blur, "Blur")
	return {"prop": prop, "blur": blur}


static func rocket(hostile: bool = false) -> Node3D:
	var root := Node3D.new()
	root.name = "Rocket"
	Toon.add(root, Toon.capsule(0.0055, 0.05, 10), Toon.mat(OLIVE if not hostile else DARK, 0.4, 0.0012), Vector3.ZERO, Vector3(90, 0, 0))
	Toon.add(root, Toon.can(0.0, 0.0056, 0.016, 10), Toon.mat(RED, 0.5, 0.0012), Vector3(0, 0, -0.03), Vector3(-90, 0, 0))
	Toon.add(root, Toon.can(0.0058, 0.0058, 0.005, 10), Toon.mat(YELLOW, 0.5, 0.0), Vector3(0, 0, -0.012), Vector3(90, 0, 0))
	for a in [0.0, 90.0]:
		Toon.add(root, Toon.block(Vector3(0.02, 0.0012, 0.01)), Toon.mat(RED, 0.3, 0.0008), Vector3(0, 0, 0.02), Vector3(0, 0, a))
	return root


static func bomb() -> Node3D:
	var root := Node3D.new()
	root.name = "Bomb"
	Toon.add(root, Toon.capsule(0.011, 0.045, 12), Toon.mat(OLIVE, 0.45, 0.0014), Vector3.ZERO, Vector3(90, 0, 0), Vector3(1, 1, 1))
	Toon.add(root, Toon.can(0.0113, 0.0113, 0.005, 12), Toon.mat(YELLOW, 0.4, 0.0), Vector3(0, 0, -0.008), Vector3(90, 0, 0))
	for a in [45.0, 135.0]:
		Toon.add(root, Toon.block(Vector3(0.026, 0.0014, 0.012)), Toon.mat(OLIVE, 0.3, 0.0008), Vector3(0, 0, 0.024), Vector3(0, 0, a))
	return root


# --- fighters ------------------------------------------------------------------------

## The cartoon fighter (player palette or enemy palette). ~28 cm long, 34 cm span.
## Returns {root, prop, blur, gear: Array, rockets: Array, bombs: Array,
##          muzzles: Array, nose, exhaust: Array}.
static func fighter(pal: Dictionary, outline: float = 0.0018) -> Dictionary:
	var root := Node3D.new()
	root.name = "Fighter"
	var body := Toon.mat(pal.body, 0.55, outline)
	var trim := Toon.mat(pal.trim, 0.45, outline)
	var metal := Toon.mat(METAL, 0.6, outline)
	var dark := Toon.mat(DARK, 0.4, outline)
	# Fuselage: a fat capsule tapering to the tail.
	Toon.add(root, Toon.capsule(0.031, 0.19, 18), body, Vector3(0, 0, 0.0), Vector3(90, 0, 0), Vector3(1.0, 1.0, 1.08))
	Toon.add(root, Toon.can(0.011, 0.028, 0.11, 16), body, Vector3(0, 0.004, 0.115), Vector3(90, 0, 0))
	# Engine cowling, radial cylinders, nose ring.
	Toon.add(root, Toon.can(0.037, 0.035, 0.05, 20), metal, Vector3(0, 0, -0.1), Vector3(90, 0, 0))
	Toon.add(root, Toon.torus(0.034, 0.005, 20), Toon.mat(pal.nose, 0.5, outline), Vector3(0, 0, -0.124), Vector3(90, 0, 0))
	Toon.add(root, Toon.can(0.03, 0.03, 0.004, 18), dark, Vector3(0, 0, -0.123), Vector3(90, 0, 0))
	for i in range(7):
		var a := TAU * i / 7.0
		Toon.add(root, Toon.capsule(0.0055, 0.02, 8), Toon.mat(Color(0.35, 0.35, 0.36), 0.4, 0.0), Vector3(cos(a) * 0.02, sin(a) * 0.02, -0.126), Vector3(0, 0, rad_to_deg(a) + 90))
	for side: float in [-1.0, 1.0]:
		for k in range(3):
			Toon.add(root, Toon.can(0.0035, 0.0035, 0.012, 8), dark, Vector3(0.037 * side, -0.005 + k * 0.008, -0.075), Vector3(0, 0, 90))
	# Spinner + propeller.
	Toon.add(root, Toon.ball(0.016, 14, 8), Toon.mat(METAL, 0.8, outline), Vector3(0, 0, -0.136), Vector3.ZERO, Vector3(1, 1, 1.6))
	var p := propeller(root, pal, 0.08, Vector3(0, 0, -0.134))
	# Canopy with a frame.
	Toon.add(root, Toon.ball(0.022, 16, 10), Toon.mat(GLASS, 0.9, outline), Vector3(0, 0.026, -0.015), Vector3.ZERO, Vector3(0.82, 0.85, 1.75))
	Toon.add(root, Toon.torus(0.02, 0.0025, 18), metal, Vector3(0, 0.03, -0.015), Vector3(0, 0, 90), Vector3(1, 1, 1))
	Toon.add(root, Toon.block(Vector3(0.003, 0.004, 0.07)), metal, Vector3(0, 0.044, -0.015))
	# Low wings with rounded tips and a little dihedral.
	var wing := PackedVector2Array([Vector2(0.02, -0.04), Vector2(0.12, -0.03), Vector2(0.158, -0.022), Vector2(0.172, -0.008), Vector2(0.172, 0.008), Vector2(0.162, 0.02), Vector2(0.12, 0.028), Vector2(0.02, 0.034)])
	for side: float in [-1.0, 1.0]:
		var holder := Node3D.new()
		holder.position = Vector3(0, -0.016, 0)
		holder.rotation_degrees.z = 5.0 * side
		root.add_child(holder)
		Toon.add(holder, Toon.slab(wing if side > 0 else Toon.mirror_x(wing), 0.013), body)
		insignia(holder, pal, 0.026, Vector3(0.11 * side, 0.0068, -0.003), Vector3.ZERO)
		Toon.add(holder, Toon.block(Vector3(0.05, 0.0135, 0.008)), trim, Vector3(0.145 * side, 0, -0.016))
	# Tailplane with stripes, fin with stripes.
	var stab := PackedVector2Array([Vector2(0.01, 0.11), Vector2(0.06, 0.112), Vector2(0.074, 0.122), Vector2(0.074, 0.136), Vector2(0.06, 0.146), Vector2(0.01, 0.15)])
	for side: float in [-1.0, 1.0]:
		Toon.add(root, Toon.slab(stab if side > 0 else Toon.mirror_x(stab), 0.008), body, Vector3(0, 0.006, 0))
		for k in range(2):
			Toon.add(root, Toon.block(Vector3(0.008, 0.0085, 0.036)), trim, Vector3((0.04 + k * 0.018) * side, 0.006, 0.13))
	var fin := PackedVector2Array([Vector2(0.0, 0.07), Vector2(0.03, 0.095), Vector2(0.07, 0.112), Vector2(0.078, 0.126), Vector2(0.07, 0.15), Vector2(0.0, 0.16)])
	var fin_holder := Node3D.new()
	fin_holder.position = Vector3(0, 0.008, 0)
	fin_holder.rotation_degrees.z = 90
	root.add_child(fin_holder)
	Toon.add(fin_holder, Toon.slab(fin, 0.008), body)
	for k in range(2):
		Toon.add(fin_holder, Toon.block(Vector3(0.008, 0.0086, 0.05)), trim, Vector3(0.045 + k * 0.016, 0, 0.13))
	insignia(root, pal, 0.018, Vector3(0.0315, 0.004, 0.06), Vector3(0, 0, -90))
	insignia(root, pal, 0.018, Vector3(-0.0315, 0.004, 0.06), Vector3(0, 0, 90))
	# Guns under the wings: two per side.
	var muzzles: Array = []
	for side: float in [-1.0, 1.0]:
		for x in [0.055, 0.08]:
			Toon.add(root, Toon.capsule(0.0065, 0.04, 10), metal, Vector3(x * side, -0.027, -0.03), Vector3(90, 0, 0))
			Toon.add(root, Toon.can(0.0032, 0.0032, 0.05, 8), dark, Vector3(x * side, -0.027, -0.065), Vector3(90, 0, 0))
			var m := Node3D.new()
			m.position = Vector3(x * side, -0.027, -0.092)
			root.add_child(m)
			_live(m, "Muzzle")
			muzzles.append(m)
	# Rockets (two per side) and bombs (belly + roots) — visible stock.
	var rockets: Array = []
	for side: float in [-1.0, 1.0]:
		for x in [0.112, 0.138]:
			Toon.add(root, Toon.block(Vector3(0.003, 0.008, 0.03)), dark, Vector3(x * side, -0.026, 0.0))
			var r := rocket()
			r.position = Vector3(x * side, -0.034, -0.002)
			root.add_child(r)
			_live(r, "RocketRack")
			rockets.append(r)
	var bombs: Array = []
	for pos in [Vector3(0, -0.045, 0.01), Vector3(-0.034, -0.038, 0.02), Vector3(0.034, -0.038, 0.02)]:
		var b := bomb()
		b.position = pos
		root.add_child(b)
		_live(b, "BombRack")
		bombs.append(b)
	# Landing gear (main legs fold into the wings; tail wheel stays).
	var gear: Array = []
	for side: float in [-1.0, 1.0]:
		var leg := pivot(root, "Gear", Vector3(0.058 * side, -0.02, -0.035))
		Toon.add(leg, Toon.can(0.0032, 0.0032, 0.036, 8), metal, Vector3(0, -0.018, 0))
		Toon.add(leg, Toon.torus(0.0125, 0.0055, 16), Toon.mat(TIRE, 0.3, 0.0012), Vector3(0, -0.038, 0), Vector3(0, 0, 90))
		Toon.add(leg, Toon.can(0.008, 0.008, 0.008, 12), Toon.mat(pal.body, 0.5, 0.0), Vector3(0, -0.038, 0), Vector3(0, 0, 90))
		gear.append(leg)
	Toon.add(root, Toon.torus(0.0055, 0.0028, 12), Toon.mat(TIRE, 0.3, 0.001), Vector3(0, -0.026, 0.14), Vector3(0, 0, 90))
	Toon.add(root, Toon.can(0.002, 0.002, 0.02, 6), metal, Vector3(0, -0.017, 0.14))
	var nose := pivot(root, "Nose", Vector3(0, 0, -0.16))
	var exhaust: Array = [pivot(root, "Exhaust", Vector3(0.04, 0.0, -0.075)), pivot(root, "Exhaust", Vector3(-0.04, 0.0, -0.075))]
	Toon.bake(root)
	return {"root": root, "prop": p.prop, "blur": p.blur, "gear": gear, "rockets": rockets, "bombs": bombs, "muzzles": muzzles, "nose": nose, "exhaust": exhaust}


## Twin-engine cargo plane that drops parachute crates. ~45 cm long.
static func transport(palette: Dictionary = {}) -> Dictionary:
	var pal := ENEMY.duplicate()
	pal.body = Color(0.58, 0.52, 0.38)
	if not palette.is_empty():
		pal = palette.duplicate()
	var root := Node3D.new()
	root.name = "Transport"
	var o := 0.0024
	var body := Toon.mat(pal.body, 0.5, o)
	var dark := Toon.mat(DARK, 0.4, o)
	Toon.add(root, Toon.capsule(0.05, 0.36, 18), body, Vector3.ZERO, Vector3(90, 0, 0), Vector3(1, 1.1, 1))
	Toon.add(root, Toon.can(0.016, 0.045, 0.12, 16), body, Vector3(0, 0.012, 0.2), Vector3(90, 0, 0))
	Toon.add(root, Toon.ball(0.035, 14, 8), Toon.mat(GLASS, 0.9, o), Vector3(0, 0.03, -0.13), Vector3.ZERO, Vector3(1.1, 0.7, 1.2))
	var wing := PackedVector2Array([Vector2(0.03, -0.05), Vector2(0.24, -0.035), Vector2(0.27, -0.02), Vector2(0.27, 0.01), Vector2(0.24, 0.02), Vector2(0.03, 0.035)])
	Toon.add(root, Toon.slab(wing, 0.014), body, Vector3(0, 0.045, -0.02))
	Toon.add(root, Toon.slab(Toon.mirror_x(wing), 0.014), body, Vector3(0, 0.045, -0.02))
	var props: Array = []
	for side: float in [-1.0, 1.0]:
		Toon.add(root, Toon.capsule(0.026, 0.11, 14), Toon.mat(METAL, 0.6, o), Vector3(0.11 * side, 0.035, -0.06), Vector3(90, 0, 0))
		Toon.add(root, Toon.torus(0.025, 0.004, 16), Toon.mat(pal.nose, 0.5, o), Vector3(0.11 * side, 0.035, -0.115), Vector3(90, 0, 0))
		var p := propeller(root, pal, 0.06, Vector3(0.11 * side, 0.035, -0.122))
		props.append(p)
		insignia(root, pal, 0.028, Vector3(0.2 * side, 0.053, -0.01), Vector3.ZERO)
	var stab := PackedVector2Array([Vector2(0.01, 0.22), Vector2(0.1, 0.23), Vector2(0.11, 0.25), Vector2(0.1, 0.27), Vector2(0.01, 0.27)])
	Toon.add(root, Toon.slab(stab, 0.009), body, Vector3(0, 0.02, 0))
	Toon.add(root, Toon.slab(Toon.mirror_x(stab), 0.009), body, Vector3(0, 0.02, 0))
	var fin_holder := Node3D.new()
	fin_holder.position = Vector3(0, 0.02, 0)
	fin_holder.rotation_degrees.z = 90
	root.add_child(fin_holder)
	Toon.add(fin_holder, Toon.slab(PackedVector2Array([Vector2(0, 0.17), Vector2(0.1, 0.23), Vector2(0.1, 0.27), Vector2(0, 0.28)]), 0.009), Toon.mat(pal.trim, 0.4, o))
	Toon.add(root, Toon.block(Vector3(0.002, 0.05, 0.06)), dark, Vector3(0.05, -0.005, 0.06))
	var hatch := pivot(root, "Hatch", Vector3(0, -0.05, 0.06))
	Toon.bake(root)
	return {"root": root, "props": props, "hatch": hatch}


## The boss: a four-engine bomber with turrets. ~70 cm span.
static func bomber(body_color: Color = Color(0.33, 0.37, 0.44)) -> Dictionary:
	var pal := ENEMY.duplicate()
	pal.body = body_color
	var root := Node3D.new()
	root.name = "Bomber"
	var o := 0.003
	var body := Toon.mat(pal.body, 0.55, o)
	var dark := Toon.mat(DARK, 0.4, o)
	var metal := Toon.mat(METAL, 0.6, o)
	Toon.add(root, Toon.capsule(0.06, 0.48, 20), body, Vector3.ZERO, Vector3(90, 0, 0), Vector3(1, 1.08, 1))
	Toon.add(root, Toon.can(0.02, 0.055, 0.16, 18), body, Vector3(0, 0.012, 0.29), Vector3(90, 0, 0))
	Toon.add(root, Toon.ball(0.05, 16, 10), Toon.mat(GLASS, 0.9, o), Vector3(0, -0.005, -0.215), Vector3.ZERO, Vector3(1, 0.9, 1.0))
	Toon.add(root, Toon.can(0.052, 0.052, 0.02, 20), Toon.mat(YELLOW, 0.5, o), Vector3(0, 0, -0.18), Vector3(90, 0, 0))
	var wing := PackedVector2Array([Vector2(0.04, -0.07), Vector2(0.3, -0.04), Vector2(0.36, -0.025), Vector2(0.37, 0.0), Vector2(0.34, 0.02), Vector2(0.04, 0.05)])
	Toon.add(root, Toon.slab(wing, 0.02), body, Vector3(0, 0.0, 0))
	Toon.add(root, Toon.slab(Toon.mirror_x(wing), 0.02), body, Vector3(0, 0.0, 0))
	for side: float in [-1.0, 1.0]:
		insignia(root, pal, 0.04, Vector3(0.27 * side, 0.011, 0.0), Vector3.ZERO)
	var engines: Array = []
	for x in [-0.25, -0.13, 0.13, 0.25]:
		var eng := pivot(root, "Engine", Vector3(x, 0.005, -0.06))
		Toon.add(eng, Toon.capsule(0.032, 0.13, 14), metal)
		eng.get_child(0).rotation_degrees.x = 90
		Toon.add(eng, Toon.torus(0.03, 0.005, 16), Toon.mat(YELLOW, 0.5, o), Vector3(0, 0, -0.06), Vector3(90, 0, 0))
		var p := propeller(eng, pal, 0.07, Vector3(0, 0, -0.068))
		engines.append({"node": eng, "prop": p.prop, "blur": p.blur, "hp": WarMath.ENGINE_HP})
	var stab := PackedVector2Array([Vector2(0.01, 0.3), Vector2(0.14, 0.31), Vector2(0.15, 0.33), Vector2(0.14, 0.36), Vector2(0.01, 0.37)])
	Toon.add(root, Toon.slab(stab, 0.012), body, Vector3(0, 0.03, 0))
	Toon.add(root, Toon.slab(Toon.mirror_x(stab), 0.012), body, Vector3(0, 0.03, 0))
	for side: float in [-1.0, 1.0]:
		var fh := Node3D.new()
		fh.position = Vector3(0.14 * side, 0.03, 0)
		fh.rotation_degrees.z = 90
		root.add_child(fh)
		Toon.add(fh, Toon.slab(PackedVector2Array([Vector2(-0.03, 0.29), Vector2(0.07, 0.31), Vector2(0.08, 0.36), Vector2(-0.03, 0.38)]), 0.01), Toon.mat(pal.trim, 0.4, o))
	# Dorsal and tail turrets.
	var top := pivot(root, "TopTurret", Vector3(0, 0.065, -0.05))
	Toon.add(top, Toon.ball(0.03, 14, 8), Toon.mat(GLASS, 0.9, o), Vector3.ZERO, Vector3.ZERO, Vector3(1, 0.8, 1))
	var top_guns: Array = []
	for side: float in [-1.0, 1.0]:
		Toon.add(top, Toon.can(0.003, 0.003, 0.06, 6), dark, Vector3(0.01 * side, 0.005, -0.04), Vector3(90, 0, 0))
		var m := Node3D.new()
		m.position = Vector3(0.01 * side, 0.005, -0.07)
		top.add_child(m)
		top_guns.append(m)
	var tail := pivot(root, "TailTurret", Vector3(0, 0.02, 0.37))
	Toon.add(tail, Toon.ball(0.025, 14, 8), Toon.mat(GLASS, 0.9, o))
	var tail_guns: Array = []
	for side: float in [-1.0, 1.0]:
		Toon.add(tail, Toon.can(0.003, 0.003, 0.05, 6), dark, Vector3(0.008 * side, 0, 0.035), Vector3(90, 0, 0))
		var m2 := Node3D.new()
		m2.position = Vector3(0.008 * side, 0, 0.06)
		tail.add_child(m2)
		tail_guns.append(m2)
	var bay := pivot(root, "BombBay", Vector3(0, -0.065, 0.02))
	Toon.bake(root)
	return {"root": root, "engines": engines, "top": top, "top_guns": top_guns, "tail": tail, "tail_guns": tail_guns, "bay": bay}


# --- ground units -------------------------------------------------------------------------

## Chunky cartoon tank ~20 cm. Returns {root, turret, barrel, muzzle, tracks}.
static func tank() -> Dictionary:
	var root := Node3D.new()
	root.name = "Tank"
	var o := 0.0018
	var body := Toon.mat(OLIVE, 0.45, o)
	var dark := Toon.mat(DARK, 0.4, o)
	Toon.add(root, Toon.block(Vector3(0.13, 0.04, 0.17)), body, Vector3(0, 0.04, 0))
	Toon.add(root, Toon.capsule(0.02, 0.13, 12), body, Vector3(0, 0.045, -0.085), Vector3(0, 0, 90), Vector3(1, 1.0, 0.8))
	var tracks: Array = []
	for side: float in [-1.0, 1.0]:
		Toon.add(root, Toon.capsule(0.025, 0.22, 14), Toon.mat(TIRE, 0.3, o), Vector3(0.072 * side, 0.025, 0), Vector3(90, 0, 0), Vector3(0.7, 1, 1))
		for k in range(4):
			Toon.add(root, Toon.can(0.014, 0.014, 0.012, 12), Toon.mat(METAL, 0.5, 0.0), Vector3(0.083 * side, 0.024, -0.07 + k * 0.047), Vector3(0, 0, 90))
	insignia(root, ENEMY, 0.02, Vector3(0.066, 0.045, 0.03), Vector3(0, 0, -90))
	insignia(root, ENEMY, 0.02, Vector3(-0.066, 0.045, 0.03), Vector3(0, 0, 90))
	var turret := pivot(root, "Turret", Vector3(0, 0.062, 0.01))
	Toon.add(turret, Toon.ball(0.048, 16, 8), body, Vector3(0, 0.0, 0), Vector3.ZERO, Vector3(1, 0.62, 1.1))
	Toon.add(turret, Toon.can(0.012, 0.014, 0.012, 10), dark, Vector3(0.015, 0.032, 0.02))
	var barrel := Node3D.new()
	barrel.position = Vector3(0, 0.01, -0.035)
	turret.add_child(barrel)
	Toon.add(barrel, Toon.can(0.007, 0.0085, 0.11, 12), body, Vector3(0, 0, -0.055), Vector3(90, 0, 0))
	Toon.add(barrel, Toon.can(0.011, 0.011, 0.018, 12), dark, Vector3(0, 0, -0.11), Vector3(90, 0, 0))
	var muzzle := Node3D.new()
	muzzle.position = Vector3(0, 0, -0.122)
	barrel.add_child(muzzle)
	Toon.bake(root)
	return {"root": root, "turret": turret, "barrel": barrel, "muzzle": muzzle}


const GUN_MESH := "res://assets/models/aa_gun.res"
const GUN_TEX := "res://assets/models/aa_gun_albedo.jpg"


## Flak gun: the user's vintage mounted gun when present, else the built-in one.
static func aa_gun() -> Dictionary:
	if ResourceLoader.exists(GUN_MESH) and ResourceLoader.exists(GUN_TEX):
		return _aa_gun_model()
	return _aa_gun_builtin()


static func _aa_gun_model() -> Dictionary:
	var root := Node3D.new()
	root.name = "AAGun"
	var o := 0.0016
	var sand := Toon.mat(Color(0.82, 0.72, 0.5), 0.2, o)
	for i in range(11):
		var a := TAU * i / 11.0
		Toon.add(root, Toon.capsule(0.016, 0.05, 10), sand, Vector3(cos(a) * 0.12, 0.014, sin(a) * 0.12), Vector3(0, -rad_to_deg(a), 90), Vector3(1, 1, 0.8))
	var mount := pivot(root, "Mount", Vector3(0, 0, 0))
	var body := MeshInstance3D.new()
	body.mesh = load(GUN_MESH)
	body.material_override = Toon.textured(load(GUN_TEX), 0.3, 0.0012)
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mount.add_child(body)
	var guns := Node3D.new()
	mount.add_child(guns)
	var m := Node3D.new()
	m.position = Vector3(0.0, 0.095, -0.112)
	guns.add_child(m)
	Toon.bake(root)
	return {"root": root, "mount": mount, "guns": guns, "muzzles": [m]}


static func _aa_gun_builtin() -> Dictionary:
	var root := Node3D.new()
	root.name = "AAGun"
	var o := 0.0016
	var sand := Toon.mat(Color(0.82, 0.72, 0.5), 0.2, o)
	for ring in range(2):
		for i in range(9):
			var a := TAU * (i + ring * 0.5) / 9.0
			Toon.add(root, Toon.capsule(0.016, 0.05, 10), sand, Vector3(cos(a) * 0.075, 0.014 + ring * 0.024, sin(a) * 0.075), Vector3(0, -rad_to_deg(a), 90), Vector3(1, 1, 0.8))
	Toon.add(root, Toon.can(0.07, 0.07, 0.008, 18), Toon.mat(Color(0.35, 0.33, 0.3), 0.2, 0.0), Vector3(0, 0.004, 0))
	var mount := pivot(root, "Mount", Vector3(0, 0.03, 0))
	var green := Toon.mat(Color(0.32, 0.4, 0.3), 0.45, o)
	Toon.add(mount, Toon.can(0.03, 0.035, 0.03, 14), green)
	var guns := Node3D.new()
	guns.position = Vector3(0, 0.03, 0)
	mount.add_child(guns)
	Toon.add(guns, Toon.block(Vector3(0.05, 0.03, 0.04)), green)
	var muzzles: Array = []
	for side: float in [-1.0, 1.0]:
		Toon.add(guns, Toon.can(0.005, 0.006, 0.11, 10), Toon.mat(DARK, 0.4, o), Vector3(0.016 * side, 0, -0.06), Vector3(90, 0, 0))
		Toon.add(guns, Toon.can(0.008, 0.008, 0.014, 10), Toon.mat(DARK, 0.4, o), Vector3(0.016 * side, 0, -0.112), Vector3(90, 0, 0))
		var m := Node3D.new()
		m.position = Vector3(0.016 * side, 0, -0.122)
		guns.add_child(m)
		muzzles.append(m)
	Toon.add(guns, Toon.block(Vector3(0.07, 0.04, 0.004)), Toon.mat(Color(0.4, 0.42, 0.38), 0.4, o), Vector3(0, 0.01, -0.025))
	Toon.bake(root)
	return {"root": root, "mount": mount, "guns": guns, "muzzles": muzzles}


## Barrage balloon on a cable. Returns {root, body, cable}. The cable hangs to y = 0 of root.
static func balloon() -> Dictionary:
	var root := Node3D.new()
	root.name = "Balloon"
	var o := 0.0022
	var body := pivot(root, "Body")
	Toon.add(body, Toon.ball(0.07, 18, 10), Toon.mat(Color(0.68, 0.7, 0.74), 0.7, o), Vector3.ZERO, Vector3.ZERO, Vector3(1, 1, 1.9))
	Toon.add(body, Toon.torus(0.069, 0.006, 20), Toon.mat(RED, 0.5, o), Vector3(0, 0, -0.03), Vector3(90, 0, 0))
	Toon.add(body, Toon.torus(0.062, 0.006, 20), Toon.mat(RED, 0.5, o), Vector3(0, 0, 0.05), Vector3(90, 0, 0))
	for a in [0.0, 120.0, 240.0]:
		var fh := Node3D.new()
		fh.rotation_degrees.z = a
		body.add_child(fh)
		Toon.add(fh, Toon.ball(0.03, 12, 6), Toon.mat(Color(0.68, 0.7, 0.74), 0.7, o), Vector3(0, 0.05, 0.11), Vector3.ZERO, Vector3(0.35, 1, 1.2))
	var cable := MeshInstance3D.new()
	cable.mesh = Toon.can(0.0012, 0.0012, 1.0, 6)
	cable.material_override = Toon.flat(Color(0.15, 0.15, 0.15, 1.0))
	root.add_child(cable)
	_live(cable, "Cable")
	return {"root": root, "body": body, "cable": cable}


## Supply crate under a parachute. Returns {root, chute}.
static func crate() -> Dictionary:
	var root := Node3D.new()
	root.name = "Crate"
	var o := 0.0018
	Toon.add(root, Toon.block(Vector3(0.08, 0.06, 0.08)), Toon.mat(Color(0.62, 0.44, 0.24), 0.2, o), Vector3(0, 0.03, 0))
	for z in [-0.03, 0.03]:
		Toon.add(root, Toon.block(Vector3(0.084, 0.064, 0.008)), Toon.mat(Color(0.44, 0.3, 0.16), 0.2, 0.0), Vector3(0, 0.03, z))
	insignia(root, ENEMY, 0.018, Vector3(0, 0.061, 0), Vector3.ZERO)
	var chute := pivot(root, "Chute", Vector3(0, 0.2, 0))
	var dome := SphereMesh.new()
	dome.radius = 0.11
	dome.height = 0.11
	dome.is_hemisphere = true
	dome.radial_segments = 16
	dome.rings = 6
	var cm := Toon.mat(WHITE, 0.3, 0.002)
	Toon.add(chute, dome, cm, Vector3.ZERO, Vector3.ZERO, Vector3(1, 0.7, 1))
	for i in range(8):
		if i % 2 == 0:
			var a := TAU * i / 8.0
			Toon.add(chute, Toon.block(Vector3(0.02, 0.002, 0.11)), Toon.mat(RED, 0.3, 0.0), Vector3(cos(a) * 0.05, 0.056, sin(a) * 0.05), Vector3(-30, -rad_to_deg(a) + 90, 0))
	for i in range(4):
		var a2 := TAU * (i + 0.5) / 4.0
		var top := Vector3(cos(a2) * 0.1, 0.0, sin(a2) * 0.1)
		var bottom := Vector3(cos(a2) * 0.035, -0.14, sin(a2) * 0.035)
		var line := Toon.add(chute, Toon.can(0.0008, 0.0008, top.distance_to(bottom), 4), Toon.flat(Color(0.2, 0.2, 0.2, 1)), (top + bottom) * 0.5)
		line.basis = Basis(Quaternion(Vector3.UP, (top - bottom).normalized()))
	return {"root": root, "chute": chute}


# --- the player's own model ----------------------------------------------------------

const PLAYER_MESH := "res://assets/models/player_plane.res"
const PILOT_SEAT := Vector3(0.0, 0.024, -0.031)
const PLAYER_TEX := "res://assets/models/player_plane_albedo.jpg"


static func has_player_model() -> bool:
	return ResourceLoader.exists(PLAYER_MESH) and ResourceLoader.exists(PLAYER_TEX)


## The user's vintage plane (prepared by tools/import_player_plane.gd), with
## the game's own spinning propeller and weapons hung under the wings.
## Same dictionary as fighter(), plus gear_height and parked_pitch.
static func player_plane(outline: float = 0.0018) -> Dictionary:
	var root := Node3D.new()
	root.name = "PlayerPlane"
	var body := MeshInstance3D.new()
	body.mesh = load(PLAYER_MESH)
	var skin := Toon.textured(load(PLAYER_TEX), 0.3, 0.0012)
	# Richer paint: a touch darker base, deeper shadow side, crisp rim light.
	skin.set_shader_parameter("albedo", Color(0.9, 0.88, 0.86))
	skin.set_shader_parameter("shade", Color(0.42, 0.4, 0.52))
	skin.set_shader_parameter("rim", 0.2)
	body.material_override = skin
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Pre-cut pieces for the crash (tools/split_player_plane.gd).
	var cut := {}
	for b in Debris.BUCKETS:
		var path := "res://assets/models/player_parts/%s.res" % b
		if ResourceLoader.exists(path):
			cut[b] = load(path)
	if not cut.is_empty():
		body.set_meta("debris_parts", cut)
	root.add_child(body)
	var pal := PLAYER.duplicate()
	pal.tip = YELLOW
	var p := propeller(root, pal, 0.076, Vector3(0, -0.004, -0.144))
	var arm := _arm(root, pal, outline, -0.034, [0.06, 0.085], [0.115, 0.14], 0.0)
	var nose := pivot(root, "Nose", Vector3(0, 0, -0.16))
	var exhaust: Array = [pivot(root, "Exhaust", Vector3(0.045, 0.01, -0.09)), pivot(root, "Exhaust", Vector3(-0.045, 0.01, -0.09))]
	var pil := pilot()
	pil.root.position = PILOT_SEAT
	pil.root.scale = Vector3.ONE * 1.35
	root.add_child(pil.root)
	var tips: Array = [pivot(root, "WingTip", Vector3(0.165, -0.02, 0.0)), pivot(root, "WingTip", Vector3(-0.165, -0.02, 0.0))]
	# Navigation lights: green right tip, red left tip, white tail.
	var lights: Array = []
	for spec in [[Vector3(0.168, -0.016, 0.005), Color(0.3, 1.0, 0.4)], [Vector3(-0.168, -0.016, 0.005), Color(1.0, 0.25, 0.2)], [Vector3(0.0, 0.05, 0.152), Color(1.0, 1.0, 0.92)]]:
		var l := Toon.add(root, Toon.ball(0.0042, 8, 5), Toon.flat(spec[1]), spec[0])
		lights.append(l)
	# Exhaust flames (shown with throttle and boost).
	var flames: Array = []
	for ex in exhaust:
		var fl := Toon.add(ex, Toon.can(0.0, 0.006, 0.03, 8), Toon.flat(Color(1.0, 0.62, 0.15, 0.9)), Vector3(0, 0, 0.015), Vector3(90, 0, 0))
		var core := Toon.add(fl, Toon.can(0.0, 0.003, 0.02, 8), Toon.flat(Color(1.0, 0.95, 0.7, 1.0)), Vector3(0, -0.003, 0))
		core.visible = true
		fl.visible = false
		flames.append(fl)
	return {"root": root, "body": body, "prop": p.prop, "blur": p.blur, "gear": [], "rockets": arm.rockets, "bombs": arm.bombs, "muzzles": arm.muzzles, "nose": nose, "exhaust": exhaust, "gear_height": 0.0865, "parked_pitch": 0.0, "pilot": pil, "tips": tips, "lights": lights, "flames": flames}


## Guns, rocket rails and bombs under the wings. `y` is the wing underside.
static func _arm(root: Node3D, pal: Dictionary, outline: float, y: float, gun_x: Array, rocket_x: Array, z: float) -> Dictionary:
	var metal := Toon.mat(METAL, 0.6, outline)
	var dark := Toon.mat(DARK, 0.4, outline)
	var muzzles: Array = []
	for side: float in [-1.0, 1.0]:
		for x in gun_x:
			Toon.add(root, Toon.capsule(0.0065, 0.04, 10), metal, Vector3(x * side, y, z - 0.03), Vector3(90, 0, 0))
			Toon.add(root, Toon.can(0.0032, 0.0032, 0.05, 8), dark, Vector3(x * side, y, z - 0.065), Vector3(90, 0, 0))
			var m := Node3D.new()
			m.position = Vector3(x * side, y, z - 0.092)
			root.add_child(m)
			_live(m, "Muzzle")
			muzzles.append(m)
	var rockets: Array = []
	for side: float in [-1.0, 1.0]:
		for x in rocket_x:
			Toon.add(root, Toon.block(Vector3(0.003, 0.008, 0.03)), dark, Vector3(x * side, y + 0.002, z))
			var r := rocket()
			r.position = Vector3(x * side, y - 0.007, z - 0.002)
			root.add_child(r)
			_live(r, "RocketRack")
			rockets.append(r)
	var bombs: Array = []
	for pos in [Vector3(0, y - 0.022, z + 0.01), Vector3(-0.034, y - 0.012, z + 0.02), Vector3(0.034, y - 0.012, z + 0.02)]:
		var b := bomb()
		b.position = pos
		root.add_child(b)
		_live(b, "BombRack")
		bombs.append(b)
	return {"muzzles": muzzles, "rockets": rockets, "bombs": bombs}


# --- campaign units ---------------------------------------------------------------------

const SKIN := Color(0.95, 0.74, 0.58)
const LEATHER := Color(0.45, 0.28, 0.16)
const KHAKI := Color(0.55, 0.52, 0.33)
const ACE := {"body": Color(0.78, 0.1, 0.12), "trim": Color(0.1, 0.1, 0.1), "ring": YELLOW, "disc": Color(0.1, 0.1, 0.1), "mark": YELLOW, "mark_kind": "diamond", "tip": YELLOW, "nose": Color(0.1, 0.1, 0.1)}


## A cartoon pilot sitting in the cockpit: leather helmet, goggles, red scarf.
## Origin at the seat; the head is ~2 cm above it. Returns {root, head, scarf}.
static func pilot() -> Dictionary:
	var root := Node3D.new()
	root.name = "Pilot"
	Toon.add(root, Toon.capsule(0.011, 0.03, 10), Toon.mat(LEATHER, 0.4, 0.0012), Vector3(0, 0.0, 0))
	var head := Node3D.new()
	head.position = Vector3(0, 0.022, -0.002)
	root.add_child(head)
	Toon.add(head, Toon.ball(0.0095, 12, 8), Toon.mat(SKIN, 0.3, 0.0012))
	var cap := SphereMesh.new()
	cap.radius = 0.0102
	cap.height = 0.0102
	cap.is_hemisphere = true
	cap.radial_segments = 12
	cap.rings = 5
	Toon.add(head, cap, Toon.mat(LEATHER, 0.5, 0.0012), Vector3(0, 0.001, 0.0008))
	for side: float in [-1.0, 1.0]:
		Toon.add(head, Toon.torus(0.0034, 0.0011, 10), Toon.mat(Color(0.3, 0.3, 0.32), 0.7, 0.0), Vector3(0.0042 * side, 0.0045, -0.0082), Vector3(80, 0, 0))
		Toon.add(head, Toon.ball(0.0026, 8, 4), Toon.mat(GLASS, 0.9, 0.0), Vector3(0.0042 * side, 0.0045, -0.0086))
		Toon.add(head, Toon.ball(0.003, 8, 4), Toon.mat(LEATHER, 0.4, 0.0), Vector3(0.0095 * side, -0.001, 0.0))
	Toon.add(head, Toon.ball(0.0018, 6, 3), Toon.mat(Color(0.9, 0.55, 0.45), 0.3, 0.0), Vector3(0, -0.0012, -0.0094))
	var scarf := Node3D.new()
	scarf.position = Vector3(0, 0.011, 0.006)
	root.add_child(scarf)
	_live(scarf, "Scarf")
	Toon.add(scarf, Toon.capsule(0.0035, 0.024, 8), Toon.mat(Color(0.9, 0.12, 0.1), 0.3, 0.001), Vector3(0, 0, 0.011), Vector3(80, 0, 0), Vector3(1.6, 1, 0.5))
	return {"root": root, "head": head, "scarf": scarf}


## A little cartoon soldier, ~6 cm tall. kind: "rifle" or "crew".
## Returns {root, legs: Array, arms: Node3D}.
static func soldier(kind: String = "rifle") -> Dictionary:
	var root := Node3D.new()
	root.name = "Soldier"
	var o := 0.0012
	var cloth := Toon.mat(KHAKI if kind == "rifle" else Color(0.42, 0.48, 0.3), 0.3, o)
	var legs: Array = []
	for side: float in [-1.0, 1.0]:
		var hip := pivot(root, "Leg", Vector3(0.006 * side, 0.024, 0))
		Toon.add(hip, Toon.capsule(0.0045, 0.022, 8), cloth, Vector3(0, -0.011, 0))
		Toon.add(hip, Toon.capsule(0.0045, 0.01, 8), Toon.mat(Color(0.2, 0.15, 0.1), 0.3, o), Vector3(0, -0.021, -0.003), Vector3(90, 0, 0))
		legs.append(hip)
	Toon.add(root, Toon.capsule(0.01, 0.026, 10), cloth, Vector3(0, 0.035, 0), Vector3.ZERO, Vector3(1.1, 1, 0.85))
	Toon.add(root, Toon.ball(0.0085, 12, 8), Toon.mat(SKIN, 0.3, o), Vector3(0, 0.054, 0))
	var helm := SphereMesh.new()
	helm.radius = 0.0105
	helm.height = 0.0105
	helm.is_hemisphere = true
	helm.radial_segments = 12
	helm.rings = 5
	Toon.add(root, helm, Toon.mat(Color(0.3, 0.36, 0.22), 0.4, o), Vector3(0, 0.056, 0))
	Toon.add(root, Toon.can(0.013, 0.013, 0.0015, 14), Toon.mat(Color(0.3, 0.36, 0.22), 0.4, o), Vector3(0, 0.0565, 0))
	var arms := pivot(root, "Arms", Vector3(0, 0.042, 0))
	for side: float in [-1.0, 1.0]:
		Toon.add(arms, Toon.capsule(0.0038, 0.02, 8), cloth, Vector3(0.012 * side, -0.006, -0.006), Vector3(-60, 0, 0))
	if kind == "rifle":
		Toon.add(arms, Toon.block(Vector3(0.003, 0.004, 0.036)), Toon.mat(Color(0.3, 0.2, 0.12), 0.3, o), Vector3(0.004, -0.008, -0.016), Vector3(-15, 0, 0))
	return {"root": root, "legs": legs, "arms": arms}


## Anti-aircraft rocket launcher on a tripod (tube pitches up). Returns
## {root, mount, tube, muzzle, lamp}. Built folded; the team raises it.
static func launcher() -> Dictionary:
	var root := Node3D.new()
	root.name = "Launcher"
	var o := 0.0014
	var green := Toon.mat(Color(0.36, 0.42, 0.28), 0.4, o)
	var dark := Toon.mat(DARK, 0.4, o)
	for i in range(3):
		var a := TAU * i / 3.0
		Toon.add(root, Toon.can(0.002, 0.002, 0.05, 6), dark, Vector3(cos(a) * 0.012, 0.02, sin(a) * 0.012), Vector3(rad_to_deg(sin(a)) * 25.0, 0, -rad_to_deg(cos(a)) * 25.0))
	var mount := pivot(root, "Mount", Vector3(0, 0.042, 0))
	var tube := Node3D.new()
	mount.add_child(tube)
	Toon.add(tube, Toon.can(0.008, 0.008, 0.07, 12), green, Vector3(0, 0, -0.01), Vector3(90, 0, 0))
	Toon.add(tube, Toon.can(0.0095, 0.0095, 0.008, 12), dark, Vector3(0, 0, -0.044), Vector3(90, 0, 0))
	Toon.add(tube, Toon.block(Vector3(0.006, 0.01, 0.02)), dark, Vector3(0.011, 0, 0.0))
	var muzzle := Node3D.new()
	muzzle.position = Vector3(0, 0, -0.05)
	tube.add_child(muzzle)
	var lamp := Toon.add(mount, Toon.ball(0.0045, 8, 4), Toon.unique(Toon.mat(Color(0.4, 0.05, 0.05), 0.4, 0.0)), Vector3(0, 0.014, 0.012))
	return {"root": root, "mount": mount, "tube": tube, "muzzle": muzzle, "lamp": lamp}


## Cartoon army truck with a canvas back (~16 cm). Returns {root, wheels}.
static func truck() -> Dictionary:
	var root := Node3D.new()
	root.name = "Truck"
	var o := 0.0016
	var body := Toon.mat(OLIVE, 0.4, o)
	Toon.add(root, Toon.block(Vector3(0.07, 0.012, 0.16)), Toon.mat(DARK, 0.3, o), Vector3(0, 0.022, 0))
	Toon.add(root, Toon.block(Vector3(0.068, 0.045, 0.045)), body, Vector3(0, 0.05, -0.055))
	Toon.add(root, Toon.block(Vector3(0.06, 0.02, 0.003)), Toon.mat(GLASS, 0.9, 0.0), Vector3(0, 0.062, -0.078))
	Toon.add(root, Toon.block(Vector3(0.07, 0.025, 0.03)), body, Vector3(0, 0.038, -0.09))
	var canvas := Toon.mat(Color(0.62, 0.6, 0.42), 0.2, o)
	Toon.add(root, Toon.block(Vector3(0.066, 0.034, 0.1)), canvas, Vector3(0, 0.045, 0.03))
	Toon.add(root, Toon.can(0.033, 0.033, 0.1, 16), canvas, Vector3(0, 0.062, 0.03), Vector3(90, 0, 0), Vector3(1, 1, 0.55))
	insignia(root, ENEMY, 0.016, Vector3(0.0355, 0.05, -0.055), Vector3(0, 0, -90))
	var wheels: Array = []
	for z in [-0.075, 0.02, 0.055]:
		for side: float in [-1.0, 1.0]:
			var wnode := pivot(root, "Wheel", Vector3(0.036 * side, 0.015, z))
			Toon.add(wnode, Toon.can(0.015, 0.015, 0.012, 14), Toon.mat(TIRE, 0.3, o), Vector3.ZERO, Vector3(0, 0, 90))
			wheels.append(wnode)
	Toon.bake(root)
	return {"root": root, "wheels": wheels}


## Radar tower with a spinning dish (~35 cm). Returns {root, dish}.
static func radar() -> Dictionary:
	var root := Node3D.new()
	root.name = "Radar"
	var o := 0.0018
	var metal := Toon.mat(Color(0.5, 0.52, 0.5), 0.5, o)
	for i in range(4):
		var a := TAU * (i + 0.5) / 4.0
		Toon.add(root, Toon.can(0.003, 0.004, 0.3, 6), metal, Vector3(cos(a) * 0.03, 0.15, sin(a) * 0.03), Vector3(rad_to_deg(sin(a)) * -5.0, 0, rad_to_deg(cos(a)) * 5.0))
	for h in [0.08, 0.18]:
		Toon.add(root, Toon.torus(0.028, 0.002, 4), metal, Vector3(0, h, 0), Vector3(0, 45, 0))
	Toon.add(root, Toon.block(Vector3(0.07, 0.04, 0.07)), Toon.mat(OLIVE, 0.4, o), Vector3(0, 0.02, 0))
	var dish := pivot(root, "Dish", Vector3(0, 0.31, 0))
	var bowl := SphereMesh.new()
	bowl.radius = 0.055
	bowl.height = 0.03
	bowl.is_hemisphere = true
	bowl.radial_segments = 16
	bowl.rings = 4
	Toon.add(dish, bowl, Toon.mat(Color(0.85, 0.85, 0.82), 0.6, o), Vector3(0, 0.02, -0.01), Vector3(-70, 0, 0))
	Toon.add(dish, Toon.can(0.004, 0.004, 0.05, 6), metal, Vector3(0, 0.03, -0.03), Vector3(-70, 0, 0))
	Toon.add(dish, Toon.ball(0.007, 8, 4), Toon.mat(Color(1.0, 0.2, 0.1), 0.4, 0.0), Vector3(0, 0.055, -0.05))
	Toon.bake(root)
	return {"root": root, "dish": dish}


## Striped fuel tank on legs (~14 cm). Returns {root}.
static func fuel_tank() -> Dictionary:
	var root := Node3D.new()
	root.name = "FuelTank"
	var o := 0.0018
	Toon.add(root, Toon.capsule(0.045, 0.16, 16), Toon.mat(Color(0.88, 0.86, 0.8), 0.6, o), Vector3(0, 0.07, 0), Vector3(0, 0, 90))
	for x in [-0.04, 0.0, 0.04]:
		Toon.add(root, Toon.torus(0.0455, 0.004, 18), Toon.mat(RED, 0.5, 0.0), Vector3(x, 0.07, 0), Vector3(0, 0, 90))
	for x in [-0.05, 0.05]:
		Toon.add(root, Toon.block(Vector3(0.008, 0.035, 0.07)), Toon.mat(DARK, 0.3, o), Vector3(x, 0.017, 0))
	Toon.add(root, Toon.can(0.008, 0.008, 0.012, 10), Toon.mat(DARK, 0.3, o), Vector3(0, 0.118, 0))
	Toon.bake(root)
	return {"root": root}


## A flight ring to fly through (inner radius ~19 cm), striped. Faces +Z.
## Returns {root, spin, mat}.
static func ring() -> Dictionary:
	var root := Node3D.new()
	root.name = "Ring"
	var spin := pivot(root, "Spin")
	var m := Toon.unique(Toon.mat(Color(1.0, 0.8, 0.15), 0.6, 0.002))
	Toon.add(spin, Toon.torus(0.27, 0.016, 36), m, Vector3.ZERO, Vector3(90, 0, 0))
	for i in range(8):
		var a := TAU * i / 8.0
		Toon.add(spin, Toon.ball(0.018, 8, 4), Toon.mat(RED, 0.5, 0.0015), Vector3(cos(a) * 0.27, sin(a) * 0.27, 0))
	return {"root": root, "spin": spin, "mat": m}


## A friendly round-roofed hangar for the airfield mission (~26 cm long),
## its door facing +Z... (front = -Z like everything else).
static func hangar() -> Dictionary:
	var root := Node3D.new()
	root.name = "Hangar"
	var o := 0.0016
	var roof := Toon.mat(Color(0.42, 0.48, 0.34), 0.12, o)
	# Half-round roof (a half cylinder, open underneath).
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 16
	for i in range(segs):
		var a0 := PI * i / segs
		var a1 := PI * (i + 1) / segs
		var p00 := Vector3(cos(a0) * 0.084, sin(a0) * 0.084, -0.12)
		var p01 := Vector3(cos(a0) * 0.084, sin(a0) * 0.084, 0.12)
		var p10 := Vector3(cos(a1) * 0.084, sin(a1) * 0.084, -0.12)
		var p11 := Vector3(cos(a1) * 0.084, sin(a1) * 0.084, 0.12)
		for v in [p00, p11, p10, p00, p01, p11]:
			st.set_normal(Vector3(v.x, v.y, 0.0).normalized())
			st.add_vertex(v)
	Toon.add(root, st.commit(), roof)
	# Ribs over the roof.
	var rib := PackedVector2Array()
	for i in range(17):
		var a2 := PI * i / 16.0
		rib.append(Vector2(cos(a2) * 0.089, -sin(a2) * 0.089))
	for i in range(16, -1, -1):
		var a3 := PI * i / 16.0
		rib.append(Vector2(cos(a3) * 0.083, -sin(a3) * 0.083))
	rib.reverse()
	for k in range(5):
		Toon.add(root, Toon.slab(rib, 0.006), Toon.mat(Color(0.4, 0.42, 0.38), 0.4, 0.0), Vector3(0, 0, -0.1 + k * 0.05), Vector3(90, 0, 0))
	# Front wall with a big dark door and a red star.
	var wall := PackedVector2Array()
	for i in range(17):
		var a4 := PI * i / 16.0
		wall.append(Vector2(cos(a4) * 0.086, -sin(a4) * 0.086))
	wall.reverse()
	Toon.add(root, Toon.slab(wall, 0.004), Toon.mat(CREAM, 0.3, o), Vector3(0, 0, -0.12), Vector3(90, 0, 0))
	Toon.add(root, Toon.slab(wall, 0.004), Toon.mat(Color(0.42, 0.48, 0.34), 0.12, o), Vector3(0, 0, 0.12), Vector3(90, 0, 0))
	Toon.add(root, Toon.block(Vector3(0.1, 0.07, 0.006)), Toon.mat(DARK, 0.3, o), Vector3(0, 0.035, -0.121))
	Toon.add(root, Toon.slab(Toon.star(0.014), 0.002), Toon.mat(RED, 0.4, 0.0), Vector3(0, 0.086, -0.123), Vector3(90, 0, 0))
	# A wind sock on a pole beside it.
	Toon.add(root, Toon.can(0.002, 0.002, 0.16, 6), Toon.mat(METAL, 0.5, 0.0), Vector3(0.11, 0.08, -0.08))
	Toon.add(root, Toon.can(0.004, 0.009, 0.035, 8), Toon.mat(Color(1.0, 0.5, 0.1), 0.3, 0.0), Vector3(0.125, 0.15, -0.08), Vector3(0, 0, 90))
	# Sandbags ring the front.
	for k in range(6):
		Toon.add(root, Toon.capsule(0.008, 0.03, 8), Toon.mat(KHAKI, 0.2, 0.001), Vector3(-0.075 + k * 0.03, 0.006, -0.15), Vector3(0, 0, 90))
	Toon.bake(root)
	return {"root": root}


const RAIDER := {"body": Color(0.24, 0.26, 0.29), "trim": Color(1.0, 0.5, 0.1), "ring": Color(1.0, 0.5, 0.1), "disc": Color(0.12, 0.12, 0.13), "mark": Color(1.0, 0.5, 0.1), "mark_kind": "diamond", "tip": Color(1.0, 0.5, 0.1), "nose": Color(0.12, 0.12, 0.13)}
const HELI_GREEN := Color(0.36, 0.42, 0.28)


## Armored raider: a heavy gunmetal fighter with bolted armour plates, four
## guns and rocket rails under the wings. Returns the fighter dict + "rails".
static func raider() -> Dictionary:
	var f := fighter(RAIDER, 0.002)
	var root: Node3D = f.root
	var plate := Toon.mat(Color(0.38, 0.4, 0.42), 0.7, 0.0015)
	var orange := Toon.mat(Color(1.0, 0.5, 0.1), 0.4, 0.0012)
	var dark := Toon.mat(DARK, 0.4, 0.0012)
	# Armour: a bolted plate over the nose and slabs on each wing root.
	Toon.add(root, Toon.block(Vector3(0.05, 0.022, 0.07)), plate, Vector3(0, 0.022, -0.07))
	for side: float in [-1.0, 1.0]:
		Toon.add(root, Toon.block(Vector3(0.06, 0.008, 0.05)), plate, Vector3(0.07 * side, 0.004, 0.0))
		for k in range(2):
			Toon.add(root, Toon.ball(0.0035, 6, 3), Toon.mat(METAL, 0.8, 0.0), Vector3((0.05 + k * 0.04) * side, 0.009, 0.018))
		# Extra guns and a rocket rail with two rockets.
		Toon.add(root, Toon.can(0.004, 0.004, 0.06, 8), dark, Vector3(0.1 * side, -0.004, -0.06), Vector3(90, 0, 0))
		Toon.add(root, Toon.block(Vector3(0.008, 0.006, 0.07)), dark, Vector3(0.13 * side, -0.014, -0.005))
		for k in range(2):
			Toon.add(root, Toon.capsule(0.006, 0.05, 8), orange, Vector3(0.13 * side + (k - 0.5) * 0.014, -0.022, -0.01), Vector3(90, 0, 0))
	root.scale = Vector3.ONE * 1.12
	return f


## Attack helicopter (~32 cm): bubble canopy, stub wings with rocket pods,
## chin gun, tail boom; main and tail rotors spin.
static func heli() -> Dictionary:
	var root := Node3D.new()
	root.name = "Heli"
	var o := 0.002
	var body := Toon.mat(HELI_GREEN, 0.45, o)
	var dark := Toon.mat(DARK, 0.4, o)
	var metal := Toon.mat(METAL, 0.6, o)
	var yellow := Toon.mat(YELLOW, 0.4, o)
	# Fuselage: a fat egg, glass bubble at the front.
	Toon.add(root, Toon.ball(0.06, 18, 12), body, Vector3(0, 0, 0), Vector3.ZERO, Vector3(0.9, 0.85, 1.35))
	Toon.add(root, Toon.ball(0.042, 16, 10), Toon.mat(GLASS, 0.9, o), Vector3(0, 0.012, -0.06), Vector3.ZERO, Vector3(0.95, 0.85, 1.0))
	# Tail boom, fin, little stabiliser, tail rotor.
	Toon.add(root, Toon.can(0.012, 0.022, 0.2, 12), body, Vector3(0, 0.018, 0.16), Vector3(90, 0, 0))
	Toon.add(root, Toon.slab(PackedVector2Array([Vector2(-0.01, 0.0), Vector2(0.03, 0.0), Vector2(0.035, 0.06), Vector2(0.015, 0.06)]), 0.006), body, Vector3(0, 0.02, 0.255), Vector3(0, 90, 90))
	Toon.add(root, Toon.block(Vector3(0.08, 0.005, 0.025)), body, Vector3(0, 0.02, 0.23))
	var tail_rotor := pivot(root, "TailRotor", Vector3(0.012, 0.06, 0.27))
	for k in range(2):
		Toon.add(tail_rotor, Toon.block(Vector3(0.003, 0.06, 0.008)), dark, Vector3.ZERO, Vector3(k * 90.0, 0, 0))
	# Mast and main rotor (two long blades, yellow tips).
	Toon.add(root, Toon.can(0.008, 0.012, 0.035, 10), metal, Vector3(0, 0.065, 0.0))
	var rotor := pivot(root, "Rotor", Vector3(0, 0.085, 0.0))
	Toon.add(rotor, Toon.ball(0.012, 10, 6), metal)
	for k in range(2):
		var blade := Node3D.new()
		blade.rotation.y = PI * k
		rotor.add_child(blade)
		Toon.add(blade, Toon.block(Vector3(0.022, 0.003, 0.3)), dark, Vector3(0, 0, 0.15))
		Toon.add(blade, Toon.block(Vector3(0.0225, 0.0035, 0.025)), yellow, Vector3(0, 0, 0.29))
	# Stub wings with rocket pods, and a chin gun.
	var pods: Array = []
	for side: float in [-1.0, 1.0]:
		Toon.add(root, Toon.block(Vector3(0.07, 0.006, 0.03)), body, Vector3(0.075 * side, -0.005, 0.0))
		var pod := Node3D.new()
		pod.position = Vector3(0.1 * side, -0.02, -0.005)
		root.add_child(pod)
		Toon.add(pod, Toon.can(0.014, 0.014, 0.06, 12), dark, Vector3.ZERO, Vector3(90, 0, 0))
		Toon.add(pod, Toon.can(0.0145, 0.0145, 0.006, 12), Toon.mat(RED, 0.4, 0.0), Vector3(0, 0, -0.03), Vector3(90, 0, 0))
		pods.append(pod)
	var gun := pivot(root, "ChinGun", Vector3(0, -0.045, -0.06))
	Toon.add(gun, Toon.ball(0.012, 10, 6), dark)
	Toon.add(gun, Toon.can(0.003, 0.003, 0.04, 6), metal, Vector3(0, 0, -0.022), Vector3(90, 0, 0))
	var muzzle := Node3D.new()
	muzzle.position = Vector3(0, 0, -0.045)
	gun.add_child(muzzle)
	# Skids.
	for side: float in [-1.0, 1.0]:
		Toon.add(root, Toon.capsule(0.004, 0.18, 6), metal, Vector3(0.045 * side, -0.075, 0.0), Vector3(90, 0, 0))
		for z: float in [-0.04, 0.04]:
			Toon.add(root, Toon.can(0.0025, 0.0025, 0.03, 6), metal, Vector3(0.04 * side, -0.06, z), Vector3(0, 0, 20 * side))
	# Star on the side.
	for side: float in [-1.0, 1.0]:
		Toon.add(root, Toon.slab(Toon.star(0.012), 0.002), yellow, Vector3(0.054 * side, 0.005, 0.02), Vector3(0, 0, 90 * side))
	return {"root": root, "rotor": rotor, "tail_rotor": tail_rotor, "pods": pods, "gun": gun, "muzzle": muzzle}


## The flying fortress: the four-engine bomber in black and orange, armour
## plating and two extra side cannon turrets.
static func fortress() -> Dictionary:
	var b := bomber(Color(0.2, 0.21, 0.24))
	var root: Node3D = b.root
	root.name = "Fortress"
	var plate := Toon.mat(Color(0.3, 0.31, 0.33), 0.6, 0.003)
	var orange := Toon.mat(Color(1.0, 0.5, 0.1), 0.45, 0.002)
	# Armour belts and orange stripes.
	for z: float in [-0.1, 0.05, 0.18]:
		Toon.add(root, Toon.can(0.066, 0.066, 0.025, 20), plate, Vector3(0, 0, z), Vector3(90, 0, 0))
	Toon.add(root, Toon.can(0.0665, 0.0665, 0.012, 20), orange, Vector3(0, 0, -0.16), Vector3(90, 0, 0))
	var side_guns: Array = []
	for side: float in [-1.0, 1.0]:
		var t := pivot(root, "SideTurret", Vector3(0.062 * side, 0.0, 0.02))
		Toon.add(t, Toon.ball(0.026, 12, 8), plate)
		for k in range(2):
			Toon.add(t, Toon.can(0.004, 0.004, 0.06, 8), Toon.mat(DARK, 0.4, 0.0015), Vector3(0.012 * (k - 0.5) * 2.0, 0.006, -0.03), Vector3(90, 0, 0))
		var mz := Node3D.new()
		mz.position = Vector3(0, 0.006, -0.062)
		t.add_child(mz)
		side_guns.append({"pivot": t, "muzzle": mz})
	b["side_guns"] = side_guns
	return b
