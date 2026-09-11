extends "res://Scripts/game.gd"
class_name DriftPreset

# ===========================================================================
#  PRESET: RANDOMNESS — THE BASIS OF GENETIC DRIFT
#
#  INHERITS from game.gd, reusing the entire Playground scene and UI.
#
#  This script also doubles as the BASE for other single-population presets
#  (see long_shot.gd, which does `extends DriftPreset`) AND for the whole
#  Drift Events mode (see drift_event.gd).
#  Everything a scenario is likely to change is either a variable (set it in
#  _ready BEFORE calling super._ready()) or an overridable method:
#
#     p_start_mix      blobs of each color at the start  [red, green, blue]
#     p_max_pop        population ceiling
#     p_lifespan       base lifespan (jittered per blob)
#     p_time_cap       sim-seconds before ending without fixation
#     p_speed_index    0..4 -> 0.25x .. 1.25x
#
#     _preset_title()             card + intro heading
#     _preset_intro_bbcode()      intro card body text — THE SCIENCE section,
#                                 which should end by appending _howto_bbcode()
#     _howto_bbcode()             HOW THIS SIMULATION WORKS + WHAT TO DO. Shown
#                                 at the end of the intro AND on demand from the
#                                 help button in the side panel, which pauses
#                                 the whole sim while it's open.
#     _preset_questions()         the three PREDICT FIRST questions
#     _build_extra_end_content()  extra widgets on the results card
#     _refresh_extra_end_content()refresh them when a run finishes
#     _end_fixation/_end_timecap/_end_extinct   result wording
#     _menu_scene_path()          where the back/exit buttons go
#     _menu_button_text()         what the exit button is called
#
#  HELP BUTTON
#  -----------
#  A standalone amber "?  What do I do?" button sits in the side panel between
#  the speed slider and whatever controls the scenario adds. It's built here
#  once, so every preset and every event has it without any per-file work.
#  It opens HowToPopup (res://Scripts/howto_popup.gd) with _howto_bbcode().
#
#  SETUP:
#    1. Open Game.tscn -> Scene -> "Save Scene As..." -> CoinFlip.tscn
#    2. Select the ROOT node of the NEW scene (check the tab says CoinFlip!)
#    3. Clear game.gd, attach coin_flip.gd.
#    4. Confirm Blob Scene + the 5 textures are assigned. Save at once.
# ===========================================================================

const PRESET_MENU_SCENE := "res://Scenes/PresetMenu.tscn"

# --- FIXED ACROSS ALL PRESETS ---
const MATURATION_TIME := 9.0   # must match blob.gd's maturation_time
const FIXED_SHAPE := 0
const FIXED_EYES := 1
const GRACE_PERIOD := 1.5
const LIFESPAN_JITTER := 0.28

# --- PER-SCENARIO TUNABLES ---
# These values are THIS scenario's settings (an even 4/4/4 split). Subclasses
# overwrite them in their own _ready() before calling super._ready().
# Drift strength scales as 1/N, so a small cap keeps chance visible.
var p_start_mix: Array = [4, 4, 4]    # [red, green, blue] — even start
var p_max_pop: int = 16
var p_lifespan: float = 32.0
var p_time_cap: float = 180.0
var p_speed_index: int = 3             # 1.0x

# --- PANEL SIZING ---
const CHART_BAR_WIDTH := 150.0
const CHART_BAR_HEIGHT := 24.0
const CHART_FONT_SIZE := 16
const TRACKER_HEIGHT := 200.0
const GRAPH_HEIGHT := 130.0

# Cards never grow taller than the viewport minus this margin; past that
# they scroll internally instead of running off the bottom of the screen.
const CARD_VERTICAL_MARGIN := 90.0

# --- PREDICT-FIRST PANEL COLORS ---
const PREDICT_ACCENT := Color(0.95, 0.78, 0.38)

# --- HELP BUTTON ---
# Same amber as the PREDICT FIRST block, so "instructions" always look the
# same wherever they appear, and never the blue of Begin or the red of Fire.
const HELP_ACCENT := PREDICT_ACCENT

# --- PRESET STATE ---
var ended: bool = false
var lost_announced: Array[bool] = [false, false, false]
var mid_caption_shown: bool = false
var growth_done: bool = false
var start_counts: Array = [0, 0, 0]
var start_total: int = 0
var graph_sample_timer: float = 0.0
const GRAPH_SAMPLE_INTERVAL := 0.25

# --- PRESET UI ---
var preset_layer: CanvasLayer
var graph: FreqGraph
var caption_box: PanelContainer
var caption_label: Label
var intro_card: Control
var end_card: Control
var end_text: RichTextLabel
var compare_box: VBoxContainer
var help_button: Button
var card_scrolls: Array = []     # [{ "scroll": ScrollContainer, "vb": VBoxContainer }]

var preset_color_names: Array[String] = ["Red", "Green", "Blue"]
var preset_color_tints: Array[Color] = [
	Color(1.0, 0.45, 0.45),
	Color(0.45, 0.9, 0.45),
	Color(0.45, 0.65, 1.0)
]

# ===========================================================================
#  FREQUENCY GRAPH
#  Every sample is kept forever. The x axis always spans 0 -> current time,
#  so as the run gets longer the existing points compress leftward instead of
#  scrolling off. Nothing is ever discarded.
#
#  The y axis is labelled 0 / 25 / 50 / 75 / 100 % in a gutter on the left.
# ===========================================================================
class FreqGraph extends Control:
	var samples: Array = []          # [{ "t": float, "pct": [r, g, b] }]
	var max_time: float = 5.0
	var maturity_time: float = 9.0
	# Vertical lines at moments worth marking. Drift Events puts one here when
	# the event fires, so "before" and "after" are visible on the graph itself
	# rather than only in the results card.
	var marks: Array = []            # [{ "t": float }]
	var line_colors: Array[Color] = [
		Color(1.0, 0.42, 0.42),
		Color(0.42, 0.92, 0.42),
		Color(0.42, 0.62, 1.0)
	]

	const GUTTER := 34.0             # left strip reserved for the % labels
	const LABEL_SIZE := 11

	func add_sample(t: float, pcts: Array):
		samples.append({"t": t, "pct": pcts})
		if t > max_time:
			max_time = t
		queue_redraw()

	func clear_samples():
		samples.clear()
		marks.clear()
		max_time = 5.0
		queue_redraw()

	func _draw():
		var full_w := size.x
		var h := size.y
		if full_w <= GUTTER or h <= 0:
			return

		# The plot itself starts after the label gutter.
		var ox := GUTTER
		var w := full_w - GUTTER
		var plot := Rect2(ox, 0, w, h)

		draw_rect(plot, Color(0.085, 0.085, 0.105), true)

		# shaded "growing up" region — nothing can reproduce in here
		var mx: float = (maturity_time / max_time) * w
		mx = clamp(mx, 0.0, w)
		if mx > 1.0:
			draw_rect(Rect2(ox, 0, mx, h), Color(0.30, 0.26, 0.16, 0.45), true)
			draw_line(Vector2(ox + mx, 0), Vector2(ox + mx, h), Color(0.75, 0.62, 0.30, 0.8), 1.0)

		# gridlines + y-axis labels at 0 / 25 / 50 / 75 / 100 %
		var font := get_theme_default_font()
		var label_col := Color(0.60, 0.60, 0.68)
		for i in range(5):
			var pct: int = i * 25
			var gy: float = h - (float(i) / 4.0) * h
			var gcol := Color(0.22, 0.22, 0.27)
			if i == 2:
				gcol = Color(0.32, 0.32, 0.38)   # midline, slightly brighter
			draw_line(Vector2(ox, gy), Vector2(ox + w, gy), gcol, 1.0)

			# small tick into the gutter
			draw_line(Vector2(ox - 4.0, gy), Vector2(ox, gy), Color(0.38, 0.38, 0.45), 1.0)

			if font:
				var txt := "%d%%" % pct
				var tw: float = font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT,
					-1, LABEL_SIZE).x
				# nudge the top and bottom labels inward so they aren't clipped
				var ty: float = gy + LABEL_SIZE * 0.35
				if i == 4:
					ty = gy + LABEL_SIZE * 0.9
				elif i == 0:
					ty = gy - 1.0
				draw_string(font, Vector2(ox - 8.0 - tw, ty), txt,
					HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE, label_col)

		# event markers, drawn under the traces so they never hide a line
		for m in marks:
			var mtx: float = ox + (float(m["t"]) / max_time) * w
			draw_line(Vector2(mtx, 0), Vector2(mtx, h), Color(1.0, 0.38, 0.30, 0.9), 1.5)

		# the three frequency traces
		if samples.size() >= 2:
			for c in range(3):
				var pts := PackedVector2Array()
				for s in samples:
					var x: float = ox + (float(s["t"]) / max_time) * w
					var y: float = h - (float(s["pct"][c]) / 100.0) * h
					pts.append(Vector2(x, y))
				draw_polyline(pts, line_colors[c], 2.0, true)

		draw_rect(plot, Color(0.28, 0.28, 0.34), false, 1.0)

# ---------------------------------------------------------------------------
#  OVERRIDABLE SCENARIO TEXT
# ---------------------------------------------------------------------------
func _preset_title() -> String:
	return "Randomness: The Basis of Genetic Drift"

func _preset_intro_bbcode() -> String:
	return (
		"[b]THE SCIENCE[/b]\n\n"
		+ "Every individual in a population carries [b]alleles[/b] — alternative versions of a gene. The fraction of the population carrying a particular allele is its [b]allele frequency[/b], and evolution, at its most basic, is a change in allele frequencies over time.\n\n"
		+ "Natural selection is one way frequencies change: an allele that helps its carrier survive or reproduce becomes more common. But it is not the only way. In every generation, some individuals happen to leave more offspring than others for reasons that have nothing to do with their genes — one is eaten before breeding, another gets lucky and has an extra litter. The next generation is therefore a [i]random sample[/i] of the alleles in the current one, and a random sample never perfectly matches what it was drawn from. This sampling error, accumulating generation after generation, is [b]genetic drift[/b].\n\n"
		+ "Drift happens in every population that is not infinitely large, but its strength depends on population size. If one individual in a population of 10 dies without offspring, a tenth of the gene pool is gone in a single step; in a population of 100, the same death removes only one percent. Small populations therefore lurch; large ones are buffered.\n\n"
		+ "Left running long enough, drift has only two endings for any allele. Either it reaches 100% — called [b]fixation[/b] — or it drops to 0% and is lost. Once an allele is lost it cannot return unless mutation recreates it or migration brings it back. Drift does not care whether an allele is useful: it can fix a harmful one or throw away a beneficial one, because nothing about the allele is steering the outcome.\n\n"
		+ "One important consequence: an allele does not have to be better to take over. For a neutral allele — one with no effect on survival or reproduction — its chance of eventually reaching fixation is simply its current frequency. Three equally common colors each have a one-in-three chance of winning, and one of them always does.\n\n"
		+ "[i]Sources: UC Berkeley Understanding Evolution, \"Genetic drift\"; Khan Academy, \"Genetic drift\" (AP Biology, Population genetics); Biology LibreTexts, \"Genetic Drift\" (Raven 12th ed. §20.9.2); OpenStax, Biology for AP Courses §19.2 Population Genetics.[/i]\n\n"
	) + _howto_bbcode()

# Shown at the end of the intro card and, on demand, in the pause popup opened
# by the help button. Every subclass should override this with its own
# mechanics and procedure; this default is Lesson 1's.
func _howto_bbcode() -> String:
	return (
		"[b]HOW THIS SIMULATION WORKS[/b]\n"
		+ "[i]This section is about the sim, not the biology.[/i]\n\n"
		+ "The pen starts with 12 blobs, 4 of each color, and never holds more than 16. Every blob has the same shape and the same eyes; color is the only difference and it does nothing — no color lives longer or breeds faster. Blobs are born small and cannot reproduce until they mature; the graph shades that growing-up period. After that, whenever two adult blobs meet there is a chance they produce a child, and the child inherits one parent's color at random. Blobs also die of old age at random times. The graph traces each color's share of the population over time. The run ends when one color is the only one left, or when time runs out.\n\n"
		+ "[b]WHAT TO DO[/b]\n\n"
		+ "1.  Before pressing Begin, pick the color you think will win and write it down.\n"
		+ "2.  Watch the graph. Note the first time any color drops below 20%.\n"
		+ "3.  When a color disappears, watch whether it ever comes back. (It can't — ask yourself why.)\n"
		+ "4.  Run it at least three times. Keep a tally of which color won each time."
	)

# THREE QUESTIONS THE USER SHOULD ANSWER BEFORE PRESSING BEGIN.
# Every preset overrides this. Prediction before observation is the whole
# point of the exercise — a user who has committed to a guess actually
# notices when the simulation contradicts them.
func _preset_questions() -> Array:
	return [
		"All three colors start dead even. Which one do you predict wins?",
		"If you ran this ten times, how often would the same color win?",
		"Can a color come back after it drops to a single blob? What would have to happen?",
	]

# ---------------------------------------------------------------------------
#  WHERE THE EXIT BUTTONS GO
#  Presets return to the presets menu. Drift Events overrides both of these
#  and returns to the events menu instead. Nothing else in this file needs to
#  know which mode it's running in.
# ---------------------------------------------------------------------------
func _menu_scene_path() -> String:
	return PRESET_MENU_SCENE

func _menu_button_text() -> String:
	return "Presets"

# Hooks for subclasses that want extra widgets on the results card.
func _build_extra_end_content(_vb: VBoxContainer):
	pass

func _refresh_extra_end_content():
	pass

# ---------------------------------------------------------------------------
#  SETUP
# ---------------------------------------------------------------------------
func _ready():
	super._ready()
	max_population = p_max_pop
	spawn_count = _mix_total()
	_apply_speed(p_speed_index)
	_hide_playground_only_controls()
	_declutter_tracker()
	_enlarge_chart()
	_build_help_button()
	_build_graph()
	_build_caption_box()
	_build_preset_overlays()
	get_viewport().size_changed.connect(_fit_cards)
	_show_intro()

func _mix_total() -> int:
	var t := 0
	for n in p_start_mix:
		t += int(n)
	return t

func _hide_playground_only_controls():
	var hide_paths := [
		"UIPanel/VBox/TopButtons",
		"UIPanel/VBox/CommandsLabel",
		"UIPanel/VBox/BtnBottleneck",
		"UIPanel/VBox/BtnUnluckyDeath",
		"UIPanel/VBox/BtnNaturalDisaster",
	]
	for p in hide_paths:
		var n = get_node_or_null(p)
		if n:
			n.visible = false

func _set_gated_visible(vis: bool):
	super._set_gated_visible(vis)
	_hide_playground_only_controls()
	if help_button:
		help_button.visible = vis
	if caption_box:
		caption_box.visible = vis
	if graph:
		graph.visible = vis
	var gl = get_node_or_null("UIPanel/VBox/GraphLabel")
	if gl:
		gl.visible = vis

func _declutter_tracker():
	var tbase := "UIPanel/VBox/TrackerScroll/TrackerVBox/TrackerContainer/"
	for b in ["RoundBar", "StarBar", "FlowerBar", "OneEyeBar", "ThreeEyeBar"]:
		var n = get_node_or_null(tbase + b)
		if n:
			n.visible = false

	var container = get_node_or_null(tbase)
	if container:
		for child in container.get_children():
			if child is HSeparator:
				child.visible = false
			elif child is Label:
				var t: String = child.text.strip_edges()
				if t == "Shape" or t == "Eye Count" or t == "Eye":
					child.visible = false

	for n_path in ["UIPanel/VBox/TrackerScroll/TrackerVBox/DeltaToggle",
			"UIPanel/VBox/TrackerScroll/TrackerVBox/DeltaContainer"]:
		var n = get_node_or_null(n_path)
		if n:
			n.visible = false

func _enlarge_chart():
	bar_max_width = CHART_BAR_WIDTH
	var tbase := "UIPanel/VBox/TrackerScroll/TrackerVBox/TrackerContainer/"
	var rows := [
		["RedBar", "RedFill", "RedPct"],
		["GreenBar", "GreenFill", "GreenPct"],
		["BlueBar", "BlueFill", "BluePct"],
	]
	for r in rows:
		var bar = get_node_or_null(tbase + r[0])
		if bar and bar is Control:
			bar.custom_minimum_size.y = CHART_BAR_HEIGHT + 4.0
		var fill = get_node_or_null(tbase + r[0] + "/" + r[1])
		if fill and fill is Control:
			fill.custom_minimum_size.y = CHART_BAR_HEIGHT
		var lbl = get_node_or_null(tbase + r[0] + "/" + r[2])
		if lbl and lbl is Label:
			lbl.add_theme_font_size_override("font_size", CHART_FONT_SIZE)

	var container = get_node_or_null(tbase)
	if container and container is VBoxContainer:
		container.add_theme_constant_override("separation", 8)

func _fit_tracker_height():
	var ts = get_node_or_null("UIPanel/VBox/TrackerScroll")
	if not ts or not ts.visible:
		return
	ts.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	ts.custom_minimum_size.y = TRACKER_HEIGHT

func _on_back_to_menu():
	Engine.time_scale = 1.0
	get_tree().change_scene_to_file(_menu_scene_path())

# ---------------------------------------------------------------------------
#  HELP BUTTON — shares the header row with "← Menu". The side panel's VBox
#  has no spare height (the caption box already sits at the bottom edge), so
#  the button borrows width from the back button instead of taking a row of
#  its own. game.gd puts the back button at index 0; it gets reparented into
#  an HBox here, with the help button on its right.
# ---------------------------------------------------------------------------
func _build_help_button():
	var vbox = get_node_or_null("UIPanel/VBox")
	if not vbox:
		return

	help_button = Button.new()
	help_button.name = "HelpButton"
	help_button.text = "?  Help"
	help_button.tooltip_text = "Pause the sim and re-read how this scenario works and what to do."
	help_button.custom_minimum_size = Vector2(112, 0)
	help_button.add_theme_font_size_override("font_size", 16)

	# Outlined amber pill: clearly not a sim control, clearly "instructions".
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(HELP_ACCENT.r, HELP_ACCENT.g, HELP_ACCENT.b, 0.12)
	normal.border_color = Color(HELP_ACCENT.r, HELP_ACCENT.g, HELP_ACCENT.b, 0.90)
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(8)
	normal.content_margin_left = 12
	normal.content_margin_right = 12
	normal.content_margin_top = 4
	normal.content_margin_bottom = 4
	var hover: StyleBoxFlat = normal.duplicate()
	hover.bg_color = Color(HELP_ACCENT.r, HELP_ACCENT.g, HELP_ACCENT.b, 0.25)
	var pressed: StyleBoxFlat = normal.duplicate()
	pressed.bg_color = Color(HELP_ACCENT.r, HELP_ACCENT.g, HELP_ACCENT.b, 0.35)

	help_button.add_theme_stylebox_override("normal", normal)
	help_button.add_theme_stylebox_override("hover", hover)
	help_button.add_theme_stylebox_override("pressed", pressed)
	help_button.add_theme_stylebox_override("focus", normal)
	help_button.add_theme_color_override("font_color", HELP_ACCENT)
	help_button.add_theme_color_override("font_hover_color", HELP_ACCENT.lightened(0.15))
	help_button.add_theme_color_override("font_pressed_color", HELP_ACCENT)
	help_button.add_theme_color_override("font_focus_color", HELP_ACCENT)
	help_button.visible = false
	help_button.pressed.connect(_on_help_pressed)

	# Find the back button game.gd made, and put it and the help button in
	# one row at the same index, so the rest of the panel doesn't shift.
	var back: Button = null
	for ch in vbox.get_children():
		if ch is Button and str(ch.text).begins_with("←"):
			back = ch
			break

	var row := HBoxContainer.new()
	row.name = "HeaderRow"
	row.add_theme_constant_override("separation", 8)

	if back:
		var idx: int = back.get_index()
		vbox.remove_child(back)
		vbox.add_child(row)
		vbox.move_child(row, idx)
		back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(back)
	else:
		vbox.add_child(row)
		vbox.move_child(row, 0)

	row.add_child(help_button)

func _on_help_pressed():
	HowToPopup.open(self, _preset_title(), _howto_bbcode())

# ---------------------------------------------------------------------------
#  SIDE-PANEL ADDITIONS
# ---------------------------------------------------------------------------
func _build_graph():
	var vbox = get_node_or_null("UIPanel/VBox")
	if not vbox:
		return

	var header := Label.new()
	header.name = "GraphLabel"
	header.text = "Frequency over time"
	header.add_theme_font_size_override("font_size", 14)
	header.add_theme_color_override("font_color", Color(0.62, 0.62, 0.70))
	header.visible = false
	vbox.add_child(header)

	graph = FreqGraph.new()
	graph.maturity_time = MATURATION_TIME
	graph.custom_minimum_size = Vector2(0, GRAPH_HEIGHT)
	graph.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	graph.visible = false
	vbox.add_child(graph)

func _build_caption_box():
	var vbox = get_node_or_null("UIPanel/VBox")
	if not vbox:
		return

	caption_box = PanelContainer.new()
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.115, 0.115, 0.145)
	s.border_color = Color(0.26, 0.26, 0.32)
	s.set_border_width_all(1)
	s.set_corner_radius_all(8)
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	caption_box.add_theme_stylebox_override("panel", s)
	caption_box.visible = false
	vbox.add_child(caption_box)

	caption_label = Label.new()
	caption_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caption_label.custom_minimum_size = Vector2(0, 66)
	caption_label.add_theme_font_size_override("font_size", 14)
	caption_label.add_theme_color_override("font_color", Color(0.86, 0.86, 0.90))
	caption_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	caption_box.add_child(caption_label)

func _set_caption(text: String):
	if caption_label:
		caption_label.text = text

# ---------------------------------------------------------------------------
#  RUN CONTROL
# ---------------------------------------------------------------------------
func start_simulation():
	if blob_scene == null:
		push_error("Preset: Blob Scene is not assigned on the root node.")
		return
	simulation_running = true
	sim_time = 0.0
	births = 0
	deaths = 0
	ended = false
	growth_done = false
	lost_announced = [false, false, false]
	mid_caption_shown = false
	graph_sample_timer = 0.0
	if graph:
		graph.clear_samples()
	_set_gated_visible(true)
	_fit_tracker_height.call_deferred()
	_spawn_preset_population()
	set_blobs_paused(false)
	update_tracker()
	start_counts = _color_counts()
	start_total = _alive().size()
	_set_caption("Growing up. Blobs are born small and can't reproduce until they reach full size — that's why nothing is happening yet.")

# Rolled per blob, independent of color, so no allele gets an advantage.
# Without this the founding cohort would all die at the same instant and the
# population could wipe out before anything drifted.
func _rolled_lifespan() -> float:
	return p_lifespan * randf_range(1.0 - LIFESPAN_JITTER, 1.0 + LIFESPAN_JITTER)

func _spawn_preset_population():
	var colors: Array = []
	for c in range(3):
		for i in range(int(p_start_mix[c])):
			colors.append(c)
	colors.shuffle()
	for c in colors:
		var blob = _create_blob()
		blob.setup(FIXED_SHAPE, c, FIXED_EYES,
			[blob_tex_1, blob_tex_2, blob_tex_3], [eye_tex_1, eye_tex_2])
		blob.lifespan = _rolled_lifespan()

func spawn_blob_from_parents(traits_a: Dictionary, traits_b: Dictionary, pos: Vector2):
	var blob = blob_scene.instantiate()
	add_child(blob)
	blob.global_position = Vector2(
		clamp(pos.x, world_bounds.position.x, world_bounds.end.x),
		clamp(pos.y, world_bounds.position.y, world_bounds.end.y)
	)
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

func _process(delta):
	super._process(delta)
	if not simulation_running or ended:
		return

	_sample_graph(delta)
	_update_growth_phase()

	if sim_time < GRACE_PERIOD:
		return
	_check_captions()
	_check_end()

func _sample_graph(delta):
	if not graph:
		return
	graph_sample_timer += delta
	if graph_sample_timer < GRAPH_SAMPLE_INTERVAL:
		return
	graph_sample_timer = 0.0
	var counts := _color_counts()
	var total: int = _alive().size()
	var pcts: Array = [0.0, 0.0, 0.0]
	if total > 0:
		for i in range(3):
			pcts[i] = float(counts[i]) / float(total) * 100.0
	graph.add_sample(sim_time, pcts)

func _update_growth_phase():
	if growth_done:
		return
	if sim_time < MATURATION_TIME:
		var remaining: int = int(ceil(MATURATION_TIME - sim_time))
		_set_caption("Growing up — %ds until the blobs mature.\n\nBlobs are born small and can't reproduce until they reach full size. Nothing drifts yet." % remaining)
	else:
		growth_done = true
		_set_caption("Everyone's an adult. From here, every meeting is a coin flip — and the frequencies start to wander.")

# ---------------------------------------------------------------------------
#  POPULATION HELPERS
# ---------------------------------------------------------------------------
func _alive() -> Array:
	return blobs.filter(func(b):
		return is_instance_valid(b) and not b.is_dying)

func _color_counts() -> Array:
	var counts: Array = [0, 0, 0]
	for b in _alive():
		counts[b.color_trait] += 1
	return counts

# ---------------------------------------------------------------------------
#  LIVE NARRATION
# ---------------------------------------------------------------------------
func _check_captions():
	if not growth_done:
		return
	var counts := _color_counts()
	for i in range(3):
		if counts[i] == 0 and not lost_announced[i] and _alive().size() > 0:
			lost_announced[i] = true
			_set_caption("%s is gone. Once an allele is lost, it can't come back on its own." % preset_color_names[i])
			return
	if not mid_caption_shown and sim_time > MATURATION_TIME + 14.0:
		mid_caption_shown = true
		_set_caption("Look at the graph — the lines wander with nothing steering them. That wandering is genetic drift.")

# ---------------------------------------------------------------------------
#  END CONDITIONS
# ---------------------------------------------------------------------------
func _check_end():
	var alive := _alive()
	var counts := _color_counts()
	var present := 0
	var lead := 0
	for i in range(3):
		if counts[i] > 0:
			present += 1
			if counts[i] > counts[lead]:
				lead = i

	if alive.size() == 0:
		_end_extinct()
	elif present == 1:
		_end_fixation(lead)
	elif sim_time >= p_time_cap:
		_end_timecap(lead, counts, alive.size())

func _end_fixation(color_idx: int):
	var c: String = preset_color_names[color_idx]
	_finish("[b]%s took over completely.[/b]\n\nThat color is now [b]fixed[/b] — every blob alive is %s, and the other two are gone for good.\n\nNothing made %s better. It won by pure chance. Run it again and a different color will probably come out on top." % [c, c, c])

func _end_timecap(lead: int, counts: Array, total: int):
	var c: String = preset_color_names[lead]
	var pct: int = int(round(float(counts[lead]) / float(total) * 100.0))
	_finish("[b]%s is out in front at %d%%.[/b]\n\nIt started level with the others. No color was ever better — chance alone pushed %s ahead. Given more time it would most likely keep drifting until the others are gone." % [c, pct, c])

func _end_extinct():
	_finish("[b]The population died out[/b] before any color came out on top.\n\nSmall populations are fragile — sometimes drift ends the whole run. Try again.")

func _finish(bbcode: String):
	ended = true
	simulation_running = false
	set_blobs_paused(true)
	end_text.text = bbcode
	_build_comparison()
	_refresh_extra_end_content()
	end_card.visible = true
	_fit_cards.call_deferred()

func _build_comparison():
	for child in compare_box.get_children():
		child.queue_free()

	var header := Label.new()
	header.text = "Start  →  End"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 15)
	header.add_theme_color_override("font_color", Color(0.62, 0.62, 0.68))
	compare_box.add_child(header)

	var end_counts := _color_counts()
	var end_total: int = _alive().size()

	for i in range(3):
		var s_pct := 0
		var e_pct := 0
		if start_total > 0:
			s_pct = int(round(float(start_counts[i]) / float(start_total) * 100.0))
		if end_total > 0:
			e_pct = int(round(float(end_counts[i]) / float(end_total) * 100.0))

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		compare_box.add_child(row)

		var swatch := ColorRect.new()
		swatch.color = preset_color_tints[i]
		swatch.custom_minimum_size = Vector2(16, 16)
		var sw_wrap := CenterContainer.new()
		sw_wrap.add_child(swatch)
		row.add_child(sw_wrap)

		var name_lbl := Label.new()
		name_lbl.text = preset_color_names[i]
		name_lbl.custom_minimum_size = Vector2(70, 0)
		name_lbl.add_theme_font_size_override("font_size", 16)
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
		val.add_theme_font_size_override("font_size", 16)
		val.add_theme_color_override("font_color", col)
		row.add_child(val)

func _on_begin_pressed():
	intro_card.visible = false
	start_simulation()

func _on_run_again_pressed():
	end_card.visible = false
	reset_simulation()
	await get_tree().process_frame
	await get_tree().process_frame
	start_simulation()

func _on_presets_pressed():
	Engine.time_scale = 1.0
	get_tree().change_scene_to_file(_menu_scene_path())

func _show_intro():
	intro_card.visible = true
	_fit_cards.call_deferred()

# ---------------------------------------------------------------------------
#  INTRO / END CARDS
# ---------------------------------------------------------------------------
func _build_preset_overlays():
	preset_layer = CanvasLayer.new()
	preset_layer.layer = 10
	add_child(preset_layer)
	_build_intro_card()
	_build_end_card()

func _build_intro_card():
	intro_card = _make_overlay()
	var vb := _card_body(intro_card, Vector2(640, 0))

	var title := Label.new()
	title.text = _preset_title()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.custom_minimum_size = Vector2(560, 0)
	title.add_theme_font_size_override("font_size", 27)
	vb.add_child(title)

	var body := RichTextLabel.new()
	body.bbcode_enabled = true
	body.fit_content = true
	body.scroll_active = false
	body.custom_minimum_size = Vector2(560, 0)
	body.add_theme_font_size_override("normal_font_size", 16)
	body.add_theme_color_override("default_color", Color(0.88, 0.88, 0.91))
	body.text = _preset_intro_bbcode()
	vb.add_child(body)

	# The three questions sit between the explanation and the Begin button,
	# so there is no way to start the run without scrolling past them.
	vb.add_child(_build_question_panel())

	var begin := _preset_button("Begin", Color(0.36, 0.55, 0.95), Vector2(190, 46))
	var wrap := CenterContainer.new()
	wrap.add_child(begin)
	vb.add_child(wrap)
	begin.pressed.connect(_on_begin_pressed)

# A bordered, amber-tinted block. Deliberately styled unlike anything else on
# the card so it reads as an instruction rather than more explanation.
func _build_question_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	var s := StyleBoxFlat.new()
	s.bg_color = Color(PREDICT_ACCENT.r, PREDICT_ACCENT.g, PREDICT_ACCENT.b, 0.09)
	s.border_color = Color(PREDICT_ACCENT.r, PREDICT_ACCENT.g, PREDICT_ACCENT.b, 0.70)
	s.set_border_width_all(2)
	s.set_corner_radius_all(10)
	s.content_margin_left = 18
	s.content_margin_right = 18
	s.content_margin_top = 14
	s.content_margin_bottom = 14
	panel.add_theme_stylebox_override("panel", s)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 9)
	panel.add_child(vb)

	var head := Label.new()
	head.text = "PREDICT FIRST — commit to an answer before you press Begin"
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.custom_minimum_size = Vector2(520, 0)
	head.add_theme_font_size_override("font_size", 15)
	head.add_theme_color_override("font_color", PREDICT_ACCENT)
	vb.add_child(head)

	var questions: Array = _preset_questions()
	for i in range(questions.size()):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		vb.add_child(row)

		var num := Label.new()
		num.text = "%d." % (i + 1)
		num.custom_minimum_size = Vector2(20, 0)
		num.add_theme_font_size_override("font_size", 16)
		num.add_theme_color_override("font_color", PREDICT_ACCENT)
		row.add_child(num)

		var q := Label.new()
		q.text = str(questions[i])
		q.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		q.custom_minimum_size = Vector2(490, 0)
		q.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		q.add_theme_font_size_override("font_size", 16)
		q.add_theme_color_override("font_color", Color(0.93, 0.91, 0.86))
		row.add_child(q)

	return panel

func _build_end_card():
	end_card = _make_overlay()
	var vb := _card_body(end_card, Vector2(620, 0))

	var title := Label.new()
	title.text = "What just happened"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	vb.add_child(title)

	end_text = RichTextLabel.new()
	end_text.bbcode_enabled = true
	end_text.fit_content = true
	end_text.scroll_active = false
	end_text.custom_minimum_size = Vector2(540, 0)
	end_text.add_theme_font_size_override("normal_font_size", 16)
	end_text.add_theme_color_override("default_color", Color(0.88, 0.88, 0.91))
	vb.add_child(end_text)

	vb.add_child(HSeparator.new())

	compare_box = VBoxContainer.new()
	compare_box.add_theme_constant_override("separation", 8)
	vb.add_child(compare_box)

	# Scenario-specific extras (e.g. the cross-run tally in The Long Shot)
	_build_extra_end_content(vb)

	vb.add_child(HSeparator.new())

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	vb.add_child(row)

	var again := _preset_button("Run Again", Color(0.36, 0.55, 0.95), Vector2(180, 46))
	var back := _preset_button(_menu_button_text(), Color(0.28, 0.28, 0.32), Vector2(180, 46))
	row.add_child(again)
	row.add_child(back)
	again.pressed.connect(_on_run_again_pressed)
	back.pressed.connect(_on_presets_pressed)

# --- card helpers ---
func _make_overlay() -> Control:
	var c := Control.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.add_child(dim)
	preset_layer.add_child(c)
	return c

# Builds a centered card. The content lives inside a ScrollContainer whose
# height is set by _fit_cards(): short cards hug their content, tall ones stop
# at the viewport edge and scroll instead of clipping off the bottom.
func _card_body(overlay: Control, min_size: Vector2) -> VBoxContainer:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(min_size.x, 0)
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.15, 0.15, 0.18)
	s.border_color = Color(0.26, 0.26, 0.31)
	s.set_border_width_all(1)
	s.set_corner_radius_all(14)
	panel.add_theme_stylebox_override("panel", s)
	center.add_child(panel)

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 26)
	pad.add_theme_constant_override("margin_right", 26)
	pad.add_theme_constant_override("margin_top", 22)
	pad.add_theme_constant_override("margin_bottom", 22)
	panel.add_child(pad)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_child(scroll)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vb)

	card_scrolls.append({"scroll": scroll, "vb": vb})
	return vb

# Height each card actually needs, capped at what the screen can show.
func _fit_cards():
	var vp_h := get_viewport_rect().size.y
	var cap: float = max(200.0, vp_h - CARD_VERTICAL_MARGIN)
	for entry in card_scrolls:
		var scroll: ScrollContainer = entry["scroll"]
		var vb: VBoxContainer = entry["vb"]
		if not is_instance_valid(scroll) or not is_instance_valid(vb):
			continue
		var needed: float = vb.get_combined_minimum_size().y
		scroll.custom_minimum_size.y = min(needed, cap)

func _preset_button(text: String, base_color: Color, min_size: Vector2) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.add_theme_font_size_override("font_size", 17)
	b.add_theme_stylebox_override("normal",  _preset_style(base_color))
	b.add_theme_stylebox_override("hover",   _preset_style(base_color.lightened(0.10)))
	b.add_theme_stylebox_override("pressed", _preset_style(base_color.darkened(0.12)))
	b.add_theme_stylebox_override("focus",   _preset_style(base_color))
	b.add_theme_color_override("font_color", Color(0.94, 0.94, 0.94))
	b.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	b.add_theme_color_override("font_pressed_color", Color(0.94, 0.94, 0.94))
	b.add_theme_color_override("font_focus_color", Color(0.94, 0.94, 0.94))
	return b

func _preset_style(c: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.set_corner_radius_all(8)
	s.content_margin_left = 18
	s.content_margin_right = 18
	s.content_margin_top = 9
	s.content_margin_bottom = 9
	return s
