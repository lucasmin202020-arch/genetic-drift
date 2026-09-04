extends DriftPreset
class_name DriftEvent

# ===========================================================================
#  DRIFT EVENT BASE  (v2.1)
#
#  Shared machinery for the Drift Events mode. Every event underneath is the
#  same experiment:
#
#     GROW        build a population and let it mature
#     READY       the fire button is live
#     RECOVERING  the event has happened; the population responds
#     DONE        compare the reading from before the first fire to now
#
#  WHAT CHANGED FROM v1 AND WHY
#  ----------------------------
#  v1 treated every event as "fire once, watch for 30 seconds, end". That is
#  only right for the founder effect. For the disaster it meant one strike
#  and the run was over before anything had been learned, and for the
#  bottleneck it threw away the most interesting experiment (crash it AGAIN
#  once it's recovered). So the base now understands three REPEAT MODES:
#
#     REPEAT_ANYTIME          fire as often as you like   (Unlucky Death)
#     REPEAT_AFTER_RECOVERY   fire, let it breed back, fire again
#                                                         (Disaster, Bottleneck)
#     REPEAT_NONE             one shot, then observe      (Founder Effect)
#
#  And the user decides when the run ends: a FINISH button appears after the
#  first fire. Runs only end on their own at fixation, extinction, or the
#  time cap. Every fire is logged, marked on the graph, and listed on the
#  results card.
#
#  The old Allele Tracker is hidden here. It cost 200px of panel height to
#  show numbers the graph and the event box already show, and it was pushing
#  the graph and caption off the bottom of the screen. In its place the lab
#  itself gets a stacked frequency bar along its bottom edge — the same bar
#  every pen in the presets already draws.
#
#  A subclass sets its tunables in _ready() BEFORE super._ready(), then
#  overrides:
#
#     _do_event()             REQUIRED. The thing that happens.
#     _repeat_mode()          one of the three constants above
#     _fire_button_text()     re-read every time the button re-arms
#     _arm_min()              population needed before the button unlocks
#     _recovered()            when a REPEAT_AFTER_RECOVERY event can re-arm
#     _observe_seconds()      REPEAT_NONE only: how long to watch
#     _observation_done()     REPEAT_NONE only: end early
#     _build_extra_controls() sliders etc. above the fire button
#     _refresh_extra_controls()
#     _show_lab_bar()         false for events that draw their own pens
#     _setup_lab()            deferred arena setup; multi-pen events override
#     _ready_caption() / _fired_caption() / _event_summary()
#
#  SETUP FOR EVERY EVENT SCENE:
#    1. Open Game.tscn -> Scene -> "Save Scene As..." -> <EventName>.tscn
#    2. Select the ROOT node "Game" — NOT the background sprite
#    3. Clear game.gd, attach the event script.
#    4. Confirm Blob Scene + the 5 textures are assigned. Save at once.
# ===========================================================================

const EVENTS_MENU_SCENE := "res://Scenes/EventsMenu.tscn"

# --- PHASES ---
const PHASE_GROW := 0
const PHASE_READY := 1
const PHASE_RECOVERING := 2
const PHASE_DONE := 3

# --- REPEAT MODES ---
const REPEAT_NONE := 0
const REPEAT_ANYTIME := 1
const REPEAT_AFTER_RECOVERY := 2

# --- LAB MEASUREMENT ---
# game.gd carries a hard-coded world_bounds from before the side panel
# existed, and it's far smaller than the lab actually is. Anything anchored
# to it — the frequency bar, the disaster zone, the inspector bounds — ends
# up floating in the wrong place. So the lab is MEASURED at runtime, the way
# MultiPen does it, and world_bounds is overwritten with the result.
# Tune these two if the bar sits a few pixels off the drawn lab frame.
const LAB_EDGE := 16.0             # inset from the window edge, matches MultiPen
const LAB_BAR_INSET := 8.0         # gap between the bar and the lab's bottom edge

# --- SIZING ---
const EVENT_GRAPH_HEIGHT := 96.0   # shorter than the preset graph on purpose
const LAB_BAR_H := 10.0
const Z_LAB_BAR := 1

var phase: int = PHASE_GROW
var lab_rect: Rect2 = Rect2()

# --- EVENT STATE ---
var event_fired: bool = false
var first_fire_time: float = -1.0
var last_fire_time: float = -1.0
var fire_count: int = 0
var fire_log: Array = []           # [{ "t": float, "text": String }]

# The reading taken the instant before the FIRST fire. Every results card
# compares against this — not the start of the run, because the population
# drifts a little while growing and that isn't the event's doing.
var before_counts: Array = [0, 0, 0]
var before_total: int = 0
var before_colors: int = 0

# --- EVENT UI ---
var event_box: PanelContainer
var event_vb: VBoxContainer
var lbl_status: Label
var lbl_counts: RichTextLabel
var btn_fire: Button
var btn_finish: Button
var event_ui: Array = []
var lab_bar: LabBar = null

const EVENT_ACCENT := Color(1.0, 0.55, 0.42)

# ===========================================================================
#  LAB BAR
#  Stacked frequency bar along the bottom inside edge of the play area.
#  Identical to the one MultiPen draws in every pen, so the whole lab reads
#  the same way regardless of mode.
# ===========================================================================
class LabBar extends Node2D:
	var preset = null
	var rect: Rect2 = Rect2()

	func _draw():
		if preset == null or rect.size.x < 24.0:
			return
		var counts: Array = preset._color_counts()
		var total: int = 0
		for c in counts:
			total += int(c)

		draw_rect(rect, Color(0.09, 0.09, 0.115), true)
		if total > 0:
			var x: float = rect.position.x
			for c in range(3):
				var seg_w: float = rect.size.x * (float(counts[c]) / float(total))
				if seg_w > 0.5:
					draw_rect(Rect2(x, rect.position.y, seg_w, rect.size.y),
						preset.preset_color_tints[c], true)
				x += seg_w
		draw_rect(rect, Color(0.30, 0.31, 0.37), false, 1.0)

# ---------------------------------------------------------------------------
#  NAVIGATION — events go back to the events menu, not the presets menu
# ---------------------------------------------------------------------------
func _menu_scene_path() -> String:
	return EVENTS_MENU_SCENE

func _menu_button_text() -> String:
	return "Events"

# ---------------------------------------------------------------------------
#  OVERRIDABLES
# ---------------------------------------------------------------------------
func _do_event():
	push_error("DriftEvent: _do_event() not overridden by %s" % _preset_title())

func _repeat_mode() -> int:
	return REPEAT_NONE

func _fire_button_text() -> String:
	return "Fire event"

# How full the population must be before the button unlocks. Firing into a
# half-grown population would measure the growth, not the event.
func _arm_min() -> int:
	return int(float(p_max_pop) * 0.85)

# REPEAT_AFTER_RECOVERY: when the button comes back.
func _recovered() -> bool:
	return _alive().size() >= _arm_min()

# REPEAT_NONE only.
func _observe_seconds() -> float:
	return 30.0

func _observation_done() -> bool:
	return false

func _build_extra_controls(_vb: VBoxContainer):
	pass

func _refresh_extra_controls():
	pass

func _show_lab_bar() -> bool:
	return true

func _ready_caption() -> String:
	return "Population is up and stable. Take a look at the frequencies, then fire the event."

func _fired_caption() -> String:
	return "Fired. Watch what happens to the frequencies now."

func _event_summary() -> String:
	return "The event has finished."

# A run ends by itself at fixation. Events that need to see a recovery
# first can hold that off until the population is back.
func _fixation_ends_run() -> bool:
	if _repeat_mode() == REPEAT_AFTER_RECOVERY:
		return _recovered()
	return true

# ---------------------------------------------------------------------------
#  SETUP
# ---------------------------------------------------------------------------
func _ready():
	super._ready()
	# Deferred so the panel and PopLabel have been laid out and can be
	# measured — same reason MultiPen defers its arena.
	_setup_lab.call_deferred()

# The usable lab: everything left of the side panel and below the read-out.
# top_extra reserves room for name plates in multi-pen layouts.
func _measure_lab_rect(top_extra: float = 0.0) -> Rect2:
	var vp := get_viewport_rect().size
	var right: float = vp.x
	var panel = get_node_or_null("UIPanel")
	if panel and panel is Control:
		right = panel.global_position.x
	var top := 46.0
	var pop = get_node_or_null("PopLabel")
	if pop and pop is Control:
		top = pop.global_position.y + pop.size.y + 12.0
	return Rect2(
		LAB_EDGE,
		top + top_extra,
		max(200.0, right - LAB_EDGE * 2.0),
		max(200.0, vp.y - top - top_extra - LAB_EDGE))

# Default single-pen setup. Multi-pen events override this entirely.
func _setup_lab():
	lab_rect = _measure_lab_rect(0.0)
	world_bounds = lab_rect
	if inspector:
		inspector.bounds = lab_rect
	if _show_lab_bar():
		_build_lab_bar()

func _build_lab_bar():
	if lab_bar:
		return
	lab_bar = LabBar.new()
	lab_bar.preset = self
	lab_bar.rect = Rect2(
		lab_rect.position.x + LAB_BAR_INSET,
		lab_rect.end.y - LAB_BAR_H - LAB_BAR_INSET,
		lab_rect.size.x - LAB_BAR_INSET * 2.0,
		LAB_BAR_H)
	lab_bar.z_index = Z_LAB_BAR
	lab_bar.visible = simulation_running
	add_child(lab_bar)

# ---------------------------------------------------------------------------
#  PANEL — the event control block sits ABOVE the frequency graph
# ---------------------------------------------------------------------------
func _build_graph():
	_build_event_controls()
	super._build_graph()
	if graph:
		graph.custom_minimum_size = Vector2(0, EVENT_GRAPH_HEIGHT)

func _build_event_controls():
	var vbox = get_node_or_null("UIPanel/VBox")
	if not vbox:
		return
	event_ui.clear()

	event_box = PanelContainer.new()
	var s := StyleBoxFlat.new()
	s.bg_color = Color(EVENT_ACCENT.r, EVENT_ACCENT.g, EVENT_ACCENT.b, 0.08)
	s.border_color = Color(EVENT_ACCENT.r, EVENT_ACCENT.g, EVENT_ACCENT.b, 0.55)
	s.set_border_width_all(1)
	s.set_corner_radius_all(8)
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	event_box.add_theme_stylebox_override("panel", s)
	vbox.add_child(event_box)
	event_ui.append(event_box)

	event_vb = VBoxContainer.new()
	event_vb.add_theme_constant_override("separation", 5)
	event_box.add_child(event_vb)

	lbl_status = Label.new()
	lbl_status.text = "Growing…"
	lbl_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl_status.add_theme_font_size_override("font_size", 13)
	lbl_status.add_theme_color_override("font_color", Color(0.80, 0.80, 0.86))
	event_vb.add_child(lbl_status)

	# The live counts, replacing the hidden Allele Tracker in one line.
	lbl_counts = RichTextLabel.new()
	lbl_counts.bbcode_enabled = true
	lbl_counts.fit_content = true
	lbl_counts.scroll_active = false
	lbl_counts.add_theme_font_size_override("normal_font_size", 14)
	lbl_counts.custom_minimum_size = Vector2(0, 20)
	event_vb.add_child(lbl_counts)

	_build_extra_controls(event_vb)

	btn_fire = _preset_button(_fire_button_text(), Color(0.78, 0.32, 0.28), Vector2(0, 38))
	btn_fire.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_fire.add_theme_font_size_override("font_size", 15)
	btn_fire.disabled = true
	btn_fire.pressed.connect(_on_fire_pressed)
	event_vb.add_child(btn_fire)

	btn_finish = _preset_button("Finish — see results", Color(0.30, 0.30, 0.36), Vector2(0, 32))
	btn_finish.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_finish.add_theme_font_size_override("font_size", 13)
	btn_finish.visible = false
	btn_finish.pressed.connect(_on_finish_pressed)
	event_vb.add_child(btn_finish)

	for n in event_ui:
		n.visible = false

func _set_gated_visible(vis: bool):
	super._set_gated_visible(vis)
	# The inherited tracker stays hidden in every event — see header.
	var ts = get_node_or_null("UIPanel/VBox/TrackerScroll")
	if ts:
		ts.visible = false
	for n in event_ui:
		if is_instance_valid(n):
			n.visible = vis
	if btn_finish:
		btn_finish.visible = vis and event_fired
	if lab_bar:
		lab_bar.visible = vis

func _fit_tracker_height():
	pass   # tracker isn't shown here

func _set_status(text: String):
	if lbl_status:
		lbl_status.text = text

func _refresh_counts():
	if lbl_counts == null:
		return
	var c := _color_counts()
	lbl_counts.text = "[color=#ff7373]Red %d[/color]   ·   [color=#73e673]Green %d[/color]   ·   [color=#73a6ff]Blue %d[/color]" % [
		c[0], c[1], c[2]]

# ---------------------------------------------------------------------------
#  RUN CONTROL
# ---------------------------------------------------------------------------
func start_simulation():
	phase = PHASE_GROW
	event_fired = false
	first_fire_time = -1.0
	last_fire_time = -1.0
	fire_count = 0
	fire_log.clear()
	before_counts = [0, 0, 0]
	before_total = 0
	before_colors = 0
	if btn_fire:
		btn_fire.disabled = true
		btn_fire.text = _fire_button_text()
	if btn_finish:
		btn_finish.visible = false
	super.start_simulation()
	if graph:
		graph.marks.clear()
	_set_status("Growing — the button unlocks once the population is up to size.")

func _process(delta):
	super._process(delta)
	if lab_bar and simulation_running:
		lab_bar.queue_redraw()
	if not simulation_running or ended:
		return
	_refresh_counts()
	_update_phase()
	_refresh_extra_controls()

func _update_phase():
	if phase == PHASE_GROW:
		if growth_done and _alive().size() >= _arm_min():
			_arm("Ready — %d blobs alive." % _alive().size())
			_set_caption(_ready_caption())
		else:
			_set_status("Growing — %d / %d blobs." % [_alive().size(), p_max_pop])
		return

	if phase == PHASE_RECOVERING:
		var n: int = _alive().size()
		if _repeat_mode() == REPEAT_AFTER_RECOVERY:
			if _recovered():
				_arm("Recovered to %d. Fire again, or finish to see the results." % n)
			else:
				_set_status("Recovering — %d / %d blobs, %d color%s left." % [
					n, p_max_pop, _colors_present(), "" if _colors_present() == 1 else "s"])
		else:
			_set_status("Watching — %d blobs, %d color%s left." % [
				n, _colors_present(), "" if _colors_present() == 1 else "s"])
			if _observation_done() or sim_time >= last_fire_time + _observe_seconds():
				phase = PHASE_DONE

func _arm(status: String):
	phase = PHASE_READY
	if btn_fire:
		btn_fire.disabled = false
		btn_fire.text = _fire_button_text()
	_set_status(status)

# ---------------------------------------------------------------------------
#  FIRING
# ---------------------------------------------------------------------------
func _on_fire_pressed():
	if not simulation_running or ended or phase != PHASE_READY:
		return

	if not event_fired:
		before_counts = _color_counts()
		before_total = _alive().size()
		before_colors = _colors_present()
		first_fire_time = sim_time
		event_fired = true
		if btn_finish:
			btn_finish.visible = true

	fire_count += 1
	last_fire_time = sim_time
	if graph:
		graph.marks.append({"t": sim_time})

	_do_event()
	update_tracker()

	match _repeat_mode():
		REPEAT_ANYTIME:
			_set_status("Fired %d time%s." % [fire_count, "" if fire_count == 1 else "s"])
		_:
			phase = PHASE_RECOVERING
			if btn_fire:
				btn_fire.disabled = true
	_set_caption(_fired_caption())

func _on_finish_pressed():
	if event_fired and phase != PHASE_DONE:
		phase = PHASE_DONE

# Subclasses call this from _do_event() to record what happened.
func _log(text: String):
	fire_log.append({"t": sim_time, "text": text})

func _colors_present() -> int:
	var n := 0
	for c in _color_counts():
		if c > 0:
			n += 1
	return n

func _clock(t: float) -> String:
	return "%d:%02d" % [int(t) / 60, int(t) % 60]

# ---------------------------------------------------------------------------
#  END CONDITIONS
# ---------------------------------------------------------------------------
func _check_end():
	if _alive().size() == 0:
		_end_extinct()
		return
	if phase == PHASE_DONE:
		_finish(_event_summary())
		return
	if event_fired and _colors_present() <= 1 and _fixation_ends_run():
		_finish(_event_summary())
		return
	if sim_time >= p_time_cap:
		if event_fired:
			_finish(_event_summary())
		else:
			_finish("[b]Time ran out before you fired anything.[/b]\n\nThe event was never triggered, so there's nothing to compare. Run it again and press the button once the population is up.")

func _check_captions():
	pass   # events narrate through the status line and phase changes instead

# ---------------------------------------------------------------------------
#  RESULTS CARD — before the first fire vs now, plus the log
# ---------------------------------------------------------------------------
func _build_comparison():
	for child in compare_box.get_children():
		child.queue_free()

	var header := Label.new()
	header.text = "Before the first event  →  Now"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 15)
	header.add_theme_color_override("font_color", Color(0.62, 0.62, 0.68))
	compare_box.add_child(header)

	var end_counts := _color_counts()
	var end_total: int = _alive().size()

	for i in range(3):
		var b_pct := 0
		var e_pct := 0
		if before_total > 0:
			b_pct = int(round(float(before_counts[i]) / float(before_total) * 100.0))
		if end_total > 0:
			e_pct = int(round(float(end_counts[i]) / float(end_total) * 100.0))

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		compare_box.add_child(row)

		var swatch := ColorRect.new()
		swatch.color = preset_color_tints[i]
		swatch.custom_minimum_size = Vector2(16, 16)
		var sw := CenterContainer.new()
		sw.custom_minimum_size = Vector2(26, 0)
		sw.add_child(swatch)
		row.add_child(sw)

		var name_lbl := Label.new()
		name_lbl.text = preset_color_names[i]
		name_lbl.custom_minimum_size = Vector2(70, 0)
		name_lbl.add_theme_font_size_override("font_size", 16)
		row.add_child(name_lbl)

		var arrow := "─"
		var col := Color(0.80, 0.80, 0.84)
		if e_pct > b_pct:
			arrow = "▲"
			col = Color(0.45, 0.95, 0.5)
		elif e_pct < b_pct:
			arrow = "▼"
			col = Color(1.0, 0.45, 0.45)
		if before_counts[i] > 0 and end_counts[i] == 0:
			arrow = "LOST"
			col = Color(1.0, 0.40, 0.40)

		var val := Label.new()
		val.text = "%d%%   →   %d%%   %s" % [b_pct, e_pct, arrow]
		val.add_theme_font_size_override("font_size", 16)
		val.add_theme_color_override("font_color", col)
		row.add_child(val)

	compare_box.add_child(HSeparator.new())

	var stats := HBoxContainer.new()
	stats.alignment = BoxContainer.ALIGNMENT_CENTER
	stats.add_theme_constant_override("separation", 22)
	compare_box.add_child(stats)

	stats.add_child(_event_stat("Fired", str(fire_count), Color(0.86, 0.86, 0.92)))
	stats.add_child(_event_stat("Blobs before", str(before_total), Color(0.86, 0.86, 0.92)))
	stats.add_child(_event_stat("Blobs now", str(end_total), Color(0.86, 0.86, 0.92)))

	var now_colors: int = _colors_present()
	stats.add_child(_event_stat("Colors left", "%d of %d" % [now_colors, before_colors],
		Color(1.0, 0.55, 0.45) if now_colors < before_colors else Color(0.55, 0.90, 0.62)))

	stats.add_child(_event_stat("Mix moved", "%.0f%%" % _shift_from_before(),
		Color(1.0, 0.62, 0.42) if _shift_from_before() >= 20.0 else Color(0.55, 0.88, 0.62)))

	if fire_log.size() > 0:
		compare_box.add_child(HSeparator.new())
		var lh := Label.new()
		lh.text = "What you fired"
		lh.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lh.add_theme_font_size_override("font_size", 14)
		lh.add_theme_color_override("font_color", Color(0.62, 0.62, 0.68))
		compare_box.add_child(lh)

		# Cap the list so a 300-step Unlucky Death run doesn't make the card
		# unscrollable. The subclass summary has the totals anyway.
		var shown: int = min(fire_log.size(), 8)
		for i in range(shown):
			var e: Dictionary = fire_log[i]
			var l := Label.new()
			l.text = "%s   %s" % [_clock(float(e["t"])), str(e["text"])]
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.custom_minimum_size = Vector2(520, 0)
			l.add_theme_font_size_override("font_size", 13)
			l.add_theme_color_override("font_color", Color(0.78, 0.78, 0.84))
			compare_box.add_child(l)
		if fire_log.size() > shown:
			var more := Label.new()
			more.text = "…and %d more." % (fire_log.size() - shown)
			more.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			more.add_theme_font_size_override("font_size", 13)
			more.add_theme_color_override("font_color", Color(0.58, 0.58, 0.66))
			compare_box.add_child(more)

# How far the mix moved since the reading taken before the first fire, 0-100.
func _shift_from_before() -> float:
	if before_total == 0:
		return 0.0
	var end_counts := _color_counts()
	var end_total: int = _alive().size()
	if end_total == 0:
		return 100.0
	var sum := 0.0
	for c in range(3):
		var b: float = float(before_counts[c]) / float(before_total) * 100.0
		var e: float = float(end_counts[c]) / float(end_total) * 100.0
		sum += abs(e - b)
	return sum * 0.5

func _event_stat(title: String, value: String, col: Color) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)

	var v := Label.new()
	v.text = value
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_theme_font_size_override("font_size", 19)
	v.add_theme_color_override("font_color", col)
	box.add_child(v)

	var t := Label.new()
	t.text = title
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 12)
	t.add_theme_color_override("font_color", Color(0.58, 0.58, 0.66))
	box.add_child(t)

	return box

# --- shared helper for subclass sliders ---
func _labelled_slider(vb: VBoxContainer, text: String, lo: float, hi: float,
		start: float) -> HSlider:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", Color(0.66, 0.66, 0.72))
	vb.add_child(lbl)

	var sl := HSlider.new()
	sl.min_value = lo
	sl.max_value = hi
	sl.step = 1.0
	sl.value = start
	sl.custom_minimum_size = Vector2(0, 18)
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Same look as the speed slider, so it doesn't vanish into the panel.
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.16, 0.16, 0.19)
	track.set_corner_radius_all(5)
	track.content_margin_top = 4
	track.content_margin_bottom = 4
	sl.add_theme_stylebox_override("slider", track)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.90, 0.48, 0.38)
	fill.set_corner_radius_all(5)
	sl.add_theme_stylebox_override("grabber_area", fill)
	sl.add_theme_stylebox_override("grabber_area_highlight", fill)
	vb.add_child(sl)

	return sl
