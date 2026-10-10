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

# One sentence. Shown above the lab for the whole run and on the results card.
func _takeaway_line() -> String:
	return "After a crash the numbers come back. The lost colors never do."

func _science_bbcode() -> String:
	return (
		"[b]A crash kills at random. The survivors are a small sample — and a small sample can't carry every color.[/b]\n"
		+ "The population breeds back to full size from whoever survived, so the recovered mix is the survivors' mix. "
		+ "Any color no survivor carried is gone for good."
	)

# The full write-up + sources. "Read more" on the intro card; Why tab in About.
func _science_long_bbcode() -> String:
	return (
		"Genetic drift is a change in how common each allele (each version of a gene) is in a population, caused by chance rather than by any allele being better than another. It happens in every population that is not infinitely large, and its effects are strongest in small populations.\n\n"
		+ "A [b]population bottleneck[/b] is genetic drift at its most extreme. Some event — a fire, a drought, a disease, overhunting — kills most of a population in a short time. Which individuals survive has nothing to do with their genes: a fire cannot tell one genotype from another, so no genotype survives it better than any other. The survivors are therefore a random sample of the original population, and a small random sample is usually not a representative one.\n\n"
		+ "From that moment on, the survivors' allele frequencies [i]are[/i] the population's allele frequencies, however different they may be from what existed before. Any allele that no survivor happened to carry is gone permanently, because offspring can only inherit alleles their parents have. Even a beneficial allele can be lost this way.\n\n"
		+ "Real case: northern elephant seals were hunted down to roughly twenty animals by the 1890s. Protected since then, they have rebounded to well over 100,000 — but they carry far less genetic variation than southern elephant seals, which were never hunted so severely. The headcount recovered fully. The diversity did not, and could not.\n\n"
		+ "Two consequences follow. First, the smaller the surviving group, the more diversity is lost. Second, bottlenecks compound: a population that is hit again and again loses a further slice of variation each time, even if each individual crash is mild.\n\n"
		+ "[i]Sources: Khan Academy, \"Genetic drift\" (AP Biology, Population genetics); OpenStax, Biology for AP Courses §19.2 Population Genetics; UC Berkeley Understanding Evolution, \"Bottlenecks and founder effects\"; Biology LibreTexts, \"Genetic Drift\" (Raven 12th ed. §20.9.2).[/i]"
	)

# Shown on the intro card and, on demand, in the About popup's How tab.
func _howto_bbcode() -> String:
	return (
		"[b]How it works[/b]\n"
		+ "•  24 blobs, 8 per color. The slider sets how many survive a crash.\n"
		+ "•  Crash → everyone past that number dies, chosen at random.\n"
		+ "•  Survivors breed back to 24, then you can crash again.\n\n"
		+ "[b]What to do[/b]\n"
		+ "1.  Leave 4 survivors. Crash once and watch the recovery.\n"
		+ "2.  Crash again until a color disappears.\n"
		+ "3.  Run it at 12 survivors, then at 2. Compare."
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

	return "[b]%d crash%s.[/b]\n\n%s\n\n%s\n\nNumbers bounce back. [b]Diversity doesn't[/b] — everything alive now descends from the few that made it, and their mix is the only mix there is. That's why biologists care about a species' lowest point, not its current headcount." % [
		fire_count, "" if fire_count == 1 else "es", diversity, recovery]

func start_simulation():
	last_survivors = [0, 0, 0]
	colors_lost_at = [-1, -1, -1]
	super.start_simulation()
