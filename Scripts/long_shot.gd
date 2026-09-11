extends "res://Scripts/coin_flip.gd"

# ===========================================================================
#  PRESET: THE LONG SHOT
#
#  INHERITS from coin_flip.gd, so the entire look is identical — same panel,
#  same bar chart, same frequency graph, same caption box, same cards.
#  Only three things change:
#
#    1. The starting mix is lopsided: 8 blue, 2 red, 2 green.
#    2. The wording frames it as a prediction to be tested.
#    3. The results card keeps a TALLY across runs, comparing the predicted
#       win rate (= each color's starting share) against what actually happens.
#
#  THE LESSON: an allele's chance of eventually taking over is exactly its
#  starting frequency. Blue starts at 67%, so blue wins about two runs in
#  three. Red and green start at 17% each and usually vanish early — but not
#  always, and the tally converges on those numbers if you run it enough.
#
#  This is why drift erodes diversity: rare variants are usually the ones lost.
#
#  SETUP:
#    1. Open CoinFlip.tscn -> Scene -> "Save Scene As..." -> LongShot.tscn
#    2. Select the ROOT node of the NEW scene (check the tab says LongShot!)
#    3. Clear coin_flip.gd, attach long_shot.gd.
#    4. Confirm Blob Scene + the 5 textures are assigned. Save at once.
# ===========================================================================

# --- STARTING MIX: [red, green, blue] ---
const MIX := [2, 2, 8]

# Tally persists for the whole session, so leaving to the preset menu and
# coming back doesn't wipe the experiment.
static var wins: Array = [0, 0, 0]      # fixations, per color
static var unresolved: int = 0          # runs that hit the time cap
static var wipeouts: int = 0            # runs where everything died

# --- tally UI refs ---
var tally_rows: Array = []
var tally_footer: Label

func _ready():
	# Set the scenario tunables BEFORE the base class builds anything.
	p_start_mix = MIX
	p_max_pop = 14           # small, so most runs resolve quickly
	p_lifespan = 28.0
	p_time_cap = 150.0
	p_speed_index = 3        # 1.0x
	super._ready()

# ---------------------------------------------------------------------------
#  SCENARIO TEXT
# ---------------------------------------------------------------------------
func _preset_title() -> String:
	return "The Long Shot"

func _preset_intro_bbcode() -> String:
	return (
		"[b]THE SCIENCE[/b]\n\n"
		+ "Lesson 1 showed that a neutral allele — one that makes no difference to survival or reproduction — can still take over a population by chance. This lesson is about [i]how likely[/i] that is.\n\n"
		+ "Population geneticists have a precise answer. For a neutral allele, the probability that it will eventually reach [b]fixation[/b] (100% of the population) is equal to its [b]current frequency[/b]. An allele carried by half the population has a 50% chance of winning; one carried by a tenth has a 10% chance. The rest of the time it is lost. This was worked out formally by Motoo Kimura in 1962, and it holds no matter how large the population is — size only changes how [i]long[/i] the process takes, not the odds.\n\n"
		+ "The consequence is easy to miss but important: [b]rare alleles almost always disappear[/b]. A brand-new mutation starts as a single copy in a population of thousands, so its chance of ever becoming common is tiny — even if it happens to be beneficial. Most new variants, useful or not, are gone within a few generations. Drift is a constant filter that removes rare variation, which is one of the main reasons small or shrinking populations lose genetic diversity over time.\n\n"
		+ "Note what the rule does [i]not[/i] say. It does not say the common allele always wins. It says the common allele wins in proportion to how common it is. A one-in-six shot still comes in one time in six, and when it does, nothing about that allele was better — it was simply the unlikely branch of a random process.\n\n"
		+ "[i]Sources: Khan Academy, \"Genetic drift\" (AP Biology, Population genetics); UC Berkeley Understanding Evolution, \"Genetic drift\"; Kimura, M. (1962), \"On the probability of fixation of mutant genes in a population\", Genetics 47(6): 713–719.[/i]\n\n"
	) + _howto_bbcode()

func _howto_bbcode() -> String:
	return (
		"[b]HOW THIS SIMULATION WORKS[/b]\n"
		+ "[i]This section is about the sim, not the biology.[/i]\n\n"
		+ "The pen starts with 12 blobs — 8 blue, 2 red, 2 green — and never holds more than 14. Color does nothing: no color lives longer or breeds faster, and the rules are identical to Lesson 1. Blue's starting share is 67%, red's and green's are 17% each; those numbers are the predicted win rates. The run ends when one color is the only one left. The results card keeps a running tally for the whole session — leaving to the menu and coming back does not reset it — and shows each color's predicted win rate next to its actual one. A run that hits the time limit or dies out completely does not count toward the tally.\n\n"
		+ "[b]WHAT TO DO[/b]\n\n"
		+ "1.  Before pressing Begin, write down which color you expect to win this run.\n"
		+ "2.  Watch the two rare colors. Note how quickly one of them usually drops to a single blob.\n"
		+ "3.  When the run ends, look at the tally, then press Run Again. Do this at least six times.\n"
		+ "4.  After six or more completed runs, compare the Actual column to the Predicted column. The rows turn green when they're close."
	)

func _preset_questions() -> Array:
	return [
		"Blue starts with 8 and the others with 2 each. Does blue have to win?",
		"Guess how often a starting-2 color wins — 1 run in 4? 1 in 10? Never?",
		"If a rare color does win, does that mean it was better than the others?",
	]

# ---------------------------------------------------------------------------
#  RESULT WORDING — reframed around the odds
# ---------------------------------------------------------------------------
func _end_fixation(color_idx: int):
	_record_win(color_idx)
	var c: String = preset_color_names[color_idx]
	var share: int = _predicted_pct(color_idx)
	var msg := ""
	if color_idx == 2:
		msg = "[b]Blue took over.[/b]\n\nThe favourite won — it started with %d%% of the population, so this is the outcome you'd expect most of the time.\n\nBlue was never better. It just had more tickets in the draw." % share
	else:
		msg = "[b]%s took over — the long shot came in.[/b]\n\n%s started as just %d%% of the population and drove both other colors to extinction anyway.\n\nThis was always possible; it was simply unlikely. Rare alleles usually disappear, but every so often chance carries one all the way." % [c, c, share]
	_finish(msg)

func _end_timecap(lead: int, counts: Array, total: int):
	unresolved += 1
	var c: String = preset_color_names[lead]
	var pct: int = int(round(float(counts[lead]) / float(total) * 100.0))
	_finish("[b]Time's up — %s leads at %d%%.[/b]\n\nNo color has taken over yet, so this run doesn't count toward the tally. Run it again and let one finish." % [c, pct])

func _end_extinct():
	wipeouts += 1
	_finish("[b]The population died out[/b] before any color took over.\n\nSmall populations are fragile. This run doesn't count toward the tally — try again.")

func _record_win(color_idx: int):
	wins[color_idx] += 1

func _predicted_pct(color_idx: int) -> int:
	var total := 0
	for n in MIX:
		total += int(n)
	if total == 0:
		return 0
	return int(round(float(MIX[color_idx]) / float(total) * 100.0))

# ---------------------------------------------------------------------------
#  CROSS-RUN TALLY  (the real payoff of this scenario)
# ---------------------------------------------------------------------------
func _build_extra_end_content(vb: VBoxContainer):
	vb.add_child(HSeparator.new())

	var header := Label.new()
	header.text = "Across all your runs"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 15)
	header.add_theme_color_override("font_color", Color(0.62, 0.62, 0.68))
	vb.add_child(header)

	# column headings
	var head_row := HBoxContainer.new()
	head_row.add_theme_constant_override("separation", 10)
	head_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(head_row)
	head_row.add_child(_spacer(26))
	head_row.add_child(_col_label("", 70))
	head_row.add_child(_col_label("Predicted", 100, Color(0.60, 0.60, 0.68)))
	head_row.add_child(_col_label("Actual", 150, Color(0.60, 0.60, 0.68)))

	tally_rows.clear()
	for i in range(3):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		vb.add_child(row)

		var swatch := ColorRect.new()
		swatch.color = preset_color_tints[i]
		swatch.custom_minimum_size = Vector2(16, 16)
		var sw_wrap := CenterContainer.new()
		sw_wrap.custom_minimum_size = Vector2(26, 0)
		sw_wrap.add_child(swatch)
		row.add_child(sw_wrap)

		row.add_child(_col_label(preset_color_names[i], 70))

		var pred := _col_label("%d%%" % _predicted_pct(i), 100, Color(0.70, 0.70, 0.78))
		row.add_child(pred)

		var actual := _col_label("—", 150)
		row.add_child(actual)

		tally_rows.append(actual)

	tally_footer = Label.new()
	tally_footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tally_footer.add_theme_font_size_override("font_size", 14)
	tally_footer.add_theme_color_override("font_color", Color(0.58, 0.58, 0.66))
	vb.add_child(tally_footer)

func _refresh_extra_end_content():
	var resolved := 0
	for w in wins:
		resolved += int(w)

	for i in range(3):
		if i >= tally_rows.size():
			continue
		var lbl: Label = tally_rows[i]
		if resolved == 0:
			lbl.text = "—"
			lbl.add_theme_color_override("font_color", Color(0.70, 0.70, 0.78))
			continue
		var pct: int = int(round(float(wins[i]) / float(resolved) * 100.0))
		var word := "win" if int(wins[i]) == 1 else "wins"
		lbl.text = "%d %s  (%d%%)" % [int(wins[i]), word, pct]
		# green when observed is close to predicted, neutral otherwise
		var diff: int = abs(pct - _predicted_pct(i))
		if resolved >= 5 and diff <= 12:
			lbl.add_theme_color_override("font_color", Color(0.50, 0.92, 0.55))
		else:
			lbl.add_theme_color_override("font_color", Color(0.88, 0.88, 0.92))

	if tally_footer:
		var extra := ""
		var skipped: int = unresolved + wipeouts
		if skipped > 0:
			extra = "   (%d run%s didn't finish)" % [skipped, "" if skipped == 1 else "s"]
		if resolved == 0:
			tally_footer.text = "No completed runs yet.%s" % extra
		elif resolved < 5:
			tally_footer.text = "%d completed run%s — too few to judge. Keep going.%s" % [
				resolved, "" if resolved == 1 else "s", extra]
		else:
			tally_footer.text = "%d completed runs.%s" % [resolved, extra]

# --- small layout helpers ---
func _col_label(text: String, width: float, col: Color = Color(0.88, 0.88, 0.92)) -> Label:
	var l := Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(width, 0)
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", col)
	return l

func _spacer(width: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(width, 0)
	return c
