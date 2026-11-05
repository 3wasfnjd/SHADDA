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
static func transport() -> Dictionary:
	var pal := ENEMY.duplicate()
	pal.body = Color(0.58, 0.52, 0.38)
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
static func bomber() -> Dictionary:
	var pal := ENEMY.duplicate()
	pal.body = Color(0.33, 0.37, 0.44)
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
	body.material_override = Toon.textured(load(PLAYER_TEX), 0.2, 0.0012)
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(body)
	var pal := PLAYER.duplicate()
	pal.tip = YELLOW
	var p := propeller(root, pal, 0.076, Vector3(0, -0.004, -0.144))
	var arm := _arm(root, pal, outline, -0.034, [0.06, 0.085], [0.115, 0.14], 0.0)
	var nose := pivot(root, "Nose", Vector3(0, 0, -0.16))
	var exhaust: Array = [pivot(root, "Exhaust", Vector3(0.045, 0.01, -0.09)), pivot(root, "Exhaust", Vector3(-0.045, 0.01, -0.09))]
	return {"root": root, "prop": p.prop, "blur": p.blur, "gear": [], "rockets": arm.rockets, "bombs": arm.bombs, "muzzles": arm.muzzles, "nose": nose, "exhaust": exhaust, "gear_height": 0.0865, "parked_pitch": 0.0}


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
