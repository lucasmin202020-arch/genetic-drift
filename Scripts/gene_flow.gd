extends MultiPen

# ===========================================================================
#  PRESET: GENE FLOW
#
#  Two equal populations in adjacent pens, separated by a gap with a GATE.
#  The run has two acts:
#
#    ACT 1 (sealed)    — the gate is welded shut. The pens drift apart.
#    ACT 2 (connected) — the gate opens for a few seconds at a time, letting
#                        blobs wander across. The pens are pulled back together.
#
#  THE LESSON: drift makes isolated populations diverge, but even a trickle
#  of migration is enough to keep them alike. Isolation isn't a detail — it's
#  the precondition for populations becoming different from one another.
#
#  THE GRAPH, AND WHY IT LOOKS LIKE THIS
#  -------------------------------------
#  This panel has been through two bad versions, and the reasons are worth
#  keeping written down.
#
#  v1 was a single yellow line labelled "divergence" with no scale anywhere.
#     You could see it move but not what had moved. Unreadable.
#  v2 replaced it with two stacked colour ribbons, one per pen. That failed
#     for a subtler reason: comparing two stacked area charts by eye is
#     genuinely hard. Both ribbons look like the same coloured mush, and the
#     one thing the graph exists to show — the DIFFERENCE between them — was
#     the one thing you couldn't see.
#
#  v3, below, plots the difference itself as a filled area, and fixes v1's
#  actual problem: the scale is spelled out in plain words directly above the
#  chart ("0% = identical mixes, 100% = no colors in common"), so the number
#  needs no decoding. Green shading marks every stretch where the gate was
#  open, which puts cause and effect on the same picture.
#
#  SETUP:
#    1. Open CoinFlip.tscn -> Scene -> "Save Scene As..." -> GeneFlow.tscn
#    2. Select the ROOT node of the NEW scene (check the tab!)
#    3. Clear coin_flip.gd, attach gene_flow.gd.
#    4. Confirm Blob Scene + the 5 textures are assigned. Save at once.
# ===========================================================================

const PEN_SIZE := 15              # starting blobs: 5 of each colour
# The cap sits above the starting count so births can begin the moment the
# blobs mature, instead of waiting a full lifespan for a slot to open up.
const PEN_CAP := 20
# The air gap between the two pens. There is no drawn wall any more — the gap
# IS the wall. The physics segments that fill it are invisible.
const GAP_W := 30.0
const GATE_FRAC := 0.6          # how much of the gap's height is gate

# Blobs mature at 9s, so the gate opening at 15 leaves a short sealed act and
# then puts the interesting part — open, shut, open — in front of the user
# instead of making them wait a minute for anything to happen. Divergence
# keeps building during every CLOSED stretch after that, so the sealed-vs-
# connected contrast still gets made, just repeatedly instead of once.
const SEAL_UNTIL := 15.0
const GATE_OPEN_FOR := 15.0       # long enough for blobs to actually find it
const GATE_CLOSED_FOR := 16.0     # long enough for the pens to drift apart again

const NAMES := ["West", "East"]
const ACCENTS := [Color(0.62, 0.80, 0.62), Color(0.72, 0.66, 0.95)]

# --- gate state ---
var gate_body: StaticBody2D = null
var gate_shape: CollisionShape2D = null
var gate_rect: Rect2 = Rect2()
var gate_open: bool = false
var gate_timer: float = 0.0
var gate_cycles: int = 0
var first_open_recorded: bool = false

# --- migration ---
var migrants: int = 0
var peak_divergence: float = 0.0
var divergence_at_open: float = 0.0
var opened_announced: bool = false
var seal_caption_shown: bool = false
var converge_caption_shown: bool = false

# --- panel ---
var div_graph: DivergenceGraph = null
var lbl_diff: Label
var lbl_diff_note: Label
var bar_fills: Array = []
var bar_labels: Array = []
var lbl_gate: Label
var lbl_migrants: Label

const TRACK_W := 96.0
const TRACK_H := 15.0
# Deliberately short. The caption box lives below this in the same VBox and
# was being pushed off the bottom of the panel.
const PANEL_GRAPH_H := 86.0

# ===========================================================================
#  DIVERGENCE GRAPH
#
#  One filled area: how different the two pens are, 0% at the bottom to 100%
#  at the top. Every stretch where the gate stood open is shaded green behind
#  the fill, so "the line falls whenever the green starts" is visible without
#  anyone being told to look for it.
#
#  No text is drawn inside the chart. The number lives in the big readout
#  above it and the gate state lives in the panel label, so repeating either
#  one here would just be clutter.
# ===========================================================================
class DivergenceGraph extends Control:
	# [{ "t": float, "v": float 0-100, "open": bool }]
	var samples: Array = []
	var max_time: float = 5.0
	var maturity_time: float = 9.0

	const GUTTER := 34.0
	const LABEL_SIZE := 10

	# Background bands. Grey until the gate first opens, then green while
	# open and red while shut. Red only starts meaning something once the
	# user has seen a green stretch to contrast it against — before that
	# it's just "nothing has happened yet", which is what grey says.
	const BAND_BEFORE := Color(0.20, 0.20, 0.25, 0.55)
	const BAND_OPEN := Color(0.20, 0.46, 0.30, 0.55)
	const BAND_SHUT := Color(0.48, 0.19, 0.22, 0.50)

	func add_sample(t: float, v: float, is_open: bool):
		samples.append({"t": t, "v": v, "open": is_open})
		if t > max_time:
			max_time = t
		queue_redraw()

	func clear_samples():
		samples.clear()
		max_time = 5.0
		queue_redraw()

	func _draw():
		var full_w: float = size.x
		var h: float = size.y
		if full_w <= GUTTER + 20.0 or h <= 20.0:
			return

		var ox: float = GUTTER
		var w: float = full_w - GUTTER
		var plot := Rect2(ox, 0.0, w, h)
		draw_rect(plot, Color(0.085, 0.085, 0.105), true)

		# --- state bands, one per sampling interval ---
		# seen_open flips permanently the first time the gate opens, which is
		# what separates "not started yet" grey from "actively sealed" red.
		var seen_open: bool = false
		if samples.size() >= 2:
			for i in range(samples.size() - 1):
				var s0: Dictionary = samples[i]
				var is_open: bool = bool(s0["open"])
				if is_open:
					seen_open = true

				var band: Color = BAND_BEFORE
				if is_open:
					band = BAND_OPEN
				elif seen_open:
					band = BAND_SHUT

				var x0: float = ox + (float(s0["t"]) / max_time) * w
				var x1: float = ox + (float(samples[i + 1]["t"]) / max_time) * w
				draw_rect(Rect2(x0, 0.0, max(1.0, x1 - x0), h), band, true)

		# --- gridlines + labels at 0 / 50 / 100 ---
		var font := get_theme_default_font()
		for i in range(3):
			var gy: float = h - (float(i) / 2.0) * h
			draw_line(Vector2(ox, gy), Vector2(ox + w, gy),
				Color(0.34, 0.34, 0.40) if i == 1 else Color(0.28, 0.28, 0.33), 1.0)
			if font:
				var txt := "%d%%" % (i * 50)
				var tw: float = font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT,
					-1, LABEL_SIZE).x
				var ty: float = gy + LABEL_SIZE * 0.35
				if i == 2:
					ty = gy + LABEL_SIZE * 0.9
				elif i == 0:
					ty = gy - 1.0
				draw_string(font, Vector2(ox - 7.0 - tw, ty), txt,
					HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE, Color(0.58, 0.58, 0.66))

		# where the blobs finished growing up — nothing drifts before this
		var mx: float = clamp((maturity_time / max_time) * w, 0.0, w)
		if mx > 1.0:
			draw_line(Vector2(ox + mx, 0.0), Vector2(ox + mx, h),
				Color(0.85, 0.72, 0.38, 0.8), 1.0)

		# --- the filled trace ---
		if samples.size() >= 2:
			var line := PackedVector2Array()
			for s in samples:
				line.append(Vector2(
					ox + (float(s["t"]) / max_time) * w,
					h - (float(s["v"]) / 100.0) * h))

			var area := PackedVector2Array(line)
			area.append(Vector2(line[line.size() - 1].x, h))
			area.append(Vector2(line[0].x, h))
			draw_colored_polygon(area, Color(1.0, 0.92, 0.62, 0.22))
			draw_polyline(line, Color(1.0, 0.94, 0.70), 2.2, true)

		draw_rect(plot, Color(0.28, 0.28, 0.34), false, 1.0)
# ---------------------------------------------------------------------------
#  SETUP
# ---------------------------------------------------------------------------
func _ready():
	pen_caps = [PEN_CAP, PEN_CAP]
	pen_start_mix = [[5, 5, 5], [5, 5, 5]]
	pen_titles = ["WEST population", "EAST population"]
	pen_accents = ACCENTS
	blob_spawn_scale = 0.075
	blob_mature_scale = 0.11
	p_lifespan = 32.0
	p_time_cap = 175.0
	p_speed_index = 3
	super._ready()

func _on_run_reset():
	migrants = 0
	peak_divergence = 0.0
	divergence_at_open = 0.0
	gate_open = false
	gate_timer = 0.0
	gate_cycles = 0
	first_open_recorded = false
	opened_announced = false
	seal_caption_shown = false
	converge_caption_shown = false
	if div_graph:
		div_graph.clear_samples()
	_set_gate(false)

# Two equal pens with an air gap between them. The gap is where the gate goes.
func _layout_pens() -> Array:
	var w: float = (lab_rect.size.x - GAP_W) * 0.5
	return [
		Rect2(lab_rect.position.x, lab_rect.position.y, w, lab_rect.size.y),
		Rect2(lab_rect.position.x + w + GAP_W, lab_rect.position.y, w, lab_rect.size.y),
	]

# Perimeter walls plus a divider built in three pieces, the middle one being
# the gate we can switch on and off. All of it is invisible — the only thing
# drawn in the gap is the gate itself.
func _build_pen_walls():
	var full := Rect2(pens[0].position.x, pens[0].position.y,
		pens[1].end.x - pens[0].position.x, pens[0].size.y)

	# outer perimeter
	_wall(Vector2(full.position.x + full.size.x * 0.5, full.position.y - WALL_T * 0.5),
		Vector2(full.size.x + WALL_T * 2.0, WALL_T))
	_wall(Vector2(full.position.x + full.size.x * 0.5, full.end.y + WALL_T * 0.5),
		Vector2(full.size.x + WALL_T * 2.0, WALL_T))
	_wall(Vector2(full.position.x - WALL_T * 0.5, full.position.y + full.size.y * 0.5),
		Vector2(WALL_T, full.size.y))
	_wall(Vector2(full.end.x + WALL_T * 0.5, full.position.y + full.size.y * 0.5),
		Vector2(WALL_T, full.size.y))

	# the divider, in three pieces
	var wx: float = pens[0].end.x + GAP_W * 0.5
	var gate_h: float = full.size.y * GATE_FRAC
	var seg_h: float = (full.size.y - gate_h) * 0.5

	_wall(Vector2(wx, full.position.y + seg_h * 0.5), Vector2(GAP_W, seg_h))
	_wall(Vector2(wx, full.end.y - seg_h * 0.5), Vector2(GAP_W, seg_h))

	gate_rect = Rect2(pens[0].end.x, full.position.y + seg_h, GAP_W, gate_h)
	gate_body = _wall(Vector2(wx, gate_rect.position.y + gate_h * 0.5),
		Vector2(GAP_W, gate_h))
	gate_shape = gate_body.get_child(0)
	_set_gate(false)

func _set_gate(is_open: bool):
	gate_open = is_open
	if gate_shape:
		gate_shape.set_deferred("disabled", is_open)

# ---------------------------------------------------------------------------
#  GATE + MIGRATION
# ---------------------------------------------------------------------------
func _process(delta):
	super._process(delta)
	if not simulation_running or ended:
		return
	_update_gate(delta)
	_track_migration()

func _update_gate(delta):
	if sim_time < SEAL_UNTIL:
		if gate_open:
			_set_gate(false)
		return

	gate_timer -= delta
	if gate_timer <= 0.0:
		if gate_open:
			_set_gate(false)
			gate_timer = GATE_CLOSED_FOR
		else:
			_set_gate(true)
			gate_timer = GATE_OPEN_FOR
			gate_cycles += 1
			if not first_open_recorded:
				first_open_recorded = true
				divergence_at_open = _divergence()

# A blob's pen is decided by where it actually is, so crossing the gate
# genuinely moves it between populations.
func _track_migration():
	for b in blobs:
		if not is_instance_valid(b) or b.is_dying:
			continue
		var now := 0 if b.global_position.x < pens[0].end.x + GAP_W * 0.5 else 1
		if b.get_meta("pen", 0) != now:
			b.set_meta("pen", now)
			migrants += 1

# ---------------------------------------------------------------------------
#  DIVERGENCE — how different the two pens are, 0 to 100
# ---------------------------------------------------------------------------
func _divergence() -> float:
	var ta: int = _pen_alive(0).size()
	var tb: int = _pen_alive(1).size()
	if ta == 0 or tb == 0:
		return 0.0
	var ca := _pen_counts(0)
	var cb := _pen_counts(1)
	var sum := 0.0
	for c in range(3):
		sum += abs(float(ca[c]) / float(ta) - float(cb[c]) / float(tb))
	return sum * 0.5 * 100.0

# ---------------------------------------------------------------------------
#  SCENARIO TEXT
# ---------------------------------------------------------------------------
func _preset_title() -> String:
	return "Gene Flow"

func _preset_intro_bbcode() -> String:
	return "Two populations of 15 blobs, side by side, starting from exactly the same mix — 5 red, 5 green, 5 blue each.\n\nBetween them is a solid divide with one [b]gate[/b] in it, and it doesn't stay in one state:\n\n[b]Sealed.[/b] The gate starts shut. The two populations drift completely independently, and they'll start to look different from each other.\n\n[b]Connected.[/b] Every so often the gate swings open and blobs can wander across. A blob that crosses joins the population it lands in and breeds there. That trickle of movement is called [b]gene flow[/b].\n\nThe gate opens for the first time [b]15 seconds in[/b], then keeps cycling open and shut for the rest of the run.\n\n[b]The graph[/b] shows how different the two pens are right now, and shades the background green for every stretch where the gate was open."

func _preset_questions() -> Array:
	return [
		"While the gate is shut, what should the graph line do?",
		"Predict what the line does in the first ten seconds after the gate opens.",
		"Can a color that went extinct in one pen come back? How would that happen?",
	]

# ---------------------------------------------------------------------------
#  PANEL
# ---------------------------------------------------------------------------
func _build_graph():
	var vbox = get_node_or_null("UIPanel/VBox")
	if not vbox:
		return
	ui_nodes.clear()
	bar_fills.clear()
	bar_labels.clear()

	lbl_gate = Label.new()
	lbl_gate.text = "Gate: sealed"
	lbl_gate.add_theme_font_size_override("font_size", 16)
	lbl_gate.add_theme_color_override("font_color", Color(1.0, 0.55, 0.5))
	vbox.add_child(lbl_gate)
	ui_nodes.append(lbl_gate)

	lbl_migrants = Label.new()
	lbl_migrants.text = "Crossings: 0"
	lbl_migrants.add_theme_font_size_override("font_size", 14)
	lbl_migrants.add_theme_color_override("font_color", Color(0.62, 0.62, 0.70))
	vbox.add_child(lbl_migrants)
	ui_nodes.append(lbl_migrants)

	for i in range(2):
		var head := Label.new()
		head.text = "%s population" % NAMES[i]
		head.add_theme_font_size_override("font_size", 15)
		head.add_theme_color_override("font_color", ACCENTS[i])
		vbox.add_child(head)
		ui_nodes.append(head)

		var fills: Array = []
		var labels: Array = []
		var bars := VBoxContainer.new()
		bars.add_theme_constant_override("separation", 4)
		vbox.add_child(bars)
		ui_nodes.append(bars)

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

		bar_fills.append(fills)
		bar_labels.append(labels)

	var gsep := HSeparator.new()
	vbox.add_child(gsep)
	ui_nodes.append(gsep)

	# --- THE ONE-SENTENCE READOUT ---
	# The number said out loud, with its scale spelled out underneath. This
	# pair is what makes the chart below legible; keep them together.
	lbl_diff = Label.new()
	lbl_diff.text = "Pens are 0% different"
	lbl_diff.add_theme_font_size_override("font_size", 18)
	lbl_diff.add_theme_color_override("font_color", Color(0.92, 0.92, 0.96))
	vbox.add_child(lbl_diff)
	ui_nodes.append(lbl_diff)

	lbl_diff_note = Label.new()
	lbl_diff_note.text = "0% = identical mixes  ·  100% = no colors in common"
	lbl_diff_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl_diff_note.add_theme_font_size_override("font_size", 12)
	lbl_diff_note.add_theme_color_override("font_color", Color(0.58, 0.58, 0.66))
	vbox.add_child(lbl_diff_note)
	ui_nodes.append(lbl_diff_note)

	div_graph = DivergenceGraph.new()
	div_graph.maturity_time = MATURATION_TIME
	div_graph.custom_minimum_size = Vector2(0, PANEL_GRAPH_H)
	div_graph.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(div_graph)
	ui_nodes.append(div_graph)

	for n in ui_nodes:
		n.visible = false

func update_tracker():
	for i in range(2):
		if i >= bar_fills.size():
			continue
		var counts := _pen_counts(i)
		var total := 0
		for c in counts:
			total += c
		for c in range(3):
			var pct := 0.0
			if total > 0:
				pct = float(counts[c]) / float(total)
			bar_fills[i][c].size = Vector2(pct * TRACK_W, TRACK_H)
			bar_labels[i][c].text = "%d%% (%d)" % [int(round(pct * 100)), counts[c]]

	var d: float = _divergence()
	if lbl_diff:
		lbl_diff.text = "Pens are %d%% different" % int(round(d))
		lbl_diff.add_theme_color_override("font_color",
			Color(1.0, 0.62, 0.45) if d >= 30.0 else Color(0.62, 0.90, 0.70))

	if lbl_gate:
		if sim_time < SEAL_UNTIL:
			var left: int = int(ceil(SEAL_UNTIL - sim_time))
			lbl_gate.text = "Gate: SEALED  (opens in %ds)" % left
			lbl_gate.add_theme_color_override("font_color", Color(1.0, 0.55, 0.5))
		elif gate_open:
			lbl_gate.text = "Gate: OPEN  (%ds)" % int(ceil(gate_timer))
			lbl_gate.add_theme_color_override("font_color", Color(0.5, 0.95, 0.6))
		else:
			lbl_gate.text = "Gate: closed  (%ds)" % int(ceil(gate_timer))
			lbl_gate.add_theme_color_override("font_color", Color(0.90, 0.78, 0.42))
	if lbl_migrants:
		lbl_migrants.text = "Crossings: %d" % migrants

func _sample_graph(delta):
	if div_graph == null:
		return
	graph_sample_timer += delta
	if graph_sample_timer < GRAPH_SAMPLE_INTERVAL:
		return
	graph_sample_timer = 0.0
	var d := _divergence()
	# Peak is tracked across EVERY sealed stretch, not just the first one —
	# the gate now cycles, so "how far apart did they get while cut off"
	# is a question the whole run keeps answering.
	if not gate_open and d > peak_divergence:
		peak_divergence = d
	div_graph.add_sample(sim_time, d, gate_open)

func _update_pop_label():
	var pop_label = get_node_or_null("PopLabel")
	if not pop_label:
		return
	var mins = int(sim_time) / 60
	var secs = int(sim_time) % 60
	pop_label.text = "West: %d     East: %d     Pens %.0f%% different     Crossings: %d     Time: %d:%02d" % [
		_pen_alive(0).size(), _pen_alive(1).size(), _divergence(), migrants, mins, secs]

# ---------------------------------------------------------------------------
#  IN-GAP DRAWING — the gate is the only thing drawn between the pens
#  Colour and texture carry the state: green and clear when open, amber with
#  a dashed seam when shut. No label — the panel already says it in words.
# ---------------------------------------------------------------------------
func _draw_overlay_extras(ov):
	if gate_rect.size.x <= 0.0:
		return
	var col := Color(0.45, 0.92, 0.58) if gate_open else Color(0.70, 0.55, 0.35)

	var gs := StyleBoxFlat.new()
	gs.bg_color = Color(0.13, 0.24, 0.17, 0.85) if gate_open else Color(0.24, 0.20, 0.14, 0.9)
	gs.border_color = col
	gs.set_border_width_all(2)
	gs.set_corner_radius_all(5)
	ov.draw_style_box(gs, gate_rect)

	if not gate_open:
		var y: float = gate_rect.position.y + 6.0
		while y < gate_rect.end.y - 4.0:
			ov.draw_line(Vector2(gate_rect.position.x + 3.0, y),
				Vector2(gate_rect.end.x - 3.0, y), Color(col.r, col.g, col.b, 0.7), 2.0)
			y += 9.0

# ---------------------------------------------------------------------------
#  NARRATION
# ---------------------------------------------------------------------------
func _check_captions():
	if not growth_done:
		return

	if not seal_caption_shown and sim_time > MATURATION_TIME + 1.0:
		seal_caption_shown = true
		_set_caption("The gate is sealed. Both pens started identical — watch the graph line climb as they drift apart on their own.")
		return

	if gate_cycles >= 1 and not opened_announced:
		opened_announced = true
		_set_caption("The gate is open — the graph has turned green behind the line. Blobs can cross now, and whichever pen they land in is the one they breed in.")
		return

	if gate_cycles >= 2 and not converge_caption_shown and migrants >= 3:
		converge_caption_shown = true
		_set_caption("%d crossings so far. Look at what the line does inside the green stretches — a trickle of migration is enough to pull the pens back together." % migrants)
		return

	if not mid_caption_shown and sim_time > MATURATION_TIME + 30.0:
		mid_caption_shown = true
		_set_caption("The pens are %.0f%% different. Two populations, no selection anywhere, slowly becoming unlike each other." % _divergence())

# ---------------------------------------------------------------------------
#  END
# ---------------------------------------------------------------------------
func _check_end():
	var dead: bool = _pen_alive(0).size() == 0 and _pen_alive(1).size() == 0
	if dead or sim_time >= p_time_cap:
		_finish(_summary())

func _summary() -> String:
	var final_d := _divergence()
	var verdict := ""
	if migrants == 0:
		verdict = "No blob ever actually made it through the gate this run, so the two pens stayed isolated the whole way. Run it again — with a few crossings you should see the line drop inside the green stretches."
	elif final_d < peak_divergence:
		verdict = "Once blobs started crossing, the difference fell from a peak of [b]%.0f%%[/b] down to [b]%.0f%%[/b]. Only %d blob%s crossed — and that was enough." % [
			peak_divergence, final_d, migrants, "" if migrants == 1 else "s"]
	else:
		verdict = "The pens ended [b]%.0f%%[/b] different, having peaked at %.0f%% while cut off. %d crossing%s happened, but drift kept pulling the pens apart faster than migration could pull them together — which happens when the flow is small and the populations are tiny." % [
			final_d, peak_divergence, migrants, "" if migrants == 1 else "s"]

	return "[b]The pens peaked at %.0f%% different, and finished at %.0f%%.[/b]\n\n%s\n\nWhile the gate was shut, each pen drifted on its own and they became more and more different — for no reason other than chance.\n\nThe moment blobs could cross, the two pens stopped being separate experiments. A migrant carries its color into the other population and breeds there, so any difference that drift builds up gets mixed away again.\n\nThat's why [b]gene flow is the enemy of divergence[/b]. Populations only become genuinely different when something keeps them apart — a mountain range, an ocean, a road. Isolation isn't a background detail in evolution; it's the requirement." % [
		peak_divergence, final_d, verdict]

# ---------------------------------------------------------------------------
#  RESULTS CARD
# ---------------------------------------------------------------------------
func _build_comparison():
	for child in compare_box.get_children():
		child.queue_free()

	var head := Label.new()
	head.text = "West  vs  East, at the end"
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_font_size_override("font_size", 15)
	head.add_theme_color_override("font_color", Color(0.62, 0.62, 0.68))
	compare_box.add_child(head)

	var ta: int = _pen_alive(0).size()
	var tb: int = _pen_alive(1).size()
	var ca := _pen_counts(0)
	var cb := _pen_counts(1)

	for c in range(3):
		var pa := 0
		var pb := 0
		if ta > 0:
			pa = int(round(float(ca[c]) / float(ta) * 100.0))
		if tb > 0:
			pb = int(round(float(cb[c]) / float(tb) * 100.0))

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

		var gap: int = abs(pa - pb)
		var val := Label.new()
		val.text = "West %d%%    East %d%%    gap %d" % [pa, pb, gap]
		val.add_theme_font_size_override("font_size", 15)
		val.add_theme_color_override("font_color",
			Color(0.55, 0.90, 0.62) if gap <= 15 else Color(1.0, 0.62, 0.45))
		row.add_child(val)

	compare_box.add_child(HSeparator.new())

	var stats := HBoxContainer.new()
	stats.alignment = BoxContainer.ALIGNMENT_CENTER
	stats.add_theme_constant_override("separation", 26)
	compare_box.add_child(stats)

	stats.add_child(_stat("Most different", "%.0f%%" % peak_divergence, Color(1.0, 0.62, 0.45)))
	stats.add_child(_stat("Different at the end", "%.0f%%" % _divergence(),
		Color(0.55, 0.90, 0.62) if _divergence() < peak_divergence else Color(1.0, 0.62, 0.45)))
	stats.add_child(_stat("Crossings", str(migrants), Color(0.86, 0.86, 0.92)))

func _stat(title: String, value: String, col: Color) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)

	var v := Label.new()
	v.text = value
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_theme_font_size_override("font_size", 21)
	v.add_theme_color_override("font_color", col)
	box.add_child(v)

	var t := Label.new()
	t.text = title
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 13)
	t.add_theme_color_override("font_color", Color(0.58, 0.58, 0.66))
	box.add_child(t)

	return box
