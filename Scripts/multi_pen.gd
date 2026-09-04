extends DriftPreset
class_name MultiPen

# ===========================================================================
#  MULTI-PEN PRESET BASE
#
#  Shared machinery for any preset that runs SEVERAL isolated populations at
#  once: pen layout, walls, the pen overlay, per-pen spawning, per-pen caps,
#  and per-pen frequency bookkeeping.
#
#  A subclass sets its configuration in _ready() BEFORE calling super._ready():
#
#     pen_caps          population ceiling for each pen
#     pen_start_mix     [red, green, blue] starting counts for each pen
#     pen_titles        name plate text for each pen
#     pen_accents       border colour for each pen
#     blob_spawn_scale / blob_mature_scale
#
#  ...and overrides these to shape the scenario:
#
#     _layout_pens()          -> Array[Rect2], given lab_rect
#     _build_pen_walls()      physics walls (default: a box around each pen)
#     _blob_lifespan(pen, c)  per-blob lifespan (default: jittered global)
#     _pen_border_color(i, d) live border colour (e.g. turn it the winner's)
#     _draw_pen_extras(ov,i,r)anything drawn inside a pen — call super() first
#                             to keep the frequency bar
#
#  Everything visual is drawn by PenOverlay, which sits above the lab
#  background (z 1) and below the blobs (z 5).
#
#  TWO THINGS ARE NOW STANDARD ACROSS EVERY PEN:
#
#  1. SEPARATION IS AN AIR GAP, NOT A DRAWN WALL.
#     Pens used to be divided by a grey hatched slab. It looked like a piece
#     of scenery nobody could explain, and it competed with the pens for
#     attention. The physics walls are still there — blobs still can't cross
#     — but the space between pens is simply empty now. Empty space reads as
#     "these are separate" without needing a legend.
#
#  2. EVERY PEN DRAWS ITS OWN STACKED FREQUENCY BAR.
#     Parallel Worlds needed one because nine pens can't each have a panel.
#     It turned out to be the clearest read in the whole lab, so it's the
#     default here: one bar along the bottom inside edge of every pen, with
#     each colour's width equal to its share of that pen.
# ===========================================================================

# --- SUBCLASS CONFIG ---
var pen_caps: Array = []
var pen_start_mix: Array = []
var pen_titles: Array = []
var pen_accents: Array = []
var blob_spawn_scale: float = 0.075
var blob_mature_scale: float = 0.11
var pen_title_size: int = 15

# --- LAYOUT CONSTANTS ---
const EDGE_MARGIN := 16.0
const LABEL_STRIP := 30.0
const WALL_T := 24.0
const Z_OVERLAY := 1
const Z_BLOB := 5
const BAR_H := 9.0                # the stacked frequency bar inside each pen

# --- ARENA ---
var lab_rect: Rect2 = Rect2()
var pens: Array = []
var pen_overlay: PenOverlay = null
var arena_ready: bool = false

# --- PER-PEN BOOKKEEPING ---
var pen_start_counts: Array = []
var pen_start_totals: Array = []
var pen_resolved: Array = []

# --- PANEL WIDGETS THE SUBCLASS BUILDS (shown/hidden on start) ---
var ui_nodes: Array = []

# ===========================================================================
#  PEN OVERLAY
# ===========================================================================
class PenOverlay extends Node2D:
	var preset = null
	var pens: Array = []
	var titles: Array = []
	var accents: Array = []
	var title_size: int = 15
	var show_titles: bool = true

	func _draw():
		var font := ThemeDB.fallback_font

		for i in range(pens.size()):
			var r: Rect2 = pens[i]
			var col: Color = accents[i] if i < accents.size() else Color(0.6, 0.6, 0.7)
			if preset and preset.has_method("_pen_border_color"):
				col = preset._pen_border_color(i, col)

			# floor, then a single clean border
			draw_rect(r, Color(0.145, 0.148, 0.178, 1.0), true)
			draw_rect(r, Color(col.r, col.g, col.b, 0.9), false, 2.0)

			# name plate ABOVE the pen so no blob can ever cover it
			if show_titles and i < titles.size():
				var txt: String = titles[i]
				var tw: float = font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT,
					-1, title_size).x
				var chip := Rect2(r.position.x, r.position.y - title_size - 11.0,
					tw + 20.0, title_size + 9.0)
				var cs := StyleBoxFlat.new()
				cs.bg_color = Color(col.r, col.g, col.b, 0.16)
				cs.border_color = Color(col.r, col.g, col.b, 0.85)
				cs.set_border_width_all(1)
				cs.set_corner_radius_all(5)
				draw_style_box(cs, chip)
				draw_string(font, Vector2(chip.position.x + 10.0,
					chip.position.y + title_size + 1.0),
					txt, HORIZONTAL_ALIGNMENT_LEFT, -1, title_size,
					Color(col.r, col.g, col.b, 1.0))

			if preset and preset.has_method("_draw_pen_extras"):
				preset._draw_pen_extras(self, i, r)

		if preset and preset.has_method("_draw_overlay_extras"):
			preset._draw_overlay_extras(self)

# ---------------------------------------------------------------------------
#  SETUP
# ---------------------------------------------------------------------------
func _ready():
	p_max_pop = 9999               # real caps are enforced per pen
	super._ready()
	inspector_show_all_traits = false
	_hide_inherited_tracker()
	_setup_arena.call_deferred()

func _setup_arena():
	if arena_ready:
		return
	arena_ready = true
	_compute_lab_rect()
	pens = _layout_pens()
	pen_start_counts.clear()
	pen_start_totals.clear()
	pen_resolved.clear()
	for i in range(pens.size()):
		pen_start_counts.append([0, 0, 0])
		pen_start_totals.append(0)
		pen_resolved.append(false)
	_build_overlay()
	_build_pen_walls()

# The usable lab area is everything left of the side panel and below the
# read-out. Measured at runtime so it fills whatever the window gives us.
func _compute_lab_rect():
	var vp := get_viewport_rect().size
	var right: float = vp.x
	var panel = get_node_or_null("UIPanel")
	if panel and panel is Control:
		right = panel.global_position.x
	var top := 46.0
	var pop = get_node_or_null("PopLabel")
	if pop and pop is Control:
		top = pop.global_position.y + pop.size.y + 12.0
	lab_rect = Rect2(
		EDGE_MARGIN,
		top + LABEL_STRIP,
		max(200.0, right - EDGE_MARGIN * 2.0),
		max(200.0, vp.y - top - LABEL_STRIP - EDGE_MARGIN)
	)
	world_bounds = lab_rect
	if inspector:
		inspector.bounds = lab_rect

# Subclasses define the pen rectangles. Default: one pen filling the lab.
func _layout_pens() -> Array:
	return [lab_rect]

func _build_overlay():
	pen_overlay = PenOverlay.new()
	pen_overlay.preset = self
	pen_overlay.pens = pens
	pen_overlay.titles = pen_titles
	pen_overlay.accents = pen_accents
	pen_overlay.title_size = pen_title_size
	pen_overlay.z_index = Z_OVERLAY
	add_child(pen_overlay)
	pen_overlay.queue_redraw()

# A solid box of walls around every pen, so populations can't mix. These are
# invisible: the gap between two pens is what the user sees, and the walls
# are what actually stops a blob crossing it.
func _build_pen_walls():
	for r in pens:
		_wall(Vector2(r.position.x + r.size.x * 0.5, r.position.y - WALL_T * 0.5),
			Vector2(r.size.x + WALL_T * 2.0, WALL_T))
		_wall(Vector2(r.position.x + r.size.x * 0.5, r.end.y + WALL_T * 0.5),
			Vector2(r.size.x + WALL_T * 2.0, WALL_T))
		_wall(Vector2(r.position.x - WALL_T * 0.5, r.position.y + r.size.y * 0.5),
			Vector2(WALL_T, r.size.y))
		_wall(Vector2(r.end.x + WALL_T * 0.5, r.position.y + r.size.y * 0.5),
			Vector2(WALL_T, r.size.y))

func _wall(centre: Vector2, size: Vector2) -> StaticBody2D:
	var body := StaticBody2D.new()
	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	body.position = centre
	add_child(body)
	return body

func _hide_inherited_tracker():
	var ts = get_node_or_null("UIPanel/VBox/TrackerScroll")
	if ts:
		ts.visible = false

func _fit_tracker_height():
	pass

func _set_gated_visible(vis: bool):
	for p in gated_node_paths:
		var n = get_node_or_null(p)
		if n:
			n.visible = false
	_hide_playground_only_controls()
	if caption_box:
		caption_box.visible = vis
	for n in ui_nodes:
		if is_instance_valid(n):
			n.visible = vis

# ---------------------------------------------------------------------------
#  IN-PEN DRAWING
# ---------------------------------------------------------------------------
# Default extras for every pen: the stacked frequency bar. A subclass that
# wants more (tags, veils, highlights) overrides this and calls
# super._draw_pen_extras(ov, i, r) first so the bar survives.
func _draw_pen_extras(ov, i: int, r: Rect2):
	_draw_freq_bar(ov, i, r)

# One bar along the bottom inside edge of the pen. Each colour's width is its
# share of that pen right now, so the bar is a live pie chart laid flat — you
# read the whole population's makeup without counting blobs.
func _draw_freq_bar(ov, i: int, r: Rect2):
	if r.size.x < 24.0 or r.size.y < BAR_H + 12.0:
		return

	var counts: Array = _pen_counts(i)
	var total: int = 0
	for c in counts:
		total += int(c)

	var bar := Rect2(r.position.x + 4.0, r.end.y - BAR_H - 4.0,
		r.size.x - 8.0, BAR_H)
	ov.draw_rect(bar, Color(0.09, 0.09, 0.115), true)

	if total > 0:
		var x: float = bar.position.x
		for c in range(3):
			var seg_w: float = bar.size.x * (float(counts[c]) / float(total))
			if seg_w > 0.5:
				ov.draw_rect(Rect2(x, bar.position.y, seg_w, bar.size.y),
					preset_color_tints[c], true)
			x += seg_w

	ov.draw_rect(bar, Color(0.30, 0.31, 0.37), false, 1.0)

# ---------------------------------------------------------------------------
#  PEN MEMBERSHIP
# ---------------------------------------------------------------------------
# Which pen a blob belongs to. Tagged at birth; a subclass that allows
# migration overrides this (or keeps the tag updated) as blobs move.
func _pen_index_of(b) -> int:
	return b.get_meta("pen", -1)

func _pen_at(pos: Vector2) -> int:
	for i in range(pens.size()):
		if pens[i].grow(WALL_T * 0.5).has_point(pos):
			return i
	var best := 0
	var best_d: float = INF
	for i in range(pens.size()):
		var d: float = pos.distance_to(pens[i].get_center())
		if d < best_d:
			best_d = d
			best = i
	return best

func _pen_alive(i: int) -> Array:
	return blobs.filter(func(b):
		return is_instance_valid(b) and not b.is_dying and _pen_index_of(b) == i)

func _pen_counts(i: int) -> Array:
	var counts: Array = [0, 0, 0]
	for b in _pen_alive(i):
		counts[b.color_trait] += 1
	return counts

func _pen_colors_present(i: int) -> int:
	var n := 0
	for c in _pen_counts(i):
		if c > 0:
			n += 1
	return n

func _pen_winner(i: int) -> int:
	var counts := _pen_counts(i)
	for c in range(3):
		if counts[c] > 0 and _pen_colors_present(i) == 1:
			return c
	return -1

# How far a pen's composition shifted from its start, 0-100.
func _pen_drift(i: int) -> float:
	if i >= pen_start_totals.size() or pen_start_totals[i] == 0:
		return 0.0
	var end_counts := _pen_counts(i)
	var end_total: int = _pen_alive(i).size()
	if end_total == 0:
		return 100.0
	var sum := 0.0
	for c in range(3):
		var s: float = float(pen_start_counts[i][c]) / float(pen_start_totals[i]) * 100.0
		var e: float = float(end_counts[c]) / float(end_total) * 100.0
		sum += abs(e - s)
	return sum * 0.5

# ---------------------------------------------------------------------------
#  SPAWNING
# ---------------------------------------------------------------------------
func _spawn_all_pens():
	for i in range(pens.size()):
		var mix: Array = pen_start_mix[i] if i < pen_start_mix.size() else [3, 3, 3]
		var colors: Array = []
		for c in range(3):
			for k in range(int(mix[c])):
				colors.append(c)
		colors.shuffle()
		for c in colors:
			_spawn_in_pen(i, c)

func _spawn_in_pen(pen_idx: int, color_idx: int):
	var r: Rect2 = pens[pen_idx]
	var m: float = min(24.0, min(r.size.x, r.size.y) * 0.18)
	var blob = blob_scene.instantiate()
	add_child(blob)
	blob.global_position = Vector2(
		randf_range(r.position.x + m, r.end.x - m),
		randf_range(r.position.y + m, r.end.y - m)
	)
	_prepare_blob(blob, pen_idx)
	blob.setup(FIXED_SHAPE, color_idx, FIXED_EYES,
		[blob_tex_1, blob_tex_2, blob_tex_3], [eye_tex_1, eye_tex_2])
	blob.lifespan = _blob_lifespan(pen_idx, color_idx)
	blob.connect("reproduce", _on_blob_reproduce)
	blob.connect("tree_exited", _on_blob_removed.bind(blob))
	blobs.append(blob)

# Scale + tag + draw order. Must run BEFORE setup(), which applies
# spawn_scale to the node.
func _prepare_blob(blob, pen_idx: int):
	blob.spawn_scale = blob_spawn_scale
	blob.mature_scale = blob_mature_scale
	blob.z_index = Z_BLOB
	blob.set_meta("pen", pen_idx)

# Default: everyone gets the same jittered lifespan, so no allele is favoured.
# Drift vs Selection overrides this — deliberately.
func _blob_lifespan(_pen_idx: int, _color_idx: int) -> float:
	return _rolled_lifespan()

# Offspring join whichever pen they were born in, and each pen enforces its
# OWN cap.
func spawn_blob_from_parents(traits_a: Dictionary, traits_b: Dictionary, pos: Vector2):
	if pens.is_empty():
		return
	var pen_idx := _pen_at(pos)
	if _pen_alive(pen_idx).size() >= int(pen_caps[pen_idx]):
		return
	var r: Rect2 = pens[pen_idx]
	var blob = blob_scene.instantiate()
	add_child(blob)
	blob.global_position = Vector2(
		clamp(pos.x, r.position.x + 10.0, r.end.x - 10.0),
		clamp(pos.y, r.position.y + 10.0, r.end.y - 10.0)
	)
	_prepare_blob(blob, pen_idx)
	var child_color: int = traits_a["color_trait"] if randf() > 0.5 else traits_b["color_trait"]
	blob.setup(FIXED_SHAPE, child_color, FIXED_EYES,
		[blob_tex_1, blob_tex_2, blob_tex_3], [eye_tex_1, eye_tex_2])
	blob.lifespan = _blob_lifespan(pen_idx, child_color)
	blob.connect("reproduce", _on_blob_reproduce)
	blob.connect("tree_exited", _on_blob_removed.bind(blob))
	blobs.append(blob)
	births += 1
	if not simulation_running:
		blob.set_physics_process(false)

# ---------------------------------------------------------------------------
#  RUN CONTROL
# ---------------------------------------------------------------------------
func start_simulation():
	if blob_scene == null:
		push_error("MultiPen: Blob Scene is not assigned on the root node.")
		return
	_setup_arena()
	simulation_running = true
	sim_time = 0.0
	births = 0
	deaths = 0
	ended = false
	growth_done = false
	mid_caption_shown = false
	graph_sample_timer = 0.0
	_clear_inspection()
	for i in range(pens.size()):
		pen_resolved[i] = false

	_on_run_reset()
	_set_gated_visible(true)
	_spawn_all_pens()
	set_blobs_paused(false)
	update_tracker()

	for i in range(pens.size()):
		pen_start_counts[i] = _pen_counts(i)
		pen_start_totals[i] = _pen_alive(i).size()

	_set_caption(_opening_caption())

# Hook for subclasses to clear their own per-run state.
func _on_run_reset():
	pass

func _opening_caption() -> String:
	return "Growing up. Every pen starts from the same mix — no color is favoured anywhere."

func _process(delta):
	super._process(delta)
	if pen_overlay and simulation_running:
		pen_overlay.queue_redraw()
