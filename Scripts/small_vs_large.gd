extends DriftPreset

# ===========================================================================
#  PRESET: SMALL vs LARGE
#
#  Two isolated populations run at the same time from identical starting
#  frequencies (33/33/33). The only difference between them is SIZE.
#
#    LEFT  pen = SMALL  (9 blobs)
#    RIGHT pen = LARGE  (27 blobs)
#
#  THE LESSON: drift strength scales as 1/N. The small population swings
#  wildly and usually fixes within a couple of minutes; the large one barely
#  budges. Running them side by side means the contrast does the teaching.
#
#  WHY THE PENS ARE DIFFERENT SIZES:
#  Each pen's AREA is proportional to its population, so both have the SAME
#  density of blobs. With equal-sized pens the large population would have
#  far more encounters per individual and breed faster, which would confound
#  the experiment. Matching density isolates population size as the only
#  variable.
#
#  The small pen is made SHORTER as well as narrower, rather than a tall
#  slim corridor — same area either way, but the squarer shape gives the
#  blobs room to actually move around.
#
#  WHAT CHANGED IN THE OVERLAY:
#  The pens used to be split by a grey hatched slab. It read as a piece of
#  unexplained scenery, so it's gone — the pens are now separated by a plain
#  air gap. The walls that stop blobs crossing are still there, just
#  invisible, which is how every other preset already worked.
#  Each pen also draws a stacked frequency bar along its bottom edge, the
#  same one Parallel Worlds uses, so a glance tells you each pen's makeup
#  without reading the side panel.
#
#  SETUP:
#    1. Open CoinFlip.tscn -> Scene -> "Save Scene As..." -> SmallVsLarge.tscn
#    2. Select the ROOT node of the NEW scene (check the tab!)
#    3. Clear coin_flip.gd, attach small_vs_large.gd.
#    4. Confirm Blob Scene + the 5 textures are assigned. Save at once.
# ===========================================================================

# --- POPULATION SIZES (both divisible by 3 -> both start at exactly 33/33/33) ---
const POP_SIZES := [9, 27]         # starting blobs
# Caps sit above the starting counts, keeping the same 1:3 ratio. If a pen
# starts full, no baby can be born until somebody dies — a whole lifespan of
# nothing happening right after the blobs mature. The headroom means births
# begin the moment everyone is an adult.
const POP_CAPS := [12, 36]
const POP_NAMES := ["Small", "Large"]

# --- LAYOUT ---
const PEN_GAP := 18.0          # plain empty space between the pens
const WALL_T := 24.0           # physics wall thickness (invisible)
const EDGE_MARGIN := 16.0      # gap from the lab edge
const LABEL_STRIP := 34.0      # room above the pens for their name plates
const SMALL_WIDTH_FRAC := 0.34 # how much of the usable width the small pen gets
const BAR_H := 9.0             # stacked frequency bar inside each pen

# Blobs are shrunk from the usual 0.10/0.15 so both pens stay uncrowded.
const BLOB_SPAWN_SCALE := 0.075
const BLOB_MATURE_SCALE := 0.11

# --- DRAW ORDER ---
# The lab background is a UI node at z 0. The overlay sits above it, the
# blobs above that.
const Z_OVERLAY := 1
const Z_BLOB := 5

# --- ARENA ---
var lab_rect: Rect2 = Rect2()
var regions: Array = []          # [Rect2 small, Rect2 large]
var overlay: RegionOverlay = null
var arena_ready: bool = false

# --- PER-POPULATION STATE ---
var pop_start_counts: Array = [[0, 0, 0], [0, 0, 0]]
var pop_start_totals: Array = [0, 0]
var pop_resolved: Array = [false, false]
var pop_fixed_announced: Array = [false, false]
var first_fix_caption_shown: bool = false

# --- PER-POPULATION UI ---
var pop_graphs: Array = []
var pop_bar_fills: Array = []
var pop_bar_labels: Array = []
var dual_ui_nodes: Array = []

const ACCENTS := [Color(0.95, 0.72, 0.35), Color(0.45, 0.72, 0.98)]
const TRACK_W := 96.0
const TRACK_H := 15.0
const MINI_GRAPH_H := 84.0

# ===========================================================================
#  REGION OVERLAY
#  Draws the two pens: floor, border, name plate above, and the stacked
#  frequency bar along the bottom inside edge. Nothing is drawn between the
#  pens — the empty space is what says "these two can't reach each other".
# ===========================================================================
class RegionOverlay extends Node2D:
	var preset = null
	var regions: Array = []
	var titles: Array = []
	var accents: Array = []
	var bar_height: float = 9.0

	func _draw():
		if regions.size() < 2:
			return
		var font := ThemeDB.fallback_font

		for i in range(2):
			var r: Rect2 = regions[i]
			var col: Color = accents[i]

			# pen floor, then one clean border
			draw_rect(r, Color(0.145, 0.148, 0.178, 1.0), true)
			draw_rect(r, Color(col.r, col.g, col.b, 0.9), false, 2.0)

			# name plate sits ABOVE the pen so no blob can ever cover it
			var txt: String = titles[i]
			var tw: float = font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
			var chip := Rect2(r.position.x, r.position.y - 30.0, tw + 24.0, 25.0)
			var cs := StyleBoxFlat.new()
			cs.bg_color = Color(col.r, col.g, col.b, 0.16)
			cs.border_color = Color(col.r, col.g, col.b, 0.85)
			cs.set_border_width_all(1)
			cs.set_corner_radius_all(6)
			draw_style_box(cs, chip)
			draw_string(font, Vector2(chip.position.x + 12.0, chip.position.y + 18.0),
				txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(col.r, col.g, col.b, 1.0))

			_draw_freq_bar(i, r)

	# Each colour's width is its share of that pen right now — a live pie
	# chart laid flat. Identical to the bar MultiPen draws, so the two
	# families of preset read the same way.
	func _draw_freq_bar(i: int, r: Rect2):
		if preset == null or r.size.x < 24.0:
			return
		var counts: Array = preset._pop_counts(i)
		var total: int = 0
		for c in counts:
			total += int(c)

		var bar := Rect2(r.position.x + 4.0, r.end.y - bar_height - 4.0,
			r.size.x - 8.0, bar_height)
		draw_rect(bar, Color(0.09, 0.09, 0.115), true)

		if total > 0:
			var x: float = bar.position.x
			for c in range(3):
				var seg_w: float = bar.size.x * (float(counts[c]) / float(total))
				if seg_w > 0.5:
					draw_rect(Rect2(x, bar.position.y, seg_w, bar.size.y),
						preset.preset_color_tints[c], true)
				x += seg_w

		draw_rect(bar, Color(0.30, 0.31, 0.37), false, 1.0)

# ---------------------------------------------------------------------------
#  SETUP
# ---------------------------------------------------------------------------
func _ready():
	p_start_mix = [3, 3, 3]        # unused (we spawn per pen) but kept sane
	p_max_pop = 9999               # real caps are enforced per population
	p_lifespan = 34.0
	p_time_cap = 165.0
	p_speed_index = 3
	super._ready()
	inspector_show_all_traits = false
	_hide_inherited_tracker()
	# Deferred so the UI panel has been laid out and we can measure the
	# real lab area from it.
	_setup_arena.call_deferred()

func _setup_arena():
	if arena_ready:
		return
	arena_ready = true
	_compute_lab_rect()
	_compute_regions()
	_build_overlay()
	_build_region_walls()

# The usable lab area is everything left of the side panel and below the
# population read-out. Measured at runtime instead of hard-coded, so it fills
# whatever space the window actually gives us.
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

# Areas are proportional to population (equal density). The small pen takes a
# fixed share of the WIDTH and then gets whatever HEIGHT makes its area come
# out right — which keeps it a comfortable box rather than a slim corridor.
func _compute_regions():
	var usable_w: float = lab_rect.size.x - PEN_GAP
	var w_small: float = usable_w * SMALL_WIDTH_FRAC
	var w_large: float = usable_w - w_small
	var h: float = lab_rect.size.y

	var area_large: float = w_large * h
	var area_small: float = area_large * (float(POP_CAPS[0]) / float(POP_CAPS[1]))
	var h_small: float = min(h, area_small / w_small)

	regions = [
		Rect2(lab_rect.position.x, lab_rect.position.y + (h - h_small) * 0.5,
			w_small, h_small),
		Rect2(lab_rect.position.x + w_small + PEN_GAP, lab_rect.position.y,
			w_large, h),
	]

func _build_overlay():
	overlay = RegionOverlay.new()
	overlay.preset = self
	overlay.regions = regions
	overlay.accents = ACCENTS
	overlay.bar_height = BAR_H
	overlay.titles = [
		"SMALL — up to %d blobs" % POP_CAPS[0],
		"LARGE — up to %d blobs" % POP_CAPS[1],
	]
	overlay.z_index = Z_OVERLAY
	add_child(overlay)
	overlay.queue_redraw()

# Solid walls around BOTH pens keep the populations genuinely isolated —
# no blob can cross the gap, so they can never interbreed. The walls are
# invisible; the empty space between the pens is the visual cue.
func _build_region_walls():
	for r in regions:
		_wall(Vector2(r.position.x + r.size.x * 0.5, r.position.y - WALL_T * 0.5),
			Vector2(r.size.x + WALL_T * 2.0, WALL_T))                       # top
		_wall(Vector2(r.position.x + r.size.x * 0.5, r.end.y + WALL_T * 0.5),
			Vector2(r.size.x + WALL_T * 2.0, WALL_T))                       # bottom
		_wall(Vector2(r.position.x - WALL_T * 0.5, r.position.y + r.size.y * 0.5),
			Vector2(WALL_T, r.size.y))                                      # left
		_wall(Vector2(r.end.x + WALL_T * 0.5, r.position.y + r.size.y * 0.5),
			Vector2(WALL_T, r.size.y))                                      # right

func _wall(centre: Vector2, size: Vector2):
	var body := StaticBody2D.new()
	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	body.position = centre
	add_child(body)

func _hide_inherited_tracker():
	var ts = get_node_or_null("UIPanel/VBox/TrackerScroll")
	if ts:
		ts.visible = false

func _fit_tracker_height():
	pass   # the inherited tracker isn't used here

# The pen bars are live, so the overlay has to be redrawn as the run goes.
func _process(delta):
	super._process(delta)
	if overlay and simulation_running:
		overlay.queue_redraw()

# ---------------------------------------------------------------------------
#  SCENARIO TEXT
# ---------------------------------------------------------------------------
func _preset_title() -> String:
	return "Small vs Large"

func _preset_intro_bbcode() -> String:
	return "Two separate populations, running at the same time in [b]walled-off pens[/b] so they can never interbreed.\n\n•  [b]Left pen — up to 12 blobs[/b]\n•  [b]Right pen — up to 36 blobs[/b]\n\nBoth start at exactly the same frequencies: [b]one third red, one third green, one third blue[/b]. Nothing favours any color in either pen.\n\nThe pens are different sizes on purpose — each one's area is scaled to its population, so the blobs are equally crowded in both. That way the [b]only[/b] difference between the two experiments is how many individuals there are.\n\nEach pen has a [b]stacked bar along its bottom edge[/b] showing its colour makeup right now, and its own graph in the side panel."

func _preset_questions() -> Array:
	return [
		"Which pen reaches a single color first — the small one or the large one?",
		"In which pen is the winning color easier to predict in advance?",
		"Both pens use identical rules and identical odds. So why should size change anything at all?",
	]

# ---------------------------------------------------------------------------
#  SIDE PANEL — two mini trackers, each with its own graph
# ---------------------------------------------------------------------------
func _build_graph():
	var vbox = get_node_or_null("UIPanel/VBox")
	if not vbox:
		return

	pop_graphs.clear()
	pop_bar_fills.clear()
	pop_bar_labels.clear()
	dual_ui_nodes.clear()

	for i in range(2):
		if i == 1:
			var sep := HSeparator.new()
			vbox.add_child(sep)
			dual_ui_nodes.append(sep)

		var head := Label.new()
		head.text = "%s pen — up to %d" % [POP_NAMES[i], POP_CAPS[i]]
		head.add_theme_font_size_override("font_size", 15)
		head.add_theme_color_override("font_color", ACCENTS[i])
		vbox.add_child(head)
		dual_ui_nodes.append(head)

		var fills: Array = []
		var labels: Array = []
		var bars := VBoxContainer.new()
		bars.add_theme_constant_override("separation", 4)
		vbox.add_child(bars)
		dual_ui_nodes.append(bars)

		for c in range(3):
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 7)
			bars.add_child(row)

			var swatch := ColorRect.new()
			swatch.color = preset_color_tints[c]
			swatch.custom_minimum_size = Vector2(11, TRACK_H)
			row.add_child(swatch)

			var track := ColorRect.new()
			track.color = Color(0.20, 0.20, 0.25)
			track.custom_minimum_size = Vector2(TRACK_W, TRACK_H)
			row.add_child(track)

			var fill := ColorRect.new()
			fill.color = preset_color_tints[c]
			fill.position = Vector2.ZERO
			fill.size = Vector2(0, TRACK_H)
			track.add_child(fill)
			fills.append(fill)

			var lbl := Label.new()
			lbl.text = "33% (0)"
			lbl.add_theme_font_size_override("font_size", 13)
			lbl.custom_minimum_size = Vector2(74, 0)
			row.add_child(lbl)
			labels.append(lbl)

		pop_bar_fills.append(fills)
		pop_bar_labels.append(labels)

		var g = DriftPreset.FreqGraph.new()
		g.maturity_time = MATURATION_TIME
		g.custom_minimum_size = Vector2(0, MINI_GRAPH_H)
		g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vbox.add_child(g)
		pop_graphs.append(g)
		dual_ui_nodes.append(g)

	for n in dual_ui_nodes:
		n.visible = false

func _set_gated_visible(vis: bool):
	for p in gated_node_paths:
		var n = get_node_or_null(p)
		if n:
			n.visible = false      # commands + inherited tracker stay hidden
	_hide_playground_only_controls()
	if caption_box:
		caption_box.visible = vis
	for n in dual_ui_nodes:
		if is_instance_valid(n):
			n.visible = vis

# ---------------------------------------------------------------------------
#  POPULATION HELPERS
# ---------------------------------------------------------------------------
func _pop_alive(i: int) -> Array:
	return blobs.filter(func(b):
		return is_instance_valid(b) and not b.is_dying and b.get_meta("pop", -1) == i)

func _pop_counts(i: int) -> Array:
	var counts: Array = [0, 0, 0]
	for b in _pop_alive(i):
		counts[b.color_trait] += 1
	return counts

func _pop_colors_present(i: int) -> int:
	var n := 0
	for c in _pop_counts(i):
		if c > 0:
			n += 1
	return n

func _region_of(pos: Vector2) -> int:
	if regions.size() < 2:
		return 0
	for i in range(regions.size()):
		if regions[i].grow(WALL_T).has_point(pos):
			return i
	var d0: float = pos.distance_to(regions[0].get_center())
	var d1: float = pos.distance_to(regions[1].get_center())
	return 0 if d0 < d1 else 1

# ---------------------------------------------------------------------------
#  RUN CONTROL
# ---------------------------------------------------------------------------
func start_simulation():
	if blob_scene == null:
		push_error("SmallVsLarge: Blob Scene is not assigned on the root node.")
		return
	_setup_arena()   # no-op if already done; guarantees regions exist
	simulation_running = true
	sim_time = 0.0
	births = 0
	deaths = 0
	ended = false
	growth_done = false
	mid_caption_shown = false
	first_fix_caption_shown = false
	pop_resolved = [false, false]
	pop_fixed_announced = [false, false]
	graph_sample_timer = 0.0
	_clear_inspection()

	for g in pop_graphs:
		g.clear_samples()

	_set_gated_visible(true)
	_spawn_both_populations()
	set_blobs_paused(false)
	update_tracker()

	for i in range(2):
		pop_start_counts[i] = _pop_counts(i)
		pop_start_totals[i] = _pop_alive(i).size()

	_set_caption("Growing up. Both pens start at 33/33/33 — no color is favoured in either one.")

func _spawn_both_populations():
	for i in range(2):
		var per_color: int = POP_SIZES[i] / 3
		var colors: Array = []
		for c in range(3):
			for k in range(per_color):
				colors.append(c)
		colors.shuffle()
		for c in colors:
			_spawn_in_region(i, c)

func _spawn_in_region(pop_idx: int, color_idx: int):
	var r: Rect2 = regions[pop_idx]
	var m := 24.0
	var blob = blob_scene.instantiate()
	add_child(blob)
	blob.global_position = Vector2(
		randf_range(r.position.x + m, r.end.x - m),
		randf_range(r.position.y + m, r.end.y - m)
	)
	_prepare_blob(blob, pop_idx)
	blob.setup(FIXED_SHAPE, color_idx, FIXED_EYES,
		[blob_tex_1, blob_tex_2, blob_tex_3], [eye_tex_1, eye_tex_2])
	blob.lifespan = _rolled_lifespan()
	blob.connect("reproduce", _on_blob_reproduce)
	blob.connect("tree_exited", _on_blob_removed.bind(blob))
	blobs.append(blob)

# Shrink + tag + lift above the pen overlay.
# Must run BEFORE setup(), which applies spawn_scale to the node.
func _prepare_blob(blob, pop_idx: int):
	blob.spawn_scale = BLOB_SPAWN_SCALE
	blob.mature_scale = BLOB_MATURE_SCALE
	blob.z_index = Z_BLOB
	blob.set_meta("pop", pop_idx)

# Offspring belong to whichever pen they were born in, and each population
# enforces its OWN cap. That cap is what makes this experiment work.
func spawn_blob_from_parents(traits_a: Dictionary, traits_b: Dictionary, pos: Vector2):
	var pop_idx := _region_of(pos)
	if _pop_alive(pop_idx).size() >= POP_CAPS[pop_idx]:
		return
	var r: Rect2 = regions[pop_idx]
	var blob = blob_scene.instantiate()
	add_child(blob)
	blob.global_position = Vector2(
		clamp(pos.x, r.position.x + 12.0, r.end.x - 12.0),
		clamp(pos.y, r.position.y + 12.0, r.end.y - 12.0)
	)
	_prepare_blob(blob, pop_idx)
	var child_color: int = traits_a["color_trait"] if randf() > 0.5 else traits_b["color_trait"]
	blob.setup(FIXED_SHAPE, child_color, FIXED_EYES,
		[blob_tex_1, blob_tex_2, blob_tex_3], [eye_tex_1, eye_tex_2])
	blob.lifespan = _rolled_lifespan()
	blob.connect("reproduce", _on_blob_reproduce)
	blob.connect("tree_exited", _on_blob_removed.bind(blob))
	blobs.append(blob)
	births += 1
	if not simulation_running:
		blob.set_physics_process(false)

# ---------------------------------------------------------------------------
#  LIVE DISPLAY
# ---------------------------------------------------------------------------
func _update_pop_label():
	var pop_label = get_node_or_null("PopLabel")
	if not pop_label:
		return
	var mins = int(sim_time) / 60
	var secs = int(sim_time) % 60
	pop_label.text = "Small: %d / %d     Large: %d / %d     Time: %d:%02d" % [
		_pop_alive(0).size(), POP_CAPS[0],
		_pop_alive(1).size(), POP_CAPS[1],
		mins, secs
	]

func update_tracker():
	for i in range(2):
		if i >= pop_bar_fills.size():
			continue
		var counts := _pop_counts(i)
		var total := 0
		for c in counts:
			total += c
		var lead := 0
		for c in range(3):
			if counts[c] > counts[lead]:
				lead = c
		for c in range(3):
			var pct := 0.0
			if total > 0:
				pct = float(counts[c]) / float(total)
			pop_bar_fills[i][c].size = Vector2(pct * TRACK_W, TRACK_H)
			var lbl: Label = pop_bar_labels[i][c]
			lbl.text = "%d%% (%d)" % [int(round(pct * 100)), counts[c]]
			lbl.add_theme_color_override("font_color",
				Color(1.0, 0.85, 0.2) if (total > 0 and c == lead and counts[c] > 0)
				else Color(0.86, 0.86, 0.90))

func _sample_graph(delta):
	if pop_graphs.is_empty():
		return
	graph_sample_timer += delta
	if graph_sample_timer < GRAPH_SAMPLE_INTERVAL:
		return
	graph_sample_timer = 0.0
	for i in range(2):
		var counts := _pop_counts(i)
		var total: int = _pop_alive(i).size()
		var pcts: Array = [0.0, 0.0, 0.0]
		if total > 0:
			for c in range(3):
				pcts[c] = float(counts[c]) / float(total) * 100.0
		pop_graphs[i].add_sample(sim_time, pcts)

# ---------------------------------------------------------------------------
#  NARRATION
# ---------------------------------------------------------------------------
func _check_captions():
	if not growth_done:
		return

	for i in range(2):
		var alive_n: int = _pop_alive(i).size()
		var present: int = _pop_colors_present(i)
		if alive_n == 0 and not pop_fixed_announced[i]:
			pop_fixed_announced[i] = true
			pop_resolved[i] = true
			_set_caption("The %s pen died out entirely. Small populations aren't just unstable — they can vanish." % POP_NAMES[i].to_lower())
			return
		if present == 1 and not pop_fixed_announced[i]:
			pop_fixed_announced[i] = true
			pop_resolved[i] = true
			var other: int = 1 - i
			if not first_fix_caption_shown:
				first_fix_caption_shown = true
				_set_caption("The %s pen is FIXED — one color, everything else gone.\n\nNow look at the %s pen. Same rules, same odds, barely moved." % [
					POP_NAMES[i].to_lower(), POP_NAMES[other].to_lower()])
			else:
				_set_caption("The %s pen has fixed too — it just took far longer." % POP_NAMES[i].to_lower())
			return

	if not mid_caption_shown and sim_time > MATURATION_TIME + 16.0:
		mid_caption_shown = true
		_set_caption("Compare the two bottom bars. The small pen's slides around; the large pen's barely moves off thirds.")

# ---------------------------------------------------------------------------
#  END CONDITIONS
# ---------------------------------------------------------------------------
func _check_end():
	for i in range(2):
		if _pop_alive(i).size() == 0 or _pop_colors_present(i) <= 1:
			pop_resolved[i] = true

	if (pop_resolved[0] and pop_resolved[1]) or sim_time >= p_time_cap:
		_finish(_dual_summary())

func _dual_summary() -> String:
	var d_small: float = _drift_distance(0)
	var d_large: float = _drift_distance(1)
	var s_state := _pop_state_text(0)
	var l_state := _pop_state_text(1)

	var head := "[b]The small pen moved %.0f%%. The large pen moved %.0f%%.[/b]" % [d_small, d_large]
	if d_small <= d_large:
		head = "[b]This time the small pen moved %.0f%% and the large pen %.0f%%.[/b]\n\nThat's the exception, not the rule — drift is random, so any single run can surprise you. Run it again and the usual pattern should show." % [d_small, d_large]

	return "%s\n\nBoth pens started identical: a third of each color, no color favoured, same crowding. The only difference was [b]how many blobs there were[/b].\n\n•  Small (%d): %s\n•  Large (%d): %s\n\nDrift strength scales as [b]1 ÷ population size[/b]. In a small population a few chance births and deaths swing the percentages hard. In a large one those same accidents average out, so the frequencies stay put.\n\nThis is why small, isolated populations lose genetic diversity fast — and why it's one of the first things conservation biologists worry about." % [
		head, POP_CAPS[0], s_state, POP_CAPS[1], l_state]

func _pop_state_text(i: int) -> String:
	var alive_n: int = _pop_alive(i).size()
	if alive_n == 0:
		return "died out completely"
	var present: int = _pop_colors_present(i)
	if present == 1:
		var counts := _pop_counts(i)
		for c in range(3):
			if counts[c] > 0:
				return "%s reached 100%% — fixed" % preset_color_names[c]
	return "still has %d colors" % present

# How far the composition shifted from its starting point, 0-100.
# Half the total absolute change, so a complete turnover reads as 100.
func _drift_distance(i: int) -> float:
	if pop_start_totals[i] == 0:
		return 0.0
	var end_counts := _pop_counts(i)
	var end_total: int = _pop_alive(i).size()
	if end_total == 0:
		return 100.0
	var sum := 0.0
	for c in range(3):
		var s: float = float(pop_start_counts[i][c]) / float(pop_start_totals[i]) * 100.0
		var e: float = float(end_counts[c]) / float(end_total) * 100.0
		sum += abs(e - s)
	return sum * 0.5

# ---------------------------------------------------------------------------
#  RESULTS CARD — side-by-side comparison of both pens
# ---------------------------------------------------------------------------
func _build_comparison():
	for child in compare_box.get_children():
		child.queue_free()

	for i in range(2):
		var head := Label.new()
		head.text = "%s pen (up to %d blobs)" % [POP_NAMES[i], POP_CAPS[i]]
		head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		head.add_theme_font_size_override("font_size", 15)
		head.add_theme_color_override("font_color", ACCENTS[i])
		compare_box.add_child(head)

		var end_counts := _pop_counts(i)
		var end_total: int = _pop_alive(i).size()

		for c in range(3):
			var s_pct := 0
			var e_pct := 0
			if pop_start_totals[i] > 0:
				s_pct = int(round(float(pop_start_counts[i][c]) / float(pop_start_totals[i]) * 100.0))
			if end_total > 0:
				e_pct = int(round(float(end_counts[c]) / float(end_total) * 100.0))

			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 10)
			row.alignment = BoxContainer.ALIGNMENT_CENTER
			compare_box.add_child(row)

			var swatch := ColorRect.new()
			swatch.color = preset_color_tints[c]
			swatch.custom_minimum_size = Vector2(15, 15)
			var sw := CenterContainer.new()
			sw.custom_minimum_size = Vector2(24, 0)
			sw.add_child(swatch)
			row.add_child(sw)

			var name_lbl := Label.new()
			name_lbl.text = preset_color_names[c]
			name_lbl.custom_minimum_size = Vector2(64, 0)
			name_lbl.add_theme_font_size_override("font_size", 15)
			row.add_child(name_lbl)

			var arrow := "─"
			var col := Color(0.80, 0.80, 0.84)
			if e_pct > s_pct:
				arrow = "▲"
				col = Color(0.45, 0.95, 0.5)
			elif e_pct < s_pct:
				arrow = "▼"
				col = Color(1.0, 0.45, 0.45)

			var val := Label.new()
			val.text = "%d%%   →   %d%%   %s" % [s_pct, e_pct, arrow]
			val.add_theme_font_size_override("font_size", 15)
			val.add_theme_color_override("font_color", col)
			row.add_child(val)

		var dist := Label.new()
		var d: float = _drift_distance(i)
		dist.text = "Total drift: %.0f%%" % d
		dist.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		dist.add_theme_font_size_override("font_size", 16)
		dist.add_theme_color_override("font_color",
			Color(1.0, 0.62, 0.42) if d >= 25.0 else Color(0.55, 0.88, 0.62))
		compare_box.add_child(dist)

		if i == 0:
			compare_box.add_child(HSeparator.new())
