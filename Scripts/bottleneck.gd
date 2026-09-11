extends DriftEvent

# ===========================================================================
#  EVENT: BOTTLENECK  (v2.1)
#
#  A population crash. Most blobs die at random, a handful survive, and the
#  survivors breed the population back up to full size.
#
#  THE LESSON: the NUMBERS recover. The DIVERSITY does not. Every blob in
#  the recovered population descends from the few that made it, so the
#  recovered mix is the survivors' mix — not the original one.
#
#  It repeats. Once the population is back to size the button re-arms, and
#  you can crash it again — a SERIAL bottleneck. Each crash chips away
#  diversity that never comes back, until a population of twenty-four is all
#  one colour and looks completely healthy from a headcount.
#
#  INTRO TEXT LAYOUT (v2.1)
#  The start screen is now three labelled sections:
#    THE SCIENCE        — the actual biology, paraphrased from named sources
#    HOW THIS SIM WORKS — mechanics only, explicitly flagged as not-biology
#    WHAT TO DO         — a numbered procedure
#
#  SETUP:
#    1. Open Game.tscn -> Scene -> "Save Scene As..." -> Bottleneck.tscn
#    2. Select the ROOT node "Game" — not the background sprite
#    3. Clear game.gd, attach bottleneck.gd.
#    4. Confirm Blob Scene + the 5 textures are assigned. Save at once.
# ===========================================================================

const POP := 24
const MIN_SURVIVORS := 2
const MAX_SURVIVORS := 12
const DEFAULT_SURVIVORS := 4

var survivors_wanted: int = DEFAULT_SURVIVORS
var sl_survivors: HSlider
var lbl_severity: Label

var last_survivors: Array = [0, 0, 0]
var colors_lost_at: Array = [-1, -1, -1]   # which crash number lost each colour

func _ready():
	p_start_mix = [8, 8, 8]
	p_max_pop = POP
	p_lifespan = 80.0              # long, so recovery isn't fighting old age
	p_time_cap = 300.0
	p_speed_index = 3
	super._ready()

func _preset_title() -> String:
	return "Bottleneck"

func _preset_intro_bbcode() -> String:
	return (
		"[b]THE SCIENCE[/b]\n\n"
		+ "Genetic drift is a change in how common each allele (each version of a gene) is in a population, caused by chance rather than by any allele being better than another. It happens in every population that is not infinitely large, and its effects are strongest in small populations.\n\n"
		+ "A [b]population bottleneck[/b] is genetic drift at its most extreme. Some event — a fire, a drought, a disease, overhunting — kills most of a population in a short time. Which individuals survive has nothing to do with their genes: a fire cannot tell one genotype from another, so no genotype survives it better than any other. The survivors are therefore a random sample of the original population, and a small random sample is usually not a representative one.\n\n"
		+ "From that moment on, the survivors' allele frequencies [i]are[/i] the population's allele frequencies, however different they may be from what existed before. Any allele that no survivor happened to carry is gone permanently, because offspring can only inherit alleles their parents have. Even a beneficial allele can be lost this way.\n\n"
		+ "Real case: northern elephant seals were hunted down to roughly twenty animals by the 1890s. Protected since then, they have rebounded to well over 100,000 — but they carry far less genetic variation than southern elephant seals, which were never hunted so severely. The headcount recovered fully. The diversity did not, and could not.\n\n"
		+ "Two consequences follow. First, the smaller the surviving group, the more diversity is lost. Second, bottlenecks compound: a population that is hit again and again loses a further slice of variation each time, even if each individual crash is mild.\n\n"
		+ "[i]Sources: Khan Academy, \"Genetic drift\" (AP Biology, Population genetics); OpenStax, Biology for AP Courses §19.2 Population Genetics; UC Berkeley Understanding Evolution, \"Bottlenecks and founder effects\"; Biology LibreTexts, \"Genetic Drift\" (Raven 12th ed. §20.9.2).[/i]\n\n"
	) + _howto_bbcode()

# Shown on the start screen (after THE SCIENCE) and again, on demand, in the
# pause popup opened by the help button that DriftPreset puts in the panel.
func _howto_bbcode() -> String:
	return (
		"[b]HOW THIS SIMULATION WORKS[/b]\n"
		+ "[i]This section is about the sim, not the biology.[/i]\n\n"
		+ "The pen holds 24 blobs in three colors, 8 of each. Color is a blob's only gene. The slider sets how many blobs survive each crash, from 2 to 12. When you press Crash, the blobs are shuffled and every blob past that number dies — survival is random with respect to color. The survivors then breed the pen back up to 24; each offspring inherits the color of one parent, chosen at random. Once the pen is back to full size the button re-arms and you can crash it again. Every crash is marked on the graph, and the results card compares the population before the first crash with the population at the end.\n\n"
		+ "[b]WHAT TO DO[/b]\n\n"
		+ "1.  Leave the slider at 4 and press Crash once. Watch the bars while the population recovers.\n"
		+ "2.  When the button re-arms, crash it again. Keep going until a color disappears.\n"
		+ "3.  Run it again at 12 survivors and crash it five or more times. Then run it at 2.\n"
		+ "4.  Before every crash, predict how many colors will survive it. Check yourself against the log."
	)

func _preset_questions() -> Array:
	return [
		"After the pen refills to twenty-four, will the mix be back to roughly a third each?",
		"With 4 survivors, what are the chances all three colors make it through one crash?",
		"If a mild crash keeps all three colors, is it safe to repeat it? How many times?",
	]

# ---------------------------------------------------------------------------
#  CONTROLS
# ---------------------------------------------------------------------------
func _repeat_mode() -> int:
	return REPEAT_AFTER_RECOVERY

func _fire_button_text() -> String:
	return "Crash the population" if fire_count == 0 else "Crash it again"

# Re-arm only when genuinely back to size, so "the numbers recovered" is a
# fact the user has watched happen rather than something the card asserts.
func _recovered() -> bool:
	return _alive().size() >= p_max_pop - 2

func _build_extra_controls(vb: VBoxContainer):
	lbl_severity = Label.new()
	lbl_severity.text = "Survivors: %d of %d  (%d%% die)" % [
		DEFAULT_SURVIVORS, POP,
		int(round((1.0 - float(DEFAULT_SURVIVORS) / float(POP)) * 100.0))]
	lbl_severity.add_theme_font_size_override("font_size", 14)
	lbl_severity.add_theme_color_override("font_color", Color(0.92, 0.92, 0.96))
	vb.add_child(lbl_severity)

	sl_survivors = _labelled_slider(vb, "How severe each crash is",
		float(MIN_SURVIVORS), float(MAX_SURVIVORS), float(DEFAULT_SURVIVORS))
	sl_survivors.value_changed.connect(_on_severity_changed)

func _on_severity_changed(v: float):
	survivors_wanted = int(round(v))
	if lbl_severity:
		lbl_severity.text = "Survivors: %d of %d  (%d%% die)" % [
			survivors_wanted, POP,
			int(round((1.0 - float(survivors_wanted) / float(POP)) * 100.0))]

func _ready_caption() -> String:
	if fire_count == 0:
		return "Twenty-four blobs, a third of each color. Pick a severity, then crash it."
	return "Back to full size with %d color%s. It looks recovered. Crash it again and see what's actually left." % [
		_colors_present(), "" if _colors_present() == 1 else "s"]

func _fired_caption() -> String:
	var s: int = last_survivors[0] + last_survivors[1] + last_survivors[2]
	return "Crash %d. %d survivors carrying %d of 3 colors. Now watch them breed the population back up." % [
		fire_count, s, _colors_present()]

# ---------------------------------------------------------------------------
#  THE EVENT
# ---------------------------------------------------------------------------
func _do_event():
	var alive := _alive()
	if alive.size() <= survivors_wanted:
		_log("Crash %d — nothing to crash, only %d alive" % [fire_count, alive.size()])
		return

	var had: Array = _color_counts()

	# Shuffled, then everyone past the cutoff dies. The shuffle is what makes
	# survival random with respect to colour — the most important line here.
	alive.shuffle()
	for i in range(survivors_wanted, alive.size()):
		alive[i].die()

	last_survivors = [0, 0, 0]
	for i in range(survivors_wanted):
		last_survivors[alive[i].color_trait] += 1

	for c in range(3):
		if had[c] > 0 and last_survivors[c] == 0 and colors_lost_at[c] < 0:
			colors_lost_at[c] = fire_count

	_log("Crash %d — %d of %d survived: %d red, %d green, %d blue" % [
		fire_count, survivors_wanted, alive.size(),
		last_survivors[0], last_survivors[1], last_survivors[2]])

# ---------------------------------------------------------------------------
#  SUMMARY
# ---------------------------------------------------------------------------
func _event_summary() -> String:
	var end_total: int = _alive().size()
	var end_colors: int = _colors_present()

	var lost_lines: Array = []
	for c in range(3):
		if colors_lost_at[c] > 0:
			lost_lines.append("%s was lost in crash %d" % [preset_color_names[c], colors_lost_at[c]])

	var diversity := ""
	if lost_lines.is_empty():
		diversity = "All three colors made it through every crash. With %d survivors per crash that's a fair bet for one or two — try more crashes, or a lower slider, and it stops holding." % survivors_wanted
	else:
		diversity = "[b]%s.[/b] No amount of breeding brought %s back. A parent can only pass on a color it has." % [
			". ".join(lost_lines), "them" if lost_lines.size() > 1 else "it"]

	var recovery := ""
	if end_total >= p_max_pop - 2:
		recovery = "The population is at [b]%d blobs[/b] — as big as it was before anything happened. It's carrying [b]%d of the original %d colors[/b]." % [
			end_total, end_colors, before_colors]
	else:
		recovery = "The population was at [b]%d of %d[/b] when you stopped, carrying %d of the original %d colors." % [
			end_total, p_max_pop, end_colors, before_colors]

	return "[b]%d crash%s.[/b]\n\n%s\n\n%s\n\nThis is the part that catches people out. A bottleneck doesn't permanently shrink a population — numbers bounce back, sometimes within a generation or two. What doesn't bounce back is [b]genetic diversity[/b], because everything alive afterwards descends from the handful that made it, and their mix is the only mix there is. Repeat the crash and every survivor sample takes another bite.\n\nIt's why conservation biologists care about a species' historical low point, not its current headcount. Cheetahs, northern elephant seals, and European bison all recovered in numbers and are still living with the genetics of a few dozen survivors." % [
		fire_count, "" if fire_count == 1 else "es", diversity, recovery]

func start_simulation():
	last_survivors = [0, 0, 0]
	colors_lost_at = [-1, -1, -1]
	super.start_simulation()
