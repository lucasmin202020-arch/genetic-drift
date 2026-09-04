extends DriftEvent

# ===========================================================================
#  EVENT: FOUNDER EFFECT  (v2.1)
#
#  A founder event and a bottleneck produce populations that look identical.
#  The one thing that distinguishes them: in a founding event THE ORIGINAL
#  POPULATION IS STILL THERE. Nobody died. A few individuals left and started
#  somewhere new, and the source carries on — which gives you a live control
#  group to compare the new population against.
#
#      MAINLAND   large pen, fills to 24, keeps running the whole time
#      ISLAND     smaller pen, starts EMPTY
#
#  When you send founders, a few randomly chosen mainland blobs cross. The
#  mainland doesn't notice. The island's mix is a small random SAMPLE of the
#  mainland's, and the moment they land the two bars disagree — mainland
#  33/33/33, island 50/0/50. That instant is the entire founder effect.
#
#  FOUNDERS ARE CHOSEN AT RANDOM, NOT BY YOU. Hand-picking would be
#  artificial selection, which breaks the rule this project is built on. The
#  slider sets HOW MANY, never WHICH.
#
#  This is the one event that stays single-shot (REPEAT_NONE). A second wave
#  of founders would be migration, which is Gene Flow's lesson, not this one.
#
#  SETUP:
#    1. Open Game.tscn -> Scene -> "Save Scene As..." -> FounderEffect.tscn
#    2. Select the ROOT node "Game" — not the background sprite
#    3. Clear game.gd, attach founder_effect.gd.
#    4. Confirm Blob Scene + the 5 textures are assigned. Save at once.
# ===========================================================================

const MAINLAND_START := 24
const CAPS := [24, 12]             # [mainland, island]
const NAMES := ["Mainland", "Island"]
const ACCENTS := [Color(0.55, 0.78, 0.60), Color(0.95, 0.72, 0.35)]

const MIN_FOUNDERS := 2
const MAX_FOUNDERS := 6
const DEFAULT_FOUNDERS := 4

# --- LAYOUT ---
const PEN_GAP := 40.0              # wider than usual: this gap is an ocean
const MAINLAND_FRAC := 0.62
const WALL_T := 24.0
const LABEL_STRIP := 34.0
const BAR_H := 9.0
const Z_OVERLAY := 1
const Z_BLOB := 5

const BLOB_SPAWN_SCALE := 0.075
const BLOB_MATURE_SCALE := 0.11

# --- ARENA ---  (lab_rect is inherited from DriftEvent)
var regions: Array = []
var overlay: RegionOverlay = null
var arena_ready: bool = false

# --- FOUNDING ---
var founders_wanted: int = DEFAULT_FOUNDERS
var founded: bool = false
var founded_at: float = -1.0
var founder_counts: Array = [0, 0, 0]
var mainland_at_founding: Array = [0, 0, 0]

var sl_founders: HSlider
var lbl_founders: Label
var lbl_split: Label

# ===========================================================================
#  REGION OVERLAY — two pens, each with the standard frequency bar
# ===========================================================================
class RegionOverlay extends Node2D:
	var preset = null
	var regions: Array = []
	var titles: Array = []
	var accents: Array = []
	var bar_height: float = 9.0

	func _draw():
		if regions.size() < 2 or preset == null:
			return
		var font := ThemeDB.fallback_font

		for i in range(2):
			var r: Rect2 = regions[i]
			var col: Color = accents[i]

			draw_rect(r, Color(0.145, 0.148, 0.178, 1.0), true)
			draw_rect(r, Color(col.r, col.g, col.b, 0.9), false, 2.0)

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

			if i == 1 and preset._region_alive(1).size() == 0:
				var msg := "empty — nobody has crossed yet"
				var mw: float = font.get_string_size(msg, HORIZONTAL_ALIGNMENT_LEFT,
					-1, 14).x
				draw_string(font,
					Vector2(r.position.x + r.size.x * 0.5 - mw * 0.5,
						r.position.y + r.size.y * 0.5),
					msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.50, 0.50, 0.58))

	func _draw_freq_bar(i: int, r: Rect2):
		if r.size.x < 24.0:
			return
		var counts: Array = preset._region_counts(i)
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
	p_start_mix = [8, 8, 8]
	p_max_pop = 9999               # caps are enforced per region
	p_lifespan = 80.0
	p_time_cap = 240.0
	p_speed_index = 3
	super._ready()
	inspector_show_all_traits = false

# The pens draw their own bars; the base's whole-lab bar would sit across both.
func _show_lab_bar() -> bool:
	return false

# The base defers this once the panel is laid out. Two pens instead of one.
func _setup_lab():
	_setup_arena()

func _setup_arena():
	if arena_ready:
		return
	arena_ready = true
	_compute_lab_rect()
	_compute_regions()
	_build_overlay()
	_build_region_walls()

func _compute_lab_rect():
	lab_rect = _measure_lab_rect(LABEL_STRIP)
	world_bounds = lab_rect
	if inspector:
		inspector.bounds = lab_rect

# The island is smaller because it holds fewer blobs — same crowding on both
# sides, so the island isn't drifting faster merely because it's cramped.
func _compute_regions():
	var usable_w: float = lab_rect.size.x - PEN_GAP
	var w_main: float = usable_w * MAINLAND_FRAC
	var w_isle: float = usable_w - w_main
	var h: float = lab_rect.size.y

	var area_main: float = w_main * h
	var area_isle: float = area_main * (float(CAPS[1]) / float(CAPS[0]))
	var h_isle: float = min(h, area_isle / w_isle)

	regions = [
		Rect2(lab_rect.position.x, lab_rect.position.y, w_main, h),
		Rect2(lab_rect.position.x + w_main + PEN_GAP,
			lab_rect.position.y + (h - h_isle) * 0.5, w_isle, h_isle),
	]

func _build_overlay():
	overlay = RegionOverlay.new()
	overlay.preset = self
	overlay.regions = regions
	overlay.accents = ACCENTS
	overlay.bar_height = BAR_H
	overlay.titles = ["MAINLAND — up to %d" % CAPS[0], "ISLAND — up to %d" % CAPS[1]]
	overlay.z_index = Z_OVERLAY
	add_child(overlay)
	overlay.queue_redraw()

func _build_region_walls():
	for r in regions:
		_wall(Vector2(r.position.x + r.size.x * 0.5, r.position.y - WALL_T * 0.5),
			Vector2(r.size.x + WALL_T * 2.0, WALL_T))
		_wall(Vector2(r.position.x + r.size.x * 0.5, r.end.y + WALL_T * 0.5),
			Vector2(r.size.x + WALL_T * 2.0, WALL_T))
		_wall(Vector2(r.position.x - WALL_T * 0.5, r.position.y + r.size.y * 0.5),
			Vector2(WALL_T, r.size.y))
		_wall(Vector2(r.end.x + WALL_T * 0.5, r.position.y + r.size.y * 0.5),
			Vector2(WALL_T, r.size.y))

func _wall(centre: Vector2, size: Vector2):
	var body := StaticBody2D.new()
	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	body.position = centre
	add_child(body)

func _process(delta):
	super._process(delta)
	if overlay and simulation_running:
		overlay.queue_redraw()

# ---------------------------------------------------------------------------
#  REGION HELPERS
# ---------------------------------------------------------------------------
func _region_alive(i: int) -> Array:
	return blobs.filter(func(b):
		return is_instance_valid(b) and not b.is_dying and b.get_meta("pop", 0) == i)

func _region_counts(i: int) -> Array:
	var counts: Array = [0, 0, 0]
	for b in _region_alive(i):
		counts[b.color_trait] += 1
	return counts

func _region_colors(i: int) -> int:
	var n := 0
	for c in _region_counts(i):
		if c > 0:
			n += 1
	return n

func _region_of(pos: Vector2) -> int:
	for i in range(regions.size()):
		if regions[i].grow(WALL_T).has_point(pos):
			return i
	return 0

# ---------------------------------------------------------------------------
#  SPAWNING — everything starts on the mainland
# ---------------------------------------------------------------------------
func _spawn_preset_population():
	_setup_arena()
	var colors: Array = []
	for c in range(3):
		for i in range(int(p_start_mix[c])):
			colors.append(c)
	colors.shuffle()
	for c in colors:
		_spawn_in_region(0, c)

func _spawn_in_region(region_idx: int, color_idx: int):
	var r: Rect2 = regions[region_idx]
	var m: float = min(24.0, min(r.size.x, r.size.y) * 0.18)
	var blob = blob_scene.instantiate()
	add_child(blob)
	blob.global_position = Vector2(
		randf_range(r.position.x + m, r.end.x - m),
		randf_range(r.position.y + m, r.end.y - m))
	_prepare_blob(blob, region_idx)
	blob.setup(FIXED_SHAPE, color_idx, FIXED_EYES,
		[blob_tex_1, blob_tex_2, blob_tex_3], [eye_tex_1, eye_tex_2])
	blob.lifespan = _rolled_lifespan()
	blob.connect("reproduce", _on_blob_reproduce)
	blob.connect("tree_exited", _on_blob_removed.bind(blob))
	blobs.append(blob)

func _prepare_blob(blob, region_idx: int):
	blob.spawn_scale = BLOB_SPAWN_SCALE
	blob.mature_scale = BLOB_MATURE_SCALE
	blob.z_index = Z_BLOB
	blob.set_meta("pop", region_idx)

# Offspring belong to the region they're born in; each region enforces its
# own cap — the island can't grow past 12 no matter what.
func spawn_blob_from_parents(traits_a: Dictionary, traits_b: Dictionary, pos: Vector2):
	if regions.size() < 2:
		return
	var idx := _region_of(pos)
	if _region_alive(idx).size() >= CAPS[idx]:
		return
	var r: Rect2 = regions[idx]
	var blob = blob_scene.instantiate()
	add_child(blob)
	blob.global_position = Vector2(
		clamp(pos.x, r.position.x + 10.0, r.end.x - 10.0),
		clamp(pos.y, r.position.y + 10.0, r.end.y - 10.0))
	_prepare_blob(blob, idx)
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
#  SCENARIO TEXT
# ---------------------------------------------------------------------------
func _preset_title() -> String:
	return "Founder Effect"

func _preset_intro_bbcode() -> String:
	return "The lab is split into two places: a [b]mainland[/b] holding up to 24 blobs, and an [b]island[/b] that starts completely empty.\n\nThe mainland fills up with an even mix. Then a few blobs cross to the island and start a new population there.\n\n[b]Nobody dies.[/b] This is the difference between a founding event and a bottleneck: the original population is still there, carrying on exactly as before. It's your control group, running live next to the new one for the rest of the run.\n\nThe founders are picked [b]at random[/b] — you choose how many, never which. Picking them yourself would be selection, and this lab doesn't do selection.\n\nWatch the two bars along the bottom of the pens the instant the founders land. The mainland will read about a third each. The island will read something else — and it won't have drifted at all yet."

func _preset_questions() -> Array:
	return [
		"The mainland is a third of each color. Will 4 randomly-picked founders be a third of each too?",
		"What are the odds that at least one color is missing from the island entirely?",
		"Nobody died here. So why does the island end up less diverse than the mainland?",
	]

# ---------------------------------------------------------------------------
#  CONTROLS
# ---------------------------------------------------------------------------
func _repeat_mode() -> int:
	return REPEAT_NONE

func _fire_button_text() -> String:
	return "Send founders to the island"

func _arm_min() -> int:
	return int(float(MAINLAND_START) * 0.85)

func _observe_seconds() -> float:
	return 90.0

func _build_extra_controls(vb: VBoxContainer):
	lbl_founders = Label.new()
	lbl_founders.text = "Founders: %d" % DEFAULT_FOUNDERS
	lbl_founders.add_theme_font_size_override("font_size", 14)
	lbl_founders.add_theme_color_override("font_color", Color(0.92, 0.92, 0.96))
	vb.add_child(lbl_founders)

	sl_founders = _labelled_slider(vb, "How many blobs make the crossing",
		float(MIN_FOUNDERS), float(MAX_FOUNDERS), float(DEFAULT_FOUNDERS))
	sl_founders.value_changed.connect(_on_founders_changed)

	lbl_split = Label.new()
	lbl_split.text = ""
	lbl_split.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl_split.add_theme_font_size_override("font_size", 13)
	lbl_split.add_theme_color_override("font_color", Color(0.62, 0.62, 0.70))
	vb.add_child(lbl_split)

func _on_founders_changed(v: float):
	founders_wanted = int(round(v))
	if lbl_founders:
		lbl_founders.text = "Founders: %d" % founders_wanted

# The base's one-line counts are whole-lab. Here the split is the story, so
# override that readout with a two-line mainland / island one.
func _refresh_counts():
	if lbl_counts == null:
		return
	var mc := _region_counts(0)
	var ic := _region_counts(1)
	var isle := "[color=#8c8c96]empty[/color]"
	if ic[0] + ic[1] + ic[2] > 0:
		isle = "[color=#ff7373]%d[/color] · [color=#73e673]%d[/color] · [color=#73a6ff]%d[/color]" % [ic[0], ic[1], ic[2]]
	lbl_counts.text = "Mainland  [color=#ff7373]%d[/color] · [color=#73e673]%d[/color] · [color=#73a6ff]%d[/color]\nIsland  %s" % [
		mc[0], mc[1], mc[2], isle]

func _refresh_extra_controls():
	if lbl_split == null:
		return
	if not founded:
		lbl_split.text = ""
		return
	var mcol: int = _region_colors(0)
	var icol: int = _region_colors(1)
	lbl_split.text = "Mainland has %d colors.  Island has %d." % [mcol, icol]
	lbl_split.add_theme_color_override("font_color",
		Color(1.0, 0.62, 0.45) if icol < mcol else Color(0.62, 0.90, 0.70))

func _ready_caption() -> String:
	return "The mainland is full and evenly mixed. Choose how many blobs make the crossing, then send them."

func _fired_caption() -> String:
	return "%d founders landed: %d red, %d green, %d blue. Compare the two bars right now — before anything has had a chance to drift." % [
		founders_wanted, founder_counts[0], founder_counts[1], founder_counts[2]]

# ---------------------------------------------------------------------------
#  THE EVENT — a random sample crosses the water
# ---------------------------------------------------------------------------
func _do_event():
	var pool := _region_alive(0)
	if pool.size() <= founders_wanted:
		return

	mainland_at_founding = _region_counts(0)

	# Shuffle, then take the first N. This sampling error IS the founder
	# effect — no property of a blob affects whether it's picked.
	pool.shuffle()
	founder_counts = [0, 0, 0]
	var isle: Rect2 = regions[1]
	var m := 22.0

	for i in range(founders_wanted):
		var b = pool[i]
		founder_counts[b.color_trait] += 1
		b.set_meta("pop", 1)
		b.global_position = Vector2(
			randf_range(isle.position.x + m, isle.end.x - m),
			randf_range(isle.position.y + m, isle.end.y - m))

	founded = true
	founded_at = sim_time
	_log("%d founders crossed: %d red, %d green, %d blue" % [
		founders_wanted, founder_counts[0], founder_counts[1], founder_counts[2]])

# Done once the island has settled on one colour and had a moment to sit.
func _observation_done() -> bool:
	if not founded:
		return false
	if _region_alive(1).size() > 0 and _region_colors(1) == 1:
		return sim_time > founded_at + 20.0
	return false

# The base's extinction and fixation checks look at the whole lab, and the
# island is legitimately empty for the first half of every run. Only the
# mainland matters for "did everything die", and the run ends on the
# island's fixation, not the lab's.
func _check_end():
	if _region_alive(0).size() == 0 and _region_alive(1).size() == 0:
		_end_extinct()
		return
	if phase == PHASE_DONE:
		_finish(_event_summary())
		return
	if sim_time >= p_time_cap:
		if event_fired:
			_finish(_event_summary())
		else:
			_finish("[b]Time ran out before anyone crossed.[/b]\n\nNo founders were sent, so there's no island population to compare against. Run it again and send them once the mainland is full.")

# ---------------------------------------------------------------------------
#  SUMMARY
# ---------------------------------------------------------------------------
func _pct_string(counts: Array) -> String:
	var t: int = counts[0] + counts[1] + counts[2]
	if t == 0:
		return "empty"
	return "%d%% / %d%% / %d%%" % [
		int(round(float(counts[0]) / float(t) * 100.0)),
		int(round(float(counts[1]) / float(t) * 100.0)),
		int(round(float(counts[2]) / float(t) * 100.0))]

func _event_summary() -> String:
	var mc := _region_counts(0)
	var ic := _region_counts(1)
	var founders: int = founder_counts[0] + founder_counts[1] + founder_counts[2]

	var missing: Array = []
	for c in range(3):
		if mainland_at_founding[c] > 0 and founder_counts[c] == 0:
			missing.append(preset_color_names[c])

	var sampling := ""
	if missing.is_empty():
		sampling = "All three colors happened to make the crossing this time. Send fewer founders and that stops being likely — with 2 founders it's impossible."
	else:
		sampling = "[b]%s never made the crossing at all.[/b] %s alive and well on the mainland the entire time — there simply wasn't room in a sample of %d. The island could never produce a %s blob, because no founder was carrying that color." % [
			" and ".join(missing),
			"They were" if missing.size() > 1 else "It was",
			founders,
			missing[0].to_lower()]

	return "[b]Mainland finished at %s.  Island finished at %s.[/b]  (red / green / blue)\n\nThe %d founders were %d red, %d green, %d blue — drawn at random from a mainland sitting at %s.\n\n%s\n\nNotice what did [b]not[/b] happen: nothing died. The mainland is still full, still mixed, still running. That's what separates a founder effect from a bottleneck — the source population survives, so you can see exactly how far the new one strayed from it, and know the difference came entirely from the size of the sample.\n\nThis is why island species and isolated human populations so often carry unusual gene frequencies. Nothing about the island favoured those variants. They're just the ones that happened to be on the boat." % [
		_pct_string(mc), _pct_string(ic),
		founders, founder_counts[0], founder_counts[1], founder_counts[2],
		_pct_string(mainland_at_founding),
		sampling]

# ---------------------------------------------------------------------------
#  RESULTS CARD — mainland vs island, the comparison the event exists for
# ---------------------------------------------------------------------------
func _build_comparison():
	for child in compare_box.get_children():
		child.queue_free()

	var head := Label.new()
	head.text = "Mainland  vs  Island, at the end"
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_font_size_override("font_size", 15)
	head.add_theme_color_override("font_color", Color(0.62, 0.62, 0.68))
	compare_box.add_child(head)

	var mc := _region_counts(0)
	var ic := _region_counts(1)
	var mt: int = mc[0] + mc[1] + mc[2]
	var it: int = ic[0] + ic[1] + ic[2]

	for c in range(3):
		var mp := 0
		var ip := 0
		if mt > 0:
			mp = int(round(float(mc[c]) / float(mt) * 100.0))
		if it > 0:
			ip = int(round(float(ic[c]) / float(it) * 100.0))

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

		var val := Label.new()
		val.text = "mainland %d%%    ·    founders %d    ·    island %d%%" % [
			mp, founder_counts[c], ip]
		val.add_theme_font_size_override("font_size", 15)
		val.add_theme_color_override("font_color",
			Color(1.0, 0.45, 0.45) if (mp > 0 and ip == 0) else Color(0.86, 0.86, 0.92))
		row.add_child(val)

	compare_box.add_child(HSeparator.new())

	var stats := HBoxContainer.new()
	stats.alignment = BoxContainer.ALIGNMENT_CENTER
	stats.add_theme_constant_override("separation", 26)
	compare_box.add_child(stats)

	stats.add_child(_event_stat("Founders sent",
		str(founder_counts[0] + founder_counts[1] + founder_counts[2]),
		Color(0.86, 0.86, 0.92)))
	stats.add_child(_event_stat("Mainland colors", str(_region_colors(0)),
		Color(0.55, 0.90, 0.62)))
	stats.add_child(_event_stat("Island colors", str(_region_colors(1)),
		Color(1.0, 0.55, 0.45) if _region_colors(1) < _region_colors(0)
		else Color(0.55, 0.90, 0.62)))

func start_simulation():
	founded = false
	founded_at = -1.0
	founder_counts = [0, 0, 0]
	mainland_at_founding = [0, 0, 0]
	super.start_simulation()
	if lbl_split:
		lbl_split.text = ""

func _update_pop_label():
	var pop_label = get_node_or_null("PopLabel")
	if not pop_label:
		return
	var mins = int(sim_time) / 60
	var secs = int(sim_time) % 60
	pop_label.text = "Mainland: %d / %d     Island: %d / %d     Time: %d:%02d" % [
		_region_alive(0).size(), CAPS[0],
		_region_alive(1).size(), CAPS[1], mins, secs]
