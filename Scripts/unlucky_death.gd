extends DriftEvent

# ===========================================================================
#  EVENT: ONE UNLUCKY DEATH  (v1.1)
#
#  One random blob dies, and one random survivor immediately has a child.
#  The population never changes size; only its colour mix does. Press it
#  forty times and the frequencies random-walk to fixation.
#
#  This is the MORAN MODEL — the standard textbook formulation of drift in a
#  constant-size population. One press = one generation.
#
#  TO MAKE THE BUTTON THE ONLY CAUSE OF ANYTHING:
#    - Lifespans are switched off, so nobody dies of old age.
#    - The pen starts at its cap, so ordinary births are blocked.
#  Between two presses, nothing changes. Every movement on the graph is one
#  press. That is the whole design.
#
#  INTRO TEXT LAYOUT (v1.1)
#  The start screen is three labelled sections: THE SCIENCE (sourced),
#  HOW THIS SIMULATION WORKS (mechanics, flagged as not-biology), WHAT TO DO.
#
#  SETUP:
#    1. Open Game.tscn -> Scene -> "Save Scene As..." -> UnluckyDeath.tscn
#    2. Select the ROOT node "Game" — not the background sprite
#    3. Clear game.gd, attach unlucky_death.gd.
#    4. Confirm Blob Scene + the 5 textures are assigned. Save at once.
# ===========================================================================

const POP := 12                    # 4 of each colour, and the cap
const AUTO_INTERVAL := 0.45        # seconds per step when auto-stepping

var auto_on: bool = false
var auto_timer: float = 0.0
var chk_auto: CheckButton

var deaths_by_color: Array = [0, 0, 0]
var births_by_color: Array = [0, 0, 0]

func _ready():
	p_start_mix = [4, 4, 4]
	p_max_pop = POP
	p_time_cap = 600.0             # ends at fixation, not on a clock
	p_speed_index = 3
	super._ready()

# Nobody dies of old age. The button is the only source of death.
func _rolled_lifespan() -> float:
	return 1000000.0

func _preset_title() -> String:
	return "One Unlucky Death"

func _preset_intro_bbcode() -> String:
	return (
		"[b]THE SCIENCE[/b]\n\n"
		+ "In every generation, some individuals leave more descendants than others purely by chance — one gets eaten before it breeds, another happens to have an extra litter. None of that has to do with which alleles they carry. Over many generations these accidents accumulate, and the frequency of each allele wanders up and down. That wandering is [b]genetic drift[/b], and it is one of the basic mechanisms of evolution alongside natural selection, mutation, and migration.\n\n"
		+ "Drift is much stronger in small populations. If one individual in a population of 10 dies without offspring, a tenth of the gene pool is gone in a single step. In a population of 100, that same death removes only one percent, so a large population is buffered against chance in a way a small one is not.\n\n"
		+ "Drift has two possible endings for any allele. It can rise to 100% of the population, which is called [b]fixation[/b], or it can fall to 0% and be lost. Once an allele is lost it cannot return without mutation or migration, because offspring can only inherit alleles their parents still carry. Drift does not care which alleles are useful; it can fix a harmful one or eliminate a beneficial one.\n\n"
		+ "Population geneticists study this with a deliberately stripped-down model. In the [b]Moran model[/b] (P. A. P. Moran, 1958), a population of fixed size changes by exactly one event at a time: one individual chosen at random dies, and one individual chosen at random reproduces to replace it. Nothing else happens. Under this model, an allele's probability of eventually taking over the whole population is simply its current share — an allele at 25% has a one-in-four chance of winning, and it will win or be lost eventually, never settle in between. This scenario is the Moran model, one step per button press.\n\n"
		+ "[i]Sources: UC Berkeley Understanding Evolution, \"Genetic drift\"; Khan Academy, \"Genetic drift\" (AP Biology, Population genetics); Biology LibreTexts, \"Genetic Drift\" (Raven 12th ed. §20.9.2); Moran, P. A. P. (1958), \"Random processes in genetics\", Mathematical Proceedings of the Cambridge Philosophical Society 54(1).[/i]\n\n"
	) + _howto_bbcode()

# Shown on the start screen (after THE SCIENCE) and again, on demand, in the
# pause popup opened by the help button that DriftPreset puts in the panel.
func _howto_bbcode() -> String:
	return (
		"[b]HOW THIS SIMULATION WORKS[/b]\n"
		+ "[i]This section is about the sim, not the biology.[/i]\n\n"
		+ "The pen holds 12 blobs, 4 of each color, and that is also its cap, so no ordinary births can occur. Ageing is switched off, so nobody dies on their own. Left alone, nothing changes. Each press of the button does two things in order: one blob chosen at random dies, then one of the survivors, also chosen at random, has a child of its own color next to it. The population is back at 12 immediately; only the color mix has moved. Every blob has the same chance of being the one that dies and the same chance of being the parent. Auto-step presses the button for you about twice a second. The run ends when only one color is left, and the results card tallies how many deaths and births each color got.\n\n"
		+ "[b]WHAT TO DO[/b]\n\n"
		+ "1.  Press the button ten times, one at a time, watching the graph after each press.\n"
		+ "2.  Write down which color you think will win, and how many more presses it will take.\n"
		+ "3.  Turn on Auto-step and let it run to fixation. Check your prediction.\n"
		+ "4.  Run it three times. Note the winner and the number of steps each time.\n"
		+ "5.  On the results card, compare deaths and births by color. Ask whether the winner actually got a better deal, or just a luckier one."
	)

func _preset_questions() -> Array:
	return [
		"One death and one birth, both random. Should the mix drift at all, or stay near 4/4/4?",
		"Guess how many presses it takes before one color is gone entirely.",
		"Once a color hits zero, can any number of further presses bring it back?",
	]

# ---------------------------------------------------------------------------
#  CONTROLS
# ---------------------------------------------------------------------------
func _repeat_mode() -> int:
	return REPEAT_ANYTIME

func _fire_button_text() -> String:
	return "One death + one birth"

func _arm_min() -> int:
	return POP

func _build_extra_controls(vb: VBoxContainer):
	chk_auto = CheckButton.new()
	chk_auto.text = "Auto-step"
	chk_auto.add_theme_font_size_override("font_size", 13)
	chk_auto.toggled.connect(_on_auto_toggled)
	vb.add_child(chk_auto)

func _on_auto_toggled(on: bool):
	auto_on = on
	auto_timer = 0.0

func _ready_caption() -> String:
	return "Twelve blobs, four of each. Nothing will change until you press the button — nobody ages and the pen is full."

func _fired_caption() -> String:
	if fire_count <= 1:
		return "One died, one was born. Barely anything moved — which is the point. Keep pressing."
	if fire_count % 10 == 0:
		return "Step %d. Each press nudges the lines, and the nudges pile up." % fire_count
	return "Step %d." % fire_count

func _process(delta):
	super._process(delta)
	if not simulation_running or ended:
		return
	if auto_on and phase == PHASE_READY:
		auto_timer += delta
		if auto_timer >= AUTO_INTERVAL:
			auto_timer = 0.0
			_on_fire_pressed()

# ---------------------------------------------------------------------------
#  THE STEP
# ---------------------------------------------------------------------------
func _do_event():
	var alive := _alive()
	if alive.size() < 2:
		return

	# --- half one: somebody dies, chosen with no regard for colour ---
	var victim = alive[randi() % alive.size()]
	var victim_color: int = victim.color_trait
	deaths_by_color[victim_color] += 1
	victim.die()

	# --- half two: a survivor has a child ---
	# Drawn from the survivors so the dead blob can't parent its own
	# replacement. Every survivor is equally likely — no colour breeds better.
	var survivors: Array = []
	for b in alive:
		if b != victim:
			survivors.append(b)
	if survivors.is_empty():
		return
	var parent = survivors[randi() % survivors.size()]
	births_by_color[parent.color_trait] += 1
	_spawn_child_of(parent)

	_log("%s died, %s was born" % [
		preset_color_names[victim_color].to_lower(),
		preset_color_names[parent.color_trait].to_lower()])

func _spawn_child_of(parent):
	var blob = blob_scene.instantiate()
	add_child(blob)
	var p: Vector2 = parent.global_position
	blob.global_position = Vector2(
		clamp(p.x + randf_range(-34.0, 34.0),
			world_bounds.position.x + 12.0, world_bounds.end.x - 12.0),
		clamp(p.y + randf_range(-34.0, 34.0),
			world_bounds.position.y + 12.0, world_bounds.end.y - 12.0)
	)
	blob.setup(FIXED_SHAPE, parent.color_trait, FIXED_EYES,
		[blob_tex_1, blob_tex_2, blob_tex_3], [eye_tex_1, eye_tex_2])
	blob.lifespan = _rolled_lifespan()
	blob.connect("reproduce", _on_blob_reproduce)
	blob.connect("tree_exited", _on_blob_removed.bind(blob))
	blobs.append(blob)
	births += 1

# ---------------------------------------------------------------------------
#  SUMMARY
# ---------------------------------------------------------------------------
func _event_summary() -> String:
	var counts := _color_counts()
	var present: int = _colors_present()

	if present > 1:
		return "[b]You stopped after %d steps with %d colors still alive.[/b]\n\nEvery step was a fair coin: any blob could die, any survivor could be the parent. The population never changed size. Look at the graph — the lines wandered with nothing steering them, and that wandering is drift.\n\nRun it again with Auto-step on and let it go all the way. One color always wins eventually, and it's never the same one twice." % [
			fire_count, present]

	var winner := 0
	for c in range(3):
		if counts[c] > 0:
			winner = c
	var lost: Array = []
	for c in range(3):
		if counts[c] == 0:
			lost.append(preset_color_names[c])

	return "[b]%s took over after %d steps.[/b]\n\nEvery one of those steps was a fair coin: any blob could die, any survivor could be the parent. No color was ever better than another, and the population was twelve blobs the whole way through.\n\n%s went to zero and stayed there. Once a color is gone, no number of further presses brings it back, because a parent can only pass on a color that still exists.\n\nThis is genetic drift stripped to its smallest possible part. A single death changes almost nothing, which is exactly why drift is easy to miss — and %d of them was enough to wipe out two thirds of this population's diversity.\n\nRun it again. A different color will probably win, and it'll probably take a different number of steps." % [
		preset_color_names[winner], fire_count, " and ".join(lost), fire_count]

# ---------------------------------------------------------------------------
#  RESULTS CARD EXTRA — where the steps actually went
# ---------------------------------------------------------------------------
func _build_extra_end_content(vb: VBoxContainer):
	vb.add_child(HSeparator.new())

	var head := Label.new()
	head.text = "Deaths and births, by color"
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_font_size_override("font_size", 15)
	head.add_theme_color_override("font_color", Color(0.62, 0.62, 0.68))
	vb.add_child(head)

	var note := Label.new()
	note.text = "If nothing favours any color, these come out roughly even — and a winner still wins."
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(500, 0)
	note.add_theme_font_size_override("font_size", 13)
	note.add_theme_color_override("font_color", Color(0.58, 0.58, 0.66))
	vb.add_child(note)

	for c in range(3):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		vb.add_child(row)

		var swatch := ColorRect.new()
		swatch.color = preset_color_tints[c]
		swatch.custom_minimum_size = Vector2(15, 15)
		var sw := CenterContainer.new()
		sw.custom_minimum_size = Vector2(26, 0)
		sw.add_child(swatch)
		row.add_child(sw)

		var name_lbl := Label.new()
		name_lbl.text = preset_color_names[c]
		name_lbl.custom_minimum_size = Vector2(70, 0)
		name_lbl.add_theme_font_size_override("font_size", 15)
		row.add_child(name_lbl)

		var val := Label.new()
		val.name = "Tally%d" % c
		val.text = "died 0   ·   parented 0"
		val.add_theme_font_size_override("font_size", 15)
		val.add_theme_color_override("font_color", Color(0.86, 0.86, 0.92))
		row.add_child(val)

func _refresh_extra_end_content():
	for c in range(3):
		var val = end_card.find_child("Tally%d" % c, true, false)
		if val and val is Label:
			val.text = "died %d   ·   parented %d" % [deaths_by_color[c], births_by_color[c]]

func start_simulation():
	deaths_by_color = [0, 0, 0]
	births_by_color = [0, 0, 0]
	auto_on = false
	auto_timer = 0.0
	if chk_auto:
		chk_auto.button_pressed = false
	super.start_simulation()
