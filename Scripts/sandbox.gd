extends Node2D

# ===========================================================================
#  SANDBOX  (replaces the old Playground)
#
#  The free-play mode. The player builds a starting population, then shapes
#  the world with five mouse tools, fires events, changes the rules, and
#  chases optional goals. Everything else in the lab still runs on its own:
#  blobs wander, bump, and every baby inherits each trait from a random parent.
#
#  PURE DRIFT RULE
#  Nothing here gives any trait an edge. Every tool and event is blind to
#  traits (the meteor hits a place, the bottleneck picks at random), and every
#  World slider changes all blobs by the same amount. Spawning lets the player
#  choose traits, which is migration (gene flow), not selection. There is
#  deliberately NO tool that kills a blob the player picked by hand.
#
#  LAYOUT (1152 x 648)
#    Lab        left, LAB rect. Background, walls, craters and aim overlays are
#               drawn in code (LabBack under the blobs, LabFront over them).
#    HUD        above the lab: the tool hint strip, then stats + share bar.
#    Side panel right, 300 px: header (Menu / Guide / Info), Play + New world,
#               speed, then five tabs: Tools, Events, World, Data, Goals.
#    Setup card on first load and on "New world": starting size + trait mix.
#
#  KEYS   Space play/pause   1-5 pick a tool   Esc unpin / cancel a wall
#
#  SETUP:
#    1. Open res://Scenes/Sandbox.tscn (provided). The root node "Sandbox"
#       already has this script, Blob Scene, and the 5 textures assigned.
#    2. main_menu.gd's PLAYGROUND_SCENE points at Sandbox.tscn.
#  All UI is built here in code; the scene is just the root node.
# ===========================================================================

# --- BLOB SCENE + TEXTURES (assigned in Sandbox.tscn) ---
@export var blob_scene: PackedScene
@export var blob_tex_1: Texture2D
@export var blob_tex_2: Texture2D
@export var blob_tex_3: Texture2D
@export var eye_tex_1: Texture2D
@export var eye_tex_2: Texture2D

const MENU_SCENE := "res://Scenes/MainMenu.tscn"
const INFO_SCENE := "res://Scenes/InfoMenu.tscn"
const FONT_PATH := "res://Fonts/Nunito.ttf"

# --- LAYOUT ---
const LAB := Rect2(14, 76, 826, 560)
const PANEL_X := 852.0
const PANEL_W := 300.0
const SCREEN_H := 648.0

# --- LOOK (same palette as the presets and menus) ---
const COL_BG := Color(0.10, 0.10, 0.12)
const COL_LAB := Color(0.118, 0.118, 0.118)
const COL_PANEL := Color(0.13, 0.13, 0.16)
const COL_CARD := Color(0.15, 0.15, 0.18)
const COL_CARD_DARK := Color(0.115, 0.115, 0.145)
const COL_BORDER := Color(0.26, 0.26, 0.31)
const COL_TEXT := Color(0.92, 0.92, 0.94)
const COL_DIM := Color(0.62, 0.62, 0.68)
const AMBER := Color(0.95, 0.78, 0.38)
const BLUE := Color(0.36, 0.55, 0.95)
const GREY := Color(0.28, 0.28, 0.32)
const FIRE := Color(0.78, 0.38, 0.30)

# --- BLOB CONSTANTS (match blob.gd) ---
const MATURATION_TIME := 9.0
const BLOB_R := 32.0
const LIFESPAN_JITTER := 0.28

# --- TRAITS ---
# index 0 = Color, 1 = Shape, 2 = Eyes. Eyes are stored as 1 or 3 on the blob;
# here they are variant 0 (one eye) and 1 (three eyes).
const TRAIT_NAMES := ["Color", "Shape", "Eyes"]
const VARIANT_NAMES := [
	["Red", "Green", "Blue"],
	["Round", "Star", "Flower"],
	["One eye", "Three eyes"],
]
const VARIANT_COLS := [
	[Color(1.0, 0.42, 0.42), Color(0.42, 0.92, 0.42), Color(0.42, 0.62, 1.0)],
	[Color(0.86, 0.86, 0.90), Color(0.95, 0.78, 0.38), Color(0.80, 0.55, 0.95)],
	[Color(0.55, 0.85, 0.95), Color(0.95, 0.60, 0.45)],
]

# --- START MIX MODES ---
const MIX_NAMES := ["Even", "Random", "One rare", "Off"]
const MIX_HELP := [
	"Even: equal numbers of every version.",
	"Random: each blob rolls its version at random.",
	"One rare: a single blob carries one version; everyone else is split between the others.",
	"Off: everyone starts the same, so this trait never changes.",
]

# --- TOOLS ---
const T_INSPECT := 0
const T_SPAWN := 1
const T_METEOR := 2
const T_WALL := 3
const T_STIR := 4
const TOOL_NAMES := ["Inspect", "Spawn", "Meteor", "Wall", "Stir"]
const TOOL_HINTS := [
	"Hover a blob to read its traits. Click to pin its card, click empty space to let go.",
	"Click to drop a blob in, or click and drag to paint a crowd. New arrivals are migrants.",
	"Aim the crater. Every ringed blob is inside it. Click to strike.",
	"Click and drag to build a wall. Right-click a wall to knock it down.",
	"Click to blow a gust. Nearby blobs scatter away from the point.",
]
const TOOL_WHY := [
	"Looking never changes anything.",
	"Bringing blobs in from outside is gene flow. It shifts the mix because you chose who arrives, not because anyone is fitter.",
	"The meteor can't see traits. It only hits whoever happens to be standing there.",
	"Walls split one population into islands. Each island drifts on its own.",
	"A gust moves blobs around and hurts no one. It just changes who meets whom.",
]

const WALL_T := 10.0
const MAX_WALLS := 12
const SPAWN_PAINT_GAP := 36.0
const CELL := 20.0

# --- SPEED ---
const SPEEDS := [0.25, 0.5, 1.0, 2.0, 3.0]
const SPEED_LABELS := ["¼×", "½×", "1×", "2×", "3×"]

# --- WORLD STATE ---
var world_ready: bool = false
var world_id: int = 0
var running: bool = false
var blobs: Array = []
var alive_cache: Array = []
var sim_time: float = 0.0
var births: int = 0
var deaths: int = 0

# --- RULES (World tab; all affect every blob equally) ---
var max_population: int = 50
var lifespan: float = 40.0
var breed_rest: float = 2.0
var wander_mult: float = 1.0
var speed_idx: int = 2

# --- SETUP CHOICES ---
var start_count: int = 16
var mix_modes: Array = [0, 0, 0]

# --- TOOL STATE ---
var tool: int = T_INSPECT
var spawn_pick: Array = [-1, -1, -1]   # -1 = random
var spawn_adult: bool = true
var meteor_r: float = 80.0
var stir_r: float = 150.0
var walls: Array = []                  # [{ "a": Vector2, "b": Vector2, "body": StaticBody2D }]
var wall_dragging: bool = false
var wall_start: Vector2 = Vector2.ZERO
var painting: bool = false
var last_paint_pos: Vector2 = Vector2(-9999, -9999)
var mouse_lab: Vector2 = Vector2.ZERO
var mouse_in_lab: bool = false
var hovered_blob = null
var pinned_blob = null
var stir_boost: Dictionary = {}        # blob -> seconds of extra speed left

# --- EFFECTS ---
var craters: Array = []                # [{ "p", "r", "t" }]  scorch marks
var flashes: Array = []                # [{ "p", "r", "t", "kills" }]
var waves: Array = []                  # [{ "p", "r", "t" }]

# --- EVENTS ---
var bottleneck_pct: int = 80
var chaos_on: bool = false
var chaos_interval: float = 25.0
var chaos_timer: float = 25.0
var last_event_name: String = ""
var last_before: Array = []            # counts per trait, before
var last_after: Array = []
var last_before_total: int = 0
var last_after_total: int = 0

# --- DATA ---
var graph_trait: int = 0
var graph_samples: Array = []          # [{ "t": float, "p": [[..],[..],[..]] }]
var graph_marks: Array = []            # [float]
var graph_timer: float = 0.0
var latest_counts: Array = [[0, 0, 0], [0, 0, 0], [0, 0]]
var latest_total: int = 0
var log_lines: Array = []
var prev_present: Array = []
var data_timer: float = 0.0

# --- GOALS ---
var goals: Array = [
	{"id": "fix", "title": "First fixation", "desc": "Let any trait drift until one version is all that's left.", "done": false},
	{"id": "underdog", "title": "The underdog", "desc": "A version that fell under 10% climbs back above 50%.", "done": false},
	{"id": "comeback", "title": "Comeback", "desc": "After an event leaves 12 or fewer blobs, grow back to 40 (or your cap).", "done": false},
	{"id": "fullhouse", "title": "Full house", "desc": "Keep all 8 versions alive for 2 minutes straight.", "done": false},
	{"id": "islands", "title": "Island life", "desc": "Wall off two islands, each holding only one color, and not the same one.", "done": false},
	{"id": "wipeout", "title": "Wipeout", "desc": "Erase the last blob of any version with a single meteor.", "done": false},
]
var low_flags: Array = []
var comeback_armed: bool = false
var fullhouse_time: float = 0.0
var seen_variants: Array = []
var region_grid: PackedInt32Array = PackedInt32Array()
var region_w: int = 0
var region_h: int = 0
var regions_dirty: bool = true
var goal_timer: float = 0.0

# --- NODES ---
var lab_back: LabBack
var lab_front: LabFront
var card: BlobCard
var ui_layer: CanvasLayer
var ui_root: Control
var overlay_layer: CanvasLayer
var setup_overlay: Control
var setup_cancel_btn: Button
var setup_count_lbl: Label
var setup_mix_help: Array = []
var info_layer: CanvasLayer = null

var hint_tag: Label
var hint_text: Label
var stats_lbl: Label
var share_bar: ShareBar
var share_lbl: Label
var toast_box: VBoxContainer

var play_btn: Button
var speed_btns: Array = []
var tab_btns: Array = []
var tab_pages: Array = []
var tab_scroll: ScrollContainer
var current_tab: int = 0

var tool_btns: Array = []
var tool_card_box: VBoxContainer

var chaos_btn: Button
var chaos_lbl: Label
var last_event_box: VBoxContainer

var graph: TraitGraph
var graph_seg: Array = []
var tracker_box: VBoxContainer
var log_box: VBoxContainer
var goal_rows: Array = []
var goal_count_lbl: Label

var _font_file: FontFile = null
var _fonts: Dictionary = {}

# ===========================================================================
#  LAB BACK — the lab floor, craters and walls. Sits under the blobs.
# ===========================================================================
class LabBack extends Node2D:
	var host = null

	func _draw():
		var r: Rect2 = host.LAB
		var sb := StyleBoxFlat.new()
		sb.bg_color = host.COL_LAB
		sb.border_color = Color(0.24, 0.24, 0.28)
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(10)
		draw_style_box(sb, r)

		# faint dot grid so the floor reads as a lab, not a void
		var gx: float = r.position.x + 30.0
		while gx < r.end.x:
			var gy: float = r.position.y + 30.0
			while gy < r.end.y:
				draw_circle(Vector2(gx, gy), 1.2, Color(1, 1, 1, 0.045))
				gy += 40.0
			gx += 40.0

		# scorch marks from meteors, fading out
		for c in host.craters:
			var a: float = clamp(float(c["t"]) / 8.0, 0.0, 1.0)
			var p: Vector2 = c["p"]
			var rr: float = c["r"]
			draw_circle(p, rr, Color(0.30, 0.16, 0.10, 0.30 * a))
			draw_arc(p, rr, 0.0, TAU, 48, Color(0.75, 0.40, 0.22, 0.45 * a), 2.0, true)

		# walls
		for w in host.walls:
			_draw_wall(w["a"], w["b"], 1.0)

	func _draw_wall(a: Vector2, b: Vector2, alpha: float):
		var core := Color(0.55, 0.52, 0.46, alpha)
		var edge := Color(0.82, 0.74, 0.52, alpha)
		draw_line(a, b, edge, host.WALL_T + 2.0, true)
		draw_line(a, b, core, host.WALL_T - 2.0, true)
		draw_circle(a, host.WALL_T * 0.5 + 1.0, edge)
		draw_circle(b, host.WALL_T * 0.5 + 1.0, edge)

# ===========================================================================
#  LAB FRONT — aim overlays and impact effects. Sits over the blobs.
# ===========================================================================
class LabFront extends Node2D:
	var host = null
	var font: Font = null
	var pulse: float = 0.0

	func _process(delta):
		pulse += delta
		queue_redraw()

	func _draw():
		if font == null:
			font = ThemeDB.fallback_font
		var amber: Color = host.AMBER

		# impact flashes: filled circle, growing ring, "−N" or MISS
		for f in host.flashes:
			var k: float = clamp(float(f["t"]) / 0.9, 0.0, 1.0)
			var p: Vector2 = f["p"]
			var rr: float = f["r"]
			draw_circle(p, rr, Color(1.0, 0.35, 0.10, 0.50 * k))
			draw_arc(p, rr + (1.0 - k) * 50.0, 0.0, TAU, 56, Color(1.0, 0.6, 0.3, k * 0.7), 2.5, true)
			var kills: int = int(f["kills"])
			var txt: String = ("−%d" % kills) if kills > 0 else "MISS"
			var tw: float = font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 32).x
			var tp := Vector2(p.x - tw * 0.5, p.y + 11.0 - (1.0 - k) * 26.0)
			draw_string(font, tp + Vector2(2, 2), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 32, Color(0, 0, 0, k * 0.8))
			draw_string(font, tp, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 32, Color(1.0, 0.95, 0.85, k))

		# stir waves
		for w in host.waves:
			var k2: float = clamp(float(w["t"]) / 0.6, 0.0, 1.0)
			var wp: Vector2 = w["p"]
			var wr: float = float(w["r"]) * (1.0 - k2 * 0.6)
			for i in range(3):
				draw_arc(wp, wr * (1.0 - i * 0.22), 0.0, TAU, 48, Color(0.55, 0.85, 0.95, k2 * (0.6 - i * 0.15)), 2.0, true)

		if not host.world_ready or host.setup_overlay.visible:
			return
		if not host.mouse_in_lab:
			# wall preview still shows while dragging out of bounds
			if host.wall_dragging:
				_draw_wall_preview()
			return

		var m: Vector2 = host.mouse_lab
		var breathe: float = 0.75 + 0.25 * sin(pulse * 4.0)
		match int(host.tool):
			1:  # spawn
				var c: Color = host.spawn_preview_color()
				draw_circle(m, host.BLOB_R * 0.8, Color(c.r, c.g, c.b, 0.22))
				draw_arc(m, host.BLOB_R * 0.8, 0.0, TAU, 40, Color(c.r, c.g, c.b, 0.8 * breathe), 2.0, true)
				draw_line(m + Vector2(-7, 0), m + Vector2(7, 0), Color(1, 1, 1, 0.9), 2.0)
				draw_line(m + Vector2(0, -7), m + Vector2(0, 7), Color(1, 1, 1, 0.9), 2.0)
			2:  # meteor
				var r: float = host.meteor_r
				draw_circle(m, r, Color(1.0, 0.40, 0.15, 0.10))
				draw_arc(m, r, 0.0, TAU, 64, Color(1.0, 0.55, 0.25, 0.85 * breathe), 2.5, true)
				var n: int = 0
				for b in host.alive_cache:
					if b.global_position.distance_to(m) <= r:
						n += 1
						draw_arc(b.global_position, host.BLOB_R + 4.0, 0.0, TAU, 32, Color(1.0, 0.45, 0.25, 0.9), 2.0, true)
				var label: String = "%d inside" % n
				var lw: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
				var ly: float = m.y - r - 10.0
				if ly < host.LAB.position.y + 18.0:
					ly = m.y + r + 22.0
				draw_string(font, Vector2(m.x - lw * 0.5, ly), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1.0, 0.85, 0.7))
			3:  # wall
				if host.wall_dragging:
					_draw_wall_preview()
				else:
					draw_circle(m, host.WALL_T * 0.5 + 2.0, Color(amber.r, amber.g, amber.b, 0.7 * breathe))
				# highlight a wall that right-click would remove
				var wi: int = host.wall_near(m)
				if wi >= 0 and not host.wall_dragging:
					var w: Dictionary = host.walls[wi]
					draw_line(w["a"], w["b"], Color(1.0, 0.45, 0.35, 0.55), host.WALL_T + 8.0, true)
			4:  # stir
				draw_arc(m, host.stir_r, 0.0, TAU, 56, Color(0.55, 0.85, 0.95, 0.55 * breathe), 2.0, true)
				draw_arc(m, host.stir_r * 0.6, 0.0, TAU, 40, Color(0.55, 0.85, 0.95, 0.25 * breathe), 1.5, true)

	func _draw_wall_preview():
		var a: Vector2 = host.wall_start
		var b: Vector2 = host.clamp_to_lab(host.mouse_lab)
		var ok: bool = a.distance_to(b) >= 24.0 and host.walls.size() < host.MAX_WALLS
		var col := Color(0.82, 0.74, 0.52, 0.55) if ok else Color(1.0, 0.45, 0.35, 0.55)
		draw_line(a, b, col, host.WALL_T, true)
		draw_circle(a, host.WALL_T * 0.5, col)
		draw_circle(b, host.WALL_T * 0.5, col)

# ===========================================================================
#  BLOB CARD — hover / pinned inspector. Same look as the presets' inspector,
#  plus generation and children, which only the sandbox tracks.
# ===========================================================================
class BlobCard extends Node2D:
	var host = null
	var target = null
	var pinned: bool = false
	var font: Font = null
	var portrait_body: Sprite2D
	var portrait_eye: Sprite2D

	const BOX_W := 206.0
	const PAD := 12.0
	const LINE_H := 19.0
	const PORTRAIT := 52.0
	const HL := Color(1.0, 0.87, 0.25)

	func _ready():
		z_index = 200
		visible = false
		portrait_body = Sprite2D.new()
		portrait_eye = Sprite2D.new()
		add_child(portrait_body)
		add_child(portrait_eye)

	func show_blob(b, is_pinned: bool):
		var changed: bool = b != target
		target = b
		pinned = is_pinned
		visible = b != null
		if b == null:
			return
		if changed:
			_build_portrait()
		queue_redraw()

	func _build_portrait():
		var bs = target.get_node_or_null("BodySprite")
		var es = target.get_node_or_null("EyeSprite")
		if bs and bs.texture:
			portrait_body.texture = bs.texture
			var tint: Color = target.base_modulate
			portrait_body.modulate = Color(tint.r, tint.g, tint.b, 1.0)
			var s: float = (PORTRAIT * 0.78) / float(bs.texture.get_height())
			portrait_body.scale = Vector2(s, s)
			if es and es.texture:
				portrait_eye.texture = es.texture
				portrait_eye.scale = Vector2(s, s) * (Vector2(1, 1) if target.eye_count == 3 else Vector2(0.75, 0.75))
				portrait_eye.visible = true
			else:
				portrait_eye.visible = false

	func _process(_delta):
		if target == null:
			return
		if not is_instance_valid(target) or target.is_dying:
			show_blob(null, false)
			return
		queue_redraw()

	func _lines() -> Array:
		var t = target
		var out: Array = []
		out.append(["Color", host.VARIANT_NAMES[0][t.color_trait], host.VARIANT_COLS[0][t.color_trait]])
		out.append(["Shape", host.VARIANT_NAMES[1][t.shape_trait], Color(0.86, 0.86, 0.90)])
		out.append(["Eyes", str(t.eye_count), Color(0.86, 0.86, 0.90)])
		var gen: int = int(t.get_meta("gen", 0))
		out.append(["Generation", ("%d" % gen) if gen > 0 else "Founder", Color(0.80, 0.80, 0.86)])
		out.append(["Children", str(int(t.get_meta("kids", 0))), Color(0.80, 0.80, 0.86)])
		var left: float = max(0.0, t.lifespan - t.age)
		var lc := Color(0.55, 0.90, 0.60)
		if left <= 5.0:
			lc = Color(1.0, 0.45, 0.45)
		elif left <= 12.0:
			lc = Color(0.95, 0.78, 0.40)
		out.append(["Life left", "%.1fs" % left, lc])
		var stage: String = "Adult"
		if not t.is_mature:
			stage = "Juvenile (%.0fs)" % max(0.0, t.maturation_time - t.age)
		out.append(["Stage", stage, Color(0.80, 0.80, 0.85)])
		return out

	func _radius() -> float:
		var bs = target.get_node_or_null("BodySprite")
		if bs and bs.texture:
			return bs.texture.get_width() * 0.5 * target.scale.x * bs.scale.x
		return 22.0

	func _draw():
		if target == null or not is_instance_valid(target):
			return
		if font == null:
			font = ThemeDB.fallback_font
		var lines: Array = _lines()
		var box_h: float = max(PORTRAIT, lines.size() * LINE_H) + PAD * 2.0 + 18.0
		var bp: Vector2 = target.global_position
		var r: float = _radius()
		var lab: Rect2 = host.LAB

		var ring_a: float = 0.95 if pinned else 0.55
		draw_arc(bp, r, 0.0, TAU, 40, Color(HL.r, HL.g, HL.b, ring_a), 2.0, true)
		if pinned:
			draw_arc(bp, r + 5.0, 0.0, TAU, 40, Color(HL.r, HL.g, HL.b, 0.45), 1.5, true)

		var to_right: bool = bp.x < lab.position.x + lab.size.x * 0.6
		var bx: float = bp.x + r + 40.0 if to_right else bp.x - r - 40.0 - BOX_W
		var by: float = bp.y - box_h * 0.5
		bx = clamp(bx, lab.position.x + 6.0, lab.end.x - BOX_W - 6.0)
		by = clamp(by, lab.position.y + 6.0, lab.end.y - box_h - 6.0)
		var box := Rect2(bx, by, BOX_W, box_h)

		var anchor := Vector2(box.position.x, box.position.y + box_h * 0.5)
		if not to_right:
			anchor = Vector2(box.end.x, box.position.y + box_h * 0.5)
		var dir: Vector2 = (anchor - bp).normalized()
		draw_line(bp + dir * (r + 3.0), anchor, Color(HL.r, HL.g, HL.b, 0.85 if pinned else 0.5), 1.5, true)
		draw_circle(bp, 4.0, Color(1, 1, 1, 0.95))
		draw_circle(bp, 2.2, Color(0.95, 0.75, 0.15, 1.0))

		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.13, 0.13, 0.165, 0.97)
		sb.border_color = Color(0.55, 0.48, 0.26) if pinned else Color(0.34, 0.33, 0.30)
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(9)
		draw_style_box(sb, box)

		var title: String = "Blob — pinned" if pinned else "Blob"
		draw_string(font, Vector2(box.position.x + PAD, box.position.y + PAD + 11.0), title,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.85, 0.76, 0.45) if pinned else Color(0.62, 0.62, 0.68))

		var pbox := Rect2(box.position.x + PAD, box.position.y + PAD + 20.0, PORTRAIT, PORTRAIT)
		var ps := StyleBoxFlat.new()
		ps.bg_color = Color(0.08, 0.08, 0.10)
		ps.set_corner_radius_all(7)
		draw_style_box(ps, pbox)
		portrait_body.position = pbox.get_center()
		portrait_eye.position = pbox.get_center()

		var tx: float = box.position.x + PAD + PORTRAIT + 12.0
		var ty: float = box.position.y + PAD + 30.0
		for i in range(lines.size()):
			var row: Array = lines[i]
			var y: float = ty + i * LINE_H
			var key: String = str(row[0]) + ":"
			draw_string(font, Vector2(tx, y), key, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.58, 0.60, 0.68))
			var lw: float = font.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
			draw_string(font, Vector2(tx + lw + 6.0, y), str(row[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, row[2])

# ===========================================================================
#  TRAIT GRAPH — share of each version of the chosen trait over the whole run.
#  The x axis always spans 0 -> now, so old samples compress instead of
#  scrolling away. Red ticks mark events.
# ===========================================================================
class TraitGraph extends Control:
	var host = null
	const GUTTER := 34.0

	func _draw():
		var full_w: float = size.x
		var h: float = size.y
		if full_w <= GUTTER or h <= 0.0:
			return
		var ox: float = GUTTER
		var w: float = full_w - GUTTER
		var plot := Rect2(ox, 0, w, h)
		draw_rect(plot, Color(0.085, 0.085, 0.105), true)

		var font: Font = get_theme_default_font()
		for i in range(5):
			var gy: float = h - (float(i) / 4.0) * h
			draw_line(Vector2(ox, gy), Vector2(ox + w, gy), Color(0.32, 0.32, 0.38) if i == 2 else Color(0.22, 0.22, 0.27), 1.0)
			var txt: String = "%d%%" % (i * 25)
			var tw: float = font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
			var ty: float = gy + 4.0
			if i == 4:
				ty = gy + 10.0
			elif i == 0:
				ty = gy - 1.0
			draw_string(font, Vector2(ox - 6.0 - tw, ty), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.60, 0.60, 0.68))

		var samples: Array = host.graph_samples
		var max_t: float = 10.0
		if samples.size() > 0:
			max_t = max(10.0, float(samples[samples.size() - 1]["t"]))

		for mt in host.graph_marks:
			var mx: float = ox + (float(mt) / max_t) * w
			draw_line(Vector2(mx, 0), Vector2(mx, h), Color(1.0, 0.38, 0.30, 0.85), 1.5)

		var ti: int = host.graph_trait
		var cols: Array = host.VARIANT_COLS[ti]
		if samples.size() >= 2:
			for v in range(cols.size()):
				var pts := PackedVector2Array()
				for s in samples:
					var pct: float = float(s["p"][ti][v])
					pts.append(Vector2(ox + (float(s["t"]) / max_t) * w, h - pct / 100.0 * h))
				draw_polyline(pts, cols[v], 2.0, true)
		draw_rect(plot, Color(0.28, 0.28, 0.34), false, 1.0)

# ===========================================================================
#  SHARE BAR — one stacked bar above the lab: the chosen trait's live mix.
# ===========================================================================
class ShareBar extends Control:
	var host = null

	func _draw():
		var r := Rect2(Vector2.ZERO, size)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.085, 0.085, 0.105)
		sb.set_corner_radius_all(5)
		draw_style_box(sb, r)
		var total: int = host.latest_total
		if total <= 0:
			return
		var ti: int = host.graph_trait
		var counts: Array = host.latest_counts[ti]
		var x: float = 0.0
		for v in range(counts.size()):
			var wv: float = float(counts[v]) / float(total) * size.x
			if wv > 0.5:
				draw_rect(Rect2(x, 0, wv, size.y), host.VARIANT_COLS[ti][v], true)
				if v > 0 and x > 1.0:
					draw_line(Vector2(x, 0), Vector2(x, size.y), Color(0.1, 0.1, 0.12), 1.0)
			x += wv

# ===========================================================================
#  TOOL BUTTON — a big square button with a drawn icon and a key number.
# ===========================================================================
class ToolButton extends Button:
	var kind: int = 0
	var label_text: String = ""
	var selected: bool = false
	var key_no: int = 1

	func _draw():
		var font: Font = get_theme_default_font()
		var c := Color(0.95, 0.78, 0.38) if selected else Color(0.80, 0.80, 0.85)
		var mid := Vector2(size.x * 0.5, size.y * 0.40)
		match kind:
			0:  # inspect: magnifier
				draw_arc(mid + Vector2(-3, -3), 9.0, 0.0, TAU, 28, c, 2.5, true)
				draw_line(mid + Vector2(3.5, 3.5), mid + Vector2(10, 10), c, 3.0, true)
			1:  # spawn: blob with a plus
				draw_circle(mid, 11.0, Color(c.r, c.g, c.b, 0.25))
				draw_arc(mid, 11.0, 0.0, TAU, 28, c, 2.0, true)
				draw_line(mid + Vector2(-5, 0), mid + Vector2(5, 0), c, 2.5)
				draw_line(mid + Vector2(0, -5), mid + Vector2(0, 5), c, 2.5)
			2:  # meteor: rock with a trail
				draw_line(mid + Vector2(-13, -11), mid + Vector2(-1, -1), Color(c.r, c.g, c.b, 0.45), 3.0, true)
				draw_line(mid + Vector2(-8, -14), mid + Vector2(1, -5), Color(c.r, c.g, c.b, 0.30), 2.0, true)
				draw_circle(mid + Vector2(3, 3), 7.0, c)
			3:  # wall: thick bar with caps
				draw_line(mid + Vector2(-12, 8), mid + Vector2(12, -8), c, 5.0, true)
				draw_circle(mid + Vector2(-12, 8), 3.0, c)
				draw_circle(mid + Vector2(12, -8), 3.0, c)
			4:  # stir: three arcs
				for i in range(3):
					draw_arc(mid, 4.0 + i * 4.5, -PI * 0.15 + i * 0.6, PI * 0.95 + i * 0.6, 16, c, 2.0, true)
		var tw: float = font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		draw_string(font, Vector2((size.x - tw) * 0.5, size.y - 9.0), label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, c)
		draw_string(font, Vector2(6, 14), str(key_no), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.55, 0.55, 0.62))

# ===========================================================================
#  LIFECYCLE
# ===========================================================================
func _ready():
	randomize()
	Engine.time_scale = 1.0
	_load_font()
	_build_lab_bounds()

	lab_back = LabBack.new()
	lab_back.host = self
	lab_back.z_index = -5
	add_child(lab_back)

	lab_front = LabFront.new()
	lab_front.host = self
	lab_front.z_index = 50
	lab_front.font = _font(700)
	add_child(lab_front)

	card = BlobCard.new()
	card.host = self
	card.font = _font(600)
	add_child(card)

	_reset_tracking()
	_build_ui()
	_build_setup_card()
	_select_tab(0)
	_select_tool(T_INSPECT)
	_refresh_all_panels()
	_open_setup(false)

func _process(delta):
	_refresh_alive()
	_update_mouse()
	_update_card()
	_tick_effects(delta)

	if world_ready and running:
		sim_time += delta
		_tick_stir(delta)
		_tick_chaos(delta)
		graph_timer += delta
		if graph_timer >= 0.25:
			graph_timer = 0.0
			_sample_graph()
		goal_timer += delta
		if goal_timer >= 0.5:
			_check_goals(goal_timer)
			goal_timer = 0.0

	data_timer += delta
	if data_timer >= 0.25:
		data_timer = 0.0
		_count_now()
		_check_announcements()
		_refresh_live_ui()

# ===========================================================================
#  WORLD: setup, spawning, births, deaths
# ===========================================================================
func _build_lab_bounds():
	var body := StaticBody2D.new()
	body.name = "LabWalls"
	add_child(body)
	var t: float = 60.0
	var rects: Array = [
		Rect2(LAB.position.x - t, LAB.position.y - t, LAB.size.x + t * 2.0, t),
		Rect2(LAB.position.x - t, LAB.end.y, LAB.size.x + t * 2.0, t),
		Rect2(LAB.position.x - t, LAB.position.y, t, LAB.size.y),
		Rect2(LAB.end.x, LAB.position.y, t, LAB.size.y),
	]
	for r in rects:
		var rr: Rect2 = r
		var cs := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		shape.size = rr.size
		cs.shape = shape
		cs.position = rr.get_center()
		body.add_child(cs)

func _reset_tracking():
	low_flags = [[false, false, false], [false, false, false], [false, false]]
	seen_variants = [[false, false, false], [false, false, false], [false, false]]
	prev_present = [[false, false, false], [false, false, false], [false, false]]
	comeback_armed = false
	fullhouse_time = 0.0

func create_world():
	if blob_scene == null:
		push_error("Sandbox: Blob Scene is not assigned on the root node. Drag Scenes/blob.tscn into the 'Blob Scene' field in the Inspector.")
		return
	_clear_world()
	world_id += 1
	world_ready = true
	sim_time = 0.0
	births = 0
	deaths = 0
	graph_samples.clear()
	graph_marks.clear()
	log_lines.clear()
	last_event_name = ""
	chaos_timer = chaos_interval
	_reset_tracking()

	var n: int = start_count
	var lists: Array = []
	for ti in range(3):
		lists.append(_mix_list(ti, n))
	var placed: Array = []
	for i in range(n):
		var pos: Vector2 = _free_spot(placed)
		placed.append(pos)
		var b = _make_blob(pos, int(lists[0][i]), int(lists[1][i]), [1, 3][int(lists[2][i])])
		b.set_meta("gen", 0)
	_log("New world: %d blobs" % n)
	_set_running(true)
	_count_now()
	for ti in range(3):
		for v in range(latest_counts[ti].size()):
			prev_present[ti][v] = latest_counts[ti][v] > 0
	_sample_graph()
	_toast("World created. They're babies for the first 9 seconds, so nothing breeds yet.")
	_refresh_all_panels()

func _clear_world():
	pinned_blob = null
	hovered_blob = null
	stir_boost.clear()
	for b in blobs:
		if is_instance_valid(b):
			b.queue_free()
	blobs.clear()
	alive_cache.clear()
	for w in walls:
		if is_instance_valid(w["body"]):
			w["body"].queue_free()
	walls.clear()
	regions_dirty = true
	craters.clear()
	flashes.clear()
	waves.clear()
	lab_back.queue_redraw()

# A list of n variant indices for one trait, following the chosen mix mode.
func _mix_list(ti: int, n: int) -> Array:
	var k: int = VARIANT_NAMES[ti].size()
	var out: Array = []
	match int(mix_modes[ti]):
		0:  # even
			for i in range(n):
				out.append(i % k)
		1:  # random
			for i in range(n):
				out.append(randi() % k)
		2:  # one rare
			var rare: int = randi() % k
			var others: Array = []
			for v in range(k):
				if v != rare:
					others.append(v)
			out.append(rare)
			for i in range(n - 1):
				out.append(others[i % others.size()])
		_:  # off
			for i in range(n):
				out.append(0)
	out.shuffle()
	return out

func _free_spot(placed: Array) -> Vector2:
	var best := Vector2.ZERO
	var best_d: float = -1.0
	for attempt in range(30):
		var p := Vector2(
			randf_range(LAB.position.x + 50.0, LAB.end.x - 50.0),
			randf_range(LAB.position.y + 50.0, LAB.end.y - 50.0))
		var d: float = INF
		for q in placed:
			d = min(d, p.distance_to(q))
		if d >= 70.0:
			return p
		if d > best_d:
			best_d = d
			best = p
	return best

func _make_blob(pos: Vector2, color: int, shape: int, eyes: int):
	var b = blob_scene.instantiate()
	add_child(b)
	b.global_position = pos
	b.setup(shape, color, eyes, [blob_tex_1, blob_tex_2, blob_tex_3], [eye_tex_1, eye_tex_2])
	b.lifespan = lifespan * randf_range(1.0 - LIFESPAN_JITTER, 1.0 + LIFESPAN_JITTER)
	b.reproduction_cooldown_max = breed_rest
	b.set_meta("base_speed", b.speed)
	b.speed = b.speed * wander_mult
	b.set_meta("kids", 0)
	b.reproduce.connect(_on_blob_reproduce.bind(b, world_id))
	b.tree_exited.connect(_on_blob_removed.bind(b, world_id))
	blobs.append(b)
	if not running:
		b.set_physics_process(false)
	return b

func _on_blob_reproduce(traits_a: Dictionary, traits_b: Dictionary, pos: Vector2, parent, wid: int):
	await get_tree().create_timer(0.2, false).timeout
	if wid != world_id or not world_ready or not running:
		return
	if _alive_count() >= max_population:
		return
	var other = _blob_nearest(pos * 2.0 - (parent.global_position if is_instance_valid(parent) else pos), parent)
	var c: int = traits_a["color_trait"] if randf() > 0.5 else traits_b["color_trait"]
	var s: int = traits_a["shape_trait"] if randf() > 0.5 else traits_b["shape_trait"]
	var e: int = traits_a["eye_count"] if randf() > 0.5 else traits_b["eye_count"]
	var b = _make_blob(clamp_to_lab(pos), c, s, e)
	var gen: int = 0
	for p in [parent, other]:
		if p != null and is_instance_valid(p):
			gen = max(gen, int(p.get_meta("gen", 0)))
			p.set_meta("kids", int(p.get_meta("kids", 0)) + 1)
	b.set_meta("gen", gen + 1)
	births += 1

func _on_blob_removed(b, wid: int):
	blobs.erase(b)
	stir_boost.erase(b)
	if b == pinned_blob:
		pinned_blob = null
	if b == hovered_blob:
		hovered_blob = null
	if wid == world_id and world_ready and is_inside_tree():
		deaths += 1

func _blob_nearest(p: Vector2, exclude):
	var best = null
	var best_d: float = INF
	for b in alive_cache:
		if b == exclude:
			continue
		var d: float = b.global_position.distance_to(p)
		if d < best_d:
			best_d = d
			best = b
	return best

func _refresh_alive():
	alive_cache = blobs.filter(func(b): return is_instance_valid(b) and not b.is_dying)

func _alive_count() -> int:
	var n: int = 0
	for b in blobs:
		if is_instance_valid(b) and not b.is_dying:
			n += 1
	return n

func _kill(b):
	if not is_instance_valid(b) or b.is_dying:
		return
	b.die()
	# the death animation runs in the blob's physics step, so let it play
	# even when the sim is paused
	b.set_physics_process(true)

func _on_play_pressed():
	if world_ready:
		_set_running(not running)

func _set_running(on: bool):
	running = on
	for b in blobs:
		if is_instance_valid(b) and not b.is_dying:
			b.set_physics_process(on)
	if play_btn:
		_style_play_button()

# ===========================================================================
#  COUNTS, GRAPH, ANNOUNCEMENTS
# ===========================================================================
func _variant_of(b, ti: int) -> int:
	match ti:
		0:
			return b.color_trait
		1:
			return b.shape_trait
	return 0 if b.eye_count == 1 else 1

func _counts_for(list: Array) -> Array:
	var out: Array = [[0, 0, 0], [0, 0, 0], [0, 0]]
	for b in list:
		for ti in range(3):
			out[ti][_variant_of(b, ti)] += 1
	return out

func _count_now():
	latest_counts = _counts_for(alive_cache)
	latest_total = alive_cache.size()

func _sample_graph():
	_count_now()
	var p: Array = []
	for ti in range(3):
		var row: Array = []
		for v in range(latest_counts[ti].size()):
			row.append(0.0 if latest_total == 0 else float(latest_counts[ti][v]) / float(latest_total) * 100.0)
		p.append(row)
	graph_samples.append({"t": sim_time, "p": p})
	if graph_samples.size() > 1600:
		var thinned: Array = []
		for i in range(graph_samples.size()):
			if i % 2 == 0 or i == graph_samples.size() - 1:
				thinned.append(graph_samples[i])
		graph_samples = thinned
	if graph:
		graph.queue_redraw()

# Toasts for a version being lost, coming back, or a trait fixing.
func _check_announcements():
	if not world_ready:
		return
	if latest_total == 0:
		var any_before: bool = false
		for ti in range(3):
			for v in range(prev_present[ti].size()):
				any_before = any_before or prev_present[ti][v]
				prev_present[ti][v] = false
		if any_before:
			_toast("The population died out. Spawn some blobs or start a new world.")
			_log("Population died out")
		return
	for ti in range(3):
		var before_n: int = 0
		var now_n: int = 0
		var only: int = -1
		for v in range(latest_counts[ti].size()):
			var was: bool = prev_present[ti][v]
			var now: bool = latest_counts[ti][v] > 0
			if was:
				before_n += 1
			if now:
				now_n += 1
				only = v
				seen_variants[ti][v] = true
			if was and not now:
				_toast("%s is gone. It can't come back unless you spawn it in." % VARIANT_NAMES[ti][v])
				_log("%s lost" % VARIANT_NAMES[ti][v])
			elif now and not was:
				_toast("%s is back, carried in by migrants." % VARIANT_NAMES[ti][v])
				_log("%s returned" % VARIANT_NAMES[ti][v])
			prev_present[ti][v] = now
		if before_n >= 2 and now_n == 1:
			_toast("%s is fixed. Every blob is now %s." % [TRAIT_NAMES[ti], VARIANT_NAMES[ti][only]])
			_log("%s fixed: %s" % [TRAIT_NAMES[ti], VARIANT_NAMES[ti][only]])
			_complete_goal("fix")

# ===========================================================================
#  INPUT
# ===========================================================================
func _update_mouse():
	var m: Vector2 = get_global_mouse_position()
	mouse_lab = m
	mouse_in_lab = LAB.has_point(m) and not _ui_blocking()

func _ui_blocking() -> bool:
	if setup_overlay and setup_overlay.visible:
		return true
	if info_layer != null:
		return true
	if get_tree().get_first_node_in_group("howto_popup") != null:
		return true
	return false

func _unhandled_input(event):
	if event is InputEventKey and event.pressed and not event.echo:
		if _ui_blocking():
			return
		match event.keycode:
			KEY_SPACE:
				if world_ready:
					_set_running(not running)
				get_viewport().set_input_as_handled()
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5:
				_select_tool(event.keycode - KEY_1)
				_select_tab(0)
				get_viewport().set_input_as_handled()
			KEY_ESCAPE:
				pinned_blob = null
				wall_dragging = false
				painting = false
		return

	if not world_ready or _ui_blocking():
		return

	if event is InputEventMouseButton:
		var p: Vector2 = get_global_mouse_position()
		var in_lab: bool = LAB.has_point(p)
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed and in_lab:
				_tool_press(p)
				get_viewport().set_input_as_handled()
			elif not event.pressed:
				_tool_release(p)
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed and in_lab:
			if tool == T_WALL:
				var wi: int = wall_near(p)
				if wi >= 0:
					_remove_wall(wi)
			wall_dragging = false
	elif event is InputEventMouseMotion:
		var p2: Vector2 = get_global_mouse_position()
		if painting and tool == T_SPAWN and LAB.has_point(p2):
			if p2.distance_to(last_paint_pos) >= SPAWN_PAINT_GAP:
				_spawn_at(p2, false)

func _tool_press(p: Vector2):
	match tool:
		T_INSPECT:
			var hit = _blob_at(p)
			if hit == null or hit == pinned_blob:
				pinned_blob = null
			else:
				pinned_blob = hit
		T_SPAWN:
			painting = true
			_spawn_at(p, true)
		T_METEOR:
			_meteor(p, meteor_r, "Meteor")
		T_WALL:
			if walls.size() >= MAX_WALLS:
				_toast("That's the most walls the lab can hold (%d). Right-click one to remove it." % MAX_WALLS)
				return
			wall_dragging = true
			wall_start = clamp_to_lab(p)
		T_STIR:
			_stir(p)

func _tool_release(p: Vector2):
	painting = false
	if tool == T_WALL and wall_dragging:
		wall_dragging = false
		var b: Vector2 = clamp_to_lab(p)
		if wall_start.distance_to(b) >= 24.0:
			_add_wall(wall_start, b)

func _blob_at(pos: Vector2):
	var best = null
	var best_d: float = INF
	for b in alive_cache:
		var r: float = 24.0
		var bs = b.get_node_or_null("BodySprite")
		if bs and bs.texture:
			r = max(r, bs.texture.get_width() * 0.5 * b.scale.x * bs.scale.x)
		var d: float = pos.distance_to(b.global_position)
		if d <= r and d < best_d:
			best_d = d
			best = b
	return best

func _update_card():
	if pinned_blob != null:
		if not is_instance_valid(pinned_blob) or pinned_blob.is_dying:
			pinned_blob = null
		else:
			card.show_blob(pinned_blob, true)
			return
	var hit = null
	if tool == T_INSPECT and mouse_in_lab:
		hit = _blob_at(mouse_lab)
	hovered_blob = hit
	card.show_blob(hit, false)

func clamp_to_lab(p: Vector2) -> Vector2:
	return Vector2(
		clamp(p.x, LAB.position.x + 8.0, LAB.end.x - 8.0),
		clamp(p.y, LAB.position.y + 8.0, LAB.end.y - 8.0))

# ===========================================================================
#  TOOLS
# ===========================================================================
func spawn_preview_color() -> Color:
	if spawn_pick[0] >= 0:
		return VARIANT_COLS[0][spawn_pick[0]]
	return Color(0.9, 0.9, 0.9)

func _spawn_at(p: Vector2, first: bool):
	last_paint_pos = p
	if _alive_count() >= max_population:
		if first:
			_toast("The lab is at its population cap (%d). Raise it in the World tab." % max_population)
		return
	for w in walls:
		if _dist_to_seg(p, w["a"], w["b"]) < WALL_T * 0.5 + BLOB_R * 0.6:
			if first:
				_toast("Can't drop a blob inside a wall.")
			return
	var c: int = spawn_pick[0] if spawn_pick[0] >= 0 else randi() % 3
	var s: int = spawn_pick[1] if spawn_pick[1] >= 0 else randi() % 3
	var e: int = [1, 3][spawn_pick[2]] if spawn_pick[2] >= 0 else [1, 3][randi() % 2]
	var b = _make_blob(clamp_to_lab(p), c, s, e)
	b.set_meta("gen", 0)
	if spawn_adult:
		b.age = MATURATION_TIME
	if first:
		_log("Migrant arrived: %s %s" % [VARIANT_NAMES[0][c], VARIANT_NAMES[1][s]])

func _meteor(p: Vector2, r: float, label: String):
	var before_list: Array = alive_cache.duplicate()
	_snapshot_before(label)
	var killed: Array = []
	for b in alive_cache:
		if b.global_position.distance_to(p) <= r:
			killed.append(b)
	for b in killed:
		_kill(b)
	_refresh_alive()
	craters.append({"p": p, "r": r, "t": 8.0})
	flashes.append({"p": p, "r": r, "t": 0.9, "kills": killed.size()})
	lab_back.queue_redraw()
	_snapshot_after()
	var kc: Array = _counts_for(killed)
	_log("%s hit %d  %s" % [label, killed.size(), _color_breakdown(kc[0])])
	_mark_event()
	# Wipeout: a version present before the strike, gone after it
	var bc: Array = _counts_for(before_list)
	var ac: Array = _counts_for(alive_cache)
	for ti in range(3):
		for v in range(bc[ti].size()):
			if bc[ti][v] > 0 and ac[ti][v] == 0 and killed.size() > 0:
				_complete_goal("wipeout")
	_arm_comeback(before_list.size())

func _stir(p: Vector2):
	waves.append({"p": p, "r": stir_r, "t": 0.6})
	var n: int = 0
	for b in alive_cache:
		var d: Vector2 = b.global_position - p
		if d.length() <= stir_r:
			n += 1
			var dir: Vector2 = d.normalized() if d.length() > 1.0 else Vector2.RIGHT.rotated(randf() * TAU)
			b.direction = dir.rotated(randf_range(-0.3, 0.3))
			stir_boost[b] = 0.8
	if n > 0:
		_log("Gust scattered %d" % n)

func _tick_stir(delta: float):
	for b in stir_boost.keys():
		if not is_instance_valid(b):
			stir_boost.erase(b)
			continue
		var left: float = float(stir_boost[b]) - delta
		var base: float = float(b.get_meta("base_speed", 85.0)) * wander_mult
		if left <= 0.0:
			b.speed = base
			stir_boost.erase(b)
		else:
			b.speed = base * (1.0 + 2.2 * (left / 0.8))
			stir_boost[b] = left

func _add_wall(a: Vector2, b: Vector2):
	var body := StaticBody2D.new()
	var cs := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(a.distance_to(b) + WALL_T, WALL_T)
	cs.shape = shape
	body.add_child(cs)
	body.position = (a + b) * 0.5
	body.rotation = (b - a).angle()
	add_child(body)
	walls.append({"a": a, "b": b, "body": body})
	regions_dirty = true
	# nudge anyone the wall landed on out to the nearer side
	for bl in alive_cache:
		var cp: Vector2 = _closest_on_seg(bl.global_position, a, b)
		var off: Vector2 = bl.global_position - cp
		var need: float = WALL_T * 0.5 + BLOB_R + 2.0
		if off.length() < need:
			var n: Vector2 = off.normalized() if off.length() > 0.5 else (b - a).orthogonal().normalized()
			bl.global_position = clamp_to_lab(cp + n * need)
	lab_back.queue_redraw()
	_log("Wall built (%d)" % walls.size())
	_refresh_tool_card()

func _remove_wall(i: int):
	var w: Dictionary = walls[i]
	if is_instance_valid(w["body"]):
		w["body"].queue_free()
	walls.remove_at(i)
	regions_dirty = true
	lab_back.queue_redraw()
	_log("Wall removed")
	_refresh_tool_card()

func _clear_walls():
	for i in range(walls.size() - 1, -1, -1):
		var w: Dictionary = walls[i]
		if is_instance_valid(w["body"]):
			w["body"].queue_free()
	walls.clear()
	regions_dirty = true
	lab_back.queue_redraw()
	_refresh_tool_card()

func wall_near(p: Vector2) -> int:
	var best: int = -1
	var best_d: float = 16.0
	for i in range(walls.size()):
		var d: float = _dist_to_seg(p, walls[i]["a"], walls[i]["b"])
		if d < best_d:
			best_d = d
			best = i
	return best

func _closest_on_seg(p: Vector2, a: Vector2, b: Vector2) -> Vector2:
	var ab: Vector2 = b - a
	var l2: float = ab.length_squared()
	if l2 <= 0.0001:
		return a
	var t: float = clamp((p - a).dot(ab) / l2, 0.0, 1.0)
	return a + ab * t

func _dist_to_seg(p: Vector2, a: Vector2, b: Vector2) -> float:
	return p.distance_to(_closest_on_seg(p, a, b))

func _tick_effects(delta: float):
	for list in [craters, flashes, waves]:
		for i in range(list.size() - 1, -1, -1):
			list[i]["t"] = float(list[i]["t"]) - delta
			if float(list[i]["t"]) <= 0.0:
				list.remove_at(i)
	lab_back.queue_redraw()

# ===========================================================================
#  EVENTS (Events tab + Chaos Mode). All pick at random or by place.
# ===========================================================================
func _snapshot_before(label: String):
	last_event_name = label
	last_before = _counts_for(alive_cache)
	last_before_total = alive_cache.size()

func _snapshot_after():
	_refresh_alive()
	last_after = _counts_for(alive_cache)
	last_after_total = alive_cache.size()
	_refresh_last_event()

func _mark_event():
	graph_marks.append(sim_time)
	if graph:
		graph.queue_redraw()

func _arm_comeback(before_n: int):
	var after_n: int = alive_cache.size()
	if before_n >= 10 and after_n <= 12 and after_n > 0:
		comeback_armed = true

func ev_unlucky():
	if alive_cache.is_empty():
		_toast("No blobs left to be unlucky.")
		return
	var before_n: int = alive_cache.size()
	_snapshot_before("Unlucky Death")
	var b = alive_cache[randi() % alive_cache.size()]
	var who: String = "%s %s" % [VARIANT_NAMES[0][b.color_trait], VARIANT_NAMES[1][b.shape_trait]]
	_kill(b)
	_snapshot_after()
	_log("Unlucky death: a %s" % who)
	_mark_event()
	_arm_comeback(before_n)

func ev_bottleneck():
	if alive_cache.size() < 2:
		_toast("Too few blobs for a bottleneck.")
		return
	var before_n: int = alive_cache.size()
	_snapshot_before("Bottleneck %d%%" % bottleneck_pct)
	var pool: Array = alive_cache.duplicate()
	pool.shuffle()
	var k: int = clampi(int(round(pool.size() * bottleneck_pct / 100.0)), 1, pool.size() - 1)
	for i in range(k):
		_kill(pool[i])
	_snapshot_after()
	_log("Bottleneck: %d of %d died" % [k, before_n])
	_mark_event()
	_arm_comeback(before_n)

func ev_random_meteor():
	var p := Vector2(
		randf_range(LAB.position.x + meteor_r * 0.5, LAB.end.x - meteor_r * 0.5),
		randf_range(LAB.position.y + meteor_r * 0.5, LAB.end.y - meteor_r * 0.5))
	_meteor(p, meteor_r, "Random meteor")

func _tick_chaos(delta: float):
	if not chaos_on:
		return
	chaos_timer -= delta
	if chaos_timer > 0.0:
		return
	chaos_timer = chaos_interval
	if alive_cache.size() < 3:
		return
	var roll: float = randf()
	if roll < 0.5:
		ev_unlucky()
		_toast("Chaos: an unlucky death.")
	elif roll < 0.8:
		ev_random_meteor()
		_toast("Chaos: a meteor strikes.")
	else:
		ev_bottleneck()
		_toast("Chaos: a %d%% bottleneck." % bottleneck_pct)

func _color_breakdown(counts: Array) -> String:
	var parts: Array = []
	for v in range(counts.size()):
		if counts[v] > 0:
			parts.append("%d %s" % [counts[v], VARIANT_NAMES[0][v]])
	if parts.is_empty():
		return ""
	return "(" + ", ".join(parts) + ")"

# ===========================================================================
#  GOALS
# ===========================================================================
func _complete_goal(id: String):
	for g in goals:
		if g["id"] == id and not g["done"]:
			g["done"] = true
			_toast("Goal complete: %s!" % g["title"], true)
			_log("Goal: %s" % g["title"])
			_refresh_goals()

func _check_goals(dt: float):
	var total: int = latest_total
	if total <= 0:
		fullhouse_time = 0.0
		return
	# underdog
	if total >= 10:
		for ti in range(3):
			for v in range(latest_counts[ti].size()):
				var share: float = float(latest_counts[ti][v]) / float(total)
				if share > 0.0 and share < 0.10:
					low_flags[ti][v] = true
				elif low_flags[ti][v] and share >= 0.5:
					_complete_goal("underdog")
	# comeback
	if comeback_armed and total >= min(40, max_population):
		comeback_armed = false
		_complete_goal("comeback")
	# full house
	var all_present: bool = true
	for ti in range(3):
		for v in range(latest_counts[ti].size()):
			if latest_counts[ti][v] == 0:
				all_present = false
	if all_present:
		fullhouse_time += dt
		if fullhouse_time >= 120.0:
			_complete_goal("fullhouse")
	else:
		fullhouse_time = 0.0
	# islands
	if walls.size() > 0 and not _goal_done("islands"):
		_check_islands()

func _goal_done(id: String) -> bool:
	for g in goals:
		if g["id"] == id:
			return g["done"]
	return false

# Flood-fill the lab into regions separated by walls, then look for two
# regions that each hold 4+ blobs of a single color, with different colors.
func _rebuild_regions():
	region_w = int(ceil(LAB.size.x / CELL))
	region_h = int(ceil(LAB.size.y / CELL))
	region_grid = PackedInt32Array()
	region_grid.resize(region_w * region_h)
	for i in range(region_grid.size()):
		var cx: float = LAB.position.x + (i % region_w + 0.5) * CELL
		var cy: float = LAB.position.y + (i / region_w + 0.5) * CELL
		var blocked: bool = false
		for w in walls:
			if _dist_to_seg(Vector2(cx, cy), w["a"], w["b"]) < WALL_T * 0.5 + 6.0:
				blocked = true
				break
		region_grid[i] = -2 if blocked else -1
	var next_id: int = 0
	for start in range(region_grid.size()):
		if region_grid[start] != -1:
			continue
		var stack: Array = [start]
		region_grid[start] = next_id
		while not stack.is_empty():
			var i2: int = stack.pop_back()
			var x: int = i2 % region_w
			var y: int = i2 / region_w
			for d in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
				var nx: int = x + int(d[0])
				var ny: int = y + int(d[1])
				if nx < 0 or ny < 0 or nx >= region_w or ny >= region_h:
					continue
				var j: int = ny * region_w + nx
				if region_grid[j] == -1:
					region_grid[j] = next_id
					stack.append(j)
		next_id += 1
	regions_dirty = false

func _check_islands():
	if regions_dirty:
		_rebuild_regions()
	var per: Dictionary = {}   # region -> [r, g, b]
	for b in alive_cache:
		var gx: int = int((b.global_position.x - LAB.position.x) / CELL)
		var gy: int = int((b.global_position.y - LAB.position.y) / CELL)
		if gx < 0 or gy < 0 or gx >= region_w or gy >= region_h:
			continue
		var r: int = region_grid[gy * region_w + gx]
		if r < 0:
			continue
		if not per.has(r):
			per[r] = [0, 0, 0]
		per[r][b.color_trait] += 1
	var pure_colors: Dictionary = {}
	for r in per.keys():
		var c: Array = per[r]
		var tot: int = int(c[0]) + int(c[1]) + int(c[2])
		if tot < 4:
			continue
		for v in range(3):
			if int(c[v]) == tot:
				pure_colors[v] = true
	if pure_colors.size() >= 2:
		_complete_goal("islands")

# ===========================================================================
#  LOG + TOASTS
# ===========================================================================
func _clock(t: float) -> String:
	return "%d:%02d" % [int(t) / 60, int(t) % 60]

func _log(text: String):
	log_lines.push_front("%s   %s" % [_clock(sim_time), text])
	if log_lines.size() > 40:
		log_lines.resize(40)
	_refresh_log()

func _toast(text: String, gold: bool = false):
	if toast_box == null:
		return
	while toast_box.get_child_count() >= 3:
		var old: Node = toast_box.get_child(0)
		toast_box.remove_child(old)
		old.queue_free()
	var p := PanelContainer.new()
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.11, 0.11, 0.14, 0.95)
	var accent: Color = Color(1.0, 0.85, 0.30) if gold else AMBER
	s.border_color = Color(accent.r, accent.g, accent.b, 0.8)
	s.set_border_width_all(1)
	s.border_width_left = 4
	s.set_corner_radius_all(8)
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	p.add_theme_stylebox_override("panel", s)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", Color(1.0, 0.92, 0.6) if gold else COL_TEXT)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(l)
	toast_box.add_child(p)
	var tw: Tween = p.create_tween()
	tw.tween_interval(4.0)
	tw.tween_property(p, "modulate:a", 0.0, 0.6)
	tw.tween_callback(p.queue_free)

# ===========================================================================
#  UI: BUILD
# ===========================================================================
func _load_font():
	if ResourceLoader.exists(FONT_PATH):
		_font_file = load(FONT_PATH)

func _font(weight: int) -> Font:
	if _font_file == null:
		return ThemeDB.fallback_font
	if _fonts.has(weight):
		return _fonts[weight]
	var fv := FontVariation.new()
	fv.base_font = _font_file
	var ts: TextServer = TextServerManager.get_primary_interface()
	fv.variation_opentype = {ts.name_to_tag("wght"): float(weight)}
	_fonts[weight] = fv
	return fv

func _make_theme() -> Theme:
	var th := Theme.new()
	th.default_font = _font(500)
	th.default_font_size = 15
	th.set_font("bold_font", "RichTextLabel", _font(750))
	return th

func _build_ui():
	ui_layer = CanvasLayer.new()
	ui_layer.layer = 5
	add_child(ui_layer)
	ui_root = Control.new()
	ui_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.theme = _make_theme()
	ui_layer.add_child(ui_root)

	_build_hud()
	_build_panel()

# --- HUD above the lab: hint strip, stats, share bar, toasts ---
func _build_hud():
	var strip := PanelContainer.new()
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.11, 0.11, 0.14, 0.96)
	s.border_color = Color(AMBER.r, AMBER.g, AMBER.b, 0.75)
	s.set_border_width_all(1)
	s.border_width_left = 4
	s.set_corner_radius_all(8)
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 4
	s.content_margin_bottom = 4
	strip.add_theme_stylebox_override("panel", s)
	strip.position = Vector2(LAB.position.x, 8)
	strip.size = Vector2(LAB.size.x, 30)
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.add_child(strip)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.add_child(row)

	hint_tag = Label.new()
	hint_tag.add_theme_font_size_override("font_size", 12)
	hint_tag.add_theme_font_override("font", _font(800))
	hint_tag.add_theme_color_override("font_color", AMBER)
	hint_tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(hint_tag)

	hint_text = Label.new()
	hint_text.add_theme_font_size_override("font_size", 14)
	hint_text.add_theme_color_override("font_color", Color(0.92, 0.92, 0.95))
	hint_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint_text.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	hint_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(hint_text)

	stats_lbl = Label.new()
	stats_lbl.position = Vector2(LAB.position.x + 4, 44)
	stats_lbl.size = Vector2(520, 24)
	stats_lbl.add_theme_font_size_override("font_size", 14)
	stats_lbl.add_theme_color_override("font_color", Color(0.80, 0.80, 0.85))
	stats_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.add_child(stats_lbl)

	share_lbl = Label.new()
	share_lbl.position = Vector2(LAB.end.x - 300, 44)
	share_lbl.size = Vector2(64, 24)
	share_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	share_lbl.add_theme_font_size_override("font_size", 13)
	share_lbl.add_theme_color_override("font_color", COL_DIM)
	share_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.add_child(share_lbl)

	share_bar = ShareBar.new()
	share_bar.host = self
	share_bar.position = Vector2(LAB.end.x - 228, 49)
	share_bar.size = Vector2(228, 14)
	share_bar.mouse_filter = Control.MOUSE_FILTER_PASS
	share_bar.tooltip_text = "The live mix of the trait picked in the Data tab."
	ui_root.add_child(share_bar)

	toast_box = VBoxContainer.new()
	toast_box.position = Vector2(LAB.position.x + 14, LAB.position.y + 12)
	toast_box.size = Vector2(LAB.size.x - 28, 10)
	toast_box.add_theme_constant_override("separation", 6)
	toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.add_child(toast_box)

# --- SIDE PANEL ---
func _build_panel():
	var panel := PanelContainer.new()
	var ps := StyleBoxFlat.new()
	ps.bg_color = COL_PANEL
	ps.border_color = COL_BORDER
	ps.border_width_left = 1
	panel.add_theme_stylebox_override("panel", ps)
	panel.position = Vector2(PANEL_X, 0)
	panel.size = Vector2(PANEL_W, SCREEN_H)
	ui_root.add_child(panel)

	var pad := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 10)
	panel.add_child(pad)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	pad.add_child(col)

	# header: menu / guide / info
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	col.add_child(header)
	var back := _button("← Menu", GREY, Vector2(0, 34), 15)
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back.tooltip_text = "Leave the sandbox and go back to the main menu."
	back.pressed.connect(_to_menu)
	header.add_child(back)
	var guide := _amber_button("?  Guide", 84)
	guide.tooltip_text = "Pause and read how every tool, event and setting works."
	guide.pressed.connect(_open_guide)
	header.add_child(guide)
	var info := _amber_button("Info", 56)
	info.tooltip_text = "Pause and open the full Info menu."
	info.pressed.connect(_open_info)
	header.add_child(info)

	# run row: play / new world
	var run := HBoxContainer.new()
	run.add_theme_constant_override("separation", 6)
	col.add_child(run)
	play_btn = _button("Pause", BLUE, Vector2(0, 40), 17)
	play_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	play_btn.tooltip_text = "Freeze or unfreeze time (Space). Tools still work while paused."
	play_btn.pressed.connect(_on_play_pressed)
	run.add_child(play_btn)
	var neww := _button("New world", GREY, Vector2(118, 40), 15)
	neww.tooltip_text = "Start over with a fresh population. You'll get the setup card again."
	neww.pressed.connect(func(): _open_setup(true))
	run.add_child(neww)
	_style_play_button()

	# speed
	var sp_row := HBoxContainer.new()
	sp_row.add_theme_constant_override("separation", 4)
	col.add_child(sp_row)
	var sp_lbl := Label.new()
	sp_lbl.text = "Speed"
	sp_lbl.custom_minimum_size = Vector2(48, 0)
	sp_lbl.add_theme_font_size_override("font_size", 13)
	sp_lbl.add_theme_color_override("font_color", COL_DIM)
	sp_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sp_row.add_child(sp_lbl)
	speed_btns = []
	for i in range(SPEEDS.size()):
		var b := Button.new()
		b.text = SPEED_LABELS[i]
		b.custom_minimum_size = Vector2(0, 28)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 14)
		b.tooltip_text = "Run time at %s speed. Speeds everyone up equally." % SPEED_LABELS[i]
		b.pressed.connect(_set_speed.bind(i))
		sp_row.add_child(b)
		speed_btns.append(b)
	_set_speed(speed_idx)

	# tabs
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 3)
	col.add_child(tabs)
	tab_btns = []
	var tab_names: Array = ["Tools", "Events", "World", "Data", "Goals"]
	var tab_tips: Array = [
		"Pick what your mouse does in the lab.",
		"Fire random events, or turn on Chaos Mode.",
		"Change the rules for every blob at once.",
		"Live tracker, graph, last event, and the log.",
		"Optional challenges that tick themselves off.",
	]
	for i in range(tab_names.size()):
		var b := Button.new()
		b.text = tab_names[i]
		b.custom_minimum_size = Vector2(0, 30)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 13)
		b.tooltip_text = tab_tips[i]
		b.pressed.connect(_select_tab.bind(i))
		tabs.add_child(b)
		tab_btns.append(b)

	tab_scroll = ScrollContainer.new()
	tab_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tab_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(tab_scroll)
	HowToPopup._style_scrollbar(tab_scroll)

	var pages := VBoxContainer.new()
	pages.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab_scroll.add_child(pages)

	tab_pages = []
	for builder in [_build_tools_tab, _build_events_tab, _build_world_tab, _build_data_tab, _build_goals_tab]:
		var page := VBoxContainer.new()
		page.add_theme_constant_override("separation", 10)
		page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pages.add_child(page)
		builder.call(page)
		tab_pages.append(page)

# --- TOOLS TAB ---
func _build_tools_tab(page: VBoxContainer):
	page.add_child(_dim_text("Pick a tool, then use it in the lab. Keys 1 to 5 switch tools."))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	page.add_child(grid)
	tool_btns = []
	for i in range(TOOL_NAMES.size()):
		var b := ToolButton.new()
		b.kind = i
		b.key_no = i + 1
		b.label_text = TOOL_NAMES[i]
		b.custom_minimum_size = Vector2(84, 60)
		b.focus_mode = Control.FOCUS_NONE
		b.tooltip_text = TOOL_HINTS[i]
		b.pressed.connect(_select_tool.bind(i))
		grid.add_child(b)
		tool_btns.append(b)
	tool_card_box = VBoxContainer.new()
	tool_card_box.add_theme_constant_override("separation", 8)
	page.add_child(tool_card_box)

func _refresh_tool_card():
	if tool_card_box == null:
		return
	for ch in tool_card_box.get_children():
		ch.queue_free()
	var cardp := _card()
	tool_card_box.add_child(cardp)
	var vb: VBoxContainer = cardp.get_child(0)
	vb.add_child(_heading(TOOL_NAMES[tool]))
	vb.add_child(_body_text(TOOL_HINTS[tool]))
	match tool:
		T_SPAWN:
			vb.add_child(_small_label("Color"))
			vb.add_child(_segmented(["Any", "Red", "Green", "Blue"], spawn_pick[0] + 1,
				func(i): spawn_pick[0] = i - 1))
			vb.add_child(_small_label("Shape"))
			vb.add_child(_segmented(["Any", "Round", "Star", "Flower"], spawn_pick[1] + 1,
				func(i): spawn_pick[1] = i - 1))
			vb.add_child(_small_label("Eyes"))
			vb.add_child(_segmented(["Any", "One", "Three"], spawn_pick[2] + 1,
				func(i): spawn_pick[2] = i - 1))
			vb.add_child(_small_label("Arrives as"))
			vb.add_child(_segmented(["Baby", "Adult"], 1 if spawn_adult else 0,
				func(i): spawn_adult = i == 1))
			vb.add_child(_dim_text("\"Any\" rolls that trait at random for each new blob. Adults can breed straight away; babies need 9 seconds to grow up."))
		T_METEOR:
			_slider_row(vb, "Crater size", 40, 170, 5, meteor_r,
				func(v): return "%d px" % int(v),
				func(v): meteor_r = v)
			vb.add_child(_dim_text("Random Meteor in the Events tab uses this size too."))
		T_WALL:
			var count := Label.new()
			count.text = "Walls built: %d / %d" % [walls.size(), MAX_WALLS]
			count.add_theme_font_size_override("font_size", 14)
			count.add_theme_color_override("font_color", COL_TEXT)
			vb.add_child(count)
			var clear := _button("Clear all walls", GREY, Vector2(0, 34), 14)
			clear.disabled = walls.is_empty()
			clear.pressed.connect(_clear_walls)
			vb.add_child(clear)
			vb.add_child(_dim_text("Tip: run a wall from edge to edge to cut the lab in two, then watch each side drift its own way."))
		T_STIR:
			_slider_row(vb, "Gust size", 60, 260, 10, stir_r,
				func(v): return "%d px" % int(v),
				func(v): stir_r = v)
		T_INSPECT:
			vb.add_child(_dim_text("Generation counts how many births back a blob is from the founders or a migrant. Children counts the babies it has had."))
	vb.add_child(_why_box(TOOL_WHY[tool]))

# --- EVENTS TAB ---
func _build_events_tab(page: VBoxContainer):
	page.add_child(_dim_text("Events strike at random or by place, never by trait. Each one is marked on the graph."))

	var c1 := _card()
	page.add_child(c1)
	var v1: VBoxContainer = c1.get_child(0)
	v1.add_child(_heading("Unlucky Death"))
	v1.add_child(_body_text("One random blob dies. Small numbers, real effect."))
	var b1 := _button("Fire", FIRE, Vector2(0, 34), 15)
	b1.pressed.connect(ev_unlucky)
	v1.add_child(b1)

	var c2 := _card()
	page.add_child(c2)
	var v2: VBoxContainer = c2.get_child(0)
	v2.add_child(_heading("Bottleneck"))
	v2.add_child(_body_text("A random share of the population dies at once. The survivors' mix becomes everyone's future."))
	_slider_row(v2, "How many die", 50, 95, 5, bottleneck_pct,
		func(v): return "%d%%" % int(v),
		func(v): bottleneck_pct = int(v))
	var b2 := _button("Fire", FIRE, Vector2(0, 34), 15)
	b2.pressed.connect(ev_bottleneck)
	v2.add_child(b2)

	var c3 := _card()
	page.add_child(c3)
	var v3: VBoxContainer = c3.get_child(0)
	v3.add_child(_heading("Random Meteor"))
	v3.add_child(_body_text("A meteor lands somewhere you didn't choose. Size comes from the Meteor tool."))
	var b3 := _button("Fire", FIRE, Vector2(0, 34), 15)
	b3.pressed.connect(ev_random_meteor)
	v3.add_child(b3)

	var c4 := _card()
	page.add_child(c4)
	var v4: VBoxContainer = c4.get_child(0)
	v4.add_child(_heading("Chaos Mode"))
	v4.add_child(_body_text("Fires a random event on a timer: mostly unlucky deaths, sometimes a meteor, now and then a bottleneck."))
	_slider_row(v4, "Every", 10, 60, 5, chaos_interval,
		func(v): return "%ds" % int(v),
		func(v):
			chaos_interval = v
			chaos_timer = min(chaos_timer, v))
	chaos_btn = _button("Turn on", BLUE, Vector2(0, 34), 15)
	chaos_btn.pressed.connect(func():
		chaos_on = not chaos_on
		chaos_timer = chaos_interval
		_log("Chaos Mode " + ("on" if chaos_on else "off"))
		_style_chaos_button())
	v4.add_child(chaos_btn)
	chaos_lbl = _dim_text("")
	v4.add_child(chaos_lbl)

	var c5 := _card()
	page.add_child(c5)
	last_event_box = c5.get_child(0)

func _style_chaos_button():
	if chaos_btn == null:
		return
	chaos_btn.text = "Turn off" if chaos_on else "Turn on"
	var base: Color = FIRE if chaos_on else BLUE
	chaos_btn.add_theme_stylebox_override("normal", _round(base))
	chaos_btn.add_theme_stylebox_override("hover", _round(base.lightened(0.1)))
	chaos_btn.add_theme_stylebox_override("pressed", _round(base.darkened(0.12)))

func _refresh_last_event():
	if last_event_box == null:
		return
	for ch in last_event_box.get_children():
		ch.queue_free()
	last_event_box.add_child(_heading("Last event"))
	if last_event_name == "" or last_before_total == 0:
		last_event_box.add_child(_dim_text("Nothing yet. Fire an event or drop a meteor, and the before and after shares show up here."))
		return
	last_event_box.add_child(_body_text("%s:  %d → %d blobs" % [last_event_name, last_before_total, last_after_total]))
	for ti in range(3):
		last_event_box.add_child(_small_label(TRAIT_NAMES[ti]))
		for v in range(VARIANT_NAMES[ti].size()):
			var b_pct: int = int(round(float(last_before[ti][v]) / float(last_before_total) * 100.0))
			var a_pct: int = 0
			if last_after_total > 0:
				a_pct = int(round(float(last_after[ti][v]) / float(last_after_total) * 100.0))
			var arrow: String = "▲" if a_pct > b_pct else ("▼" if a_pct < b_pct else "─")
			var col: Color = Color(0.45, 0.95, 0.5) if a_pct > b_pct else (Color(1.0, 0.45, 0.45) if a_pct < b_pct else Color(0.8, 0.8, 0.84))
			var l := Label.new()
			l.text = "%s   %d%% → %d%%  %s" % [VARIANT_NAMES[ti][v], b_pct, a_pct, arrow]
			l.add_theme_font_size_override("font_size", 13)
			l.add_theme_color_override("font_color", col)
			last_event_box.add_child(l)

# --- WORLD TAB ---
func _build_world_tab(page: VBoxContainer):
	page.add_child(_dim_text("These rules apply to every blob the same way."))
	var c := _card()
	page.add_child(c)
	var vb: VBoxContainer = c.get_child(0)

	_slider_row(vb, "Population cap", 10, 120, 5, max_population,
		func(v): return "%d" % int(v),
		func(v): max_population = int(v))
	vb.add_child(_dim_text("Births stop at the cap. Small caps make drift fast and wild; big ones make it slow."))
	vb.add_child(HSeparator.new())

	_slider_row(vb, "Lifespan", 15, 90, 5, lifespan,
		func(v): return "%ds" % int(v),
		func(v): lifespan = v)
	vb.add_child(_dim_text("How long new blobs live, give or take a little luck. Short lives mean quicker generations."))
	vb.add_child(HSeparator.new())

	_slider_row(vb, "Breeding rest", 1, 8, 0.5, breed_rest,
		func(v): return "%.1fs" % v,
		func(v):
			breed_rest = v
			for b in alive_cache:
				b.reproduction_cooldown_max = v)
	vb.add_child(_dim_text("How long a parent waits before it can have another baby."))
	vb.add_child(HSeparator.new())

	_slider_row(vb, "Wander speed", 0.5, 2.0, 0.25, wander_mult,
		func(v): return "%.2fx" % v,
		func(v):
			wander_mult = v
			for b in alive_cache:
				if not stir_boost.has(b):
					b.speed = float(b.get_meta("base_speed", 85.0)) * v)
	vb.add_child(_dim_text("How fast blobs roam. Faster roaming means more meetings and better mixing."))

	page.add_child(_why_box("Every setting moves all blobs by the same amount, so no trait gets an edge. They change how fast drift works, never which way it goes."))

# --- DATA TAB ---
func _build_data_tab(page: VBoxContainer):
	page.add_child(_small_label("Show trait"))
	graph_seg = []
	page.add_child(_segmented(["Color", "Shape", "Eyes"], graph_trait, func(i):
		graph_trait = i
		if graph:
			graph.queue_redraw()
		if share_bar:
			share_bar.queue_redraw()
		_refresh_live_ui()))

	page.add_child(_small_label("Share over time  (red lines = events)"))
	graph = TraitGraph.new()
	graph.host = self
	graph.custom_minimum_size = Vector2(0, 120)
	graph.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_child(graph)

	var c := _card()
	page.add_child(c)
	tracker_box = c.get_child(0)

	var c2 := _card()
	page.add_child(c2)
	var lv: VBoxContainer = c2.get_child(0)
	lv.add_child(_heading("Event log"))
	log_box = VBoxContainer.new()
	log_box.add_theme_constant_override("separation", 3)
	lv.add_child(log_box)

func _refresh_tracker():
	if tracker_box == null:
		return
	for ch in tracker_box.get_children():
		ch.queue_free()
	tracker_box.add_child(_heading("Allele tracker"))
	var total: int = latest_total
	for ti in range(3):
		tracker_box.add_child(_small_label(TRAIT_NAMES[ti]))
		var lead: int = 0
		for v in range(latest_counts[ti].size()):
			if latest_counts[ti][v] > latest_counts[ti][lead]:
				lead = v
		for v in range(latest_counts[ti].size()):
			var n: int = latest_counts[ti][v]
			var pct: float = 0.0 if total == 0 else float(n) / float(total)
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 6)
			tracker_box.add_child(row)
			var vname := Label.new()
			vname.text = VARIANT_NAMES[ti][v]
			vname.custom_minimum_size = Vector2(78, 0)
			vname.add_theme_font_size_override("font_size", 13)
			vname.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3) if (v == lead and total > 0) else COL_TEXT)
			row.add_child(vname)
			var bar_bg := Panel.new()
			bar_bg.custom_minimum_size = Vector2(90, 14)
			var bs := StyleBoxFlat.new()
			bs.bg_color = Color(0.085, 0.085, 0.105)
			bs.set_corner_radius_all(4)
			bar_bg.add_theme_stylebox_override("panel", bs)
			var cc := CenterContainer.new()
			cc.add_child(bar_bg)
			row.add_child(cc)
			var fill := ColorRect.new()
			fill.color = VARIANT_COLS[ti][v]
			fill.size = Vector2(90.0 * pct, 14)
			bar_bg.add_child(fill)
			var val := Label.new()
			if total > 0 and n == 0:
				val.text = "LOST"
				val.add_theme_color_override("font_color", Color(1.0, 0.45, 0.45))
			elif total > 0 and n == total:
				val.text = "FIXED"
				val.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
			else:
				val.text = "%d%% (%d)" % [int(round(pct * 100.0)), n]
				val.add_theme_color_override("font_color", COL_DIM)
			val.add_theme_font_size_override("font_size", 12)
			row.add_child(val)

func _refresh_log():
	if log_box == null:
		return
	for ch in log_box.get_children():
		ch.queue_free()
	if log_lines.is_empty():
		log_box.add_child(_dim_text("Nothing has happened yet."))
		return
	for i in range(min(14, log_lines.size())):
		var l := Label.new()
		l.text = log_lines[i]
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.add_theme_font_size_override("font_size", 12)
		l.add_theme_color_override("font_color", COL_TEXT if i == 0 else COL_DIM)
		log_box.add_child(l)

# --- GOALS TAB ---
func _build_goals_tab(page: VBoxContainer):
	page.add_child(_dim_text("Optional challenges. They tick themselves off when they happen."))
	goal_count_lbl = Label.new()
	goal_count_lbl.add_theme_font_size_override("font_size", 15)
	goal_count_lbl.add_theme_color_override("font_color", AMBER)
	page.add_child(goal_count_lbl)
	goal_rows = []
	for g in goals:
		var c := _card()
		page.add_child(c)
		var vb: VBoxContainer = c.get_child(0)
		var title := Label.new()
		title.add_theme_font_size_override("font_size", 15)
		vb.add_child(title)
		vb.add_child(_dim_text(g["desc"]))
		goal_rows.append({"card": c, "title": title})
	page.add_child(_why_box("Goals say nothing about which trait is better. In every one of them, luck decides the winner."))

func _refresh_goals():
	if goal_count_lbl == null:
		return
	var done: int = 0
	for i in range(goals.size()):
		var g: Dictionary = goals[i]
		var row: Dictionary = goal_rows[i]
		var t: Label = row["title"]
		if g["done"]:
			done += 1
			t.text = "✓  " + g["title"]
			t.add_theme_color_override("font_color", Color(0.55, 0.92, 0.60))
		else:
			t.text = "○  " + g["title"]
			t.add_theme_color_override("font_color", COL_TEXT)
	goal_count_lbl.text = "%d / %d done" % [done, goals.size()]

# ===========================================================================
#  UI: REFRESH
# ===========================================================================
func _refresh_all_panels():
	_refresh_tool_card()
	_refresh_last_event()
	_refresh_tracker()
	_refresh_log()
	_refresh_goals()
	_style_chaos_button()
	_refresh_live_ui()

func _refresh_live_ui():
	if stats_lbl:
		if world_ready:
			stats_lbl.text = "Population %d / %d    ·    Time %s    ·    Births %d    ·    Deaths %d%s" % [
				latest_total, max_population, _clock(sim_time), births, deaths,
				"" if running else "    ·    PAUSED"]
		else:
			stats_lbl.text = "No world yet"
	if share_lbl:
		share_lbl.text = TRAIT_NAMES[graph_trait]
	if share_bar:
		share_bar.queue_redraw()
	if chaos_lbl:
		chaos_lbl.text = ("Next event in %ds" % int(ceil(chaos_timer))) if chaos_on else "Off"
	if current_tab == 3:
		_refresh_tracker()

func _select_tab(i: int):
	current_tab = i
	for j in range(tab_pages.size()):
		tab_pages[j].visible = j == i
	for j in range(tab_btns.size()):
		_style_tab(tab_btns[j], j == i)
	if tab_scroll:
		tab_scroll.scroll_vertical = 0
	if i == 3:
		_refresh_tracker()
		_refresh_log()

func _select_tool(i: int):
	tool = clampi(i, 0, TOOL_NAMES.size() - 1)
	wall_dragging = false
	painting = false
	for j in range(tool_btns.size()):
		var b: ToolButton = tool_btns[j]
		b.selected = j == tool
		var s := StyleBoxFlat.new()
		s.bg_color = Color(AMBER.r, AMBER.g, AMBER.b, 0.16) if b.selected else Color(0.17, 0.17, 0.21)
		s.border_color = Color(AMBER.r, AMBER.g, AMBER.b, 0.9) if b.selected else COL_BORDER
		s.set_border_width_all(2 if b.selected else 1)
		s.set_corner_radius_all(9)
		var h: StyleBoxFlat = s.duplicate()
		h.bg_color = s.bg_color.lightened(0.06)
		b.add_theme_stylebox_override("normal", s)
		b.add_theme_stylebox_override("hover", h)
		b.add_theme_stylebox_override("pressed", s)
		b.add_theme_stylebox_override("focus", s)
		b.queue_redraw()
	if hint_tag:
		hint_tag.text = TOOL_NAMES[tool].to_upper()
		hint_text.text = TOOL_HINTS[tool]
	_refresh_tool_card()

func _set_speed(i: int):
	speed_idx = i
	Engine.time_scale = SPEEDS[i]
	for j in range(speed_btns.size()):
		_style_tab(speed_btns[j], j == i)

func _style_play_button():
	var base: Color = BLUE if not running else GREY
	play_btn.text = "Play" if not running else "Pause"
	play_btn.add_theme_stylebox_override("normal", _round(base))
	play_btn.add_theme_stylebox_override("hover", _round(base.lightened(0.1)))
	play_btn.add_theme_stylebox_override("pressed", _round(base.darkened(0.12)))
	play_btn.add_theme_stylebox_override("focus", _round(base))

# ===========================================================================
#  SETUP CARD (first load + New world)
# ===========================================================================
func _build_setup_card():
	overlay_layer = CanvasLayer.new()
	overlay_layer.layer = 10
	add_child(overlay_layer)

	setup_overlay = Control.new()
	setup_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	setup_overlay.theme = _make_theme()
	overlay_layer.add_child(setup_overlay)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	setup_overlay.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	setup_overlay.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(660, 0)
	var s := StyleBoxFlat.new()
	s.bg_color = COL_CARD
	s.border_color = COL_BORDER
	s.set_border_width_all(1)
	s.set_corner_radius_all(14)
	panel.add_theme_stylebox_override("panel", s)
	center.add_child(panel)

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 26)
	pad.add_theme_constant_override("margin_right", 26)
	pad.add_theme_constant_override("margin_top", 20)
	pad.add_theme_constant_override("margin_bottom", 20)
	panel.add_child(pad)

	# the buttons sit in a footer outside the scroll, so Create world is
	# always on screen (beta: "almost missed Begin")
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 14)
	pad.add_child(outer)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, SCREEN_H - 170.0)
	outer.add_child(scroll)
	HowToPopup._style_scrollbar(scroll)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vb)

	var title := Label.new()
	title.text = "Sandbox"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_font_override("font", _font(800))
	vb.add_child(title)

	var sub := Label.new()
	sub.text = "Your own drift lab. Build a population, then break it, split it, bring in migrants, and watch chance decide what survives."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.custom_minimum_size = Vector2(580, 0)
	sub.add_theme_font_size_override("font_size", 16)
	sub.add_theme_color_override("font_color", Color(0.80, 0.80, 0.86))
	vb.add_child(sub)

	# quick start, in the presets' amber instruction style
	var qs := PanelContainer.new()
	var qss := StyleBoxFlat.new()
	qss.bg_color = Color(AMBER.r, AMBER.g, AMBER.b, 0.09)
	qss.border_color = Color(AMBER.r, AMBER.g, AMBER.b, 0.70)
	qss.set_border_width_all(2)
	qss.set_corner_radius_all(10)
	qss.content_margin_left = 18
	qss.content_margin_right = 18
	qss.content_margin_top = 12
	qss.content_margin_bottom = 12
	qs.add_theme_stylebox_override("panel", qss)
	vb.add_child(qs)
	var qv := VBoxContainer.new()
	qv.add_theme_constant_override("separation", 6)
	qs.add_child(qv)
	var qh := Label.new()
	qh.text = "QUICK START"
	qh.add_theme_font_size_override("font_size", 14)
	qh.add_theme_font_override("font", _font(800))
	qh.add_theme_color_override("font_color", AMBER)
	qv.add_child(qh)
	var steps: Array = [
		"Choose your starting blobs below, then press Create world.",
		"Pick a tool on the right (Spawn, Meteor, Wall, Stir) and use it in the lab.",
		"Open the Data tab to watch the shares drift, and Goals for challenges.",
	]
	for i in range(steps.size()):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		qv.add_child(row)
		var num := Label.new()
		num.text = "%d." % (i + 1)
		num.custom_minimum_size = Vector2(20, 0)
		num.add_theme_font_size_override("font_size", 15)
		num.add_theme_color_override("font_color", AMBER)
		row.add_child(num)
		var t := Label.new()
		t.text = steps[i]
		t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		t.custom_minimum_size = Vector2(520, 0)
		t.add_theme_font_size_override("font_size", 15)
		t.add_theme_color_override("font_color", Color(0.93, 0.91, 0.86))
		row.add_child(t)

	# build-your-world controls
	var bh := Label.new()
	bh.text = "BUILD YOUR WORLD"
	bh.add_theme_font_size_override("font_size", 14)
	bh.add_theme_font_override("font", _font(800))
	bh.add_theme_color_override("font_color", COL_DIM)
	vb.add_child(bh)

	var count_row := HBoxContainer.new()
	count_row.add_theme_constant_override("separation", 12)
	vb.add_child(count_row)
	var cl := Label.new()
	cl.text = "Starting blobs"
	cl.custom_minimum_size = Vector2(130, 0)
	cl.add_theme_font_size_override("font_size", 16)
	count_row.add_child(cl)
	var sl := HSlider.new()
	sl.min_value = 2
	sl.max_value = 40
	sl.step = 1
	sl.value = start_count
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.custom_minimum_size = Vector2(0, 22)
	sl.focus_mode = Control.FOCUS_NONE
	_style_slider(sl)
	count_row.add_child(sl)
	setup_count_lbl = Label.new()
	setup_count_lbl.text = str(start_count)
	setup_count_lbl.custom_minimum_size = Vector2(36, 0)
	setup_count_lbl.add_theme_font_size_override("font_size", 16)
	setup_count_lbl.add_theme_color_override("font_color", AMBER)
	count_row.add_child(setup_count_lbl)
	sl.value_changed.connect(func(v):
		start_count = int(v)
		setup_count_lbl.text = str(start_count))

	setup_mix_help = []
	for ti in range(3):
		var r := HBoxContainer.new()
		r.add_theme_constant_override("separation", 12)
		vb.add_child(r)
		var tl := Label.new()
		tl.text = TRAIT_NAMES[ti] + " mix"
		tl.custom_minimum_size = Vector2(130, 0)
		tl.add_theme_font_size_override("font_size", 16)
		r.add_child(tl)
		var help := _dim_text(MIX_HELP[mix_modes[ti]])
		var tidx: int = ti
		var seg := _segmented(MIX_NAMES, mix_modes[ti], func(i):
			mix_modes[tidx] = i
			setup_mix_help[tidx].text = MIX_HELP[i])
		seg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r.add_child(seg)
		var hr := MarginContainer.new()
		hr.add_theme_constant_override("margin_left", 142)
		hr.add_child(help)
		vb.add_child(hr)
		setup_mix_help.append(help)

	vb.add_child(_why_box("Every blob lives, roams and breeds by the same rules. No version of any trait is better, so whatever takes over does it by luck."))

	var btns := HBoxContainer.new()
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	btns.add_theme_constant_override("separation", 14)
	outer.add_child(btns)
	var create := _button("Create world", BLUE, Vector2(200, 46), 17)
	create.pressed.connect(func():
		setup_overlay.visible = false
		create_world())
	btns.add_child(create)
	setup_cancel_btn = _button("Back to my world", GREY, Vector2(190, 46), 16)
	setup_cancel_btn.pressed.connect(func(): setup_overlay.visible = false)
	btns.add_child(setup_cancel_btn)
	var menu := _button("Menu", GREY, Vector2(120, 46), 16)
	menu.pressed.connect(_to_menu)
	btns.add_child(menu)

func _open_setup(can_cancel: bool):
	setup_cancel_btn.visible = can_cancel and world_ready
	setup_overlay.visible = true
	painting = false
	wall_dragging = false

# ===========================================================================
#  GUIDE + INFO + MENU
# ===========================================================================
func _open_guide():
	HowToPopup.open_tabs(self, "Sandbox guide", [
		{"label": "Start", "bbcode": _guide_start()},
		{"label": "Tools", "bbcode": _guide_tools()},
		{"label": "Events", "bbcode": _guide_events()},
		{"label": "World", "bbcode": _guide_world()},
		{"label": "Why drift", "bbcode": _guide_why()},
	])

func _guide_start() -> String:
	return (
		"[b]The sandbox is your own lab.[/b] There is no lesson and no end. You set up a population, then shape it however you like.\n\n"
		+ "[b]The basics[/b]\n"
		+ "•  Blobs are born small and grow up in 9 seconds. Only adults breed.\n"
		+ "•  Two adults bump → one baby. For each trait, the baby copies a random parent.\n"
		+ "•  Everyone dies of old age eventually. Births stop at the population cap.\n\n"
		+ "[b]The panel[/b]\n"
		+ "•  [b]Play / Pause[/b] (or Space) freezes time. Tools still work while paused.\n"
		+ "•  [b]New world[/b] brings back the setup card.\n"
		+ "•  [b]Speed[/b] runs time from ¼× to 3×, equally for everyone.\n"
		+ "•  Tabs: [b]Tools[/b], [b]Events[/b], [b]World[/b], [b]Data[/b], [b]Goals[/b].\n\n"
		+ "[b]Above the lab[/b]\n"
		+ "•  The amber strip says what your current tool does.\n"
		+ "•  The bar on the right is the live mix of the trait picked in the Data tab.\n"
		+ "•  Pop-ups announce when a version is lost, returns, or a trait becomes fixed."
	)

func _guide_tools() -> String:
	var t: String = "Pick a tool in the Tools tab or press 1 to 5.\n\n"
	for i in range(TOOL_NAMES.size()):
		t += "[b]%d.  %s[/b]\n%s\n[i]%s[/i]\n\n" % [i + 1, TOOL_NAMES[i], TOOL_HINTS[i], TOOL_WHY[i]]
	t += "[b]Spawn options[/b]: choose each trait or leave it on Any, and whether newcomers arrive as babies or adults.\n"
	t += "[b]Meteor[/b] and [b]Stir[/b] have a size slider. [b]Wall[/b] can hold up to %d walls; Clear all walls removes them." % MAX_WALLS
	return t

func _guide_events() -> String:
	return (
		"Events live in the Events tab. Each one is marked with a red line on the graph and written to the log.\n\n"
		+ "[b]Unlucky Death[/b]\nOne random blob dies. Even one death shifts the shares a little.\n\n"
		+ "[b]Bottleneck[/b]\nA random share of everyone dies at once (50% to 95%, you choose). The few survivors' mix becomes the whole future.\n\n"
		+ "[b]Random Meteor[/b]\nA crater lands somewhere random. Blobs are born next to their parents, so colors clump, and a meteor can wipe out a whole clump.\n\n"
		+ "[b]Chaos Mode[/b]\nFires a random event every few seconds (you set how often). Half are unlucky deaths, about a third are meteors, the rest bottlenecks.\n\n"
		+ "[b]Last event[/b]\nShows every version's share just before and just after the latest event, so you can see what that one moment did."
	)

func _guide_world() -> String:
	return (
		"[b]World tab[/b] (rules for everyone)\n"
		+ "•  [b]Population cap[/b]: births stop here. Small caps drift fast.\n"
		+ "•  [b]Lifespan[/b]: how long new blobs live. Shorter means faster generations.\n"
		+ "•  [b]Breeding rest[/b]: how long a parent waits before breeding again.\n"
		+ "•  [b]Wander speed[/b]: how fast blobs roam, and so how well they mix.\n\n"
		+ "[b]Data tab[/b]\n"
		+ "•  [b]Show trait[/b] switches the graph and the bar above the lab between Color, Shape and Eyes.\n"
		+ "•  The [b]graph[/b] keeps the whole run. Red lines are events.\n"
		+ "•  The [b]allele tracker[/b] shows each version's share and count. LOST means gone for good (unless you spawn it back). FIXED means it's the only one left.\n"
		+ "•  The [b]event log[/b] lists what happened and when.\n\n"
		+ "[b]Goals tab[/b]\nSix optional challenges, like getting an underdog from under 10% to over 50%. They tick off on their own."
	)

func _guide_why() -> String:
	return (
		"[b]Everything you see here is genetic drift: change caused by chance.[/b]\n\n"
		+ "No color, shape or eye count helps a blob live longer or have more babies. So when one version takes over, it got lucky: it happened to be in the right place, meet the right partners, or dodge the meteor.\n\n"
		+ "That's why the sandbox has no tool that lets you pick a blob and kill it. Choosing who dies by their traits would be [b]selection[/b], a different force. Every way of killing here is random or hits a place, not a trait.\n\n"
		+ "[b]Spawning[/b] is the one tool where you choose traits. In biology that's [b]gene flow[/b]: migrants arriving from another population. It changes the mix because new blobs came in, not because anyone was fitter.\n\n"
		+ "[b]Walls[/b] create [b]isolated populations[/b]. Each island drifts on its own, and given time they usually end up different. Knock the wall down and gene flow pulls them back together.\n\n"
		+ "Want the full theory? Press [b]Info[/b] for the drift lessons."
	)

func _open_info():
	if info_layer != null:
		return
	if get_tree().get_first_node_in_group("howto_popup") != null:
		return
	if not ResourceLoader.exists(INFO_SCENE):
		push_error("Sandbox: no Info scene at %s" % INFO_SCENE)
		return
	var packed: PackedScene = load(INFO_SCENE)
	var menu: Node = packed.instantiate()
	if not ("overlay_mode" in menu):
		menu.queue_free()
		return
	menu.set("overlay_mode", true)
	menu.connect("closed", _on_info_closed)
	info_layer = CanvasLayer.new()
	info_layer.layer = 100
	info_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(info_layer)
	info_layer.add_child(menu)
	info_layer.set_meta("was_paused", get_tree().paused)
	get_tree().paused = true

func _on_info_closed():
	if info_layer == null:
		return
	get_tree().paused = bool(info_layer.get_meta("was_paused", false))
	info_layer.queue_free()
	info_layer = null

func _to_menu():
	Engine.time_scale = 1.0
	get_tree().paused = false
	get_tree().change_scene_to_file(MENU_SCENE)

# ===========================================================================
#  UI HELPERS (same shapes and colors as the presets)
# ===========================================================================
func _round(c: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.set_corner_radius_all(8)
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	return s

func _button(text: String, base: Color, min_size: Vector2, font_size: int) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_stylebox_override("normal", _round(base))
	b.add_theme_stylebox_override("hover", _round(base.lightened(0.10)))
	b.add_theme_stylebox_override("pressed", _round(base.darkened(0.12)))
	b.add_theme_stylebox_override("focus", _round(base))
	b.add_theme_stylebox_override("disabled", _round(base.darkened(0.35)))
	b.add_theme_color_override("font_color", Color(0.94, 0.94, 0.94))
	b.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	b.add_theme_color_override("font_pressed_color", Color(0.94, 0.94, 0.94))
	b.add_theme_color_override("font_disabled_color", Color(0.55, 0.55, 0.60))
	return b

# Outlined amber pill, like the presets' About / Info buttons.
func _amber_button(text: String, min_w: float) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_w, 34)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 15)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(AMBER.r, AMBER.g, AMBER.b, 0.12)
	normal.border_color = Color(AMBER.r, AMBER.g, AMBER.b, 0.90)
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(8)
	normal.content_margin_left = 8
	normal.content_margin_right = 8
	var hover: StyleBoxFlat = normal.duplicate()
	hover.bg_color = Color(AMBER.r, AMBER.g, AMBER.b, 0.25)
	var pressed: StyleBoxFlat = normal.duplicate()
	pressed.bg_color = Color(AMBER.r, AMBER.g, AMBER.b, 0.35)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("focus", normal)
	b.add_theme_color_override("font_color", AMBER)
	b.add_theme_color_override("font_hover_color", AMBER.lightened(0.15))
	b.add_theme_color_override("font_pressed_color", AMBER)
	return b

# Tab look from HowToPopup: amber outline when on, faint when off.
func _style_tab(b: Button, on: bool):
	var s := StyleBoxFlat.new()
	s.bg_color = Color(AMBER.r, AMBER.g, AMBER.b, 0.28 if on else 0.06)
	s.border_color = Color(AMBER.r, AMBER.g, AMBER.b, 0.9 if on else 0.30)
	s.set_border_width_all(2 if on else 1)
	s.set_corner_radius_all(8)
	s.content_margin_left = 4
	s.content_margin_right = 4
	s.content_margin_top = 2
	s.content_margin_bottom = 2
	var h: StyleBoxFlat = s.duplicate()
	h.bg_color = Color(AMBER.r, AMBER.g, AMBER.b, 0.32 if on else 0.14)
	b.add_theme_stylebox_override("normal", s)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", s)
	b.add_theme_stylebox_override("focus", s)
	var fc: Color = AMBER if on else Color(0.80, 0.80, 0.84)
	b.add_theme_color_override("font_color", fc)
	b.add_theme_color_override("font_hover_color", AMBER)
	b.add_theme_color_override("font_pressed_color", AMBER)

# A row of toggle buttons; exactly one is on. cb receives the new index.
func _segmented(options: Array, selected: int, cb: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var btns: Array = []
	for i in range(options.size()):
		var b := Button.new()
		b.text = str(options[i])
		b.custom_minimum_size = Vector2(0, 28)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 13)
		row.add_child(b)
		btns.append(b)
	for i in range(btns.size()):
		_style_tab(btns[i], i == selected)
		btns[i].pressed.connect(func():
			for j in range(btns.size()):
				_style_tab(btns[j], j == i)
			cb.call(i))
	return row

func _style_slider(sl: HSlider):
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.16, 0.16, 0.19)
	track.set_corner_radius_all(6)
	track.content_margin_top = 5
	track.content_margin_bottom = 5
	sl.add_theme_stylebox_override("slider", track)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.40, 0.60, 1.0)
	fill.set_corner_radius_all(6)
	sl.add_theme_stylebox_override("grabber_area", fill)
	sl.add_theme_stylebox_override("grabber_area_highlight", fill)

# Title + live value on one line, slider underneath.
func _slider_row(parent: VBoxContainer, title: String, lo: float, hi: float, step: float,
		value: float, fmt: Callable, cb: Callable):
	var row := HBoxContainer.new()
	parent.add_child(row)
	var l := Label.new()
	l.text = title
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_font_size_override("font_size", 14)
	row.add_child(l)
	var v := Label.new()
	v.text = fmt.call(value)
	v.add_theme_font_size_override("font_size", 14)
	v.add_theme_color_override("font_color", AMBER)
	row.add_child(v)
	var sl := HSlider.new()
	sl.min_value = lo
	sl.max_value = hi
	sl.step = step
	sl.value = value
	sl.custom_minimum_size = Vector2(0, 22)
	sl.focus_mode = Control.FOCUS_NONE
	_style_slider(sl)
	parent.add_child(sl)
	sl.value_changed.connect(func(nv):
		v.text = fmt.call(nv)
		cb.call(nv))

func _card() -> PanelContainer:
	var p := PanelContainer.new()
	var s := StyleBoxFlat.new()
	s.bg_color = COL_CARD_DARK
	s.border_color = COL_BORDER
	s.set_border_width_all(1)
	s.set_corner_radius_all(8)
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	p.add_theme_stylebox_override("panel", s)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	p.add_child(vb)
	return p

func _heading(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_font_override("font", _font(750))
	l.add_theme_color_override("font_color", COL_TEXT)
	return l

func _body_text(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(200, 0)
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", Color(0.86, 0.86, 0.90))
	return l

func _dim_text(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(200, 0)
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", COL_DIM)
	return l

func _small_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_font_override("font", _font(750))
	l.add_theme_color_override("font_color", Color(0.70, 0.70, 0.78))
	return l

# Amber "why it's still drift" callout, the same voice as the presets' strips.
func _why_box(text: String) -> PanelContainer:
	var p := PanelContainer.new()
	var s := StyleBoxFlat.new()
	s.bg_color = Color(AMBER.r, AMBER.g, AMBER.b, 0.08)
	s.border_color = Color(AMBER.r, AMBER.g, AMBER.b, 0.7)
	s.set_border_width_all(1)
	s.border_width_left = 4
	s.set_corner_radius_all(8)
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	p.add_theme_stylebox_override("panel", s)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	p.add_child(vb)
	var tag := Label.new()
	tag.text = "WHY IT'S STILL DRIFT"
	tag.add_theme_font_size_override("font_size", 11)
	tag.add_theme_font_override("font", _font(800))
	tag.add_theme_color_override("font_color", AMBER)
	vb.add_child(tag)
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(200, 0)
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", Color(0.93, 0.91, 0.86))
	vb.add_child(l)
	return p
