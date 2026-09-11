extends MultiPen

# ===========================================================================
#  PRESET: DRIFT vs SELECTION
#
#  Two pens of the SAME size, running at once.
#
#    LEFT  — pure drift. Every blob is identical apart from colour.
#    RIGHT — red blobs live 55% longer than green or blue.
#
#  THE LESSON: this is the only preset that deliberately breaks the lab's
#  rule that no trait may confer an advantage — because the point is to show
#  what the difference looks like.
#
#  Drift wanders: the left pen lands on a different colour every run.
#  Selection pushes: the right pen climbs steadily toward red, run after run.
#  Same randomness in both — only the right one has a direction.
#
#  Both pens are the same size and same density, so population size can't
#  explain the difference. The ONLY difference is the advantage.
#
#  SETUP:
#    1. Open CoinFlip.tscn -> Scene -> "Save Scene As..." -> DriftVsSelection.tscn
#    2. Select the ROOT node of the NEW scene (check the tab!)
#    3. Clear coin_flip.gd, attach drift_vs_selection.gd.
#    4. Confirm Blob Scene + the 5 textures are assigned. Save at once.
# ===========================================================================

const PEN_SIZE := 18              # starting blobs: 6 of each colour
# Cap above the starting count, so births can start as soon as the blobs
# mature rather than waiting for the first death to free a slot.
const PEN_CAP := 24
const PEN_GAP := 34.0
const ADVANTAGED_COLOR := 0       # red
const ADVANTAGE := 1.55           # red lives 55% longer in the selection pen
const SELECTION_PEN := 1

const NAMES := ["Pure drift", "Selection"]
const ACCENTS := [Color(0.60, 0.72, 0.95), Color(0.95, 0.55, 0.45)]

# Cross-run tally — the strongest evidence this preset offers.
static var wins_drift: Array = [0, 0, 0]
static var wins_select: Array = [0, 0, 0]
static var runs_counted: int = 0

# --- panel ---
var pen_graphs: Array = []
var bar_fills: Array = []
var bar_labels: Array = []

var announced: Array = [false, false]
var advantage_caption_shown: bool = false

const TRACK_W := 96.0
const TRACK_H := 15.0
const MINI_GRAPH_H := 84.0

func _ready():
	pen_caps = [PEN_CAP, PEN_CAP]
	pen_start_mix = [[6, 6, 6], [6, 6, 6]]
	# The pen title says the number outright — and it's the SAME number as
	# ADVANTAGE above, so the two can't drift apart.
	pen_titles = ["No advantage — pure drift",
		"RED LIVES %d%% LONGER" % int(round((ADVANTAGE - 1.0) * 100.0))]
	pen_accents = ACCENTS
	blob_spawn_scale = 0.075
	blob_mature_scale = 0.11
	p_lifespan = 30.0
	p_time_cap = 170.0
	p_speed_index = 3
	super._ready()

func _on_run_reset():
	announced = [false, false]
	advantage_caption_shown = false

# ---------------------------------------------------------------------------
#  LAYOUT — two equal pens. Equal size matters here: it rules out population
#  size as an explanation for the difference.
# ---------------------------------------------------------------------------
func _layout_pens() -> Array:
	var w: float = (lab_rect.size.x - PEN_GAP) * 0.5
	return [
		Rect2(lab_rect.position.x, lab_rect.position.y, w, lab_rect.size.y),
		Rect2(lab_rect.position.x + w + PEN_GAP, lab_rect.position.y, w, lab_rect.size.y),
	]


# ---------------------------------------------------------------------------
#  THE ADVANTAGE
#  Red blobs in the selection pen simply live longer, so they get more
#  chances to reproduce. That is selection: a trait changing an individual's
#  expected number of offspring. Everywhere else in this project that would
#  be a bug — here it's the point.
# ---------------------------------------------------------------------------
func _blob_lifespan(pen_idx: int, color_idx: int) -> float:
	var base: float = _rolled_lifespan()
	if pen_idx == SELECTION_PEN and color_idx == ADVANTAGED_COLOR:
		return base * ADVANTAGE
	return base

# Mark advantaged blobs so you can see which individuals are favoured.
func _draw_pen_extras(ov, i: int, r: Rect2):
	if i != SELECTION_PEN:
		return
	for b in _pen_alive(i):
		if b.color_trait != ADVANTAGED_COLOR:
			continue
		var rad: float = 16.0
		var bs = b.get_node_or_null("BodySprite")
		if bs and bs.texture:
			rad = bs.texture.get_width() * 0.5 * b.scale.x * bs.scale.x
		ov.draw_arc(b.global_position, rad + 3.0, 0.0, TAU, 24,
			Color(1.0, 0.82, 0.35, 0.55), 1.5, true)

# ---------------------------------------------------------------------------
#  SCENARIO TEXT
# ---------------------------------------------------------------------------
func _preset_title() -> String:
	return "Drift vs Selection"

func _preset_intro_bbcode() -> String:
	return (
		"[b]THE SCIENCE[/b]\n\n"
		+ "Genetic drift and natural selection both change allele frequencies, and both involve chance, but they are different mechanisms and they leave different signatures.\n\n"
		+ "[b]Natural selection[/b] happens when a heritable trait changes how many offspring an individual leaves. Individuals with the trait survive longer, mate more, or produce more young, so the allele behind it becomes more common. Selection has a [i]direction[/i]: run the same population again and the same allele rises again, because the advantage is real and repeatable. This is the mechanism Darwin described, and it is the one that produces adaptation — traits that fit an organism to its environment.\n\n"
		+ "[b]Genetic drift[/b] happens when allele frequencies change by chance alone, with no trait affecting reproduction. Drift has no direction: run the same population again and a different allele may rise, because nothing was favouring the first one. Drift does not produce adaptation. It can just as easily remove a useful allele as spread it.\n\n"
		+ "In real populations both act at once, and which one dominates depends on population size and on how strong the advantage is. In small populations drift is powerful enough to overwhelm weak selection, so a mildly beneficial allele can still be lost by bad luck; in large populations even a small advantage wins out reliably, because chance averages away. The rough rule is that selection controls an allele's fate only when its advantage is larger than about one over twice the population size.\n\n"
		+ "The two are told apart the same way in the field as in this lab: by [b]repeatability[/b] and [b]direction[/b]. If isolated populations keep converging on the same trait in the same environment, selection is at work. If they wander to different endpoints with no pattern, drift is. The peppered moth's shift to dark coloration during industrial pollution, repeated across many separate populations, is a selection signature; the scatter of allele frequencies across islands with identical climates is a drift signature.\n\n"
		+ "[i]Sources: UC Berkeley Understanding Evolution, \"Natural selection\" and \"Genetic drift\"; Khan Academy, \"Natural selection\" and \"Genetic drift\" (AP Biology); Biology LibreTexts, \"Genetic Drift\" (Raven 12th ed. §20.9.2); Kimura, M. (1983), The Neutral Theory of Molecular Evolution, Cambridge University Press.[/i]\n\n"
	) + _howto_bbcode()

func _howto_bbcode() -> String:
	return (
		"[b]HOW THIS SIMULATION WORKS[/b]\n"
		+ "[i]This section is about the sim, not the biology.[/i]\n\n"
		+ "Two pens of the same size run side by side, each starting with 18 blobs — 6 of each color — and each holding up to 24. In the left pen, color does nothing; these are exactly the rules from every other lesson. In the right pen, [b]red blobs live %d%% longer[/b] than green or blue, which gives them more time to reproduce. Nothing else differs: same size, same crowding, same random breeding. Advantaged blobs in the right pen are ringed in gold so you can see who is favoured. Each pen has its own tracker and graph in the side panel. The run ends when both pens have settled on one color (or died out), or when time runs out. The results card records which color won in each pen and keeps a tally across every run this session.\n\n"
		+ "[b]WHAT TO DO[/b]\n\n"
		+ "1.  Before pressing Begin, predict the winner in each pen separately.\n"
		+ "2.  Once the blobs mature, compare the two graphs. Look at the shape of the lines — jagged with no trend on the left, a steady climb on the right.\n"
		+ "3.  Note which pen settles first and which color won in each.\n"
		+ "4.  Run it at least three times. On the results card, compare the two tallies: the drift pen's winner should keep changing; the selection pen's should not."
	) % int(round((ADVANTAGE - 1.0) * 100.0))

# ---------------------------------------------------------------------------
#  PANEL — two trackers, two graphs
# ---------------------------------------------------------------------------
func _build_graph():
	var vbox = get_node_or_null("UIPanel/VBox")
	if not vbox:
		return
	ui_nodes.clear()
	pen_graphs.clear()
	bar_fills.clear()
	bar_labels.clear()

	for i in range(2):
		if i == 1:
			var sep := HSeparator.new()
			vbox.add_child(sep)
			ui_nodes.append(sep)

		var head := Label.new()
		head.text = NAMES[i]
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

		var g = DriftPreset.FreqGraph.new()
		g.maturity_time = MATURATION_TIME
		g.custom_minimum_size = Vector2(0, MINI_GRAPH_H)
		g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vbox.add_child(g)
		pen_graphs.append(g)
		ui_nodes.append(g)

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
		var lead := 0
		for c in range(3):
			if counts[c] > counts[lead]:
				lead = c
		for c in range(3):
			var pct := 0.0
			if total > 0:
				pct = float(counts[c]) / float(total)
			bar_fills[i][c].size = Vector2(pct * TRACK_W, TRACK_H)
			var lbl: Label = bar_labels[i][c]
			lbl.text = "%d%% (%d)" % [int(round(pct * 100)), counts[c]]
			lbl.add_theme_color_override("font_color",
				Color(1.0, 0.85, 0.2) if (total > 0 and c == lead and counts[c] > 0)
				else Color(0.86, 0.86, 0.90))

func _sample_graph(delta):
	if pen_graphs.is_empty():
		return
	graph_sample_timer += delta
	if graph_sample_timer < GRAPH_SAMPLE_INTERVAL:
		return
	graph_sample_timer = 0.0
	for i in range(2):
		var counts := _pen_counts(i)
		var total: int = _pen_alive(i).size()
		var pcts: Array = [0.0, 0.0, 0.0]
		if total > 0:
			for c in range(3):
				pcts[c] = float(counts[c]) / float(total) * 100.0
		pen_graphs[i].add_sample(sim_time, pcts)

func _update_pop_label():
	var pop_label = get_node_or_null("PopLabel")
	if not pop_label:
		return
	var mins = int(sim_time) / 60
	var secs = int(sim_time) % 60
	pop_label.text = "Drift pen: %d / %d     Selection pen: %d / %d     Time: %d:%02d" % [
		_pen_alive(0).size(), PEN_CAP, _pen_alive(1).size(), PEN_CAP, mins, secs]

# ---------------------------------------------------------------------------
#  NARRATION
# ---------------------------------------------------------------------------
func _check_captions():
	if not growth_done:
		return

	for i in range(2):
		if not announced[i] and _pen_alive(i).size() > 0 and _pen_colors_present(i) == 1:
			announced[i] = true
			pen_resolved[i] = true
			var counts := _pen_counts(i)
			var win := 0
			for c in range(3):
				if counts[c] > 0:
					win = c
			if i == SELECTION_PEN:
				_set_caption("The selection pen has fixed on %s — the advantaged color. Re-run this and it will almost certainly be %s again." % [
					preset_color_names[win], preset_color_names[win]])
			else:
				_set_caption("The drift pen has fixed on %s. Nothing made %s better there — re-run it and expect a different winner." % [
					preset_color_names[win], preset_color_names[win]])
			return

	var red_pct: float = _pct(SELECTION_PEN, ADVANTAGED_COLOR)
	if not advantage_caption_shown and red_pct >= 60.0:
		advantage_caption_shown = true
		_set_caption("Red is pulling clear on the right — steadily, not by luck. That steady climb is what selection looks like.")
		return

	if not mid_caption_shown and sim_time > MATURATION_TIME + 15.0:
		mid_caption_shown = true
		_set_caption("Compare the two graphs. One set of lines wanders aimlessly; the other has somewhere to go.")

func _pct(pen: int, color: int) -> float:
	var total: int = _pen_alive(pen).size()
	if total == 0:
		return 0.0
	return float(_pen_counts(pen)[color]) / float(total) * 100.0

# ---------------------------------------------------------------------------
#  END
# ---------------------------------------------------------------------------
func _check_end():
	for i in range(2):
		if _pen_alive(i).size() == 0 or _pen_colors_present(i) <= 1:
			pen_resolved[i] = true
	if (pen_resolved[0] and pen_resolved[1]) or sim_time >= p_time_cap:
		_record_run()
		_finish(_summary())

func _record_run():
	runs_counted += 1
	for i in range(2):
		if _pen_alive(i).size() > 0 and _pen_colors_present(i) == 1:
			var counts := _pen_counts(i)
			for c in range(3):
				if counts[c] > 0:
					if i == 0:
						wins_drift[c] += 1
					else:
						wins_select[c] += 1

func _leader(i: int) -> int:
	var counts := _pen_counts(i)
	var lead := 0
	for c in range(3):
		if counts[c] > counts[lead]:
			lead = c
	return lead

func _summary() -> String:
	var d_lead: int = _leader(0)
	var s_red: float = _pct(SELECTION_PEN, ADVANTAGED_COLOR)
	var d_red: float = _pct(0, ADVANTAGED_COLOR)

	return "[b]Left pen (drift): %s came out on top. Right pen (selection): red reached %.0f%%.[/b]\n\nBoth pens had the same size, the same crowding, the same randomness. The only difference was that red lived longer on the right.\n\n[b]Drift[/b] moved the left pen around — red ended at %.0f%% there, up or down purely by accident. Run it again and a different color will lead. There is no direction to it.\n\n[b]Selection[/b] moved the right pen too, but toward a specific answer. Run it again and red will climb again, because a longer life genuinely produces more offspring. Chance still decides the details; it no longer decides the destination.\n\nThat's the distinction this whole lab rests on: [b]drift is change without direction[/b]. The moment a trait changes how many offspring an individual leaves, you've stopped modelling drift and started modelling evolution by natural selection." % [
		preset_color_names[d_lead], s_red, d_red]

# ---------------------------------------------------------------------------
#  RESULTS CARD
# ---------------------------------------------------------------------------
func _build_comparison():
	for child in compare_box.get_children():
		child.queue_free()

	for i in range(2):
		var head := Label.new()
		head.text = NAMES[i] + " pen"
		head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		head.add_theme_font_size_override("font_size", 15)
		head.add_theme_color_override("font_color", ACCENTS[i])
		compare_box.add_child(head)

		var end_counts := _pen_counts(i)
		var end_total: int = _pen_alive(i).size()

		for c in range(3):
			var s_pct := 0
			var e_pct := 0
			if pen_start_totals[i] > 0:
				s_pct = int(round(float(pen_start_counts[i][c]) / float(pen_start_totals[i]) * 100.0))
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
			if i == SELECTION_PEN and c == ADVANTAGED_COLOR:
				name_lbl.text += " ★"
			name_lbl.custom_minimum_size = Vector2(74, 0)
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

		if i == 0:
			compare_box.add_child(HSeparator.new())

	# --- cross-run tally: the real proof ---
	var total_d := 0
	var total_s := 0
	for w in wins_drift:
		total_d += int(w)
	for w in wins_select:
		total_s += int(w)
	if total_d + total_s == 0:
		return

	compare_box.add_child(HSeparator.new())
	var h := Label.new()
	h.text = "Winners across %d run%s" % [runs_counted, "" if runs_counted == 1 else "s"]
	h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	h.add_theme_font_size_override("font_size", 15)
	h.add_theme_color_override("font_color", Color(0.62, 0.62, 0.68))
	compare_box.add_child(h)

	for i in range(2):
		var arr: Array = wins_drift if i == 0 else wins_select
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		compare_box.add_child(row)

		var tag := Label.new()
		tag.text = NAMES[i]
		tag.custom_minimum_size = Vector2(96, 0)
		tag.add_theme_font_size_override("font_size", 15)
		tag.add_theme_color_override("font_color", ACCENTS[i])
		row.add_child(tag)

		for c in range(3):
			var chip := Label.new()
			chip.text = "%s %d " % [preset_color_names[c].substr(0, 1), int(arr[c])]
			chip.add_theme_font_size_override("font_size", 15)
			chip.add_theme_color_override("font_color",
				preset_color_tints[c] if int(arr[c]) > 0 else Color(0.45, 0.45, 0.52))
			row.add_child(chip)

	var note := Label.new()
	note.text = "Drift's winner should keep changing. Selection's shouldn't."
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.add_theme_font_size_override("font_size", 14)
	note.add_theme_color_override("font_color", Color(0.58, 0.58, 0.66))
	compare_box.add_child(note)
