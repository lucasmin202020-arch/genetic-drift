extends MultiPen

# ===========================================================================
#  PRESET: PARALLEL WORLDS
#
#  Nine tiny populations, in a 3x3 grid, each starting from EXACTLY the same
#  mix (2 red, 2 green, 2 blue). They run at the same time, sealed off from
#  each other.
#
#  THE LESSON: identical starting conditions do not produce identical
#  outcomes. Some worlds end up red, some green, some blue. Nothing about
#  the setup predicts which. That unpredictability IS drift — and it's also
#  why two isolated populations of the same species slowly become different
#  from one another.
#
#  The stacked frequency bar each world draws along its bottom edge now lives
#  in MultiPen, so every pen in every preset has one. This script only adds
#  what's specific to Parallel Worlds: the border turning the winner's colour,
#  the FIXED / EMPTY tag, and the veil over a settled world.
#
#  SETUP:
#    1. Open CoinFlip.tscn -> Scene -> "Save Scene As..." -> ParallelWorlds.tscn
#    2. Select the ROOT node of the NEW scene (check the tab!)
#    3. Clear coin_flip.gd, attach parallel_worlds.gd.
#    4. Confirm Blob Scene + the 5 textures are assigned. Save at once.
# ===========================================================================

const WORLDS := 9
const PER_WORLD := 6              # starting blobs: 2 of each colour
# The cap sits ABOVE the starting count on purpose. If a pen starts full,
# no baby can be born until somebody dies — which is a whole lifespan of
# nothing happening right after the blobs mature. The headroom means births
# begin the moment everyone is an adult.
const WORLD_CAP := 9
const GRID_COLS := 3
const GRID_ROWS := 3
const CELL_GAP_X := 26.0
const CELL_GAP_Y := 34.0          # extra room for each world's name plate

# Cross-run tally, kept for the whole session.
static var run_wins: Array = [0, 0, 0]
static var run_unresolved: int = 0
static var runs_played: int = 0

# --- this run ---
var fixed_flash: Array = []       # seconds of highlight left, per world
var pen_frozen: Array = []        # a settled world stops running entirely
var first_fix_shown: bool = false
var half_fix_shown: bool = false

# --- panel widgets ---
var lbl_progress: Label
var tally_rows: Array = []
var lbl_alltime: Label
var alltime_rows: Array = []

func _ready():
	pen_caps = []
	pen_start_mix = []
	pen_titles = []
	pen_accents = []
	for i in range(WORLDS):
		pen_caps.append(WORLD_CAP)
		pen_start_mix.append([2, 2, 2])
		pen_titles.append("World %d" % (i + 1))
		pen_accents.append(Color(0.52, 0.55, 0.66))
	blob_spawn_scale = 0.055
	blob_mature_scale = 0.08
	pen_title_size = 13
	p_lifespan = 26.0
	p_time_cap = 170.0
	p_speed_index = 3
	super._ready()

func _on_run_reset():
	fixed_flash = []
	pen_frozen = []
	for i in range(WORLDS):
		fixed_flash.append(0.0)
		pen_frozen.append(false)
	first_fix_shown = false
	half_fix_shown = false

# ---------------------------------------------------------------------------
#  LAYOUT — a 3x3 grid of equal cells, separated by plain air gaps
# ---------------------------------------------------------------------------
func _layout_pens() -> Array:
	var cell_w: float = (lab_rect.size.x - CELL_GAP_X * float(GRID_COLS - 1)) / float(GRID_COLS)
	var cell_h: float = (lab_rect.size.y - CELL_GAP_Y * float(GRID_ROWS - 1)) / float(GRID_ROWS)
	var out: Array = []
	for row in range(GRID_ROWS):
		for c in range(GRID_COLS):
			out.append(Rect2(
				lab_rect.position.x + float(c) * (cell_w + CELL_GAP_X),
				lab_rect.position.y + float(row) * (cell_h + CELL_GAP_Y),
				cell_w, cell_h))
	return out

# ---------------------------------------------------------------------------
#  IN-PEN DRAWING — border turns the winner's colour, plus the tag and veil
# ---------------------------------------------------------------------------
func _pen_border_color(i: int, default_col: Color) -> Color:
	if i >= pens.size():
		return default_col
	var alive_n: int = _pen_alive(i).size()
	if alive_n == 0:
		return Color(0.45, 0.45, 0.50)
	if _pen_colors_present(i) == 1:
		var counts := _pen_counts(i)
		for c in range(3):
			if counts[c] > 0:
				var col: Color = preset_color_tints[c]
				# brief brighten right after it fixes
				if i < fixed_flash.size() and fixed_flash[i] > 0.0:
					return col.lightened(0.35)
				return col
	return default_col

func _draw_pen_extras(ov, i: int, r: Rect2):
	# The stacked frequency bar comes from MultiPen — draw it first so the
	# veil below can dim it along with everything else in a settled world.
	super._draw_pen_extras(ov, i, r)

	var counts := _pen_counts(i)
	var total := 0
	for c in counts:
		total += c

	# a settled world is frozen — veil it so finished pens read as finished
	if i < pen_frozen.size() and pen_frozen[i]:
		ov.draw_rect(r, Color(0.05, 0.05, 0.07, 0.32), true)

	# --- FIXED / EMPTY tag ---
	var font := ThemeDB.fallback_font
	var tag := ""
	var tag_col := Color.WHITE
	if total == 0:
		tag = "EMPTY"
		tag_col = Color(0.62, 0.62, 0.68)
	elif _pen_colors_present(i) == 1:
		for c in range(3):
			if counts[c] > 0:
				tag = "FIXED"
				tag_col = preset_color_tints[c]
	if tag != "":
		var tw: float = font.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		var chip := Rect2(r.position.x + r.size.x * 0.5 - tw * 0.5 - 8.0,
			r.position.y + 6.0, tw + 16.0, 20.0)
		var cs := StyleBoxFlat.new()
		cs.bg_color = Color(0.08, 0.08, 0.11, 0.92)
		cs.border_color = Color(tag_col.r, tag_col.g, tag_col.b, 0.9)
		cs.set_border_width_all(1)
		cs.set_corner_radius_all(5)
		ov.draw_style_box(cs, chip)
		ov.draw_string(font, Vector2(chip.position.x + 8.0, chip.position.y + 15.0),
			tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, tag_col)

# ---------------------------------------------------------------------------
#  SCENARIO TEXT
# ---------------------------------------------------------------------------
func _preset_title() -> String:
	return "Parallel Worlds"

func _preset_intro_bbcode() -> String:
	return "Nine separate worlds, each sealed off in its own pen, all running at the same time.\n\nEvery world starts [b]completely identical[/b]: 6 blobs — 2 red, 2 green, 2 blue. Same rules everywhere. No color is favoured in any of them, and no world is different from any other in any way.\n\nEach pen shows its own [b]stacked bar[/b] along the bottom: the width of each color is how common it is right now. When a world drops to a single color it's [b]FIXED[/b], its border turns that color, and it's done.\n\nWith three equal colors you'd expect roughly [b]three worlds each[/b] — but any single run will scatter."

func _preset_questions() -> Array:
	return [
		"All nine worlds start identical. Will they end identical?",
		"How many of the nine do you think land on the same color?",
		"If this were survival-of-the-fittest instead of drift, what would the nine endings look like?",
	]

# ---------------------------------------------------------------------------
#  PANEL
# ---------------------------------------------------------------------------
func _build_graph():
	var vbox = get_node_or_null("UIPanel/VBox")
	if not vbox:
		return
	ui_nodes.clear()
	tally_rows.clear()
	alltime_rows.clear()

	lbl_progress = Label.new()
	lbl_progress.text = "Worlds settled: 0 / 9"
	lbl_progress.add_theme_font_size_override("font_size", 16)
	lbl_progress.add_theme_color_override("font_color", Color(0.90, 0.90, 0.94))
	vbox.add_child(lbl_progress)
	ui_nodes.append(lbl_progress)

	var head := Label.new()
	head.text = "This run"
	head.add_theme_font_size_override("font_size", 14)
	head.add_theme_color_override("font_color", Color(0.60, 0.60, 0.68))
	vbox.add_child(head)
	ui_nodes.append(head)

	for c in range(3):
		var row := _tally_row(c)
		vbox.add_child(row["row"])
		ui_nodes.append(row["row"])
		tally_rows.append(row["value"])

	var sep := HSeparator.new()
	vbox.add_child(sep)
	ui_nodes.append(sep)

	lbl_alltime = Label.new()
	lbl_alltime.text = "Across all your runs"
	lbl_alltime.add_theme_font_size_override("font_size", 14)
	lbl_alltime.add_theme_color_override("font_color", Color(0.60, 0.60, 0.68))
	vbox.add_child(lbl_alltime)
	ui_nodes.append(lbl_alltime)

	for c in range(3):
		var row := _tally_row(c)
		vbox.add_child(row["row"])
		ui_nodes.append(row["row"])
		alltime_rows.append(row["value"])

	for n in ui_nodes:
		n.visible = false

func _tally_row(color_idx: int) -> Dictionary:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 9)

	var swatch := ColorRect.new()
	swatch.color = preset_color_tints[color_idx]
	swatch.custom_minimum_size = Vector2(13, 13)
	var wrap := CenterContainer.new()
	wrap.custom_minimum_size = Vector2(18, 0)
	wrap.add_child(swatch)
	row.add_child(wrap)

	var name_lbl := Label.new()
	name_lbl.text = preset_color_names[color_idx]
	name_lbl.custom_minimum_size = Vector2(58, 0)
	name_lbl.add_theme_font_size_override("font_size", 14)
	row.add_child(name_lbl)

	var val := Label.new()
	val.text = "0 worlds"
	val.add_theme_font_size_override("font_size", 14)
	val.add_theme_color_override("font_color", Color(0.86, 0.86, 0.90))
	row.add_child(val)

	return {"row": row, "value": val}

func update_tracker():
	if lbl_progress == null:
		return
	var settled := 0
	var wins := [0, 0, 0]
	for i in range(pens.size()):
		var total: int = _pen_alive(i).size()
		if total == 0:
			settled += 1
			continue
		if _pen_colors_present(i) == 1:
			settled += 1
			var counts := _pen_counts(i)
			for c in range(3):
				if counts[c] > 0:
					wins[c] += 1

	lbl_progress.text = "Worlds settled: %d / %d" % [settled, WORLDS]
	for c in range(3):
		if c < tally_rows.size():
			var lbl: Label = tally_rows[c]
			lbl.text = "%d world%s" % [wins[c], "" if wins[c] == 1 else "s"]
			lbl.add_theme_color_override("font_color",
				preset_color_tints[c] if wins[c] > 0 else Color(0.55, 0.55, 0.60))

	var total_all := 0
	for w in run_wins:
		total_all += int(w)
	for c in range(3):
		if c < alltime_rows.size():
			var lbl2: Label = alltime_rows[c]
			if total_all == 0:
				lbl2.text = "—"
				lbl2.add_theme_color_override("font_color", Color(0.55, 0.55, 0.60))
			else:
				var pct: int = int(round(float(run_wins[c]) / float(total_all) * 100.0))
				lbl2.text = "%d  (%d%%)" % [int(run_wins[c]), pct]
				lbl2.add_theme_color_override("font_color", Color(0.86, 0.86, 0.90))

func _sample_graph(_delta):
	pass   # nine worlds are read from the pens themselves, not a panel graph

# ---------------------------------------------------------------------------
#  NARRATION
# ---------------------------------------------------------------------------
func _process(delta):
	super._process(delta)
	for i in range(fixed_flash.size()):
		if fixed_flash[i] > 0.0:
			fixed_flash[i] -= delta
	if simulation_running and not ended:
		_update_world_states()

# A world that has settled is done — freeze it so it sits there as a finished
# result instead of a pen of blobs still milling about with nothing to decide.
func _update_world_states():
	for i in range(pens.size()):
		if i >= pen_frozen.size() or pen_frozen[i]:
			continue
		var total: int = _pen_alive(i).size()
		if total == 0 or _pen_colors_present(i) == 1:
			pen_resolved[i] = true
			pen_frozen[i] = true
			if i < fixed_flash.size():
				fixed_flash[i] = 1.2
			_freeze_world(i)

func _freeze_world(i: int):
	for b in blobs:
		if is_instance_valid(b) and _pen_index_of(b) == i:
			b.set_physics_process(false)

func _check_captions():
	if not growth_done:
		return
	var settled := 0
	for i in range(pen_frozen.size()):
		if pen_frozen[i]:
			settled += 1

	if settled >= 1 and not first_fix_shown:
		first_fix_shown = true
		_set_caption("First world settled. Every world began with exactly the same six blobs — but they're already coming apart.")
		return
	if settled >= 5 and not half_fix_shown:
		half_fix_shown = true
		_set_caption("Over half of them have settled, and they're not agreeing. Same start, different endings — that's the whole point.")
		return
	if not mid_caption_shown and sim_time > MATURATION_TIME + 14.0:
		mid_caption_shown = true
		_set_caption("Nine identical experiments running at once. Watch the bars in each pen slide in different directions.")

# ---------------------------------------------------------------------------
#  END
# ---------------------------------------------------------------------------
func _check_end():
	var settled := 0
	for i in range(pen_frozen.size()):
		if pen_frozen[i]:
			settled += 1
	if settled >= WORLDS or sim_time >= p_time_cap:
		_record_run()
		_finish(_summary())

func _record_run():
	runs_played += 1
	for i in range(pens.size()):
		var total: int = _pen_alive(i).size()
		if total == 0:
			run_unresolved += 1
			continue
		if _pen_colors_present(i) == 1:
			var counts := _pen_counts(i)
			for c in range(3):
				if counts[c] > 0:
					run_wins[c] += 1
		else:
			run_unresolved += 1

func _this_run_wins() -> Array:
	var wins := [0, 0, 0]
	for i in range(pens.size()):
		if _pen_alive(i).size() > 0 and _pen_colors_present(i) == 1:
			var counts := _pen_counts(i)
			for c in range(3):
				if counts[c] > 0:
					wins[c] += 1
	return wins

func _summary() -> String:
	var wins := _this_run_wins()
	var settled: int = wins[0] + wins[1] + wins[2]
	var parts: Array = []
	for c in range(3):
		parts.append("%s %d" % [preset_color_names[c], wins[c]])

	var spread := "they did not all agree"
	if settled > 0:
		var max_w: int = wins.max()
		if max_w == settled:
			spread = "they all happened to land on the same color this time — which is itself just luck"

	return "[b]Nine identical worlds. %s.[/b]\n\nEvery pen started with the same six blobs, the same rules, and the same odds — and %s.\n\nThere was nothing different about world 1 and world 9 at the start. No color was stronger anywhere. The only thing separating these outcomes is [b]which blobs happened to bump into which[/b].\n\nThis is what people mean when they call drift [b]random[/b]: not that anything is unfair, but that the outcome genuinely cannot be predicted from the starting conditions.\n\nIt's also why isolated populations of one species slowly [b]diverge[/b]. Cut a species into nine separate groups and, given enough time, you get nine different-looking groups — with no selection involved at all." % [
		", ".join(parts), spread]

# ---------------------------------------------------------------------------
#  RESULTS CARD
# ---------------------------------------------------------------------------
func _build_comparison():
	for child in compare_box.get_children():
		child.queue_free()

	var wins := _this_run_wins()
	var settled: int = wins[0] + wins[1] + wins[2]

	var head := Label.new()
	head.text = "How the nine worlds ended"
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_font_size_override("font_size", 15)
	head.add_theme_color_override("font_color", Color(0.62, 0.62, 0.68))
	compare_box.add_child(head)

	for c in range(3):
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

		# a little bar of squares, one per world won
		var squares := HBoxContainer.new()
		squares.add_theme_constant_override("separation", 3)
		squares.custom_minimum_size = Vector2(120, 0)
		for k in range(WORLDS):
			var pip := ColorRect.new()
			pip.custom_minimum_size = Vector2(10, 14)
			pip.color = preset_color_tints[c] if k < wins[c] else Color(0.22, 0.22, 0.27)
			squares.add_child(pip)
		row.add_child(squares)

		var val := Label.new()
		val.text = "%d" % wins[c]
		val.custom_minimum_size = Vector2(28, 0)
		val.add_theme_font_size_override("font_size", 15)
		val.add_theme_color_override("font_color", preset_color_tints[c])
		row.add_child(val)

	var note := Label.new()
	var unresolved: int = WORLDS - settled
	if unresolved > 0:
		note.text = "%d world%s hadn't settled when time ran out. Expected split with three equal colors: 3 / 3 / 3." % [
			unresolved, "" if unresolved == 1 else "s"]
	else:
		note.text = "Expected split with three equal colors: 3 / 3 / 3."
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(500, 0)
	note.add_theme_font_size_override("font_size", 14)
	note.add_theme_color_override("font_color", Color(0.58, 0.58, 0.66))
	compare_box.add_child(note)

	# --- cross-run totals ---
	var total_all := 0
	for w in run_wins:
		total_all += int(w)
	if total_all > 0:
		compare_box.add_child(HSeparator.new())
		var h2 := Label.new()
		h2.text = "Every world you've run (%d run%s)" % [runs_played, "" if runs_played == 1 else "s"]
		h2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		h2.add_theme_font_size_override("font_size", 15)
		h2.add_theme_color_override("font_color", Color(0.62, 0.62, 0.68))
		compare_box.add_child(h2)

		for c in range(3):
			var pct: int = int(round(float(run_wins[c]) / float(total_all) * 100.0))
			var r2 := HBoxContainer.new()
			r2.add_theme_constant_override("separation", 10)
			r2.alignment = BoxContainer.ALIGNMENT_CENTER
			compare_box.add_child(r2)

			var sw2 := ColorRect.new()
			sw2.color = preset_color_tints[c]
			sw2.custom_minimum_size = Vector2(15, 15)
			var w2 := CenterContainer.new()
			w2.custom_minimum_size = Vector2(24, 0)
			w2.add_child(sw2)
			r2.add_child(w2)

			var n2 := Label.new()
			n2.text = preset_color_names[c]
			n2.custom_minimum_size = Vector2(64, 0)
			n2.add_theme_font_size_override("font_size", 15)
			r2.add_child(n2)

			var v2 := Label.new()
			v2.text = "%d worlds   (%d%%)   ·   expected 33%%" % [int(run_wins[c]), pct]
			v2.add_theme_font_size_override("font_size", 15)
			v2.add_theme_color_override("font_color",
				Color(0.50, 0.92, 0.55) if (total_all >= 18 and abs(pct - 33) <= 10)
				else Color(0.86, 0.86, 0.92))
			r2.add_child(v2)
