extends DriftEvent

# ===========================================================================
#  EVENT: NATURAL DISASTER  (v2.1)
#
#  A zone of the lab is wiped out. The zone is blind to colour — but blobs
#  are born next to their parents, so colours clump by accident, and a zone
#  that selects on LOCATION therefore selects on colour anyway. Drift, not
#  selection: the reds that died weren't worse, they were standing there.
#
#  The disaster REPEATS. Strike, the survivors breed back to size, the
#  button re-arms, strike again. Finish whenever you like. Every strike is
#  logged and marked on the graph.
#
#    - a ZONE SIZE slider (small / medium / large), so severity is a variable
#    - while you're aiming, every blob inside the zone gets a RING, so you
#      can see exactly who is about to die, not just a count
#    - right-click cancels an armed zone
#
#  INTRO TEXT LAYOUT (v2.1)
#  The start screen is three labelled sections: THE SCIENCE (sourced),
#  HOW THIS SIMULATION WORKS (mechanics, flagged as not-biology), WHAT TO DO.
#
#  SETUP:
#    1. Open Game.tscn -> Scene -> "Save Scene As..." -> NaturalDisaster.tscn
#    2. Select the ROOT node "Game" — not the background sprite
#    3. Clear game.gd, attach natural_disaster.gd.
#    4. Confirm Blob Scene + the 5 textures are assigned. Save at once.
# ===========================================================================

const POP := 24
const ZONE_SIZES := [Vector2(170, 140), Vector2(250, 210), Vector2(340, 280)]
const ZONE_NAMES := ["Small", "Medium", "Large"]
const Z_ZONE := 8                  # above the blobs, so the zone is readable

var zone_idx: int = 1
var armed: bool = false
var zone: Rect2 = Rect2()
var zone_overlay: ZoneOverlay = null
var flash_left: float = 0.0

var sl_zone: HSlider
var lbl_zone: Label
var lbl_contents: Label

var last_killed: Array = [0, 0, 0]
var total_killed: Array = [0, 0, 0]

# ===========================================================================
#  ZONE OVERLAY
#  The aiming rectangle, rings on everything inside it, and the flash.
# ===========================================================================
class ZoneOverlay extends Node2D:
	var preset = null
	var rect: Rect2 = Rect2()
	var active: bool = false
	var flash: float = 0.0

	func _draw():
		if flash > 0.0:
			draw_rect(rect, Color(1.0, 0.35, 0.10, 0.55 * flash), true)
			draw_rect(rect, Color(1.0, 0.60, 0.30, flash), false, 3.0)
			return
		if not active:
			return

		draw_rect(rect, Color(1.0, 0.30, 0.15, 0.14), true)
		draw_rect(rect, Color(1.0, 0.48, 0.28, 0.92), false, 2.0)

		# corner ticks, so it reads as a target rather than a panel
		var t := 14.0
		var c := Color(1.0, 0.62, 0.35, 0.95)
		draw_line(rect.position, rect.position + Vector2(t, 0), c, 3.0)
		draw_line(rect.position, rect.position + Vector2(0, t), c, 3.0)
		draw_line(Vector2(rect.end.x, rect.position.y),
			Vector2(rect.end.x - t, rect.position.y), c, 3.0)
		draw_line(Vector2(rect.end.x, rect.position.y),
			Vector2(rect.end.x, rect.position.y + t), c, 3.0)
		draw_line(Vector2(rect.position.x, rect.end.y),
			Vector2(rect.position.x + t, rect.end.y), c, 3.0)
		draw_line(Vector2(rect.position.x, rect.end.y),
			Vector2(rect.position.x, rect.end.y - t), c, 3.0)
		draw_line(rect.end, rect.end - Vector2(t, 0), c, 3.0)
		draw_line(rect.end, rect.end - Vector2(0, t), c, 3.0)

		# a ring on every blob that would die if you clicked right now
		if preset == null:
			return
		for b in preset._alive():
			if rect.has_point(b.global_position):
				draw_arc(b.global_position, 26.0, 0.0, TAU, 32,
					Color(1.0, 0.55, 0.30, 0.95), 2.5, true)

func _ready():
	p_start_mix = [8, 8, 8]
	p_max_pop = POP
	p_lifespan = 70.0              # long, so the run isn't about ageing
	p_time_cap = 260.0
	p_speed_index = 3
	super._ready()
	zone_overlay = ZoneOverlay.new()
	zone_overlay.preset = self
	zone_overlay.z_index = Z_ZONE
	add_child(zone_overlay)

func _preset_title() -> String:
	return "Natural Disaster"

func _preset_intro_bbcode() -> String:
	return (
		"[b]THE SCIENCE[/b]\n\n"
		+ "Genetic drift is driven by [b]sampling error[/b]: in every generation, which individuals happen to survive and reproduce is partly a matter of chance, and those accidents change allele frequencies with no regard to which alleles are better. A natural disaster that kills a large share of a population at random is the classic textbook trigger. A fire, flood, or eruption does not distinguish between genotypes, so no genotype survives it better than any other — and yet the survivors' allele frequencies can end up very different from the original population's.\n\n"
		+ "Textbooks usually treat a disaster as a whole-population bottleneck. This scenario looks at something subtler. Real disasters are [i]local[/i]: they hit a place, not a genotype. And individuals are almost never spread evenly through a habitat. Offspring tend to live near their parents, so relatives — and the alleles they share — cluster in space. A disaster that only cares about [b]where[/b] you are will therefore remove alleles unevenly, purely because of that clustering.\n\n"
		+ "This is still drift, not natural selection. Selection requires that an allele changes an individual's own chance of surviving or reproducing. Being in the wrong place when the disaster hits is not a heritable trait, so the alleles that are lost are lost by chance. That is the definition of drift. When biologists say drift is \"random\", they mean random with respect to genotype — not that every individual in a habitat faces exactly the same risk.\n\n"
		+ "[i]Sources: UC Berkeley Understanding Evolution, \"Genetic drift\" and \"Bottlenecks and founder effects\"; OpenStax, Biology for AP Courses §19.2 Population Genetics; Khan Academy, \"Genetic drift\" (AP Biology, Population genetics).[/i]\n\n"
	) + _howto_bbcode()

# Shown on the start screen (after THE SCIENCE) and again, on demand, in the
# pause popup opened by the help button that DriftPreset puts in the panel.
func _howto_bbcode() -> String:
	return (
		"[b]HOW THIS SIMULATION WORKS[/b]\n"
		+ "[i]This section is about the sim, not the biology.[/i]\n\n"
		+ "The pen holds 24 blobs, 8 of each color, moving freely. Because offspring are born next to their parents, colors end up clumped without anyone arranging it. The slider sets the disaster zone size: small, medium, or large. Pressing Arm turns the zone on; it follows your cursor, every blob inside it gets a ring, and the readout counts what is inside by color. Left-click to strike: every ringed blob dies. Right-click to cancel without firing. After a strike the survivors breed the pen back to 24, the button re-arms, and you can strike again. Each strike is logged and marked on the graph; the results card totals the kills by color across the whole run.\n\n"
		+ "[b]WHAT TO DO[/b]\n\n"
		+ "1.  Before arming, look at the pen. Are the colors evenly spread or clumped?\n"
		+ "2.  Press Arm and move the zone around without firing. Watch the count by color change as you move.\n"
		+ "3.  Strike a spot where one color is concentrated. Watch the bars during recovery.\n"
		+ "4.  When it re-arms, strike a spot with an even mix. Compare the two results in the log.\n"
		+ "5.  Fire at least four strikes in one run, then read the results card. Try a run with only Large strikes, then one with only Small."
	)

func _preset_questions() -> Array:
	return [
		"Before you arm it — do you expect the colors to be evenly spread out, or clumped?",
		"If a strike kills 9 blobs, will it kill roughly 3 of each color? Why or why not?",
		"The blobs that die aren't worse at anything. So is this selection, or is it drift?",
	]

# ---------------------------------------------------------------------------
#  CONTROLS
# ---------------------------------------------------------------------------
func _repeat_mode() -> int:
	return REPEAT_AFTER_RECOVERY

func _fire_button_text() -> String:
	return "Arm disaster" if fire_count == 0 else "Arm next strike"

func _build_extra_controls(vb: VBoxContainer):
	lbl_zone = Label.new()
	lbl_zone.text = "Zone size: Medium"
	lbl_zone.add_theme_font_size_override("font_size", 14)
	lbl_zone.add_theme_color_override("font_color", Color(0.92, 0.92, 0.96))
	vb.add_child(lbl_zone)

	sl_zone = _labelled_slider(vb, "Small — Medium — Large", 0.0, 2.0, 1.0)
	sl_zone.value_changed.connect(_on_zone_size_changed)

	lbl_contents = Label.new()
	lbl_contents.text = ""
	lbl_contents.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl_contents.add_theme_font_size_override("font_size", 13)
	lbl_contents.add_theme_color_override("font_color", Color(0.62, 0.62, 0.70))
	vb.add_child(lbl_contents)

func _on_zone_size_changed(v: float):
	zone_idx = clampi(int(round(v)), 0, 2)
	if lbl_zone:
		lbl_zone.text = "Zone size: %s" % ZONE_NAMES[zone_idx]

func _ready_caption() -> String:
	if fire_count == 0:
		return "Twenty-four blobs. Press Arm, then move the zone around and watch the rings — the mix inside changes a lot depending on where you point."
	return "Recovered. Same rules, same zone size if you like — pick a different spot and see if the answer changes."

func _fired_caption() -> String:
	var k: int = last_killed[0] + last_killed[1] + last_killed[2]
	if k == 0:
		return "Nothing was inside the zone. Aim at a cluster next time."
	return "Strike %d killed %d. The survivors will breed back to twenty-four — watch whether the mix comes back with them." % [fire_count, k]

# ---------------------------------------------------------------------------
#  AIMING
# ---------------------------------------------------------------------------
# The fire button ARMS the zone. The strike itself is a click in the lab.
func _on_fire_pressed():
	if phase != PHASE_READY or armed:
		return
	armed = true
	zone_overlay.active = true
	if btn_fire:
		btn_fire.disabled = true
	_set_status("Armed — click in the lab to strike. Right-click to cancel.")

func _cancel_arm():
	armed = false
	zone_overlay.active = false
	zone_overlay.queue_redraw()
	if lbl_contents:
		lbl_contents.text = ""
	_arm("Cancelled. Arm again when you're ready.")

func _process(delta):
	super._process(delta)

	if flash_left > 0.0:
		flash_left -= delta
		zone_overlay.flash = max(0.0, flash_left / 0.45)
		zone_overlay.queue_redraw()

	if not armed:
		return
	_track_zone_to_cursor()
	_update_contents_label()

func _track_zone_to_cursor():
	var sz: Vector2 = ZONE_SIZES[zone_idx]
	var m := get_global_mouse_position()
	var x: float = clamp(m.x - sz.x * 0.5,
		world_bounds.position.x, world_bounds.end.x - sz.x)
	var y: float = clamp(m.y - sz.y * 0.5,
		world_bounds.position.y, world_bounds.end.y - sz.y)
	zone = Rect2(x, y, sz.x, sz.y)
	zone_overlay.rect = zone
	zone_overlay.queue_redraw()

func _zone_counts() -> Array:
	var counts: Array = [0, 0, 0]
	for b in _alive():
		if zone.has_point(b.global_position):
			counts[b.color_trait] += 1
	return counts

func _update_contents_label():
	if lbl_contents == null:
		return
	var c := _zone_counts()
	var total: int = c[0] + c[1] + c[2]
	lbl_contents.text = "In the zone: %d  (%d red · %d green · %d blue)" % [
		total, c[0], c[1], c[2]]
	lbl_contents.add_theme_color_override("font_color",
		Color(1.0, 0.62, 0.45) if total > 0 else Color(0.62, 0.62, 0.70))

# The armed click has to beat the inspector's click-to-pin, so this runs
# first and only falls through to the base when the disaster isn't armed.
func _unhandled_input(event):
	if armed and event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_cancel_arm()
			return
		if event.button_index == MOUSE_BUTTON_LEFT \
				and world_bounds.has_point(get_global_mouse_position()):
			_strike()
			return
	super._unhandled_input(event)

func _strike():
	armed = false
	zone_overlay.active = false
	# Hand back to the base, which snapshots on the first fire, marks the
	# graph, and moves the run into RECOVERING.
	super._on_fire_pressed()

# ---------------------------------------------------------------------------
#  THE EVENT
# ---------------------------------------------------------------------------
func _do_event():
	last_killed = [0, 0, 0]
	for b in _alive():
		if zone.has_point(b.global_position):
			last_killed[b.color_trait] += 1
			b.die()
	for c in range(3):
		total_killed[c] += last_killed[c]

	flash_left = 0.45
	zone_overlay.rect = zone
	zone_overlay.flash = 1.0
	zone_overlay.queue_redraw()

	var k: int = last_killed[0] + last_killed[1] + last_killed[2]
	if k == 0:
		_log("Strike %d (%s) — missed, zone was empty" % [fire_count, ZONE_NAMES[zone_idx].to_lower()])
	else:
		_log("Strike %d (%s) — killed %d: %d red, %d green, %d blue" % [
			fire_count, ZONE_NAMES[zone_idx].to_lower(), k,
			last_killed[0], last_killed[1], last_killed[2]])
	if lbl_contents:
		lbl_contents.text = ""

# ---------------------------------------------------------------------------
#  SUMMARY
# ---------------------------------------------------------------------------
func _event_summary() -> String:
	var killed: int = total_killed[0] + total_killed[1] + total_killed[2]
	if killed == 0:
		return "[b]Nothing died.[/b]\n\nEvery strike landed on empty space, so nothing changed. Run it again and aim somewhere with rings in it — and notice how much the contents of the zone vary as you move it. That variation is the point."

	var worst := 0
	for c in range(3):
		if total_killed[c] > total_killed[worst]:
			worst = c
	var even_share: float = float(killed) / 3.0

	var fairness := ""
	if float(total_killed[worst]) > even_share * 1.4:
		fairness = "If the disasters had been even-handed they'd have killed about %.0f of each color. They killed %d %s. Nothing aimed at %s — %s just happened to be where you pointed." % [
			even_share, total_killed[worst], preset_color_names[worst].to_lower(),
			preset_color_names[worst].to_lower(), preset_color_names[worst].to_lower()]
	else:
		fairness = "Across all your strikes the kills came out fairly even, so the mix didn't move much. That's luck too — each individual strike was lopsided, they just happened to cancel out. Try fewer, bigger strikes."

	var lost: Array = []
	for c in range(3):
		if before_counts[c] > 0 and _color_counts()[c] == 0:
			lost.append(preset_color_names[c])
	var loss_line := ""
	if not lost.is_empty():
		loss_line = "\n\n[b]%s %s gone.[/b] No strike targeted %s. A strike hit a patch where %s happened to be concentrated, and breeding back from the survivors couldn't restore what no survivor was carrying." % [
			" and ".join(lost), "are" if lost.size() > 1 else "is",
			"them" if lost.size() > 1 else "it",
			"they" if lost.size() > 1 else "it"]

	return "[b]%d strike%s, %d blobs killed: %d red, %d green, %d blue.[/b]\n\n%s%s\n\nThe zone had no idea what color anything was. It selected on [b]location[/b], and location correlates with color for one reason only: blobs are born next to their parents, so colors clump together by accident.\n\nThat's what makes this drift rather than selection. The blobs that died weren't slower, weaker, or worse at anything. They were in the wrong rectangle.\n\nAnd each time the population bred back to twenty-four, it bred back from [b]whoever survived[/b] — so the recovered mix was the survivors' mix, not the original one." % [
		fire_count, "" if fire_count == 1 else "s", killed,
		total_killed[0], total_killed[1], total_killed[2], fairness, loss_line]

func start_simulation():
	armed = false
	flash_left = 0.0
	last_killed = [0, 0, 0]
	total_killed = [0, 0, 0]
	if zone_overlay:
		zone_overlay.active = false
		zone_overlay.flash = 0.0
		zone_overlay.queue_redraw()
	super.start_simulation()
	if lbl_contents:
		lbl_contents.text = ""
